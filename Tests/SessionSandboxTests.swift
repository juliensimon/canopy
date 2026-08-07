import Testing
import Foundation
@testable import Canopy

/// Per-session sandbox override: session → project → global resolution.
@Suite("Per-Session Sandbox")
@MainActor
struct SessionSandboxTests {

    /// Temp config dir so no test can touch the real ~/.config/canopy.
    private func makeState() -> AppState {
        AppState(configDir: NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)")
    }

    @Test func sessionOverrideWinsOverProjectAndGlobal() {
        let state = makeState()
        state.settings.sandboxBackend = .off
        let project = Project(name: "p", repositoryPath: "/tmp", sandboxBackend: .off)
        state.projects = [project]
        let session = SessionInfo(
            name: "s", workingDirectory: "/tmp",
            projectId: project.id,
            sandboxBackend: .appleContainer
        )

        #expect(state.sandboxBackend(for: session) == .appleContainer)
    }

    @Test func sessionWithoutOverrideFallsBackToProject() {
        let state = makeState()
        state.settings.sandboxBackend = .off
        let project = Project(name: "p", repositoryPath: "/tmp", sandboxBackend: .dockerSbx)
        state.projects = [project]
        let session = SessionInfo(name: "s", workingDirectory: "/tmp", projectId: project.id)

        #expect(state.sandboxBackend(for: session) == .dockerSbx)
    }

    @Test func plainSessionFallsBackToGlobal() {
        let state = makeState()
        state.settings.sandboxBackend = .appleContainer
        let session = SessionInfo(name: "s", workingDirectory: "/tmp")

        #expect(state.sandboxBackend(for: session) == .appleContainer)
    }

    @Test func claudeCommandUsesSessionBackendWithProjectFlags() {
        // The override changes only the backend; flags and image still
        // resolve through the normal project → global chain.
        let state = makeState()
        state.settings.sandboxBackend = .off
        state.settings.containerImage = "global-image"
        let project = Project(name: "p", repositoryPath: "/tmp", claudeFlags: "--model haiku")
        state.projects = [project]
        let session = SessionInfo(
            name: "s", workingDirectory: "/tmp",
            projectId: project.id,
            sandboxBackend: .appleContainer
        )

        let command = state.claudeCommand(for: session)
        #expect(command.contains("container run"))
        #expect(command.contains(" 'global-image' sh -c"))
        #expect(command.contains(#"exec claude --model haiku "$@""#))
    }

