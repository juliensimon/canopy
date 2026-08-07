import Testing
import Foundation
@testable import Canopy

/// Parses Claude Code's JSONL session files into a structured transcript view.
/// The format is append-only JSONL, each line a JSON object with a `type` field.
/// We only render `user` / `assistant` entries; everything else (attachment,
/// system, queue-operation, etc.) is metadata. Within those, `isMeta: true`
/// flags content that Claude Code injected on the user's behalf (skill loads,
/// command-result deliveries) which is NOT user-written and must be skipped.
@Suite("Claude Transcript Loader")
struct ClaudeTranscriptLoaderTests {

    // MARK: - Helpers

    private func tempJSONL(_ lines: [String]) -> String {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("canopy-transcript-\(UUID().uuidString).jsonl")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    private func userTextLine(_ text: String, isMeta: Bool = false) -> String {
        let meta = isMeta ? "true" : "false"
        return """
        {"type":"user","isMeta":\(meta),"message":{"role":"user","content":[{"type":"text","text":\(jsonString(text))}]}}
        """
    }

    private func assistantTextLine(_ text: String) -> String {
        """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":\(jsonString(text))}]}}
        """
    }

    private func toolUseLine(name: String, input: String) -> String {
        """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"\(name)","input":\(input)}]}}
        """
    }

    private func toolResultLine(_ content: String) -> String {
        """
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":\(jsonString(content))}]}}
        """
    }

    private func jsonString(_ s: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [s], options: [.fragmentsAllowed])
        let arr = String(data: data, encoding: .utf8)!
        // Strip the surrounding brackets
        return String(arr.dropFirst().dropLast())
    }

    // MARK: - Model & effort attribution

