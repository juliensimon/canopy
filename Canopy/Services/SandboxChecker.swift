import Foundation

/// Checks whether the CLI tools required by a sandbox backend are available.
///
/// Uses a login shell to resolve PATH so that tools installed via Homebrew
/// or Docker Desktop are found even when running from a GUI app.
struct SandboxChecker {
    enum Status: Equatable {
        case available
        case missingDocker
        case missingSbx
        case missingContainer
        case containerSystemStopped
    }

    /// Checks that the given backend's tools are installed and ready.
    static func check(backend: SandboxBackend) async -> Status {
        switch backend {
        case .off:
            return .available
        case .dockerSbx:
            return await check()
        case .appleContainer:
            guard await commandExists("container") else { return .missingContainer }
            // The runtime daemon must be started once per boot
            // (`container system start`) before containers can run.
            guard await succeeds("container system status") else { return .containerSystemStopped }
            return .available
        }
    }

    /// Checks for both `docker` and `sbx` in PATH.
    static func check() async -> Status {
        guard await commandExists("docker") else { return .missingDocker }
        guard await commandExists("sbx") else { return .missingSbx }
        return .available
    }

    /// Returns a shell path that supports `-ilc` for login/interactive command execution.
    ///
    /// Falls back to `/bin/zsh` when the user's configured shell is incompatible
    /// (for example, `fish`) so command checks don't fail incorrectly.
    static func loginShell() -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let name = URL(fileURLWithPath: shell).lastPathComponent
        switch name {
        case "zsh", "bash":
            return shell
        default:
            return "/bin/zsh"
        }
    }

    /// Returns true if the given command name is found in the user's shell PATH.
    ///
    /// Uses `-ilc` (interactive login) so that both `.zprofile` and `.zshrc` are
    /// sourced -- Homebrew's PATH is often configured in `.zshrc` only.
    static func commandExists(_ name: String) async -> Bool {
        await succeeds("which \(name)")
    }

    /// Returns true if the given shell command exits 0 in a login shell.
    private static func succeeds(_ command: String) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: loginShell())
        process.arguments = ["-ilc", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
