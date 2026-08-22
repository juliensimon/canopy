import Foundation

/// Token usage totals from a Claude session.
struct TokenUsage {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var models: Set<String> = []

    var totalTokens: Int { inputTokens + outputTokens }

    var formattedInput: String { inputTokens.formatted() }
    var formattedOutput: String { outputTokens.formatted() }
}

/// The Claude run's state as of its most recent turn: which model, at what
/// reasoning effort, and how much context that turn had to read.
struct SessionContext: Equatable {
    let model: String?
    let effort: String?
    let contextTokens: Int
}

/// Parses Claude Code JSONL session files for token usage data.
enum SessionCostService {

    /// Parse token usage from JSONL content string, only counting entries after `since`.
    static func parseTokenUsage(from jsonlContent: String, since: Date? = nil) -> TokenUsage {
        var usage = TokenUsage()
        for line in jsonlContent.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let usageDict = message["usage"] as? [String: Any] else {
                continue
            }
            // Skip synthetic harness entries (not real token spend), matching
            // ActivityDataService.
            if message["model"] as? String == "<synthetic>" { continue }
            // With a cutoff, only count entries we can confirm are in-window: a
            // missing/unparseable timestamp can't be placed in time, so skip it
            // rather than over-report recent usage.
            if let since {
                guard let timestamp = obj["timestamp"] as? String,
                      let entryDate = ClaudeSessionFinder.parseTimestamp(timestamp),
                      entryDate >= since else {
                    continue
                }
            }
            usage.inputTokens += usageDict["input_tokens"] as? Int ?? 0
            usage.inputTokens += usageDict["cache_creation_input_tokens"] as? Int ?? 0
            usage.inputTokens += usageDict["cache_read_input_tokens"] as? Int ?? 0
            usage.outputTokens += usageDict["output_tokens"] as? Int ?? 0
            if let model = message["model"] as? String {
                usage.models.insert(model)
            }
        }
        return usage
    }

    /// Load token usage for a specific Claude session, only counting entries after `since`.
    static func loadUsage(for workingDirectory: String, sessionId: String?, since: Date? = nil) -> TokenUsage {
        guard let sessionId, !sessionId.isEmpty else { return TokenUsage() }
        let projectDir = ClaudeSessionFinder.projectDirectory(for: workingDirectory)
        let path = (projectDir as NSString).appendingPathComponent("\(sessionId).jsonl")
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return TokenUsage()
        }
        return parseTokenUsage(from: content, since: since)
    }

    /// Compact-JSON marker for the assistant-entry fast path. Claude Code
    /// writes JSONL without spaces after the colon, which is what makes this
    /// substring reliable; ActivityDataService relies on the same shape.
    private static let assistantMarker = Data("\"type\":\"assistant\"".utf8)

    /// One line -> a context reading, or nil if this line is not a real turn.
    ///
    /// Takes raw bytes rather than a String on purpose. The window handed to
    /// the scan routinely holds a user entry carrying a multi-megabyte tool
    /// result, and decoding that to a String purely to discover it is not an
    /// assistant entry costs more than everything else here combined. The
    /// marker is only a pre-filter. The structural checks below decide: a tool
    /// result quoting the marker gets parsed and then rejected for having no
    /// assistant-shaped `message.usage`, so the fast path can never promote a
    /// user entry.
    private static func context(fromLine line: Data) -> SessionContext? {
        guard line.range(of: assistantMarker) != nil else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              obj["type"] as? String == "assistant",
              let message = obj["message"] as? [String: Any],
              let usageDict = message["usage"] as? [String: Any] else {
            return nil
        }
        // Skip synthetic harness entries, matching parseTokenUsage. They
        // trail real turns, so letting one win reports the wrong turn.
        let model = message["model"] as? String
        if model == "<synthetic>" { return nil }

        return SessionContext(
            model: model,
            effort: obj["effort"] as? String,
            contextTokens: (usageDict["input_tokens"] as? Int ?? 0)
                + (usageDict["cache_creation_input_tokens"] as? Int ?? 0)
                + (usageDict["cache_read_input_tokens"] as? Int ?? 0)
        )
    }

    /// Context as of the LAST assistant entry -- deliberately not a sum.
    /// `parseTokenUsage` above accumulates `cache_read_input_tokens` over every
    /// turn, which is the right number for spend and several times too large
    /// for context: the same window is re-read each turn and counted again.
    /// Same fields, different reduction.
    ///
    /// `effort` is TOP-LEVEL on assistant entries, a sibling of `type` -- not
    /// inside `message`. See the verified note in ClaudeTranscriptLoader.
    static func parseLastTurnContext(from jsonlContent: String) -> SessionContext? {
        parseLastTurnContext(from: Data(jsonlContent.utf8))
    }

    /// Backwards: the newest eligible entry IS the answer, so the first hit
    /// going in reverse ends the scan instead of parsing every older entry
    /// only to overwrite the result.
    static func parseLastTurnContext(from jsonlData: Data) -> SessionContext? {
        for line in jsonlData.split(separator: UInt8(ascii: "\n")).reversed() {
            if let context = context(fromLine: line) { return context }
        }
        return nil
    }

    /// Context from the newest assistant entry, found by scanning backwards
    /// from EOF in a doubling window.
    ///
    /// Backwards because this is polled and transcripts reach 14 MB -- a
    /// forward scan re-reads the whole file on every tick. A *growing* window
    /// rather than one fixed tail read because entry sizes are wildly
    /// asymmetric: assistant entries top out near 19 KB, but a single user
    /// entry carrying a large tool result was measured at 1.36 MB. A fixed
    /// 256 KB tail steps clean over the assistant entry behind one of those.
    ///
    /// A window almost always starts part-way through an entry. That needs no
    /// remainder bookkeeping: truncated JSON never parses, so the damaged
    /// leading line is skipped like any other malformed line. Staying in raw
    /// bytes covers the same hazard for free -- a window can also cut a
    /// multi-byte character, and that degrades to one unparseable line rather
    /// than poisoning a decode of the whole window.
    static func lastTurnContext(
        path: String,
        chunkBytes: Int = 256 * 1024,
        maxScanBytes: Int = 8 * 1024 * 1024
    ) -> SessionContext? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd(), end > 0 else { return nil }
        let size = Int(end)

        var window = max(1, chunkBytes)
        while true {
            let capped = min(window, size)
            guard (try? handle.seek(toOffset: UInt64(size - capped))) != nil,
                  let data = try? handle.readToEnd() else { return nil }

            if let context = parseLastTurnContext(from: data) { return context }
            // Whole file already read, or the scan budget is spent: this
            // transcript has no reportable turn near its end.
            if capped >= size || window >= maxScanBytes { return nil }
            window *= 2
        }
    }

}
