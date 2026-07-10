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

    /// Single-quoted with embedded-quote escaping: the tag is user input
    /// interpolated into a login-shell command -- unquoted (or with a raw `'`
    /// inside), spaces or metacharacters would split or inject.
    ///
    /// `noCache` bypasses the layer cache so the `RUN curl install.sh` layer
    /// re-runs and pulls the latest Claude Code -- a plain rebuild would reuse
    /// the cached layer and reinstall the same pinned version.
    static func buildCommand(tag: String, contextDir: String, noCache: Bool = false) -> String {
        let cacheFlag = noCache ? "--no-cache " : ""
        return "container build \(cacheFlag)--tag \(SandboxBackend.shellSingleQuoted(tag)) --file \(SandboxBackend.shellSingleQuoted(contextDir + "/Dockerfile")) \(SandboxBackend.shellSingleQuoted(contextDir))"
    }

    enum BuildResult: Equatable {
        case success
        case failure(String)
    }

    /// Writes the embedded Dockerfile to a temporary directory and runs
    /// `container build`. Returns the tail of the build output on failure.
    ///
    /// Pass `noCache: true` to update an existing image to the latest Claude
    /// Code (the recipe is fixed, so the cache must be busted to re-fetch it).
    static func build(tag: String, noCache: Bool = false) async -> BuildResult {
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
            buildCommand(tag: tag, contextDir: contextDir, noCache: noCache),
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

    /// Whether the image is present in the local store, and when it was
    /// built. One `container image inspect` answers both — existence from
    /// the exit code, creation date from the JSON. `created` is nil for a
    /// missing image or JSON without a creation date.
    static func imageStatus(_ name: String) async -> (exists: Bool, created: Date?) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return (false, nil) }
        let result = await runCapturingOutput(
            "container image inspect \(SandboxBackend.shellSingleQuoted(trimmed))",
            timeoutSeconds: 15
        )
        guard result.exitCode == 0 else { return (false, nil) }
        return (true, parseCreationDate(fromInspectJSON: Data(result.output.utf8)))
    }

    // MARK: - Image staleness nudge (#44)

    /// Claude Code is baked into the image with its auto-updater disabled,
    /// so the version is frozen at build time while the host CLI updates
    /// daily. Past this age, Settings nudges toward the Update button.
    static let stalenessThresholdDays = 30

    /// Extracts `configuration.creationDate` from `container image inspect`
    /// JSON (an array of image descriptions).
    static func parseCreationDate(fromInspectJSON data: Data) -> Date? {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let configuration = array.first?["configuration"] as? [String: Any],
              let creationDate = configuration["creationDate"] as? String else {
            return nil
        }
        return ClaudeSessionFinder.parseTimestamp(creationDate)
    }

    /// The nudge shown next to Build/Update, or nil while the image is
    /// fresh. Age-based on purpose: version comparisons against "latest"
    /// would nudge constantly given daily Claude Code releases.
    static func stalenessMessage(created: Date, now: Date) -> String? {
        // Threshold on the raw interval — flooring to days first would
        // silently extend "more than 30 days" to 31.
        let age = now.timeIntervalSince(created)
        guard age > TimeInterval(stalenessThresholdDays) * 86_400 else { return nil }
        let days = Int(age / 86_400)
        return "Image built \(days) days ago — Update to pull the latest Claude Code."
    }
}
