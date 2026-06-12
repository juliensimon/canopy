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

    /// Override global sandbox backend for this project. nil = use global.
    var sandboxBackend: SandboxBackend?

    /// Override global sbx flags for this project. nil = use global.
    var sbxFlags: String?

    /// Override global container image for this project. nil = use global.
    var containerImage: String?

    /// Override global container flags for this project. nil = use global.
    var containerFlags: String?

    /// Color index into ProjectColor palette. Auto-assigned on creation, user-overridable.
    var colorIndex: Int?

    init(
        name: String,
        repositoryPath: String,
        filesToCopy: [String] = [".env", ".env.local"],
        symlinkPaths: [String] = [],
        setupCommands: [String] = [],
        autoStartClaude: Bool? = nil,
        claudeFlags: String? = nil,
        sandboxBackend: SandboxBackend? = nil,
        sbxFlags: String? = nil,
        containerImage: String? = nil,
        containerFlags: String? = nil,
        colorIndex: Int? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.repositoryPath = repositoryPath
        self.filesToCopy = filesToCopy
        self.symlinkPaths = symlinkPaths
        self.setupCommands = setupCommands
        self.autoStartClaude = autoStartClaude
        self.claudeFlags = claudeFlags
        self.sandboxBackend = sandboxBackend
        self.sbxFlags = sbxFlags
        self.containerImage = containerImage
        self.containerFlags = containerFlags
        self.colorIndex = colorIndex
    }

    /// Key used by versions before the backend enum existed. Decode-only.
    private enum LegacyCodingKeys: String, CodingKey {
        case useSandbox
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
        if let backend = try container.decodeIfPresent(SandboxBackend.self, forKey: .sandboxBackend) {
            sandboxBackend = backend
        } else {
            // A legacy boolean was an explicit per-project override, so
            // false must migrate to .off (not nil, which means "use global").
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            sandboxBackend = (try legacy.decodeIfPresent(Bool.self, forKey: .useSandbox)).map { $0 ? .dockerSbx : .off }
        }
        sbxFlags = try container.decodeIfPresent(String.self, forKey: .sbxFlags)
        containerImage = try container.decodeIfPresent(String.self, forKey: .containerImage)
        containerFlags = try container.decodeIfPresent(String.self, forKey: .containerFlags)
        colorIndex = try container.decodeIfPresent(Int.self, forKey: .colorIndex)
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

    /// Resolves the sandbox backend, falling back to global settings.
    func resolvedSandboxBackend(globalSettings: CanopySettings) -> SandboxBackend {
        sandboxBackend ?? globalSettings.sandboxBackend
    }

    /// Resolves the Claude command, falling back to global settings.
    /// See `SandboxBackend.claudeCommand` for the per-backend shapes.
    func resolvedClaudeCommand(globalSettings: CanopySettings) -> String {
        resolvedSandboxBackend(globalSettings: globalSettings).claudeCommand(
            claudeFlags: claudeFlags ?? globalSettings.claudeFlags,
            sbxFlags: sbxFlags ?? globalSettings.sbxFlags,
            containerImage: containerImage ?? globalSettings.containerImage,
            containerFlags: containerFlags ?? globalSettings.containerFlags
        )
    }
}

/// Seed values for the "Override global Claude settings" section of the
/// project sheets. Must be the EFFECTIVE values (project override if set,
/// else global): seeding hardcoded false/"" used to write unintended
/// overrides that silently disabled claude auto-start when the user only
/// wanted to change one setting.
struct ClaudeOverrideDefaults {
    let autoStartClaude: Bool
    let claudeFlags: String
    let sandboxBackend: SandboxBackend
    let sbxFlags: String

    init(project: Project?, settings: CanopySettings) {
        autoStartClaude = project?.autoStartClaude ?? settings.autoStartClaude
        claudeFlags = project?.claudeFlags ?? settings.claudeFlags
        sandboxBackend = project?.sandboxBackend ?? settings.sandboxBackend
        sbxFlags = project?.sbxFlags ?? settings.sbxFlags
    }
}
