import Testing
import Foundation
@testable import Canopy

/// Applying a `claude agents --json` poll to live sessions.
///
/// Tests call `applyAgents` directly with fixture arrays, so nothing here
/// spawns a subprocess or waits on a timer.
@Suite("Agent reconciliation")
@MainActor
struct AgentReconciliationTests {

    private func makeState() -> AppState {
        let state = AppState(configDir: NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)")
        state.settings.sandboxBackend = .off
        // Notifications are guarded on NSApp.isActive; these tests only assert
        // on activity and persisted ids, never on delivery.
        state.settings.notifyOnFinish = false
        state.settings.notifyOnNeedsInput = false
        return state
    }

    /// A session with a live TerminalSession, as the app would have.
    @discardableResult
    private func addSession(
        to state: AppState,
        dir: String,
        backend: SandboxBackend? = nil,
        claudeSessionId: String? = nil
    ) -> SessionInfo {
        let session = SessionInfo(
            name: "s", workingDirectory: dir,
            claudeSessionId: claudeSessionId,
            sandboxBackend: backend
        )
        state.sessions.append(session)
        _ = state.terminalSession(for: session)
        return session
    }

    private func agent(
        cwd: String, sessionId: String = UUID().uuidString,
        status: String?, startedAt: Date = Date().addingTimeInterval(60)
    ) -> ClaudeAgent {
        ClaudeAgent(
            cwd: cwd, sessionId: sessionId, status: status,
            startedAt: startedAt.timeIntervalSince1970 * 1000
        )
    }

    // MARK: - Identity adoption

    /// The reason this exists: createWorktreeSession builds a session with no
    /// claudeSessionId, so the transcript viewer and token counts were dead
    /// for exactly the sessions Canopy creates.
    @Test func adoptsLiveSessionIdForSessionCreatedWithoutOne() {
        let state = makeState()
        let session = addSession(to: state, dir: "/tmp/wt-a")
        let live = UUID().uuidString

        state.applyAgents([agent(cwd: "/tmp/wt-a", sessionId: live, status: "idle")])

        #expect(state.sessions[0].claudeSessionId == live)
        #expect(session.claudeSessionId == nil) // the local copy is stale, by design
    }

    /// A claude the user has had running in that worktree since yesterday is
    /// not this tab's conversation.
    @Test func doesNotAdoptAgentStartedBeforeTheTabOpened() {
        let state = makeState()
        addSession(to: state, dir: "/tmp/wt-b")

        state.applyAgents([agent(
            cwd: "/tmp/wt-b", status: "idle",
            startedAt: Date().addingTimeInterval(-86400)
        )])

        #expect(state.sessions[0].claudeSessionId == nil)
    }

    @Test func doesNotAdoptWhenAmbiguous() {
        let state = makeState()
        addSession(to: state, dir: "/tmp/wt-c")

        state.applyAgents([
            agent(cwd: "/tmp/wt-c", sessionId: "a", status: "busy"),
            agent(cwd: "/tmp/wt-c/sub", sessionId: "b", status: "busy"),
        ])

        #expect(state.sessions[0].claudeSessionId == nil)
        #expect(state.terminalSessions[state.sessions[0].id]?.activity == .idle)
    }

    // MARK: - Sandbox gate

    /// The executable form of the degradation matrix. Both cases use a
    /// MATCHING cwd, so only the backend gate can be what stops them.
    @Test(arguments: [SandboxBackend.dockerSbx, .appleContainer])
    func sandboxedSessionIgnoresAgentData(_ backend: SandboxBackend) {
        let state = makeState()
        addSession(to: state, dir: "/tmp/wt-sbx", backend: backend)

        state.applyAgents([agent(cwd: "/tmp/wt-sbx", status: "waiting")])

        #expect(state.sessions[0].claudeSessionId == nil)
        #expect(state.terminalSessions[state.sessions[0].id]?.activity == .idle)
    }

    // MARK: - Activity

