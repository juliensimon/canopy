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
    /// Model that produced this turn, e.g. `claude-opus-5`. Assistant-only,
    /// and nil for Claude Code's own `<synthetic>` error/interrupt entries.
    let model: String?
    /// Reasoning effort for this turn, e.g. `xhigh`. Assistant-only, and
    /// legitimately absent both on CLIs older than ~2.1.212 and for models
    /// with no effort concept (sonnet-4-5, haiku-4-5, opus-4-8), so
    /// half-populated attribution is a valid state, not a parse failure.
    let effort: String?

    init(
        id: String = UUID().uuidString,
        role: Role,
        blocks: [Block],
        model: String? = nil,
        effort: String? = nil
    ) {
        self.id = id
        self.role = role
        self.blocks = blocks
        self.model = model
        self.effort = effort
    }

    /// Compact attribution for display, e.g. `opus-5 · xhigh`. Nil when
    /// neither field is present, so old transcripts render exactly as before.
    var attribution: String? {
        ClaudeTranscriptLoader.attributionLabel(model: model, effort: effort)
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

    /// Renders a model id and reasoning effort as one compact label, e.g.
    /// `claude-opus-5` + `xhigh` -> `opus-5 · xhigh`. Nil when neither is
    /// present; a half-populated pair is valid and renders the half it has.
    ///
    /// Lives here rather than on `TranscriptMessage` because the status bar
    /// shows the same pairing from an entirely different parse. Two copies of
    /// this formatting would drift apart the first time either changed.
    static func attributionLabel(model: String?, effort: String?) -> String? {
        let shortModel = model.map {
            $0.hasPrefix("claude-") ? String($0.dropFirst("claude-".count)) : $0
        }
        switch (shortModel, effort) {
        case let (model?, effort?): return "\(model) · \(effort)"
        case let (model?, nil): return model
        case let (nil, effort?): return effort
        case (nil, nil): return nil
        }
    }

    static func load(path: String) throws -> [TranscriptMessage] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var messages: [TranscriptMessage] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let lineString = String(line)
            guard let lineData = lineString.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            if let message = parseEntry(obj, line: lineString) {
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
        var currentAttribution: String?
        for message in messages {
            // A new header on attribution change as well as role change: the
            // model can switch mid-transcript via /model, and a transcript
            // pasted into an issue must say which model produced which turn.
            if message.role != currentRole || message.attribution != currentAttribution {
                if !lines.isEmpty { lines.append("") }
                var header = "## " + (message.role == .user ? "You" : "Claude")
                if let attribution = message.attribution {
                    header += " — \(attribution)"
                }
                lines.append(header)
                lines.append("")
                currentRole = message.role
                currentAttribution = message.attribution
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

    /// Returns the on-disk JSONL path for a (working directory, session id)
    /// pair. Routes through `ClaudeSessionFinder.projectDirectory(for:)` to
    /// share the one path-encoding implementation.
    static func sessionFilePath(workingDirectory: String, sessionId: String) -> String {
        let projectDir = ClaudeSessionFinder.projectDirectory(for: workingDirectory)
        return (projectDir as NSString).appendingPathComponent("\(sessionId).jsonl")
    }

    // MARK: - Private

    private static func parseEntry(_ obj: [String: Any], line: String) -> TranscriptMessage? {
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
        // Prefer the JSONL `uuid`; fall back to a content-derived FNV-1a hash.
        // A positional `line-N` id would shift if Claude Code ever inserted a
        // blank line (theoretical today, but the content hash is stable
        // regardless of file position).
        let id: String
        if let uuid = obj["uuid"] as? String, !uuid.isEmpty {
            id = uuid
        } else {
            id = "synth-" + fnv1a(line)
        }
        // `effort` is TOP-LEVEL on assistant entries -- a sibling of type/uuid,
        // NOT inside `message` (verified: 4,170 real entries carry it at the
        // top level, zero carry `message.effort`). `model` is inside `message`.
        // Attribution is assistant-only; a user turn has no model.
        var model: String?
        var effort: String?
        if role == .assistant {
            // Claude Code's own error/interrupt entries claim `<synthetic>`.
            let raw = message["model"] as? String
            model = raw == "<synthetic>" ? nil : raw
            effort = obj["effort"] as? String
        }
        return TranscriptMessage(id: id, role: role, blocks: blocks, model: model, effort: effort)
    }

    /// Deterministic 64-bit FNV-1a hash for synthetic ids. Stable across
    /// processes (unlike Swift's `hashValue`, which is randomized per run),
    /// so two parses of the same content produce the same hash even after a
    /// relaunch.
    private static func fnv1a(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        return String(h, radix: 16)
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
