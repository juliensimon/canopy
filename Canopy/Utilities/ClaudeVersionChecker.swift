import Foundation

/// Fetches and parses the host Claude Code CLI version for display in
/// Settings (#43). CLI behavior changes are keyed to versions (e.g. the
/// ≥ 2.1.132 alternate-screen renderer), and the sandbox image can run a
/// different version than the host — showing the host version makes drift
/// diagnosable at a glance.
struct ClaudeVersionChecker {

    /// Extracts the version from `claude --version` output
    /// (e.g. "2.1.206 (Claude Code)" → "2.1.206"). Returns nil when the
    /// output doesn't start with a semver-shaped token — such as a shell
    /// "command not found" error.
    static func parse(_ output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = trimmed.split(separator: " ").first else { return nil }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        return String(token)
    }

    /// Runs `claude --version` in a login shell (same PATH resolution as
    /// SandboxChecker: GUI apps don't inherit Homebrew/~/.local paths).
    /// Returns nil when the CLI is missing or the output is unparseable.
    static func hostVersion() async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: SandboxChecker.loginShell())
        process.arguments = ["-ilc", "claude --version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            // Drain before waiting: one line can't fill the pipe, but the
            // repo convention is to never read after waitUntilExit.
            let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8) else {
                return nil
            }
            return parse(output)
        } catch {
            NSLog("Canopy: could not run claude --version (%@)", "\(error)")
            return nil
        }
    }
}