    @Test func waitingStatusSurfacesAsNeedsInput() {
        let state = makeState()
        addSession(to: state, dir: "/tmp/wt-d")

        state.applyAgents([agent(cwd: "/tmp/wt-d", status: "waiting")])

        #expect(state.terminalSessions[state.sessions[0].id]?.activity == .needsInput)
    }

    /// The regression test for the whole feature: a permission prompt keeps
    /// redrawing, and treating those bytes as progress would stomp the state
    /// back to .working every frame.
    @Test func ptyOutputDoesNotClearNeedsInput() {
        let state = makeState()
        addSession(to: state, dir: "/tmp/wt-e")
        state.applyAgents([agent(cwd: "/tmp/wt-e", status: "waiting")])

        let terminal = try! #require(state.terminalSessions[state.sessions[0].id])
        terminal.handleOutputData(Data("redrawing spinner".utf8))

        #expect(terminal.activity == .needsInput)
    }

    /// No agent data at all must leave the existing heuristic untouched --
    /// that fallback is what every unsupported configuration relies on.
    @Test func noAgentDataLeavesPtyHeuristicIntact() {
        let state = makeState()
        addSession(to: state, dir: "/tmp/wt-f")
        let terminal = try! #require(state.terminalSessions[state.sessions[0].id])
        terminal.handleOutputData(Data("output".utf8))
        #expect(terminal.activity == .working)

        state.applyAgents([])

        #expect(terminal.activity == .working)
    }

    /// An absent status (sdk-cli entries) must be "no opinion", not "idle".
    @Test func absentStatusDoesNotOverrideActivity() {
        let state = makeState()
        addSession(to: state, dir: "/tmp/wt-g")
        let terminal = try! #require(state.terminalSessions[state.sessions[0].id])
        terminal.handleOutputData(Data("output".utf8))

        state.applyAgents([agent(cwd: "/tmp/wt-g", status: nil)])

        #expect(terminal.activity == .working)
    }

    // MARK: - Finish edge

    /// Status flaps to idle between tool calls inside a single turn, so one
    /// idle observation is not a turn boundary.
    @Test func singleIdleObservationDoesNotFinish() {
        let state = makeState()
        addSession(to: state, dir: "/tmp/wt-h")
        let terminal = try! #require(state.terminalSessions[state.sessions[0].id])

        state.applyAgents([agent(cwd: "/tmp/wt-h", status: "busy")])
        #expect(terminal.activity == .working)

        state.applyAgents([agent(cwd: "/tmp/wt-h", status: "idle")])
        #expect(terminal.activity == .working)
    }

    @Test func confirmedBusyToIdleFinishes() {
        let state = makeState()
        addSession(to: state, dir: "/tmp/wt-i")
        let terminal = try! #require(state.terminalSessions[state.sessions[0].id])

        state.applyAgents([agent(cwd: "/tmp/wt-i", status: "busy")])
        state.applyAgents([agent(cwd: "/tmp/wt-i", status: "idle")])
        state.applyAgents([agent(cwd: "/tmp/wt-i", status: "idle")])

        #expect(terminal.activity == .justFinished)
    }

    /// An idle flap mid-turn must reset the counter, not accumulate toward a
    /// spurious finish two tool calls later.
    @Test func idleFlapBetweenToolCallsResetsTheCounter() {
        let state = makeState()
        addSession(to: state, dir: "/tmp/wt-j")
        let terminal = try! #require(state.terminalSessions[state.sessions[0].id])

        state.applyAgents([agent(cwd: "/tmp/wt-j", status: "busy")])
        state.applyAgents([agent(cwd: "/tmp/wt-j", status: "idle")])
        state.applyAgents([agent(cwd: "/tmp/wt-j", status: "shell")])
        state.applyAgents([agent(cwd: "/tmp/wt-j", status: "idle")])

        #expect(terminal.activity == .working)
    }