    /// `effort` is a TOP-LEVEL field on assistant entries -- a sibling of
    /// `type`/`uuid`/`version` -- while `model` lives inside `message`.
    /// Surveyed across 60 real transcripts: 4,170 assistant entries carry a
    /// top-level `effort`, zero carry `message.effort`. Reading it from the
    /// wrong nesting level is the one thing easy to get wrong here, so assert
    /// the level, not just the value.
    @Test func parsesEffortFromTopLevelAssistantField() throws {
        let path = tempJSONL([
            #"{"type":"assistant","effort":"xhigh","message":{"role":"assistant","model":"claude-opus-5","content":[{"type":"text","text":"hi"}]}}"#
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        let messages = try ClaudeTranscriptLoader.load(path: path)
        #expect(messages.first?.effort == "xhigh")
        #expect(messages.first?.model == "claude-opus-5")
    }

    /// A CLI older than ~2.1.212 emits no `effort` at all. Old transcripts
    /// must render exactly as they did before this feature existed.
    @Test func effortAbsentOnOlderTranscriptsYieldsNil() throws {
        let path = tempJSONL([
            #"{"type":"assistant","version":"2.1.196","message":{"role":"assistant","model":"claude-fable-5","content":[{"type":"text","text":"hi"}]}}"#
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        let messages = try ClaudeTranscriptLoader.load(path: path)
        #expect(messages.first?.effort == nil)
        #expect(messages.first?.model == "claude-fable-5")
    }

    /// Some models have no effort concept even on a current CLI (sonnet-4-5,
    /// haiku-4-5, opus-4-8 all observed this way). Half-populated is a VALID
    /// state, which is why this is per-message and never a session header.
    @Test func effortAbsentForModelsWithoutEffort() throws {
        let path = tempJSONL([
            #"{"type":"assistant","version":"2.1.215","message":{"role":"assistant","model":"claude-sonnet-4-5-20250929","content":[{"type":"text","text":"hi"}]}}"#
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        let messages = try ClaudeTranscriptLoader.load(path: path)
        #expect(messages.first?.model == "claude-sonnet-4-5-20250929")
        #expect(messages.first?.effort == nil)
    }

    /// Claude Code writes `<synthetic>` for its own error/interrupt entries.
    /// Rendering that as a model name would be noise, not attribution.
    @Test func syntheticModelSuppressesBadge() throws {
        let path = tempJSONL([
            #"{"type":"assistant","message":{"role":"assistant","model":"<synthetic>","content":[{"type":"text","text":"Request interrupted"}]}}"#
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        #expect(try ClaudeTranscriptLoader.load(path: path).first?.model == nil)
    }

    @Test func userMessagesCarryNoModelOrEffort() throws {
        let path = tempJSONL([userTextLine("hello")])
        defer { try? FileManager.default.removeItem(atPath: path) }

        let message = try #require(try ClaudeTranscriptLoader.load(path: path).first)
        #expect(message.model == nil)
        #expect(message.effort == nil)
    }

    /// The copied transcript is what gets pasted into a GitHub issue. Losing
    /// the model attribution there defeats the point of showing it at all.
    @Test func plainTextRecordsModelAndEffortInClaudeHeader() throws {
        let path = tempJSONL([
            userTextLine("question"),
            #"{"type":"assistant","effort":"xhigh","message":{"role":"assistant","model":"claude-opus-5","content":[{"type":"text","text":"answer"}]}}"#
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        let text = ClaudeTranscriptLoader.plainText(
            messages: try ClaudeTranscriptLoader.load(path: path)
        )
        #expect(text.contains("## Claude — opus-5 · xhigh"))
        #expect(text.contains("## You"))
    }

    /// Both fields absent -> the header is byte-identical to today's output.
    @Test func plainTextHeaderUnchangedWithoutAttribution() throws {
        let path = tempJSONL([assistantTextLine("answer")])
        defer { try? FileManager.default.removeItem(atPath: path) }

        let text = ClaudeTranscriptLoader.plainText(
            messages: try ClaudeTranscriptLoader.load(path: path)
        )
        #expect(text.hasPrefix("## Claude\n"))
    }

    /// Model present, effort absent must not leave a dangling separator.
    @Test func plainTextOmitsSeparatorWhenEffortMissing() throws {
        let path = tempJSONL([
            #"{"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-5","content":[{"type":"text","text":"a"}]}}"#
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        let text = ClaudeTranscriptLoader.plainText(
            messages: try ClaudeTranscriptLoader.load(path: path)
        )
        #expect(text.hasPrefix("## Claude — sonnet-4-5\n"))
        #expect(!text.contains("·"))
    }

    /// The model can change mid-transcript via `/model`, so a new header must
    /// be emitted when attribution changes even though the role has not.
    @Test func plainTextStartsNewHeaderWhenModelChangesMidTranscript() throws {
        let path = tempJSONL([
            #"{"type":"assistant","effort":"xhigh","message":{"role":"assistant","model":"claude-opus-5","content":[{"type":"text","text":"a"}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","model":"claude-fable-5","content":[{"type":"text","text":"b"}]}}"#
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        let text = ClaudeTranscriptLoader.plainText(
            messages: try ClaudeTranscriptLoader.load(path: path)
        )
        #expect(text.contains("## Claude — opus-5 · xhigh"))
        #expect(text.contains("## Claude — fable-5"))
    }

    // MARK: - Empty / malformed

    @Test func parseEmptyFileYieldsEmptyTranscript() throws {
        let path = tempJSONL([])
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(try ClaudeTranscriptLoader.load(path: path).isEmpty)
    }

    @Test func parseMissingFileThrows() {
        #expect(throws: (any Error).self) {
            _ = try ClaudeTranscriptLoader.load(path: "/nonexistent/canopy-test-\(UUID()).jsonl")
        }
    }

    @Test func parseSkipsMalformedLines() throws {
        let path = tempJSONL([
            "not json",
            userTextLine("real user message"),
            "{broken",
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let messages = try ClaudeTranscriptLoader.load(path: path)
        #expect(messages.count == 1)
        #expect(messages.first?.role == .user)
    }

    // MARK: - Text blocks

    @Test func parsesUserTextBlock() throws {
        let path = tempJSONL([userTextLine("hello claude")])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let messages = try ClaudeTranscriptLoader.load(path: path)
        #expect(messages.count == 1)
        let m = try #require(messages.first)
        #expect(m.role == .user)
        guard case .text(let body) = m.blocks.first else {
            Issue.record("expected text block, got \(m.blocks)"); return
        }
        #expect(body == "hello claude")
    }

    @Test func parsesAssistantTextBlock() throws {
        let path = tempJSONL([assistantTextLine("hi there")])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let messages = try ClaudeTranscriptLoader.load(path: path)
        let m = try #require(messages.first)
        #expect(m.role == .assistant)
        guard case .text(let body) = m.blocks.first else {
            Issue.record("expected text block"); return
        }
        #expect(body == "hi there")
    }

    // MARK: - isMeta filter

    @Test func filtersIsMetaUserEntries() throws {
        // Skill loads and command-result deliveries arrive as user-role text
        // with isMeta=true. They are NOT user-written and must be hidden.
        let path = tempJSONL([
            userTextLine("real question"),
            userTextLine("skill blurb that nobody typed", isMeta: true),
            assistantTextLine("answer"),
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let messages = try ClaudeTranscriptLoader.load(path: path)
        #expect(messages.count == 2)
        #expect(messages.compactMap { m -> String? in
            if case .text(let s) = m.blocks.first { return s } else { return nil }
        } == ["real question", "answer"])
    }

    // MARK: - Tool use / result

    @Test func parsesToolUseWithCommandHint() throws {
        let path = tempJSONL([
            toolUseLine(name: "Bash", input: #"{"command":"git status","description":"check"}"#)
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let messages = try ClaudeTranscriptLoader.load(path: path)
        let m = try #require(messages.first)
        guard case .toolUse(let name, let hint) = m.blocks.first else {
            Issue.record("expected toolUse block, got \(m.blocks)"); return
        }
        #expect(name == "Bash")
        // Hint should pick the first known key (command beats description).
        #expect(hint == "git status")
    }

    @Test func parsesToolUseWithFilePathHint() throws {
        let path = tempJSONL([
            toolUseLine(name: "Read", input: #"{"file_path":"/tmp/foo.swift"}"#)
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let messages = try ClaudeTranscriptLoader.load(path: path)
        guard case .toolUse(_, let hint) = messages.first?.blocks.first else {
            Issue.record("expected toolUse"); return
        }
        #expect(hint == "/tmp/foo.swift")
    }

    @Test func parsesToolResult() throws {
        let path = tempJSONL([toolResultLine("file contents here")])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let messages = try ClaudeTranscriptLoader.load(path: path)
        guard case .toolResult(let body) = messages.first?.blocks.first else {
            Issue.record("expected toolResult"); return
        }
        #expect(body == "file contents here")
    }

    @Test func toolResultTruncatesVeryLongContent() throws {
        let huge = String(repeating: "x", count: 5000)
        let path = tempJSONL([toolResultLine(huge)])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let messages = try ClaudeTranscriptLoader.load(path: path)
        guard case .toolResult(let body) = messages.first?.blocks.first else {
            Issue.record("expected toolResult"); return
        }
        // Keep enough to be useful, not so much that the sheet drowns in tool I/O.
        #expect(body.count < 1000)
        #expect(body.hasSuffix("…") || body.count <= huge.count)
    }

    // MARK: - Stringified content shape

    @Test func parsesStringMessageContent() throws {
        // Some entries store `message.content` as a plain string, not an array.
        let line = #"{"type":"user","message":{"role":"user","content":"plain string body"}}"#
        let path = tempJSONL([line])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let messages = try ClaudeTranscriptLoader.load(path: path)
        guard case .text(let body) = messages.first?.blocks.first else {
            Issue.record("expected text block"); return
        }
        #expect(body == "plain string body")
    }

    // MARK: - Non-user/assistant types

    @Test func ignoresNonConversationTypes() throws {
        let path = tempJSONL([
            #"{"type":"attachment","attachment":"whatever"}"#,
            #"{"type":"queue-operation","operation":"enqueue"}"#,
            #"{"type":"system","subtype":"info"}"#,
            userTextLine("the only real message"),
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let messages = try ClaudeTranscriptLoader.load(path: path)
        #expect(messages.count == 1)
    }

    // MARK: - Plain-text formatting

    @Test func plainTextFormatsMessagesWithRoleHeaders() {
        let msgs: [TranscriptMessage] = [
            .init(role: .user, blocks: [.text("hello")]),
            .init(role: .assistant, blocks: [.text("hi back")]),
        ]
        let out = ClaudeTranscriptLoader.plainText(messages: msgs)
        #expect(out == "## You\n\nhello\n\n## Claude\n\nhi back")
    }

    @Test func plainTextRendersToolCallsAndResults() {
        let msgs: [TranscriptMessage] = [
            .init(role: .assistant, blocks: [
                .toolUse(name: "Bash", hint: "git status"),
                .toolResult("On branch master"),
                .text("Looks clean."),
            ]),
        ]
        let out = ClaudeTranscriptLoader.plainText(messages: msgs)
        #expect(out.contains("🔧 Bash — git status"))
        #expect(out.contains("↳ On branch master"))
        #expect(out.contains("Looks clean."))
    }

    @Test func plainTextEmptyMessagesIsEmptyString() {
        #expect(ClaudeTranscriptLoader.plainText(messages: []).isEmpty)
    }

    @Test func plainTextMergesConsecutiveSameRoleBlocksUnderOneHeader() {
        // Two assistant entries in a row should share one header, mirroring
        // the on-screen rendering where role headers don't repeat.
        let msgs: [TranscriptMessage] = [
            .init(role: .assistant, blocks: [.toolUse(name: "Read", hint: "/a.swift")]),
            .init(role: .assistant, blocks: [.text("done")]),
        ]
        let out = ClaudeTranscriptLoader.plainText(messages: msgs)
        // Only one "## Claude" header even though two messages.
        #expect(out.components(separatedBy: "## Claude").count - 1 == 1)
    }

    // MARK: - Stable identity across re-parses

    /// Auto-tail in the sheet relies on ForEach diffing by message id. If ids
    /// change on every poll, every row tears down and rebuilds, the scroll
    /// position snaps to top, and auto-tail visibly does nothing. The parser
    /// must produce stable ids — sourced from the JSONL `uuid` field — so two
    /// parses of the same file yield identical arrays.
    @Test func twoParsesOfSameFileYieldIdenticalIDs() throws {
        let path = tempJSONL([
            #"{"type":"user","uuid":"u-1","message":{"role":"user","content":"hi"}}"#,
            #"{"type":"assistant","uuid":"a-1","message":{"role":"assistant","content":[{"type":"text","text":"hello"}]}}"#,
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let first = try ClaudeTranscriptLoader.load(path: path)
        let second = try ClaudeTranscriptLoader.load(path: path)
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.map(\.id) == ["u-1", "a-1"])
    }

    @Test func messagesWithoutUUIDStillGetStableIDs() throws {
        // Synthetic id derived from FNV-1a content hash — same file, same ids.
        let path = tempJSONL([userTextLine("a"), assistantTextLine("b")])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let first = try ClaudeTranscriptLoader.load(path: path)
        let second = try ClaudeTranscriptLoader.load(path: path)
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.count == 2)
    }

    /// Regression for the synthetic-id fragility called out in PR #17 review:
    /// `enumerated()` over `split(omittingEmptySubsequences: true)` would
    /// silently renumber every subsequent entry when a blank line was inserted
    /// earlier in the file. The FNV-1a content hash is position-independent.
    @Test func syntheticIDsAreStableWhenBlankLinesAreInserted() throws {
        let lineA = userTextLine("a")
        let lineB = assistantTextLine("b")
        let withoutBlank = tempJSONL([lineA, lineB])
        let withBlank = tempJSONL([lineA, "", "", lineB])
        defer {
            try? FileManager.default.removeItem(atPath: withoutBlank)
            try? FileManager.default.removeItem(atPath: withBlank)
        }
        let baseline = try ClaudeTranscriptLoader.load(path: withoutBlank)
        let interrupted = try ClaudeTranscriptLoader.load(path: withBlank)
        #expect(baseline.map(\.id) == interrupted.map(\.id))
    }

    // MARK: - Path resolution

    @Test func sessionFilePathEncodesWorkingDirectory() {
        // Mirrors ClaudeSessionFinder's encoding: "/" and "." both become "-".
        let path = ClaudeTranscriptLoader.sessionFilePath(
            workingDirectory: "/Users/me/my.project",
            sessionId: "abc-123"
        )
        #expect(path.contains("-Users-me-my-project"))
        #expect(path.hasSuffix("/abc-123.jsonl"))
    }
}
