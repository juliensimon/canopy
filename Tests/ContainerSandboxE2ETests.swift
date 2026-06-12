import Testing
import Foundation
@testable import Canopy

/// Deep end-to-end tests: run the REAL commands Canopy generates against the
/// real Apple container runtime and image. Gated -- they skip (visibly, as
/// "skipped") on machines without the runtime, the daemon, or the image.
///
/// `-it` is stripped before running: swift test has no TTY, and
/// `container run -it` without one fails with "Operation not supported by
/// device". Everything else (guards, env, mounts, workdir, wrapper, image,
/// arg forwarding) runs exactly as in the app.
@Suite("Apple Container E2E", .serialized, .enabled(if: ContainerE2E.available))
struct ContainerSandboxE2ETests {

    @Test(.timeLimit(.minutes(3)))
    func generatedCommandRunsClaudeInsideContainer() throws {
        // Worktree-shaped scenario incl. a path with spaces: claude must
        // start inside the VM with the worktree mounted at its host path.
        let dir = try ContainerE2E.makeTempDir(name: "canopy e2e wt")
        defer { try? FileManager.default.removeItem(atPath: dir) }

        var settings = CanopySettings()
        settings.sandboxBackend = .appleContainer
        settings.containerImage = "canopy-claude"
        settings.claudeFlags = "--version"

        // Appended --resume must reach claude (forwarded via "$@") without
        // breaking the invocation.
        let command = ContainerE2E.stripTTY(settings.claudeCommand) + " --resume bogus-e2e-id"
        let result = ContainerE2E.run(command, in: dir)

        #expect(result.exitCode == 0, "output: \(result.output.suffix(400))")
        #expect(result.output.contains("(Claude Code)"))
    }

    @Test(.timeLimit(.minutes(3)))
    func gitWorksInsideSandboxedWorktree() throws {
        // A worktree's .git file points at the MAIN repo. Without the extra
        // repo mount, every git command inside the container dies with
        // "fatal: not a git repository". This runs the real mount layout.
        let base = try ContainerE2E.makeTempDir(name: "canopy-e2e-git")
        defer { try? FileManager.default.removeItem(atPath: base) }
        let repo = base + "/main-repo"
        let worktree = base + "/trees/feat"
        let setup = ContainerE2E.run("""
            mkdir -p '\(repo)' && cd '\(repo)' && git init -q -b main && \
            git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init && \
            git worktree add -q '\(worktree)' -b feat
            """, in: base)
        try #require(setup.exitCode == 0, "setup failed: \(setup.output)")

        let backend = SandboxBackend.appleContainer
        let full = backend.claudeCommand(
            claudeFlags: "", sbxFlags: "", containerImage: "canopy-claude",
            containerFlags: "", extraMountPaths: [repo]
        )
        // Surgically swap the claude exec for a git probe; guards, env,
        // mounts, workdir, image, and wrapper all stay exactly as generated.
        let probe = ContainerE2E.stripTTY(full).replacingOccurrences(
            of: #"exec claude "$@""#,
            with: #"git status --porcelain >/dev/null 2>&1 && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m sandboxed && echo GIT_OK || echo GIT_FAIL"#
        )
        let result = ContainerE2E.run(probe, in: worktree)

        #expect(result.exitCode == 0, "output: \(result.output.suffix(400))")
        #expect(result.output.contains("GIT_OK"), "output: \(result.output.suffix(400))")
    }
}

enum ContainerE2E {
    /// Runtime + daemon + image all present, computed once per run.
    static let available: Bool = {
        run("container system status && container image inspect 'canopy-claude' >/dev/null", in: NSTemporaryDirectory()).exitCode == 0
    }()

    static func stripTTY(_ command: String) -> String {
        command.replacingOccurrences(of: "container run -it ", with: "container run ")
    }

    static func makeTempDir(name: String) throws -> String {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Runs a command through a login zsh in the given directory, mirroring
    /// how Canopy's terminal sessions execute what it sends them.
    static func run(_ command: String, in directory: String) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (127, "failed to launch zsh: \(error)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
