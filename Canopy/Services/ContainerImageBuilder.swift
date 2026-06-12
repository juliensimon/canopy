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
    ENV PATH="/root/.local/bin:$PATH"
    """

    static func buildCommand(tag: String, contextDir: String) -> String {
        "container build --tag \(tag) --file \(contextDir)/Dockerfile \(contextDir)"
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

        let process = Process()
        process.executableURL = URL(fileURLWithPath: SandboxChecker.loginShell())
        process.arguments = ["-ilc", buildCommand(tag: tag, contextDir: contextDir)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: .success)
                } else {
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: .failure(String(output.suffix(500))))
                }
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: .failure(error.localizedDescription))
            }
        }
    }

    /// Returns true if the image is present in the local store.
    static func imageExists(_ name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return await SandboxChecker.succeeds("container image inspect \(trimmed)")
    }
}
