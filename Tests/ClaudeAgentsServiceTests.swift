import Testing
import Foundation
@testable import Canopy

/// `claude agents --json` reports every live `claude` process on the machine.
/// Canopy uses it to answer two questions it previously guessed at:
/// which conversation a tab is running, and whether that conversation is busy,
/// idle, or blocked waiting on the user.
///
/// Fixtures are literal JSON copied from real output, including a real
/// status-less sdk-cli entry (3 of 11 live entries had no `status` key when
/// this was written).
@Suite("ClaudeAgentsService")
struct ClaudeAgentsServiceTests {

    private func data(_ json: String) -> Data { Data(json.utf8) }

    // MARK: - Parsing

    // MARK: - Disambiguating by adopted process

    /// Two claudes under one directory normally make the tab give up, because
    /// picking the wrong one binds it to a stranger's transcript. Once a tab
    /// knows which process it took its id from, that set is no longer
    /// ambiguous *to that tab* -- and giving up costs it a `/clear` it would
    /// otherwise follow, plus its live status.
    @Test func prefersTheAdoptedProcessAmongAmbiguousMatches() {
        let mine = ClaudeProcessIdentity(pid: 4242, startedAt: 1_000)
        let agents = [
            ClaudeAgent(cwd: "/tmp/wt", sessionId: "theirs", status: "busy",
                        startedAt: 2_000, pid: 9999),
            ClaudeAgent(cwd: "/tmp/wt", sessionId: "mine", status: "idle",
                        startedAt: 1_000, pid: 4242),
        ]

        let match = ClaudeAgentsService.agent(forWorktree: "/tmp/wt", in: agents, preferring: mine)

        guard case .one(let picked) = match else {
            Issue.record("expected .one, got \(match)"); return
        }
        #expect(picked.sessionId == "mine")
    }

