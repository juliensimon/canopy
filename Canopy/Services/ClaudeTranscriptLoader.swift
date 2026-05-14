import Foundation

/// One entry in the structured transcript: a single user or assistant message
/// whose body is broken into typed blocks. We render blocks rather than raw
/// strings so the sheet can format tool calls compactly and apply markdown
/// only to plain text.
struct TranscriptMessage: Equatable, Identifiable {
    enum Role: String, Equatable { case user, assistant }
    enum Block: Equatable {
        case text(String)
        case toolUse(name: String, hint: String)
        case toolResult(String)
    }
    /// Stable across re-parses of the same JSONL file. Comes from the entry's
    /// `uuid` field when present, otherwise a synthetic `line-N` from the
    /// 0-based line offset. ForEach in the sheet diffs by this id; if it
    /// changed every parse, every row would tear down and rebuild, the
    /// scroll position would snap to top, and auto-tail would visibly do
    /// nothing.
    let id: String
    let role: Role
    let blocks: [Block]

    init(id: String = UUID().uuidString, role: Role, blocks: [Block]) {
        self.id = id
        self.role = role
        self.blocks = blocks
    }
}

/// Reads Claude Code's per-session JSONL transcript and converts it into an
/// ordered list of `TranscriptMessage`. The JSONL format is append-only, one
/// JSON object per line, written by Claude Code at
/// `~/.claude/projects/{encoded-cwd}/{session-uuid}.jsonl`.
enum ClaudeTranscriptLoader {

    /// Tool-use input keys we prefer (in order) when summarizing a tool call.
    /// First match wins, so `command` beats `description` for Bash calls,
    /// `file_path` beats `description` for Read/Write, etc.
    private static let preferredInputKeys = [
        "command", "file_path", "pattern", "query", "url", "subagent_type", "description",
    ]

    /// Cap on tool-result preview length. Larger values bloat the transcript;
    /// the full output is still available in `getFullText()` via the raw view.
    private static let toolResultMaxLength = 600

    static func load(path: String) throws -> [TranscriptMessage] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var messages: [TranscriptMessage] = []
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            guard let lineData = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            if let message = parseEntry(obj, lineIndex: index) {
                messages.append(message)
            }
        }
        return messages
    }

    /// Renders the structured transcript as a plain-text markdown string
    /// suitable for the clipboard. Mirrors what the user sees in the sheet:
    /// `## You` / `## Claude` section headers (collapsed across consecutive
    /// same-role messages), text blocks verbatim, tool calls and results as
    /// the same compact `🔧` / `↳` lines.
    static func plainText(messages: [TranscriptMessage]) -> String {
        var lines: [String] = []
        var currentRole: TranscriptMessage.Role?
        for message in messages {
            if message.role != currentRole {
                if !lines.isEmpty { lines.append("") }
                lines.append("## " + (message.role == .user ? "You" : "Claude"))
                lines.append("")
                currentRole = message.role
            }
            for block in message.blocks {
                switch block {
                case .text(let s):
                    lines.append(s)
                case .toolUse(let name, let hint):
                    lines.append(hint.isEmpty ? "🔧 \(name)" : "🔧 \(name) — \(hint)")
                case .toolResult(let s):
                    lines.append("↳ " + s)
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Mirrors Claude Code's filesystem layout. Both "/" and "." in the
    /// working directory become "-", matching `ClaudeSessionFinder`.
    static func sessionFilePath(workingDirectory: String, sessionId: String) -> String {
        let expanded = (workingDirectory as NSString).expandingTildeInPath
        let resolved = (expanded as NSString).resolvingSymlinksInPath
        let encoded = resolved
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let home = NSHomeDirectory()
        return "\(home)/.claude/projects/\(encoded)/\(sessionId).jsonl"
    }

    // MARK: - Private

    private static func parseEntry(_ obj: [String: Any], lineIndex: Int) -> TranscriptMessage? {
        guard let type = obj["type"] as? String,
              type == "user" || type == "assistant"
        else { return nil }
        // Skill loads, tool-use-result deliveries, and other Claude-Code-injected
        // user-role bodies are flagged isMeta=true. The user did not type them.
        if let isMeta = obj["isMeta"] as? Bool, isMeta { return nil }

        guard let message = obj["message"] as? [String: Any] else { return nil }
        let roleString = (message["role"] as? String) ?? type
        guard let role = TranscriptMessage.Role(rawValue: roleString) else { return nil }

        let blocks = extractBlocks(from: message["content"])
        guard !blocks.isEmpty else { return nil }
        let id = (obj["uuid"] as? String) ?? "line-\(lineIndex)"
        return TranscriptMessage(id: id, role: role, blocks: blocks)
    }

    private static func extractBlocks(from content: Any?) -> [TranscriptMessage.Block] {
        // Some entries use a plain string for `content`; treat as a single text block.
        if let s = content as? String {
            return s.isEmpty ? [] : [.text(s)]
        }
        guard let array = content as? [[String: Any]] else { return [] }
        var out: [TranscriptMessage.Block] = []
        for item in array {
            guard let type = item["type"] as? String else { continue }
            switch type {
            case "text":
                if let body = item["text"] as? String, !body.isEmpty {
                    out.append(.text(body))
                }
            case "thinking":
                // Hidden from the transcript for now. Could surface behind a toggle.
                continue
            case "tool_use":
                let name = (item["name"] as? String) ?? "?"
                let hint = toolHint(from: item["input"] as? [String: Any])
                out.append(.toolUse(name: name, hint: hint))
            case "tool_result":
                let body = toolResultBody(item["content"])
                if !body.isEmpty {
                    out.append(.toolResult(truncated(body, max: toolResultMaxLength)))
                }
            default:
                continue
            }
        }
        return out
    }

    private static func toolHint(from input: [String: Any]?) -> String {
        guard let input else { return "" }
        for key in preferredInputKeys {
            if let value = input[key] {
                return truncated(stringify(value), max: 120)
            }
        }
        return ""
    }

    private static func toolResultBody(_ raw: Any?) -> String {
        if let s = raw as? String { return s }
        if let arr = raw as? [[String: Any]] {
            for item in arr where (item["type"] as? String) == "text" {
                if let s = item["text"] as? String { return s }
            }
        }
        return ""
    }

    private static func stringify(_ value: Any) -> String {
        if let s = value as? String { return s }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return ""
    }

    private static func truncated(_ s: String, max: Int) -> String {
        if s.count <= max { return s }
        let end = s.index(s.startIndex, offsetBy: max - 1)
        return String(s[..<end]) + "…"
    }
}
