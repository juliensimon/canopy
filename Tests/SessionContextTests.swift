import Testing
import Foundation
@testable import Canopy

/// Live context size is a *different reduction* over the same JSONL fields that
/// `SessionCostService.parseTokenUsage` already reads. Cost sums every turn's
/// `cache_read_input_tokens`; context is only the newest turn's. Conflating the
/// two reports a number several times too large, so these tests pin the
/// distinction rather than merely checking that some integer comes back.
@Suite("Session context — parsing")
struct SessionContextParsingTests {

    // MARK: - Helpers

    /// One assistant entry. `effort` is TOP-LEVEL, a sibling of `type` -- not
    /// inside `message` (see ClaudeTranscriptLoader.swift's verified note).
    private func assistantLine(
        model: String = "claude-opus-5",
        effort: String? = "high",
        input: Int = 0,
        cacheCreation: Int = 0,
        cacheRead: Int = 0,
        output: Int = 0
    ) -> String {
        let effortField = effort.map { #""effort":"\#($0)","# } ?? ""
        return """
        {"type":"assistant",\(effortField)"message":{"role":"assistant","model":"\(model)","usage":{"input_tokens":\(input),"cache_creation_input_tokens":\(cacheCreation),"cache_read_input_tokens":\(cacheRead),"output_tokens":\(output)}}}
        """
    }

    // MARK: - The last turn, not the sum

    /// The whole reason this function exists next to `parseTokenUsage`. If
    /// someone routes context through the cost parser, this fails: 100 is the
    /// newest turn, 160 is the running total, and only one of them is context.
    @Test func reportsTheNewestTurnNotTheRunningTotal() {
        let jsonl = [
            assistantLine(input: 10, cacheCreation: 20, cacheRead: 30),
            assistantLine(input: 1, cacheCreation: 2, cacheRead: 97),
        ].joined(separator: "\n")

        let context = SessionCostService.parseLastTurnContext(from: jsonl)

        #expect(context?.contextTokens == 100)
        #expect(context?.contextTokens != 160, "summed across turns -- that is cost, not context")
    }

    /// Context is everything the model had to read: fresh input plus both cache
    /// tiers. Reading `input_tokens` alone under-reports by orders of magnitude
    /// on a warm session, which is exactly when the number matters.
    @Test func sumsFreshInputAndBothCacheTiers() {
        let jsonl = assistantLine(input: 5, cacheCreation: 50, cacheRead: 500)

        let context = SessionCostService.parseLastTurnContext(from: jsonl)

        #expect(context?.contextTokens == 555)
    }

    /// Output tokens are spend, not context: they are not in the window the
    /// next turn has to read.
    @Test func excludesOutputTokens() {
        let jsonl = assistantLine(input: 1, output: 9999)

        #expect(SessionCostService.parseLastTurnContext(from: jsonl)?.contextTokens == 1)
    }

    // MARK: - Attribution

    @Test func reportsModelAndEffortOfTheNewestTurn() {
        let jsonl = [
            assistantLine(model: "claude-sonnet-5", effort: "low", input: 1),
            assistantLine(model: "claude-opus-5", effort: "xhigh", input: 2),
        ].joined(separator: "\n")

        let context = SessionCostService.parseLastTurnContext(from: jsonl)

        #expect(context?.model == "claude-opus-5")
        #expect(context?.effort == "xhigh")
    }

    /// CLIs older than ~2.1.212 emit no `effort`, and several models have no
    /// effort concept at all. That is a half-populated valid state, not a parse
    /// failure -- the context number must still come through.
    @Test func missingEffortStillYieldsContext() {
        let jsonl = assistantLine(effort: nil, input: 7, cacheRead: 3)

        let context = SessionCostService.parseLastTurnContext(from: jsonl)

        #expect(context?.effort == nil)
        #expect(context?.contextTokens == 10)
    }

    // MARK: - Entries that must not win

    /// `<synthetic>` is Claude Code's own error/interrupt row, not a real turn.
    /// It trails the real entry, so taking "the last assistant line" naively
    /// would report the wrong turn -- or zero.
    @Test func syntheticEntriesFallThroughToTheRealTurn() {
        let jsonl = [
            assistantLine(model: "claude-opus-5", input: 42),
            #"{"type":"assistant","message":{"role":"assistant","model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0}}}"#,
        ].joined(separator: "\n")

        let context = SessionCostService.parseLastTurnContext(from: jsonl)

        #expect(context?.model == "claude-opus-5")
        #expect(context?.contextTokens == 42)
    }

    /// A transcript almost always ends with user/tool-result rows after the
    /// last assistant turn -- that is the normal shape while Claude is working.
    @Test func trailingUserAndSystemEntriesAreIgnored() {
        let jsonl = [
            assistantLine(input: 8),
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"go on"}]}}"#,
            #"{"type":"system","content":"hook fired"}"#,
        ].joined(separator: "\n")

        #expect(SessionCostService.parseLastTurnContext(from: jsonl)?.contextTokens == 8)
    }

    /// Assistant rows without a `usage` dict exist (streamed partials, some
    /// harness rows). They carry no context figure, so they must not shadow the
    /// last row that does.
    @Test func assistantEntriesWithoutUsageDoNotShadowTheLastRealTurn() {
        let jsonl = [
            assistantLine(input: 64),
            #"{"type":"assistant","message":{"role":"assistant","model":"claude-opus-5","content":[]}}"#,
        ].joined(separator: "\n")

        #expect(SessionCostService.parseLastTurnContext(from: jsonl)?.contextTokens == 64)
    }

    /// The reader rejects non-assistant lines on a substring marker before
    /// paying for JSON parsing. That marker is a pre-filter, not the decision.
    /// A transcript pasted into a tool result quotes it verbatim, which is not
    /// hypothetical in this repo, and such an entry must still lose to the real
    /// assistant turn behind it.
    ///
    /// Honest scope: this survives deleting the `type` check on its own,
    /// because the entry is also rejected for having no `message.usage`. It
    /// pins the outcome -- no false positive from the fast path -- rather than
    /// any single guard.
    @Test func aUserEntryQuotingTheAssistantMarkerDoesNotWin() {
        let jsonl = [
            assistantLine(model: "claude-opus-5", input: 33),
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"pasted a transcript: {"type":"assistant","message":{}}"}]}}"#,
        ].joined(separator: "\n")

        let context = SessionCostService.parseLastTurnContext(from: jsonl)

        #expect(context?.model == "claude-opus-5")
        #expect(context?.contextTokens == 33)
    }

    // MARK: - Nothing to report

    @Test func emptyContentYieldsNil() {
        #expect(SessionCostService.parseLastTurnContext(from: "") == nil)
    }

    /// Malformed lines are routine: the reader hands this function a window cut
    /// mid-file, and Claude Code can be killed mid-write. Skip, never crash.
    @Test func malformedLinesAreSkippedNotFatal() {
        let jsonl = [
            "not json at all",
            #"{"type":"assistant","message":{"model":"claude-opus-5","usage":{"input_toke"#,
            assistantLine(input: 3),
        ].joined(separator: "\n")

        #expect(SessionCostService.parseLastTurnContext(from: jsonl)?.contextTokens == 3)
    }

    @Test func contentWithNoAssistantTurnYieldsNil() {
        let jsonl = #"{"type":"user","message":{"role":"user","content":[]}}"#

        #expect(SessionCostService.parseLastTurnContext(from: jsonl) == nil)
    }
}


