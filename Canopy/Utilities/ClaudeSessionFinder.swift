import Foundation

/// Finds Claude Code session IDs stored on disk and resolves the on-disk
/// project directory Claude Code uses to namespace its session logs.
///
/// Claude Code stores session transcripts as JSONL files in:
///   ~/.claude/projects/{encoded-path}/{session-uuid}.jsonl
///
/// Claude Code 2.x encodes its resolved cwd with `[^a-zA-Z0-9]` → "-"
/// (verified against the shipped binary), e.g.
///   /Users/julien/my_proj.v2 → -Users-julien-my-proj-v2
///
/// This is the single source of truth for the encoding — `SessionCostService`
/// and `ClaudeTranscriptLoader` route through here. If Claude Code ever
/// changes the encoding, fix it once.
enum ClaudeSessionFinder {

    /// Returns the on-disk directory where Claude Code stores JSONL session
    /// logs for the given working directory.
    static func projectDirectory(for directory: String) -> String {
        let expanded = (directory as NSString).expandingTildeInPath
        // realpath, not NSString.resolvingSymlinksInPath: Claude encodes
        // process.cwd(), which is /private/tmp/... for /tmp paths.
        let resolved = SandboxBackend.realResolvedPath(expanded)
        let encoded = String(resolved.unicodeScalars.map { scalar -> Character in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9":
                return Character(scalar)
            default:
                return "-"
            }
        })
        let home = NSHomeDirectory()
        return "\(home)/.claude/projects/\(encoded)"
    }

    /// Returns the most recent Claude session ID for the given working directory.
    static func findLatestSessionId(for directory: String) -> String? {
        let projectDir = projectDirectory(for: directory)
        let fm = FileManager.default

        guard fm.fileExists(atPath: projectDir) else { return nil }

        do {
            let files = try fm.contentsOfDirectory(atPath: projectDir)
            let jsonlFiles = files.filter { $0.hasSuffix(".jsonl") }

            // Sort by modification date (newest first)
            let sorted = jsonlFiles.compactMap { filename -> (String, Date)? in
                let path = (projectDir as NSString).appendingPathComponent(filename)
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let modDate = attrs[.modificationDate] as? Date else { return nil }
                return (filename, modDate)
            }.sorted { $0.1 > $1.1 }

            // Return the UUID from the newest file
            guard let newest = sorted.first else { return nil }
            let sessionId = (newest.0 as NSString).deletingPathExtension
            // Validate it looks like a UUID
            if UUID(uuidString: sessionId) != nil {
                return sessionId
            }
            return nil
        } catch {
            return nil
        }
    }
}
