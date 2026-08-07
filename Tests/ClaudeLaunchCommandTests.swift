import Testing
import Foundation
@testable import Canopy

/// Canopy used to reverse-engineer the Claude session ID from JSONL mtimes.
/// The CLI lets us *assign* it with `--session-id`, which removes a whole
/// class of bugs -- most visibly that a brand-new worktree session had no id
/// at all for the entire app run, leaving the transcript viewer empty and the
/// token counts missing for exactly the sessions Canopy itself creates.
///
/// The CLI's constraints drive the design (confirmed against 2.1.224):
///
///   --session-id and --resume are mutually exclusive absent --fork-session;
///   the id must be a valid UUID;
///   reusing an id in the same project directory aborts with
///   "Error: Session ID <id> is already in use."
///
/// That last one is why a second launch must switch to --resume: an app
/// restart re-runs this path with the same persisted SessionInfo.id.
///
/// The decision lives in AppState rather than the SwiftUI .onAppear it used to
/// occupy, so it can be tested at all.
@Suite("Claude launch command")
@MainActor
struct ClaudeLaunchCommandTests {

    private func makeState() -> AppState {
        let state = AppState(configDir: NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)")
        state.settings.sandboxBackend = .off
        state.settings.claudeFlags = ""
        return state
    }

    // MARK: - Flag selection

    @Test func assignsSessionIdOnFirstLaunch() {
        let state = makeState()
        let session = SessionInfo(name: "s", workingDirectory: "/tmp/wt")
        state.sessions = [session]

        let launch = state.claudeLaunchCommand(for: session)
        #expect(launch.command.contains("--session-id \(session.id.uuidString)"))
        #expect(!launch.command.contains("--resume"))
        #expect(launch.assignedId == session.id.uuidString)
    }

    /// Passing --session-id again after the id is known aborts the CLI with
    /// "Session ID ... is already in use", so the flags must swap over.
    @Test func resumesInsteadOfAssigningWhenIdKnown() {
        let state = makeState()
        let workDir = "/tmp/canopy-known-\(UUID().uuidString)"
        let known = UUID().uuidString
        let projectDir = makeTranscript(workDir: workDir, sessionId: known)
        defer { try? FileManager.default.removeItem(atPath: projectDir) }

        let session = SessionInfo(name: "s", workingDirectory: workDir, claudeSessionId: known)
        state.sessions = [session]

        let launch = state.claudeLaunchCommand(for: session)
        #expect(launch.command.contains("--resume \(known)"))
        #expect(!launch.command.contains("--session-id"))
        #expect(launch.assignedId == nil)
    }

    /// The highest-value test here: an app restart re-runs the launch path
    /// with the same persisted session. Drive it twice, persisting between,
    /// exactly as MainWindow does -- and create the transcript in between,
    /// because that is what claude does with the id it was handed.
    @Test func secondLaunchResumesRatherThanColliding() {
        let state = makeState()
        let workDir = "/tmp/canopy-second-\(UUID().uuidString)"
        let session = SessionInfo(name: "s", workingDirectory: workDir)
        state.sessions = [session]

        let first = state.claudeLaunchCommand(for: session)
        let assigned = try! #require(first.assignedId)
        state.assignClaudeSessionId(assigned, to: session.id)

        // claude now owns that id and has written its transcript.
        let projectDir = makeTranscript(workDir: workDir, sessionId: assigned)
        defer { try? FileManager.default.removeItem(atPath: projectDir) }

        let reloaded = state.sessions[0]
        let second = state.claudeLaunchCommand(for: reloaded)
        #expect(second.command.contains("--resume \(assigned)"))
        #expect(!second.command.contains("--session-id"))
        #expect(second.assignedId == nil)
    }