    @Test func claudeCommandWithoutOverrideMatchesProjectResolution() {
        let state = makeState()
        state.settings.sandboxBackend = .dockerSbx
        let project = Project(name: "p", repositoryPath: "/tmp")
        state.projects = [project]
        let session = SessionInfo(name: "s", workingDirectory: "/tmp", projectId: project.id)

        #expect(state.claudeCommand(for: session)
            == project.resolvedClaudeCommand(globalSettings: state.settings))
    }

    @Test func worktreeSessionMountsMainRepository() {
        // A worktree's .git file points at the main repo: without this
        // mount, every git command inside the container fails.
        let state = makeState()
        let project = Project(name: "p", repositoryPath: "/Users/x/dev/repo")
        state.projects = [project]
        let session = SessionInfo(
            name: "s", workingDirectory: "/Users/x/dev/canopy-worktrees/repo/feat",
            projectId: project.id,
            worktreePath: "/Users/x/dev/canopy-worktrees/repo/feat",
            sandboxBackend: .appleContainer
        )

        #expect(state.claudeCommand(for: session).contains(#"--volume "/Users/x/dev/repo":"/Users/x/dev/repo""#))
    }

    @Test func nonWorktreeSessionGetsNoRepoMount() {
        // Plain/main-repo sessions don't need the extra mount: their .git is
        // self-contained, and overlapping mounts break the VM.
        let state = makeState()
        let project = Project(name: "p", repositoryPath: "/Users/x/dev/repo")
        state.projects = [project]
        let session = SessionInfo(
            name: "s", workingDirectory: "/Users/x/dev/repo",
            projectId: project.id,
            sandboxBackend: .appleContainer
        )

        #expect(!state.claudeCommand(for: session).contains(#"--volume "/Users/x/dev/repo""#))
    }

    @Test func worktreeSessionAtRepoPathDoesNotDoubleMount() {
        // Exercises the equality guard itself: worktreePath set AND equal to
        // the repo path. $PWD already mounts it; a second identical mount
        // risks the overlapping-mount failure.
        let state = makeState()
        let project = Project(name: "p", repositoryPath: "/Users/x/dev/repo")
        state.projects = [project]
        let session = SessionInfo(
            name: "s", workingDirectory: "/Users/x/dev/repo",
            projectId: project.id,
            worktreePath: "/Users/x/dev/repo",
            sandboxBackend: .appleContainer
        )

        #expect(!state.claudeCommand(for: session).contains(#"--volume "/Users/x/dev/repo""#))
    }

    // MARK: - Per-session Claude flags

    /// The sandbox backend already resolves session → project → global, but
    /// claudeFlags stopped at project → global. That is the wrong asymmetry
    /// for an app whose premise is N agents on N worktrees: "opus on the hard
    /// branch, fable on the chore branch" required editing a PROJECT-wide
    /// setting that hit every sibling session.
    @Test func sessionFlagsOverrideProjectFlags() {
        let state = makeState()
        state.settings.sandboxBackend = .off
        state.settings.claudeFlags = "--global"
        let project = Project(name: "p", repositoryPath: "/tmp", claudeFlags: "--project")
        state.projects = [project]
        let session = SessionInfo(
            name: "s", workingDirectory: "/tmp", projectId: project.id,
            claudeFlags: "--model fable"
        )

        #expect(state.claudeCommand(for: session) == "claude --model fable")
    }

    @Test func sessionWithoutFlagsFallsBackToProject() {
        let state = makeState()
        state.settings.sandboxBackend = .off
        state.settings.claudeFlags = "--global"
        let project = Project(name: "p", repositoryPath: "/tmp", claudeFlags: "--project")
        state.projects = [project]
        let session = SessionInfo(name: "s", workingDirectory: "/tmp", projectId: project.id)

        #expect(state.claudeCommand(for: session) == "claude --project")
    }

    @Test func sessionWithoutFlagsOrProjectFallsBackToGlobal() {
        let state = makeState()
        state.settings.sandboxBackend = .off
        state.settings.claudeFlags = "--global"
        let project = Project(name: "p", repositoryPath: "/tmp")
        state.projects = [project]
        let session = SessionInfo(name: "s", workingDirectory: "/tmp", projectId: project.id)

        #expect(state.claudeCommand(for: session) == "claude --global")
    }

    /// nil (inherit) and "" (explicitly no flags) must stay distinct. This is
    /// the ClaudeOverrideDefaults bug class documented in Project.swift, and
    /// it fails the moment someone "simplifies" the override to `?? ""`.
    @Test func sessionEmptyFlagsMeansNoFlagsNotInherit() {
        let state = makeState()
        state.settings.sandboxBackend = .off
        state.settings.claudeFlags = "--global"
        let project = Project(name: "p", repositoryPath: "/tmp", claudeFlags: "--verbose")
        state.projects = [project]
        let session = SessionInfo(
            name: "s", workingDirectory: "/tmp", projectId: project.id,
            claudeFlags: ""
        )

        #expect(state.claudeCommand(for: session) == "claude")
    }

    @Test func sessionFlagsRoundTripThroughSessionsJSON() throws {
        let session = SessionInfo(
            name: "s", workingDirectory: "/tmp", claudeFlags: "--model fable"
        )
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(SessionInfo.self, from: data)
        #expect(decoded.claudeFlags == "--model fable")
    }

    /// Sessions saved before the field existed must decode to nil (inherit),
    /// not "" (no flags) -- assert it rather than assuming the synthesized
    /// Codable does the right thing.
    @Test func sessionsJSONWithoutClaudeFlagsDecodesToNil() throws {
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "name": "old",
            "workingDirectory": "/tmp",
            "createdAt": 0
        }
        """
        let session = try JSONDecoder().decode(SessionInfo.self, from: json.data(using: .utf8)!)
        #expect(session.claudeFlags == nil)
    }

    /// The picker and the resolution chain are useless if the sheet's value
    /// never reaches the stored session -- that is the silent-drop the
    /// sandbox override already had (see openWorktreeSessionStoresOverride).
    @Test func openWorktreeSessionStoresClaudeFlags() {
        let state = makeState()
        let project = Project(name: "p", repositoryPath: "/tmp")
        state.projects = [project]
        state.openWorktreeSession(
            project: project, worktreePath: "/tmp/wt", branch: "b",
            claudeFlags: "--model fable"
        )

        #expect(state.sessions.first?.claudeFlags == "--model fable")
    }

    /// Per-session flags are new untrusted input reaching the
    /// security-load-bearing escape at Settings.swift:97.
    @Test func sessionFlagsWithSingleQuoteAreEscapedInContainerWrapper() {
        let state = makeState()
        let project = Project(name: "p", repositoryPath: "/tmp")
        state.projects = [project]
        let session = SessionInfo(
            name: "s", workingDirectory: "/tmp", projectId: project.id,
            claudeFlags: "--model 'o'pus",
            sandboxBackend: .appleContainer
        )

        let command = state.claudeCommand(for: session)
        #expect(command.contains(#"'\''"#))
        // The wrapper's own closing quote is still the last one.
        #expect(command.hasSuffix(#""$@"' claude"#))
    }

    /// --resume is appended AFTER claudeCommand builds the string, so it lands
    /// outside the wrapper and reaches claude through "$@". Per-session flags
    /// must not disturb that composition.
    @Test func sessionFlagsCompoundWithResumeForContainer() throws {
        let state = makeState()
        let project = Project(name: "p", repositoryPath: "/tmp")
        state.projects = [project]
        let session = SessionInfo(
            name: "s", workingDirectory: "/tmp", projectId: project.id,
            claudeFlags: "--model fable",
            sandboxBackend: .appleContainer
        )

        let uuid = UUID().uuidString
        let command = state.claudeCommand(for: session) + " --resume \(uuid)"
        let wrapperEnd = try #require(command.range(of: "' claude"))
        let resume = try #require(command.range(of: "--resume"))
        #expect(resume.lowerBound > wrapperEnd.lowerBound)
        #expect(command.contains(#"exec claude --model fable "$@""#))
    }

    // MARK: - Worktree + Docker sbx

    /// AppState computed and passed the main-repo path for every backend, but
    /// the .dockerSbx branch dropped it -- so worktree sessions on that
    /// backend had a dangling `.git` pointer and every git command inside the
    /// sandbox failed, with nothing surfaced to the user. Reproduced against
    /// sbx 0.38.0 before this test was written.
    @Test func worktreeSessionOnDockerSbxMountsMainRepository() {
        let state = makeState()
        let project = Project(name: "p", repositoryPath: "/Users/x/dev/repo")
        state.projects = [project]
        let session = SessionInfo(
            name: "s", workingDirectory: "/Users/x/dev/canopy-worktrees/repo/feat",
            projectId: project.id,
            worktreePath: "/Users/x/dev/canopy-worktrees/repo/feat",
            sandboxBackend: .dockerSbx
        )

        let command = state.claudeCommand(for: session)
        #expect(command.contains("claude . '/Users/x/dev/repo' --"))
    }

    @Test func nonWorktreeSessionOnDockerSbxGetsNoExtraWorkspace() {
        let state = makeState()
        let project = Project(name: "p", repositoryPath: "/Users/x/dev/repo")
        state.projects = [project]
        let session = SessionInfo(
            name: "s", workingDirectory: "/Users/x/dev/repo",
            projectId: project.id,
            sandboxBackend: .dockerSbx
        )

        #expect(!state.claudeCommand(for: session).contains("claude . "))
    }

    // MARK: - Main-repo tool access (--add-dir)

    /// Mounting the main repo fixes the *filesystem*; Claude Code's own tool
    /// boundary is cwd-scoped independently of what is mounted. Verified on
    /// CLI 2.1.224: from a worktree, reading a file in the main repo under
    /// `--permission-mode manual` is refused ("outside the paths this session
    /// is permitted to read") and `--add-dir <repo>` grants it. Canopy's
    /// `auto` default masks this, but #55 makes per-session `manual` a
    /// first-class choice, so the flag must be there.
    @Test func worktreeSessionAllowsToolAccessToMainRepository() {
        let state = makeState()
        state.settings.sandboxBackend = .off
        let project = Project(name: "p", repositoryPath: "/Users/x/dev/repo")
        state.projects = [project]
        let session = SessionInfo(
            name: "s", workingDirectory: "/Users/x/dev/canopy-worktrees/repo/feat",
            projectId: project.id,
            worktreePath: "/Users/x/dev/canopy-worktrees/repo/feat"
        )

        #expect(state.claudeCommand(for: session).contains("--add-dir '/Users/x/dev/repo'"))
    }

    @Test func nonWorktreeSessionGetsNoAddDir() {
        // A main-repo session already has the repo as its cwd.
        let state = makeState()
        state.settings.sandboxBackend = .off
        let project = Project(name: "p", repositoryPath: "/Users/x/dev/repo")
        state.projects = [project]
        let session = SessionInfo(
            name: "s", workingDirectory: "/Users/x/dev/repo",
            projectId: project.id
        )

        #expect(!state.claudeCommand(for: session).contains("--add-dir"))
    }

    /// The repo path is user-supplied and reaches the security-load-bearing
    /// escape at Settings.swift:97. Replay the real host-shell parse: the
    /// emitted token must come back as exactly one argv element.
    @Test func addDirPathIsOneShellTokenEvenWithMetacharacters() throws {
        let hostile = "/Users/x/dev/o'brien $(whoami) `id`;a|b&c"
        let state = makeState()
        state.settings.sandboxBackend = .off
        let project = Project(name: "p", repositoryPath: hostile)
        state.projects = [project]
        state.settings.claudeFlags = ""
        let session = SessionInfo(
            name: "s", workingDirectory: "/Users/x/dev/wt",
            projectId: project.id,
            worktreePath: "/Users/x/dev/wt"
        )

        let command = state.claudeCommand(for: session)
        let token = try #require(command.range(of: "--add-dir ")).upperBound
        #expect(try shellOutput("printf %s \(command[token...])") == hostile)
    }

    /// For .appleContainer the flags land INSIDE the `sh -c '...'` wrapper, so
    /// the path is quoted once by shellSingleQuoted and escaped again at
    /// Settings.swift:97. The wrapper must not terminate early.
    @Test func addDirSurvivesContainerWrapperEscaping() throws {
        let state = makeState()
        let project = Project(name: "p", repositoryPath: "/Users/x/dev/o'brien")
        state.projects = [project]
        let session = SessionInfo(
            name: "s", workingDirectory: "/Users/x/dev/wt",
            projectId: project.id,
            worktreePath: "/Users/x/dev/wt",
            sandboxBackend: .appleContainer
        )

        let command = state.claudeCommand(for: session)
        // Every quote in the flags region is POSIX-escaped, so the wrapper's
        // own closing quote is still the last one.
        #expect(command.contains(#"'\''"#))
        #expect(command.hasSuffix(#""$@"' claude"#))
    }

    private func shellOutput(_ command: String) throws -> String {
        let process = Process()
        let out = Pipe()
        let err = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let errText = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(process.terminationStatus == 0, "Shell failed: \(errText)")
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    @Test func openWorktreeSessionStoresOverride() {
        // Reopening a worktree must be able to carry a sandbox override,
        // like createWorktreeSession -- otherwise the override is silently
        // dropped and claude runs with weaker isolation than chosen.
        let state = makeState()
        let project = Project(name: "p", repositoryPath: "/tmp")
        state.projects = [project]
        state.openWorktreeSession(project: project, worktreePath: "/tmp/wt", branch: "b", sandboxBackend: .appleContainer)

        #expect(state.sessions.first?.sandboxBackend == .appleContainer)
        #expect(state.sandboxBackend(for: state.sessions.first!) == .appleContainer)
    }

    @Test func legacySessionDecodesWithNilBackend() throws {
        // sessions.json entries saved before the field existed.
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "name": "old",
            "workingDirectory": "/tmp",
            "createdAt": 0
        }
        """
        let session = try JSONDecoder().decode(SessionInfo.self, from: json.data(using: .utf8)!)
        #expect(session.sandboxBackend == nil)
    }

    // MARK: - Session Info visibility

    /// The value Session Info shows must be the value actually sent. Resolving
    /// the chain in two places is how they drift.
    @Test func resolvedFlagsMatchWhatTheCommandUses() {
        let state = makeState()
        state.settings.sandboxBackend = .off
        state.settings.claudeFlags = "--global"
        let project = Project(name: "p", repositoryPath: "/tmp", claudeFlags: "--project")
        state.projects = [project]

        let inherited = SessionInfo(name: "s", workingDirectory: "/tmp", projectId: project.id)
        #expect(state.resolvedClaudeFlags(for: inherited) == "--project")
        #expect(state.claudeCommand(for: inherited).contains("--project"))

        let overridden = SessionInfo(
            name: "s", workingDirectory: "/tmp", projectId: project.id,
            claudeFlags: "--model fable"
        )
        #expect(state.resolvedClaudeFlags(for: overridden) == "--model fable")
        #expect(state.claudeCommand(for: overridden) == "claude --model fable")
    }

    /// "" is a real state meaning "no flags", distinct from inheriting.
    @Test func resolvedFlagsPreserveExplicitlyEmpty() {
        let state = makeState()
        state.settings.claudeFlags = "--global"
        let session = SessionInfo(name: "s", workingDirectory: "/tmp", claudeFlags: "")
        #expect(state.resolvedClaudeFlags(for: session).isEmpty)
    }

    /// Every backend needs a name, and they must be distinct -- Session Info
    /// showing the same string for two backends would be worse than useless.
    @Test func everySandboxBackendHasADistinctDisplayName() {
        let all: [SandboxBackend] = [.off, .claudeNative, .dockerSbx, .appleContainer]
        let names = all.map(\.displayName)
        #expect(Set(names).count == all.count)
        #expect(!names.contains(where: { $0.isEmpty }))
    }

    /// The row must report the RESOLVED backend, override included -- that is
    /// the whole question being answered.
    @Test func displayedSandboxReflectsTheSessionOverride() {
        let state = makeState()
        state.settings.sandboxBackend = .off
        let project = Project(name: "p", repositoryPath: "/tmp", sandboxBackend: .dockerSbx)
        state.projects = [project]
        let session = SessionInfo(
            name: "s", workingDirectory: "/tmp", projectId: project.id,
            sandboxBackend: .claudeNative
        )

        #expect(state.sandboxBackend(for: session).displayName == "Claude sandbox (Bash only)")
    }

}