    /// An agent disappearing is `claude` exiting, already handled by
    /// onProcessExit. Firing a finish here would double-notify.
    @Test func doesNotFinishWhenAgentDisappears() {
        let state = makeState()
        addSession(to: state, dir: "/tmp/wt-k")
        let terminal = try! #require(state.terminalSessions[state.sessions[0].id])

        state.applyAgents([agent(cwd: "/tmp/wt-k", status: "busy")])
        state.applyAgents([])
        state.applyAgents([])

        #expect(terminal.activity == .working)
    }

    @Test func confirmsFinishRequiresBothConditions() {
        #expect(!AppState.confirmsFinish(wasWorking: true, consecutiveIdleObservations: 1))
        #expect(AppState.confirmsFinish(wasWorking: true, consecutiveIdleObservations: 2))
        #expect(!AppState.confirmsFinish(wasWorking: false, consecutiveIdleObservations: 5))
    }

    // MARK: - Giving up

    /// .needsInput is sticky against PTY output on purpose, so only
    /// authoritative data can clear it. If the poll gives up while a session
    /// is blocked, nothing else ever would and the tab sits amber forever.
    @Test func abandoningReconciliationReleasesStuckNeedsInput() {
        let state = makeState()
        addSession(to: state, dir: "/tmp/wt-n")
        let terminal = try! #require(state.terminalSessions[state.sessions[0].id])

        state.applyAgents([agent(cwd: "/tmp/wt-n", status: "waiting")])
        #expect(terminal.activity == .needsInput)

        state.abandonAgentReconciliation()
        #expect(terminal.activity == .idle)

        // And the PTY heuristic is back in charge.
        terminal.handleOutputData(Data("output".utf8))
        #expect(terminal.activity == .working)
    }

    /// Per-session bookkeeping must not outlive the session, matching the
    /// other per-session dictionaries cleared in performCloseSession.
    @Test func closingASessionClearsItsIdleBookkeeping() {
        let state = makeState()
        addSession(to: state, dir: "/tmp/wt-o")
        let id = state.sessions[0].id

        state.applyAgents([agent(cwd: "/tmp/wt-o", status: "idle")])
        #expect(state.agentIdleObservations[id] != nil)

        state.performCloseSession(id: id)
        #expect(state.agentIdleObservations[id] == nil)
    }

    // MARK: - Persistence

    /// saveSessions does an atomic file write. A 2-second loop must not
    /// rewrite it 1800 times an hour.
    @Test func persistsOnlyWhenSessionIdChanges() {
        let state = makeState()
        let known = UUID().uuidString
        addSession(to: state, dir: "/tmp/wt-l", claudeSessionId: known)

        state.applyAgents([agent(cwd: "/tmp/wt-l", sessionId: known, status: "idle")])
        #expect(state.sessions[0].claudeSessionId == known)
    }

    /// The authoritative state must cancel the PTY timers, or the 5-second
    /// silence timer would still fire .justFinished over a live .needsInput.
    @Test func authoritativeStatusCancelsThePtySilenceTimer() async throws {
        let state = makeState()
        addSession(to: state, dir: "/tmp/wt-m")
        let terminal = try #require(state.terminalSessions[state.sessions[0].id])

        terminal.handleOutputData(Data("starting".utf8))  // arms the 5s timer
        state.applyAgents([agent(cwd: "/tmp/wt-m", status: "waiting")])
        #expect(terminal.activity == .needsInput)

        // Well short of the 5s timer, but proves the state survives a tick.
        try await Task.sleep(for: .milliseconds(50))
        #expect(terminal.activity == .needsInput)
    }

    /// "Two consecutive idle polls" must mean consecutive. A poll with no
    /// opinion (absent or unknown status) between two idles is a gap, and
    /// pairing across it would confirm a finish that never happened.
    @Test func opinionlessPollResetsTheIdleCounter() {
        let state = makeState()
        addSession(to: state, dir: "/tmp/wt-t")
        let terminal = try! #require(state.terminalSessions[state.sessions[0].id])

        state.applyAgents([agent(cwd: "/tmp/wt-t", status: "busy")])
        state.applyAgents([agent(cwd: "/tmp/wt-t", status: "idle")])
        state.applyAgents([agent(cwd: "/tmp/wt-t", status: nil)])   // no opinion
        state.applyAgents([agent(cwd: "/tmp/wt-t", status: "idle")])

        // Without the reset this reaches two idles and fires .justFinished.
        #expect(terminal.activity == .working)
    }

