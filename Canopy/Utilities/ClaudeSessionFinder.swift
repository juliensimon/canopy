import Foundation

/// Finds Claude Code session IDs stored on disk.
///
/// Claude Code stores session transcripts as JSONL files in:
///   ~/.claude/projects/{encoded-path}/{session-uuid}.jsonl
///
/// The path encoding replaces "/" with "-" and prepends "-".
/// e.g. /Users/julien/my-project → -Users-julien-my-project
enum ClaudeSessionFinder {

    /// Returns the most recent Claude session ID for the given working directory.
    static func findLatestSessionId(for directory: String) -> String? {
        let projectDir = claudeProjectDir(for: directory)
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

    /// Returns the Claude project directory for a given working directory.
    /// Claude encodes paths by replacing both "/" and "." with "-".
    private static func claudeProjectDir(for directory: String) -> String {
        let expanded = (directory as NSString).expandingTildeInPath
        let resolved = (expanded as NSString).resolvingSymlinksInPath
        let encoded = resolved
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let home = NSHomeDirectory()
        return "\(home)/.claude/projects/\(encoded)"
    }
}
