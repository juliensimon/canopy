import Foundation

/// Builds and inspects the OCI image used by the Apple container backend.
struct ContainerImageBuilder {
    /// Recipe for the default sandbox image.
    ///
    /// Claude Code is installed with the native installer (not npm): the
    /// host's ~/.claude.json is mounted into the container and declares
    /// `installMethod: native`, so the in-container claude expects a binary
    /// at /root/.local/bin/claude and reports /doctor warnings otherwise.
    /// The node base image stays so npx-launched MCP servers can run.
    static let dockerfile = """
    FROM node:22-slim
    RUN apt-get update && apt-get install -y git ripgrep curl ca-certificates && rm -rf /var/lib/apt/lists/*
    RUN curl -fsSL https://claude.ai/install.sh | bash
    ENV PATH="/root/.local/bin:$PATH" LANG=C.UTF-8 LC_ALL=C.UTF-8 DISABLE_AUTOUPDATER=1
    """

    /// Single-quoted: the tag is user input interpolated into a login-shell
    /// command -- unquoted, spaces or metacharacters would split or inject.
    static func buildCommand(tag: String, contextDir: String) -> String {
        "container build --tag '\(tag)' --file '\(contextDir)/Dockerfile' '\(contextDir)'"
    }

    enum BuildResult: Equatable {
        case success
        case failure(String)
    }

    /// Writes the embedded Dockerfile to a temporary directory and runs
    /// `container build`. Returns the tail of the build output on failure.
    static func build(tag: String) async -> BuildResult {
        let contextDir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("canopy-image-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(atPath: contextDir, withIntermediateDirectories: true)
            try dockerfile.write(toFile: contextDir + "/Dockerfile", atomically: true, encoding: .utf8)
        } catch {
            return .failure("Could not write Dockerfile: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(atPath: contextDir) }

        let result = await runCapturingOutput(
            buildCommand(tag: tag, contextDir: contextDir),
            timeoutSeconds: 1800
        )
        return result.exitCode == 0 ? .success : .failure(String(result.output.suffix(500)))
    }

    /// Output accumulator + completion state usable from pipe/termination
    /// handler threads (Process and DispatchWorkItem aren't Sendable, so the
    /// timeout coordinates through this box instead).
    private final class OutputBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private(set) var timedOut = false
        private var finished = false

        func append(_ chunk: Data) {
            lock.lock(); defer { lock.unlock() }
            data.append(chunk)
        }
        func markTimedOut() {
            lock.lock(); defer { lock.unlock() }
            timedOut = true
        }
        func markFinished() {
            lock.lock(); defer { lock.unlock() }
            finished = true
        }
        var isFinished: Bool {
            lock.lock(); defer { lock.unlock() }
            return finished
        }
        var string: String {
            lock.lock(); defer { lock.unlock() }
            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    private final class ProcessBox: @unchecked Sendable {
        let process: Process
        init(_ process: Process) { self.process = process }
    }

    /// Runs a command in a login shell, draining output WHILE it runs.
    /// Draining only after termination deadlocks: the 64KB pipe buffer
    /// fills (real builds easily exceed it), the child blocks writing,
    /// never exits, and the termination handler never fires.
    static func runCapturingOutput(_ command: String, timeoutSeconds: Double) async -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: SandboxChecker.loginShell())
        process.arguments = ["-ilc", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let buffer = OutputBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                buffer.append(chunk)
            }
        }

        let box = ProcessBox(process)
        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
            if !buffer.isFinished, box.process.isRunning {
                buffer.markTimedOut()
                box.process.terminate()
            }
        }

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { process in
                buffer.markFinished()
                pipe.fileHandleForReading.readabilityHandler = nil
                if let remaining = try? pipe.fileHandleForReading.readToEnd() {
                    buffer.append(remaining)
                }
                let suffix = buffer.timedOut ? "\n(command timed out after \(Int(timeoutSeconds))s)" : ""
                continuation.resume(returning: (process.terminationStatus, buffer.string + suffix))
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                buffer.markFinished()
                continuation.resume(returning: (127, error.localizedDescription))
            }
        }
    }

    /// Returns true if the image is present in the local store.
    static func imageExists(_ name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return await SandboxChecker.succeeds("container image inspect '\(trimmed)'")
    }
}