    // MARK: - Review findings

    /// Quitting claude back to the shell prompt makes the agent vanish while
    /// the PTY lives on, so onProcessExit never fires. .needsInput is sticky
    /// against PTY output, so without an explicit handback the tab sat amber
    /// -- and counted in "N need input" -- for the rest of the app's life.
    @Test func agentDisappearingReleasesStuckNeedsInput() {
        let state = makeState()
        addSession(to: state, dir: "/tmp/wt-p")
        let terminal = try! #require(state.terminalSessions[state.sessions[0].id])

        state.applyAgents([agent(cwd: "/tmp/wt-p", status: "waiting")])
        #expect(terminal.activity == .needsInput)

        state.applyAgents([])
        #expect(terminal.activity == .idle)
    }

    /// Same hole via the other skip path: a second claude in the directory
    /// makes the match ambiguous, and ambiguity must not mean "stay amber".
    @Test func ambiguousMatchReleasesStuckNeedsInput() {
        let state = makeState()
        addSession(to: state, dir: "/tmp/wt-q")
        let terminal = try! #require(state.terminalSessions[state.sessions[0].id])

        state.applyAgents([agent(cwd: "/tmp/wt-q", status: "waiting")])
        #expect(terminal.activity == .needsInput)

        state.applyAgents([
            agent(cwd: "/tmp/wt-q", sessionId: "a", status: "waiting"),
            agent(cwd: "/tmp/wt-q/sub", sessionId: "b", status: "busy"),
        ])
        #expect(terminal.activity == .idle)
    }

    /// .claudeNative runs claude as an ordinary host process -- Seatbelt
    /// confines Bash, not the process's registry entry. Gating literally on
    /// .off silently removed the whole needs-input feature from the backend
    /// this milestone promotes.
    @Test func claudeNativeSessionIsReconciled() {
        let state = makeState()
        addSession(to: state, dir: "/tmp/wt-r", backend: .claudeNative)
        let live = UUID().uuidString

        state.applyAgents([agent(cwd: "/tmp/wt-r", sessionId: live, status: "waiting")])

        #expect(state.sessions[0].claudeSessionId == live)
        #expect(state.terminalSessions[state.sessions[0].id]?.activity == .needsInput)
    }

    /// An established id is user data -- the principle loadSessions was
    /// hardened around. Replacing it here would reintroduce the same hijack:
    /// the tab's claude exits, the user runs a plain `claude` in that
    /// worktree, and Canopy --resumes into a stranger's conversation.
    @Test func doesNotReplaceAnEstablishedSessionId() {
        let state = makeState()
        let owned = UUID().uuidString
        addSession(to: state, dir: "/tmp/wt-s", claudeSessionId: owned)

        state.applyAgents([agent(cwd: "/tmp/wt-s", sessionId: "stranger", status: "idle")])

        #expect(state.sessions[0].claudeSessionId == owned)
    }


    // MARK: - Poll gating

    /// The poll skips its subprocess entirely when nothing could be
    /// reconciled. On a 2-second loop that is the difference between an idle
    /// app and one spawning a process every 2 seconds for no reason.
    @Test func pollIsSkippedWhenNoSessionQualifies() {
        let state = makeState()
        #expect(!state.hasReconcilableSessions)          // no sessions at all

        addSession(to: state, dir: "/tmp/wt-v", backend: .appleContainer)
        #expect(!state.hasReconcilableSessions)          // sandboxed: invisible to the host

        addSession(to: state, dir: "/tmp/wt-w", backend: .dockerSbx)
        #expect(!state.hasReconcilableSessions)

        addSession(to: state, dir: "/tmp/wt-x")          // .off
        #expect(state.hasReconcilableSessions)
    }

}
