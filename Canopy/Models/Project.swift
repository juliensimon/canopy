import Foundation

/// A project represents a git repository the user works with.
///
/// It stores the repo path, worktree configuration, and optional
/// per-project Claude Code settings that override the global defaults.
struct Project: Identifiable, Codable {
    let id: UUID
    var name: String
    var repositoryPath: String

    /// Files to copy from the main repo into new worktrees.
    var filesToCopy: [String]

    /// Directories to symlink (not copy) into new worktrees.
    var symlinkPaths: [String]

    /// Shell commands to run in the worktree after creation.
    var setupCommands: [String]

    /// Base directory where worktrees are stored.
    var worktreeBaseDir: String?

    /// Override global auto-start setting for this project. nil = use global.
    var autoStartClaude: Bool?

    /// Override global Claude flags for this project. nil = use global.
    var claudeFlags: String?

    init(
        name: String,
        repositoryPath: String,
        filesToCopy: [String] = [".env", ".env.local"],
        symlinkPaths: [String] = [],
        setupCommands: [String] = [],
        autoStartClaude: Bool? = nil,
        claudeFlags: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.repositoryPath = repositoryPath
        self.filesToCopy = filesToCopy
        self.symlinkPaths = symlinkPaths
        self.setupCommands = setupCommands
        self.autoStartClaude = autoStartClaude
        self.claudeFlags = claudeFlags
    }

    // Forward-compatible decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        repositoryPath = try container.decode(String.self, forKey: .repositoryPath)
        filesToCopy = try container.decodeIfPresent([String].self, forKey: .filesToCopy) ?? [".env", ".env.local"]
        symlinkPaths = try container.decodeIfPresent([String].self, forKey: .symlinkPaths) ?? []
        setupCommands = try container.decodeIfPresent([String].self, forKey: .setupCommands) ?? []
        worktreeBaseDir = try container.decodeIfPresent(String.self, forKey: .worktreeBaseDir)
        autoStartClaude = try container.decodeIfPresent(Bool.self, forKey: .autoStartClaude)
        claudeFlags = try container.decodeIfPresent(String.self, forKey: .claudeFlags)
    }

    /// Returns the base directory for worktrees.
    var resolvedWorktreeBaseDir: String {
        if let custom = worktreeBaseDir, !custom.isEmpty {
            return custom
        }
        let parent = (repositoryPath as NSString).deletingLastPathComponent
        return (parent as NSString).appendingPathComponent("canopy-worktrees/\(name)")
    }

    /// Resolves whether Claude should auto-start, falling back to global settings.
    func shouldAutoStartClaude(globalSettings: CanopySettings) -> Bool {
        autoStartClaude ?? globalSettings.autoStartClaude
    }

    /// Resolves the Claude command, falling back to global settings.
    func resolvedClaudeCommand(globalSettings: CanopySettings) -> String {
        var cmd = "claude"
        let flags = claudeFlags ?? globalSettings.claudeFlags
        let trimmed = flags.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            cmd += " " + trimmed
        }
        return cmd
    }
}