/// The reader that feeds the parser above. Transcripts in `~/.claude/projects`
/// were measured at 14 MB / 3726 lines, and this is polled -- so it scans
/// backwards from EOF rather than reading the file forwards. The awkward part
/// is that entry sizes are wildly asymmetric: assistant entries top out around
/// 19 KB, but a single *user* entry carrying a large tool result was measured
/// at 1.36 MB. A fixed tail window steps straight over the assistant entry
/// behind one of those and reports nothing.
@Suite("Session context — backwards reader")
struct SessionContextReaderTests {

    private func tempJSONL(_ lines: [String]) -> String {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("canopy-context-\(UUID().uuidString).jsonl")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    private func assistantLine(input: Int) -> String {
        """
        {"type":"assistant","effort":"high","message":{"role":"assistant","model":"claude-opus-5","usage":{"input_tokens":\(input),"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}}
        """
    }

    /// A user entry of a given payload size, standing in for a large tool result.
    private func bulkyUserLine(bytes: Int) -> String {
        """
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":"\(String(repeating: "x", count: bytes))"}]}}
        """
    }

    @Test func readsTheLastTurnFromASmallFile() {
        let path = tempJSONL([assistantLine(input: 11), assistantLine(input: 22)])
        defer { try? FileManager.default.removeItem(atPath: path) }

        let context = SessionCostService.lastTurnContext(path: path)

        #expect(context?.contextTokens == 22)
        #expect(context?.model == "claude-opus-5")
        #expect(context?.effort == "high")
    }

    /// The measurement that shapes the whole design, at default settings: a
    /// 1.5 MB user entry sits between EOF and the newest assistant turn, so any
    /// single fixed 256 KB tail read returns nil here.
    @Test func findsTheTurnBehindAMultiMegabyteUserEntry() {
        let path = tempJSONL([
            assistantLine(input: 777),
            bulkyUserLine(bytes: 1_500_000),
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        #expect(SessionCostService.lastTurnContext(path: path)?.contextTokens == 777)
    }

    /// Every window but the last starts mid-entry. A cut entry is invalid JSON
    /// and gets skipped, so the window simply grows -- but it must land on the
    /// *newest* turn, not the one before it, and not nil.
    @Test func aWindowCuttingMidEntryStillResolvesToTheNewestTurn() {
        let path = tempJSONL([assistantLine(input: 1), assistantLine(input: 222)])
        defer { try? FileManager.default.removeItem(atPath: path) }

        // Tiny chunk: the first several windows all begin part-way through the
        // final entry.
        let context = SessionCostService.lastTurnContext(path: path, chunkBytes: 50)

        #expect(context?.contextTokens == 222)
    }

    /// This runs on a timer against a path that may not exist yet -- a session
    /// whose Claude run has not written a transcript. It must be quiet.
    @Test func missingFileYieldsNilWithoutThrowing() {
        let path = NSTemporaryDirectory() + "canopy-absent-\(UUID().uuidString).jsonl"

        #expect(SessionCostService.lastTurnContext(path: path) == nil)
    }

    @Test func emptyFileYieldsNil() {
        let path = tempJSONL([])
        defer { try? FileManager.default.removeItem(atPath: path) }

        #expect(SessionCostService.lastTurnContext(path: path) == nil)
    }

    @Test func fileWithNoAssistantTurnYieldsNil() {
        let path = tempJSONL([bulkyUserLine(bytes: 10)])
        defer { try? FileManager.default.removeItem(atPath: path) }

        #expect(SessionCostService.lastTurnContext(path: path) == nil)
    }

    /// The scan is bounded so a pathological transcript cannot turn a 10 s poll
    /// into a full read of a 14 MB file. Past the cap it gives up rather than
    /// escalating.
    @Test func stopsAtMaxScanBytesInsteadOfReadingTheWholeFile() {
        let path = tempJSONL([
            assistantLine(input: 5),
            bulkyUserLine(bytes: 40_000),
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        let capped = SessionCostService.lastTurnContext(
            path: path, chunkBytes: 256, maxScanBytes: 1024
        )
        #expect(capped == nil)

        // Same file, cap lifted -- proves the nil above is the cap talking and
        // not a broken fixture.
        let uncapped = SessionCostService.lastTurnContext(
            path: path, chunkBytes: 256, maxScanBytes: 1_000_000
        )
        #expect(uncapped?.contextTokens == 5)
    }
}


/// The strings the status bar actually shows. Kept as pure statics on the view
/// so they are assertable without a view host -- the same shape as
/// `ProjectDetailView.collisionSummaryText`.
@Suite("Session context — status bar label")
struct SessionContextLabelTests {

    @Test func rendersModelEffortAndAbbreviatedContext() {
        let label = StatusBar.contextLabel(
            SessionContext(model: "claude-opus-5", effort: "high", contextTokens: 71_338)
        )

        #expect(label == "opus-5 · high · 71.3K")
    }

    /// Several models have no effort concept, and older CLIs emit none. The
    /// label drops the missing half rather than showing a gap or a placeholder.
    @Test func omitsEffortWhenAbsent() {
        let label = StatusBar.contextLabel(
            SessionContext(model: "claude-sonnet-5", effort: nil, contextTokens: 2_000)
        )

        #expect(label == "sonnet-5 · 2.0K")
    }

    @Test func showsContextAloneWhenTheTurnCarriesNoAttribution() {
        let label = StatusBar.contextLabel(
            SessionContext(model: nil, effort: nil, contextTokens: 1_500_000)
        )

        #expect(label == "1.5M")
    }

    /// Every other segment in this bar is wrapped in an `if` and disappears
    /// when it has nothing to say. A "0" or an empty segment would be noise in
    /// a 24pt bar that already carries five of them.
    @Test func yieldsNilWhenThereIsNothingToShow() {
        #expect(StatusBar.contextLabel(
            SessionContext(model: nil, effort: nil, contextTokens: 0)
        ) == nil)
    }

    @Test func showsAttributionAloneWhenTheTurnReportedNoTokens() {
        let label = StatusBar.contextLabel(
            SessionContext(model: "claude-opus-5", effort: "xhigh", contextTokens: 0)
        )

        #expect(label == "opus-5 · xhigh")
    }

    /// The segment is abbreviated to fit; the exact figure has to be reachable
    /// somewhere, or the number cannot be checked against anything.
    @Test func tooltipCarriesTheUnabbreviatedCount() {
        let tooltip = StatusBar.contextTooltip(
            SessionContext(model: "claude-opus-5", effort: "high", contextTokens: 71_338)
        )

        #expect(tooltip.contains(71_338.formatted()))
        #expect(!tooltip.contains("71.3K"))
        #expect(tooltip.contains("claude-opus-5"))
        #expect(tooltip.contains("high"))
    }

    /// No percentage anywhere: `claude-opus-5` and `claude-opus-5[1m]` are
    /// indistinguishable in the transcript, so a "% of window" figure would be
    /// silently 5x wrong for long-context sessions.
    @Test func neitherLabelNorTooltipClaimsAPercentage() {
        let context = SessionContext(model: "claude-opus-5", effort: "high", contextTokens: 71_338)

        #expect(StatusBar.contextLabel(context)?.contains("%") == false)
        #expect(!StatusBar.contextTooltip(context).contains("%"))
    }
}


/// Wiring: the bar reads one published property, refreshed on the existing
/// 10 s git poll. Isolated with `AppState(configDir:)` so it never touches the
/// developer's real ~/.config/canopy, and keyed on a unique working directory
/// so the seeded transcript cannot collide with a real one.
@Suite("Session context — AppState")
@MainActor
struct SessionContextAppStateTests {

    private let fm = FileManager.default

    private func tempConfigDir() -> String {
        NSTemporaryDirectory() + "canopy-ctx-config-\(UUID().uuidString)"
    }

    /// Seeds a transcript where Claude Code would write one, for a working
    /// directory that exists nowhere else.
    private func makeWorkingDirWithTranscript(
        claudeSessionId: String, lines: [String]
    ) throws -> String {
        let workingDirectory = NSTemporaryDirectory() + "canopy-ctx-wd-\(UUID().uuidString)"
        try fm.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true)
        let transcript = ClaudeTranscriptLoader.sessionFilePath(
            workingDirectory: workingDirectory, sessionId: claudeSessionId
        )
        try fm.createDirectory(
            atPath: (transcript as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try lines.joined(separator: "\n").write(toFile: transcript, atomically: true, encoding: .utf8)
        return workingDirectory
    }

    private func cleanUp(workingDirectory: String, claudeSessionId: String) {
        let transcript = ClaudeTranscriptLoader.sessionFilePath(
            workingDirectory: workingDirectory, sessionId: claudeSessionId
        )
        try? fm.removeItem(atPath: (transcript as NSString).deletingLastPathComponent)
        try? fm.removeItem(atPath: workingDirectory)
    }

    private let assistantLine = """
    {"type":"assistant","effort":"xhigh","message":{"role":"assistant","model":"claude-opus-5","usage":{"input_tokens":100,"cache_creation_input_tokens":200,"cache_read_input_tokens":700,"output_tokens":9}}}
    """

    @Test func activeSessionTranscriptPopulatesContext() async throws {
        let claudeSessionId = UUID().uuidString
        let workingDirectory = try makeWorkingDirWithTranscript(
            claudeSessionId: claudeSessionId, lines: [assistantLine]
        )
        let configDir = tempConfigDir()
        defer {
            cleanUp(workingDirectory: workingDirectory, claudeSessionId: claudeSessionId)
            try? fm.removeItem(atPath: configDir)
        }

        let state = AppState(configDir: configDir)
        state.createSession(name: "ctx", directory: workingDirectory)
        state.activeSessionId = state.sessions[0].id
        state.assignClaudeSessionId(claudeSessionId, to: state.sessions[0].id)

        await state.refreshActiveSessionContext()

        #expect(state.activeSessionContext?.contextTokens == 1000)
        #expect(state.activeSessionContext?.model == "claude-opus-5")
        #expect(state.activeSessionContext?.effort == "xhigh")
    }

    /// A session that has never launched Claude has no session id to look up.
    /// It must report nothing rather than guessing at the newest transcript in
    /// the directory -- that would show an unrelated `claude` run started
    /// outside Canopy, the same trap TranscriptSheet documents.
    @Test func sessionWithoutClaudeSessionIdReportsNoContext() async throws {
        let configDir = tempConfigDir()
        let workingDirectory = NSTemporaryDirectory() + "canopy-ctx-wd-\(UUID().uuidString)"
        try fm.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(atPath: workingDirectory)
            try? fm.removeItem(atPath: configDir)
        }

        let state = AppState(configDir: configDir)
        state.createSession(name: "fresh", directory: workingDirectory)
        state.activeSessionId = state.sessions[0].id

        await state.refreshActiveSessionContext()

        #expect(state.activeSessionContext == nil)
    }

    /// Claude assigns the id before the transcript exists, so there is a real
    /// window where the id is set and the file is not yet there.
    @Test func missingTranscriptFileReportsNoContext() async throws {
        let configDir = tempConfigDir()
        let workingDirectory = NSTemporaryDirectory() + "canopy-ctx-wd-\(UUID().uuidString)"
        try fm.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(atPath: workingDirectory)
            try? fm.removeItem(atPath: configDir)
        }

        let state = AppState(configDir: configDir)
        state.createSession(name: "pending", directory: workingDirectory)
        state.activeSessionId = state.sessions[0].id
        state.assignClaudeSessionId(UUID().uuidString, to: state.sessions[0].id)

        await state.refreshActiveSessionContext()

        #expect(state.activeSessionContext == nil)
    }

    @Test func noActiveSessionClearsContext() async {
        let configDir = tempConfigDir()
        defer { try? fm.removeItem(atPath: configDir) }

        let state = AppState(configDir: configDir)
        state.activeSessionContext = SessionContext(
            model: "claude-opus-5", effort: "high", contextTokens: 500
        )

        await state.refreshActiveSessionContext()

        #expect(state.activeSessionContext == nil)
    }

    /// The id is followed on the 2 s agent poll but the segment is refreshed
    /// on the 10 s one, so after a `/clear` the bar would go on showing the
    /// dead transcript's numbers for up to ten more seconds -- the exact stale
    /// reading this feature exists to avoid. Clearing synchronously means the
    /// worst case is a briefly absent segment rather than a wrong one.
    @Test func changingTheActiveSessionsIdDropsTheStaleContext() {
        let configDir = tempConfigDir()
        defer { try? fm.removeItem(atPath: configDir) }

        let state = AppState(configDir: configDir)
        state.createSession(name: "s", directory: "/tmp/s")
        state.activeSessionId = state.sessions[0].id
        state.activeSessionContext = SessionContext(
            model: "claude-opus-5", effort: "high", contextTokens: 400_000
        )

        state.assignClaudeSessionId(UUID().uuidString, to: state.sessions[0].id)

        #expect(state.activeSessionContext == nil)
    }

    /// Another tab re-keying is not this tab's business. Clearing on every
    /// assignment would blank the visible segment whenever any background
    /// session churned.
    @Test func anotherSessionsIdChangeLeavesTheActiveContextAlone() {
        let configDir = tempConfigDir()
        defer { try? fm.removeItem(atPath: configDir) }

        let state = AppState(configDir: configDir)
        state.createSession(name: "active", directory: "/tmp/a")
        state.createSession(name: "other", directory: "/tmp/b")
        state.activeSessionId = state.sessions[0].id
        let shown = SessionContext(model: "claude-opus-5", effort: "high", contextTokens: 1_234)
        state.activeSessionContext = shown

        state.assignClaudeSessionId(UUID().uuidString, to: state.sessions[1].id)

        #expect(state.activeSessionContext == shown)
    }

    /// The guard has to cover *two* things changing underneath a read, not
    /// one. A tab switch is the obvious one. The other is the transcript
    /// itself: `/clear` re-keys the session while the tab UUID stays exactly
    /// the same, so a read already in flight against the pre-clear file
    /// resumes, passes an activeSessionId check, and republishes the dead
    /// conversation's numbers over the fresh ones -- undoing the reset this
    /// feature exists to show.
    @Test func aContextReadFromASupersededTranscriptIsNotPublished() {
        let configDir = tempConfigDir()
        defer { try? fm.removeItem(atPath: configDir) }

        let state = AppState(configDir: configDir)
        state.createSession(name: "s", directory: "/tmp/s")
        let tab = state.sessions[0].id
        state.activeSessionId = tab
        let before = UUID().uuidString
        state.assignClaudeSessionId(before, to: tab)

        let stale = SessionContext(model: "claude-opus-5", effort: "high", contextTokens: 402_326)
        state.applySessionContext(stale, readFor: tab, transcript: before)
        #expect(state.activeSessionContext == stale)

        // /clear: same tab, new transcript.
        let afterClear = UUID().uuidString
        state.assignClaudeSessionId(afterClear, to: tab)

        // The read that started before the re-key now lands.
        state.applySessionContext(stale, readFor: tab, transcript: before)

        #expect(state.activeSessionContext == nil,
                "a read of the pre-clear transcript was republished over the reset")
    }

    /// Issue #28 in miniature: a read finishes for one session after the user
    /// has already switched to another, and the stale numbers land under the
    /// new session's name.
    ///
    /// Asserted through `applySessionContext` rather than by racing
    /// `refreshActiveSessionContext`, because that race cannot be won
    /// reliably. The earlier version of this test arranged for a tab switch to
    /// land inside the file read and needed 4 MB of filler to make the read
    /// slow enough; it passed locally, failed under CI load, and was finally
    /// broken outright by an optimisation that made the read four times
    /// faster. A test whose correctness depends on losing a scheduling race is
    /// a test that will fail for reasons unrelated to the code it covers.
    @Test func aContextReadForAnotherSessionIsNotPublished() {
        let configDir = tempConfigDir()
        defer { try? fm.removeItem(atPath: configDir) }

        let state = AppState(configDir: configDir)
        state.createSession(name: "first", directory: "/tmp/first")
        state.createSession(name: "second", directory: "/tmp/second")
        let first = state.sessions[0].id
        let second = state.sessions[1].id
        let transcript = UUID().uuidString
        state.assignClaudeSessionId(transcript, to: first)
        let context = SessionContext(model: "claude-opus-5", effort: "high", contextTokens: 1000)

        // A read that completes while its own session is still active applies.
        state.activeSessionId = first
        state.applySessionContext(context, readFor: first, transcript: transcript)
        #expect(state.activeSessionContext == context)

        // The user switches tabs; a read still in flight for the old session
        // must not overwrite what the new one shows.
        state.activeSessionId = second
        state.activeSessionContext = nil
        state.applySessionContext(context, readFor: first, transcript: transcript)

        #expect(state.activeSessionContext == nil,
                "a context read for another session was published over the active one")
    }
}