    /// Simulates claude having created the transcript for `sessionId`.
    /// Returns the project directory so callers can clean it up.
    @discardableResult
    private func makeTranscript(workDir: String, sessionId: String) -> String {
        let projectDir = ClaudeSessionFinder.projectDirectory(for: workDir)
        try? FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: (projectDir as NSString).appendingPathComponent("\(sessionId).jsonl"),
            contents: Data("{}".utf8)
        )
        return projectDir
    }

    /// sbx session files live inside the ephemeral microVM, which is why
    /// supportsResume is false. Assigning an id there buys nothing and risks
    /// an "already in use" abort if a future sbx persists state.
    @Test func dockerSbxGetsNeitherFlag() {
        let state = makeState()
        let session = SessionInfo(
            name: "s", workingDirectory: "/tmp/wt",
            claudeSessionId: UUID().uuidString,
            sandboxBackend: .dockerSbx
        )
        state.sessions = [session]

        let launch = state.claudeLaunchCommand(for: session)
        #expect(!launch.command.contains("--session-id"))
        #expect(!launch.command.contains("--resume"))
        #expect(launch.assignedId == nil)
    }

    /// For .appleContainer the flags must land AFTER the `sh -c '...'`
    /// wrapper's closing quote so they reach claude through "$@". Assert
    /// ordering, not containment: containment would still pass if someone
    /// moved the injection inside claudeFlags, where the second escaping pass
    /// would mangle it.
    @Test func appleContainerAppendsFlagsAfterWrapper() throws {
        let state = makeState()
        let session = SessionInfo(
            name: "s", workingDirectory: "/tmp/wt",
            sandboxBackend: .appleContainer
        )
        state.sessions = [session]

        let command = state.claudeLaunchCommand(for: session).command
        let wrapperEnd = try #require(command.range(of: "' claude"))
        let flag = try #require(command.range(of: "--session-id"))
        #expect(flag.lowerBound > wrapperEnd.lowerBound)
    }

    /// UUID().uuidString is uppercase and claude echoes the string verbatim
    /// into the JSONL filename -- no normalization. ClaudeTranscriptLoader
    /// .sessionFilePath depends on that, so do NOT add a lowercasing step.
    @Test func uppercaseUuidIsPassedVerbatim() {
        let state = makeState()
        let session = SessionInfo(name: "s", workingDirectory: "/tmp/wt")
        state.sessions = [session]

        let assigned = state.claudeLaunchCommand(for: session).assignedId
        #expect(assigned == session.id.uuidString)
        #expect(assigned == assigned?.uppercased())
    }

    // MARK: - Stale ids

    /// Verified against the CLI: resuming an id that has no transcript prints
    ///
    ///   No conversation found with session ID: <id>
    ///
    /// and exits, so the tab never starts claude at all.
    ///
    /// Canopy can reach that state by its own hand: the id is persisted before
    /// the command is sent, but the sandbox-preflight path echoes a warning
    /// INSTEAD of running claude (SandboxBackendUI.launchCommand). A failed
    /// preflight therefore banked an id that was never used, and every later
    /// launch resumed into nothing. Deleting ~/.claude/projects gets there too.
    ///
    /// So an id is only worth resuming if its transcript exists -- the same
    /// check TranscriptSheet.computeJSONLPath already makes before rendering.
    @Test func doesNotResumeASessionWhoseTranscriptIsMissing() {
        let state = makeState()
        let workDir = "/tmp/canopy-stale-\(UUID().uuidString)"
        let session = SessionInfo(
            name: "s", workingDirectory: workDir,
            claudeSessionId: UUID().uuidString   // valid UUID, no file on disk
        )
        state.sessions = [session]

        let launch = state.claudeLaunchCommand(for: session)
        #expect(!launch.command.contains("--resume"))
        #expect(launch.command.contains("--session-id \(session.id.uuidString)"))
        #expect(launch.assignedId == session.id.uuidString)
    }

    @Test func resumesWhenTheTranscriptExists() throws {
        let state = makeState()
        let workDir = "/tmp/canopy-live-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let known = UUID().uuidString
        let projectDir = makeTranscript(workDir: workDir, sessionId: known)
        defer { try? FileManager.default.removeItem(atPath: projectDir) }

        let session = SessionInfo(
            name: "s", workingDirectory: workDir, claudeSessionId: known
        )
        state.sessions = [session]

        let launch = state.claudeLaunchCommand(for: session)
        #expect(launch.command.contains("--resume \(known)"))
        #expect(!launch.command.contains("--session-id"))
    }

    // MARK: - Adversarial

    /// claudeSessionId is decoded straight from sessions.json and was
    /// interpolated into a shell command with no validation. The discovery
    /// path validates as a UUID; the persistence path did not. A junk value
    /// must be discarded and a fresh id assigned, never emitted.
    @Test(arguments: [
        "abc; rm -rf ~",
        "",
        "../../etc/passwd",
        "not-a-uuid",
        "$(whoami)",
        "`id`",
    ])
    func rejectsNonUuidPersistedSessionId(_ hostile: String) {
        let state = makeState()
        let session = SessionInfo(
            name: "s", workingDirectory: "/tmp/wt", claudeSessionId: hostile
        )
        state.sessions = [session]

        let launch = state.claudeLaunchCommand(for: session)
        #expect(!launch.command.contains("--resume"))
        #expect(!launch.command.contains(hostile.isEmpty ? "\u{0}" : hostile))
        #expect(launch.assignedId == session.id.uuidString)
    }

    // MARK: - Persistence

    @Test func assignMutatorPersistsAcrossReload() {
        let dir = NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let state = AppState(configDir: dir)
        let session = SessionInfo(name: "s", workingDirectory: "/tmp/wt-\(UUID().uuidString)")
        state.sessions = [session]
        let assigned = state.claudeLaunchCommand(for: session).assignedId!
        state.assignClaudeSessionId(assigned, to: session.id)

        let reloaded = AppState(configDir: dir)
        reloaded.loadSessions()
        #expect(reloaded.sessions.first?.claudeSessionId == assigned)
    }

    @Test func assignIsIgnoredForUnknownSession() {
        let state = makeState()
        state.sessions = [SessionInfo(name: "s", workingDirectory: "/tmp/wt")]
        state.assignClaudeSessionId(UUID().uuidString, to: UUID())
        #expect(state.sessions.first?.claudeSessionId == nil)
    }

    // MARK: - Upstream contract

    /// Characterization test, same spirit as the SwiftTerm SGR one: it does
    /// not test Canopy, it tells you when the CLI contract this feature is
    /// built on has moved. Skips when `claude` is not installed (CI).
    @Test func claudeCliStillSupportsSessionId() throws {
        guard let help = try? shellOutput("claude --help 2>/dev/null"), !help.isEmpty else { return }
        #expect(help.contains("--session-id"))
        // --resume must still exist too: it is the other half of the pair.
        #expect(help.contains("--resume"))
    }

    private func shellOutput(_ command: String) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-lc", command]
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe
        try process.run()
        // BOTH pipes drained before waiting. An unread stderr pipe fills its
        // 64K buffer and blocks the child forever -- the deadlock this repo
        // already has a regression test for -- and a login shell's rc files
        // can be noisy. Kept separate rather than merged so that a machine
        // without `claude` still yields empty stdout and skips the test,
        // instead of asserting against "command not found".
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        _ = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Composition with the name flag

    /// --name was added in #63 and is appended at the same call site. Both
    /// flags must survive together, after the wrapper.
    @Test func nameFlagStillAppendedAlongsideSessionId() {
        let state = makeState()
        let session = SessionInfo(
            name: "repo-feature", workingDirectory: "/tmp/wt",
            branchName: "feature", worktreePath: "/tmp/wt"
        )
        state.sessions = [session]

        let command = state.claudeLaunchCommand(for: session).command
        #expect(command.contains("--session-id \(session.id.uuidString)"))
        #expect(command.contains("--name 'repo-feature'"))
    }
}
