import Foundation

/// Token usage totals from a Claude session.
struct TokenUsage {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var models: Set<String> = []

    var totalTokens: Int { inputTokens + outputTokens }

    var formattedInput: String { formatCount(inputTokens) }
    var formattedOutput: String { formatCount(outputTokens) }

    private func formatCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}

/// Parses Claude Code JSONL session files for token usage data.
enum SessionCostService {

    private nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

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
            // Skip entries before the cutoff date
            if let since,
               let timestamp = obj["timestamp"] as? String,
               let entryDate = iso8601.date(from: timestamp),
               entryDate < since {
                continue
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

    /// Returns the Claude project directory for a given working directory.
    static func claudeProjectDir(for directory: String) -> String {
        let expanded = (directory as NSString).expandingTildeInPath
        let resolved = (expanded as NSString).resolvingSymlinksInPath
        let encoded = resolved
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let home = NSHomeDirectory()
        return "\(home)/.claude/projects/\(encoded)"
    }

    /// Load token usage for a specific Claude session, only counting entries after `since`.
    static func loadUsage(for workingDirectory: String, sessionId: String?, since: Date? = nil) -> TokenUsage {
        guard let sessionId, !sessionId.isEmpty else { return TokenUsage() }
        let projectDir = claudeProjectDir(for: workingDirectory)
        let path = (projectDir as NSString).appendingPathComponent("\(sessionId).jsonl")
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return TokenUsage()
        }
        return parseTokenUsage(from: content, since: since)
    }
}
