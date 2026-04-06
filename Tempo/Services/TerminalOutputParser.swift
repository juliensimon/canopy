import Foundation

/// Parses Claude Code terminal output to detect actionable events.
///
/// Claude Code uses specific patterns for permission prompts, tool use,
/// and status indicators. This parser strips ANSI codes and matches
/// against known patterns to produce structured events.
///
/// The parser maintains a rolling buffer of recent lines so patterns
/// that span output chunks (e.g., a prompt split across two reads)
/// can still be detected.
final class TerminalOutputParser {
    /// Rolling buffer of recent stripped output lines
    private var recentLines: [String] = []
    private let maxBufferLines = 50

    /// Raw bytes buffer for incomplete UTF-8 sequences
    private var pendingBytes = Data()

    /// Parses raw terminal bytes and returns any detected events.
    func feed(_ data: Data) -> [TerminalEvent] {
        pendingBytes.append(data)

        // Try to decode as UTF-8
        guard let text = String(data: pendingBytes, encoding: .utf8) else {
            // Might be incomplete multi-byte sequence, wait for more data
            // But don't accumulate forever
            if pendingBytes.count > 8192 {
                pendingBytes.removeAll()
            }
            return []
        }
        pendingBytes.removeAll()

        let stripped = AnsiStripper.strip(text)
        let newLines = stripped.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var events: [TerminalEvent] = []

        for line in newLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            recentLines.append(trimmed)
            if recentLines.count > maxBufferLines {
                recentLines.removeFirst(recentLines.count - maxBufferLines)
            }

            // Check for known patterns
            if let event = matchPermissionPrompt(trimmed) {
                events.append(event)
            } else if let event = matchToolUse(trimmed) {
                events.append(event)
            } else if let event = matchError(trimmed) {
                events.append(event)
            } else if let event = matchQuestion(trimmed) {
                events.append(event)
            }
        }

        return events
    }

    /// Resets the parser state.
    func reset() {
        recentLines.removeAll()
        pendingBytes.removeAll()
    }

    // MARK: - Pattern Matching

    /// Matches Claude's permission prompts:
    ///   "? Allow Read tool? (y/n)"
    ///   "? Allow Bash(git status) tool? (y/n)"
    ///   "? Allow Edit tool on file.swift? (y/n)"
    private func matchPermissionPrompt(_ line: String) -> TerminalEvent? {
        // Pattern: starts with "?" and contains "Allow" and "(y/n)"
        guard line.hasPrefix("?") || line.hasPrefix("❯") else { return nil }
        guard line.contains("Allow") && (line.contains("(y/n)") || line.contains("[Y/n]") || line.contains("[y/N]")) else { return nil }

        // Extract the tool name: "Allow X tool?" or "Allow X?"
        if let regex = try? NSRegularExpression(pattern: #"Allow\s+(.+?)\s*(?:tool)?\?\s*\("#),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let range = Range(match.range(at: 1), in: line) {
            let toolName = String(line[range]).trimmingCharacters(in: .whitespaces)
            return .permissionPrompt(tool: toolName, fullLine: line)
        }

        return .permissionPrompt(tool: "unknown", fullLine: line)
    }

    /// Matches Claude's tool use indicators:
    ///   "⏺ Using tool: Read file.txt"
    ///   "⏺ Read file.txt"
    private func matchToolUse(_ line: String) -> TerminalEvent? {
        if line.contains("Using tool:") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count > 1 {
                let detail = String(parts[1]).trimmingCharacters(in: .whitespaces)
                return .toolUse(detail: detail)
            }
        }
        return nil
    }

    /// Matches error patterns in output.
    private func matchError(_ line: String) -> TerminalEvent? {
        let errorPrefixes = ["Error:", "error:", "ERROR:", "fatal:", "Fatal:", "panic:"]
        for prefix in errorPrefixes {
            if line.contains(prefix) {
                return .error(message: line)
            }
        }
        // Stack trace indicators
        if line.contains("at ") && (line.contains(".ts:") || line.contains(".js:") || line.contains(".py:") || line.contains(".swift:")) {
            return .error(message: line)
        }
        return nil
    }

    /// Matches generic questions (lines ending with "?") that aren't permission prompts.
    private func matchQuestion(_ line: String) -> TerminalEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Must end with "?" but not be a permission prompt (already caught above)
        guard trimmed.hasSuffix("?") else { return nil }
        guard !trimmed.contains("Allow") else { return nil }
        // Must be reasonably long to be a real question (not just "?")
        guard trimmed.count > 10 else { return nil }
        return .question(text: trimmed)
    }
}

/// Events detected in terminal output.
enum TerminalEvent: Equatable {
    /// Claude is asking for permission to use a tool.
    /// e.g. "Allow Read tool? (y/n)"
    case permissionPrompt(tool: String, fullLine: String)

    /// Claude is using a tool (informational, no action needed).
    case toolUse(detail: String)

    /// An error was detected in the output.
    case error(message: String)

    /// Claude is asking a general question.
    case question(text: String)
}
