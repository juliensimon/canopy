import Foundation

/// App-wide settings persisted to ~/.config/canopy/settings.json.
struct CanopySettings: Codable {
    /// Automatically run `claude` when opening a new terminal session.
    var autoStartClaude: Bool

    /// Default CLI flags passed to `claude` on auto-start.
    var claudeFlags: String

    /// Whether to ask for confirmation before closing a session.
    var confirmBeforeClosing: Bool

    /// Path to the IDE application used for "Open in IDE".
    /// Defaults to Cursor.
    var idePath: String

    /// Path to the terminal application used for "Open in Terminal".
    /// Defaults to Terminal.app.
    var terminalPath: String

    /// Whether to show macOS notifications when a session finishes.
    var notifyOnFinish: Bool

    /// Whether to check GitHub for a newer Canopy release on launch (rate-limited to once per day).
    var checkForUpdatesOnLaunch: Bool

    /// Whether to run Claude Code inside a Docker Sandbox (sbx) microVM.
    var useSandbox: Bool

    /// Additional flags passed to `sbx run` (e.g. "--memory 8g").
    var sbxFlags: String

    /// Path to the GitHub CLI (`gh`). Used for PR status in the status bar.
    var ghPath: String

    /// Path to the sandbox CLI (`sbx`). Used for sandboxed sessions.
    var sbxPath: String

    var ideName: String {
        ((idePath as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    var terminalName: String {
        ((terminalPath as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    init(autoStartClaude: Bool = true, claudeFlags: String = "--permission-mode auto", confirmBeforeClosing: Bool = true, idePath: String = "/Applications/Cursor.app", terminalPath: String = "/System/Applications/Utilities/Terminal.app", notifyOnFinish: Bool = true, checkForUpdatesOnLaunch: Bool = true, useSandbox: Bool = false, sbxFlags: String = "", ghPath: String? = nil, sbxPath: String? = nil) {
        self.autoStartClaude = autoStartClaude
        self.claudeFlags = claudeFlags
        self.confirmBeforeClosing = confirmBeforeClosing
        self.idePath = idePath
        self.terminalPath = terminalPath
        self.notifyOnFinish = notifyOnFinish
        self.checkForUpdatesOnLaunch = checkForUpdatesOnLaunch
        self.useSandbox = useSandbox
        self.sbxFlags = sbxFlags
        self.ghPath = ghPath ?? Self.detectCLI("gh")
        self.sbxPath = sbxPath ?? Self.detectCLI("sbx")
    }

    /// Detects a CLI tool by checking common Homebrew and system paths.
    private static func detectCLI(_ name: String) -> String {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/\(name)"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoStartClaude = try container.decodeIfPresent(Bool.self, forKey: .autoStartClaude) ?? true
        claudeFlags = try container.decodeIfPresent(String.self, forKey: .claudeFlags) ?? "--permission-mode auto"
        confirmBeforeClosing = try container.decodeIfPresent(Bool.self, forKey: .confirmBeforeClosing) ?? true
        idePath = try container.decodeIfPresent(String.self, forKey: .idePath) ?? "/Applications/Cursor.app"
        terminalPath = try container.decodeIfPresent(String.self, forKey: .terminalPath) ?? "/System/Applications/Utilities/Terminal.app"
        notifyOnFinish = try container.decodeIfPresent(Bool.self, forKey: .notifyOnFinish) ?? true
        checkForUpdatesOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .checkForUpdatesOnLaunch) ?? true
        useSandbox = try container.decodeIfPresent(Bool.self, forKey: .useSandbox) ?? false
        sbxFlags = try container.decodeIfPresent(String.self, forKey: .sbxFlags) ?? ""
        ghPath = try container.decodeIfPresent(String.self, forKey: .ghPath) ?? Self.detectCLI("gh")
        sbxPath = try container.decodeIfPresent(String.self, forKey: .sbxPath) ?? Self.detectCLI("sbx")
    }

    /// The full command sent to the terminal when auto-starting.
    ///
    /// When sandbox mode is enabled, `--` separates sbx flags from claude flags:
    /// `sbx run [sbx-flags] claude -- [claude-flags]`
    /// The `--` is always included in sandbox mode so that flags appended later
    /// (like `--resume`) are correctly passed to claude, not to sbx.
    var claudeCommand: String {
        var parts: [String] = []
        if useSandbox {
            parts.append("sbx run")
            let trimmedSbx = sbxFlags.trimmingCharacters(in: .whitespaces)
            if !trimmedSbx.isEmpty {
                parts.append(trimmedSbx)
            }
            parts.append("claude --")
            let trimmed = claudeFlags.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                parts.append(trimmed)
            }
        } else {
            parts.append("claude")
            let trimmed = claudeFlags.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                parts.append(trimmed)
            }
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Persistence

    private static var filePath: String {
        let configDir = (NSHomeDirectory() as NSString).appendingPathComponent(".config/canopy")
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        return (configDir as NSString).appendingPathComponent("settings.json")
    }

    static func load() -> CanopySettings {
        guard let data = FileManager.default.contents(atPath: filePath),
              let decoded = try? JSONDecoder().decode(CanopySettings.self, from: data) else {
            return CanopySettings()
        }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        FileManager.default.createFile(atPath: Self.filePath, contents: data)
    }
}