    /// Without an adopted process there is nothing to prefer, so the original
    /// behaviour stands: Canopy cannot know which is the tab's.
    @Test func staysAmbiguousWithNoAdoptedProcess() {
        let agents = [
            ClaudeAgent(cwd: "/tmp/wt", sessionId: "a", status: "busy", startedAt: 1_000, pid: 1),
            ClaudeAgent(cwd: "/tmp/wt", sessionId: "b", status: "busy", startedAt: 2_000, pid: 2),
        ]

        #expect(ClaudeAgentsService.agent(forWorktree: "/tmp/wt", in: agents, preferring: nil)
                == .ambiguous)
    }

    /// The tab's own process is gone and two strangers remain. Preferring an
    /// identity that matches none of them must not pick one at random.
    @Test func staysAmbiguousWhenTheAdoptedProcessIsAbsent() {
        let mine = ClaudeProcessIdentity(pid: 4242, startedAt: 1_000)
        let agents = [
            ClaudeAgent(cwd: "/tmp/wt", sessionId: "a", status: "busy", startedAt: 5_000, pid: 7),
            ClaudeAgent(cwd: "/tmp/wt", sessionId: "b", status: "busy", startedAt: 6_000, pid: 8),
        ]

        #expect(ClaudeAgentsService.agent(forWorktree: "/tmp/wt", in: agents, preferring: mine)
                == .ambiguous)
    }

    /// A single match is still a single match; preferring must not turn a
    /// lone stranger into "ours" just because our own process is missing.
    @Test func aLoneAgentIsStillReturnedRegardlessOfPreference() {
        let mine = ClaudeProcessIdentity(pid: 4242, startedAt: 1_000)
        let agents = [
            ClaudeAgent(cwd: "/tmp/wt", sessionId: "only", status: "busy", startedAt: 9_000, pid: 7)
        ]

        guard case .one(let picked) = ClaudeAgentsService.agent(
            forWorktree: "/tmp/wt", in: agents, preferring: mine
        ) else { Issue.record("expected .one"); return }
        #expect(picked.sessionId == "only")
    }

    /// The /clear fix hangs entirely on this field being read: a re-keyed
    /// session is only adopted when the reporting process is provably the one
    /// Canopy adopted from, and `pid` is half that proof. If the key were
    /// spelled wrong or the field dropped, every ownership check would fail
    /// closed and the fix would silently do nothing.
    ///
    /// Literal JSON from real `claude agents --json` output, including the
    /// interactive entry's neighbouring `background` entry, which carries no
    /// `pid` at all.
    @Test func decodesPidAndBuildsAProcessIdentity() throws {
        let json = """
        [
          {"id":"63401c10","cwd":"/Users/j/demo","kind":"background",
           "startedAt":1787303896140,"sessionId":"63401c10-479f-44f5-8f5b-16deccd5886a",
           "name":"Fork demo","state":"blocked"},
          {"pid":18001,"cwd":"/Users/j/site","kind":"interactive",
           "startedAt":1787427887639,"sessionId":"52109c55-b4b2-4186-9ee4-14d651577ffb",
           "name":"master","status":"busy"}
        ]
        """
        let agents = try #require(ClaudeAgentsService.parse(data(json)))
        #expect(agents.count == 2)

        let interactive = try #require(agents.first { $0.sessionId.hasPrefix("52109c55") })
        #expect(interactive.pid == 18001)
        let identity = try #require(interactive.processIdentity)
        #expect(identity == ClaudeProcessIdentity(pid: 18001, startedAt: 1787427887639))

        // A background entry reports no pid, so it can prove no ownership.
        let background = try #require(agents.first { $0.sessionId.hasPrefix("63401c10") })
        #expect(background.pid == nil)
        #expect(background.processIdentity == nil)
    }

    @Test func parsesRealWorldArray() throws {
        let agents = try #require(ClaudeAgentsService.parse(data("""
        [
          {"pid":69798,"cwd":"/Users/julien/Development/canopy","kind":"interactive",
           "startedAt":1786035803954,"sessionId":"28619ed8-8eb5-4461-883b-b9dc15f2a591",
           "name":"canopy-b5","status":"busy"},
          {"pid":21880,"cwd":"/Users/julien/Development/repos/ghost","kind":"interactive",
           "startedAt":1785410059006,"sessionId":"4927529c-7991-4eaf-a9c3-d40e876ed2ee",
           "name":"ghost-20","status":"idle"}
        ]
        """)))

        #expect(agents.count == 2)
        #expect(agents[0].sessionId == "28619ed8-8eb5-4461-883b-b9dc15f2a591")
        #expect(agents[0].cwd == "/Users/julien/Development/canopy")
        #expect(agents[0].status == "busy")
        #expect(agents[0].startedAt == 1786035803954)
    }

    /// sdk-cli entries carry no `status` key at all. One odd entry must never
    /// blind Canopy to every other session, so `status` is optional -- this
    /// fails the moment someone makes it required.
    @Test func missingStatusDecodesRatherThanFailing() throws {
        let agents = try #require(ClaudeAgentsService.parse(data("""
        [
          {"pid":18660,"cwd":"/Users/julien/.claude-mem/observer-sessions",
           "kind":"interactive","startedAt":1786096015426,
           "sessionId":"0a61d62b-4b0b-45ff-ae63-c3cdd94b5c88","name":"observer-sessions-e1"},
          {"pid":1,"cwd":"/tmp/wt","sessionId":"abc","status":"idle"}
        ]
        """)))

        #expect(agents.count == 2)
        #expect(agents[0].status == nil)
        #expect(agents[1].status == "idle")
    }

    @Test func unknownStatusValueDoesNotFailDecode() throws {
        let agents = try #require(ClaudeAgentsService.parse(data(
            #"[{"cwd":"/tmp/wt","sessionId":"abc","status":"teleporting"}]"#
        )))
        #expect(agents[0].status == "teleporting")
    }

    /// An old CLI prints usage text; a missing one prints a shell error.
    /// Either must be DETECTED, never read as "zero sessions running" --
    /// that would push every tab to a wrong state at once.
    @Test(arguments: [
        "command not found: claude",
        #"{"error":"nope"}"#,
        "",
        "Usage: claude [options]",
    ])
    func nonArrayOutputReturnsNil(_ junk: String) {
        #expect(ClaudeAgentsService.parse(data(junk)) == nil)
    }

    /// An empty array is a real answer -- no claude running -- and must be
    /// distinguishable from a failure.
    @Test func emptyArrayIsNotAFailure() {
        #expect(ClaudeAgentsService.parse(data("[]")) == [])
    }

    // MARK: - Matching

    private func agent(cwd: String, sessionId: String = "s", status: String? = "idle",
                       startedAt: Double? = 0) -> ClaudeAgent {
        ClaudeAgent(cwd: cwd, sessionId: sessionId, status: status, startedAt: startedAt, pid: nil)
    }

    @Test func matchesExactWorktreePath() {
        let match = ClaudeAgentsService.agent(forWorktree: "/tmp/wt", in: [agent(cwd: "/tmp/wt")])
        #expect(match == .one(agent(cwd: "/tmp/wt")))
    }

    /// `--cwd` semantics are "at or under", so a claude started in a
    /// subdirectory of the worktree still belongs to that tab.
    @Test func matchesSessionStartedInSubdirectory() {
        let match = ClaudeAgentsService.agent(forWorktree: "/tmp/wt", in: [agent(cwd: "/tmp/wt/src")])
        if case .one = match {} else { Issue.record("expected .one, got \(match)") }
    }

    /// Prefix matching must not run upward: a claude in the PARENT directory
    /// is a different session, and adopting its id would resume the wrong
    /// transcript.
    @Test func doesNotMatchParentDirectory() {
        #expect(ClaudeAgentsService.agent(forWorktree: "/tmp/wt", in: [agent(cwd: "/tmp")]) == .none)
    }

    /// Nor a sibling whose name merely starts with the same characters.
    @Test func doesNotMatchSiblingWithSharedPrefix() {
        #expect(ClaudeAgentsService.agent(forWorktree: "/tmp/wt", in: [agent(cwd: "/tmp/wt-other")]) == .none)
    }

    /// /tmp is a symlink to /private/tmp on macOS and claude reports the
    /// resolved cwd, so both sides must be resolved before comparing.
    @Test func matchesThroughSymlinkedPath() throws {
        let dir = "/tmp/canopy-agents-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let resolved = SandboxBackend.realResolvedPath(dir)
        #expect(resolved.hasPrefix("/private/tmp"))

        let match = ClaudeAgentsService.agent(forWorktree: dir, in: [agent(cwd: resolved)])
        if case .one = match {} else { Issue.record("symlinked path did not match") }
    }

    /// A split terminal, or the user starting a second claude by hand, puts
    /// two agents in one directory. Canopy cannot know which one is this
    /// tab's, and guessing would resume the wrong transcript -- so it must
    /// say so and keep the existing behaviour.
    @Test func twoAgentsInSameCwdIsAmbiguous() {
        let match = ClaudeAgentsService.agent(forWorktree: "/tmp/wt", in: [
            agent(cwd: "/tmp/wt", sessionId: "a"),
            agent(cwd: "/tmp/wt/sub", sessionId: "b"),
        ])
        #expect(match == .ambiguous)
    }

    @Test func noMatchReturnsNone() {
        #expect(ClaudeAgentsService.agent(forWorktree: "/tmp/wt", in: []) == .none)
    }

    // MARK: - Status mapping

    @Test func busyMapsToWorking() {
        #expect(ClaudeAgentsService.activity(for: "busy") == .working)
    }

    /// `shell` means a Bash tool call is running -- still working, not idle.
    @Test func shellMapsToWorking() {
        #expect(ClaudeAgentsService.activity(for: "shell") == .working)
    }

    /// The whole point of this service: claude reports `waiting` when it is
    /// blocked on a dialog, which includes permission prompts. The PTY goes
    /// silent in exactly that situation, which is why the 5-second heuristic
    /// declared the session finished mid-turn.
    @Test func waitingMapsToNeedsInput() {
        #expect(ClaudeAgentsService.activity(for: "waiting") == .needsInput)
    }

    @Test func idleMapsToIdle() {
        #expect(ClaudeAgentsService.activity(for: "idle") == .idle)
    }

    /// The most important mapping in the suite: conflating "unknown" with
    /// "idle" would fire a false finish notification for every sdk-cli entry
    /// and every status value the CLI adds later. No opinion means the PTY
    /// heuristic keeps running.
    @Test func absentStatusMapsToNilNotIdle() {
        #expect(ClaudeAgentsService.activity(for: nil) == nil)
    }

    @Test func unknownStatusMapsToNil() {
        #expect(ClaudeAgentsService.activity(for: "teleporting") == nil)
    }

    // MARK: - fetch (the impure edge)

    /// Runs the real subprocess path: shell resolution, spawn, watchdog,
    /// drain-before-wait, and parse. Deliberately tolerant of the outcome,
    /// because it legitimately differs by machine -- a developer box has
    /// `claude` on PATH and gets an array, a CI runner does not and gets nil.
    /// What it pins is that BOTH are handled: no hang, no crash, and never a
    /// half-decoded entry.
    @Test func fetchCompletesAndReturnsNilOrWellFormedAgents() async {
        let started = Date()
        let result = await ClaudeAgentsService.fetch()
        let elapsed = Date().timeIntervalSince(started)

        // The watchdog terminates at 5s; anything beyond that means it hung.
        #expect(elapsed < 15, "fetch() took \(elapsed)s -- watchdog did not fire")

        guard let agents = result else { return }   // claude not installed: valid
        for agent in agents {
            #expect(!agent.cwd.isEmpty)
            #expect(!agent.sessionId.isEmpty)
        }
    }

    /// Second call must be cheap: the resolved claude path is cached, so this
    /// exercises the cache-hit branch rather than re-resolving through a
    /// login shell.
    @Test func fetchIsRepeatableAndUsesTheCachedPath() async {
        _ = await ClaudeAgentsService.fetch()
        let started = Date()
        _ = await ClaudeAgentsService.fetch()
        #expect(Date().timeIntervalSince(started) < 15)
    }

    // MARK: - Review findings

    /// One undecodable entry must not blind Canopy to every other session.
    /// Decoding the array as a whole meant a single future entry without
    /// `cwd` returned nil for the entire poll -- and three such polls in a
    /// row permanently disable reconciliation.
    @Test func oneUndecodableElementDoesNotDiscardTheRest() throws {
        let agents = try #require(ClaudeAgentsService.parse(data("""
        [
          {"cwd":"/tmp/wt","sessionId":"good-1","status":"busy"},
          {"kind":"some-future-thing","startedAt":123},
          {"cwd":"/tmp/other","sessionId":"good-2","status":"idle"}
        ]
        """)))

        #expect(agents.map(\.sessionId) == ["good-1", "good-2"])
    }

    /// Still a hard failure, not an empty result: a non-array must remain
    /// distinguishable from "no claude running".
    @Test func nonArrayStillReturnsNilAfterPerElementDecoding() {
        #expect(ClaudeAgentsService.parse(data(#"{"cwd":"/tmp","sessionId":"x"}"#)) == nil)
    }

}
