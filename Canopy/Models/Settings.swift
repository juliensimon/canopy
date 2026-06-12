import Foundation

/// How Claude Code sessions are isolated from the host system.
enum SandboxBackend: String, Codable {
    /// No isolation -- claude runs directly on the host.
    case off
    /// Docker Sandboxes microVM (`sbx run`). Requires Docker Desktop.
    case dockerSbx
    /// Apple's `container` runtime -- one lightweight VM per container.
    /// Requires macOS 26+ on Apple silicon.
    case appleContainer

    /// Whether `--resume` works for this backend. Session JSONLs must
    /// persist on the host: sbx microVMs are ephemeral, while the Apple
    /// container backend bind-mounts ~/.claude from the host.
    var supportsResume: Bool { self != .dockerSbx }

    /// Builds the full command sent to the terminal for this backend.
    ///
    /// - `.dockerSbx`: `sbx run [sbx-flags] claude -- [claude-flags]`.
    ///   The `--` is always included so flags appended later (like `--resume`)
    ///   are passed to claude, not to sbx.
    /// - `.appleContainer`: host-side guards, then
    ///   `container run ... [container-flags] <image> sh -c '<settle>; exec claude [claude-flags] "$@"' claude`.
    ///   `"$PWD"` / `"$HOME"` are expanded by the shell the command is typed
    ///   into, which already runs in the worktree. The worktree is mounted at
    ///   its host path so session JSONLs land in the same
    ///   `~/.claude/projects/<munged-cwd>` directory as unsandboxed runs.
    ///   Details that exist for a reason:
    ///   - The guards create `~/.claude`/`~/.claude.json` so the mounts don't
    ///     fail on machines that never ran claude on the host.
    ///   - `--env`: the runtime forces TERM=xterm and strips COLORTERM/LANG,
    ///     degrading Claude Code's renderer; slim images only ship C.UTF-8.
    ///     DISABLE_AUTOUPDATER stops claude re-downloading updates into the
    ///     ephemeral container layer on every session.
    ///   - The sh wrapper waits (max 5s) for the container PTY to receive a
    ///     real window size: it briefly reads 0x0 at startup, which made
    ///     claude lay out for 80 columns and garble the terminal. Its `"$@"`
    ///     forwards externally appended args (`--resume`) to claude; the
    ///     trailing `claude` word is $0.
    ///   - With an empty image the command still targets `container run` --
    ///     it fails loudly rather than silently dropping isolation.
    /// `extraMountPaths`: additional host paths mounted at themselves.
    /// Used to mount the project's MAIN repository into worktree sessions --
    /// a worktree's `.git` file points at the main repo, so without that
    /// mount every git operation inside the container fails.
    func claudeCommand(claudeFlags: String, sbxFlags: String, containerImage: String, containerFlags: String, extraMountPaths: [String] = []) -> String {
        var parts: [String]
        let flags = claudeFlags.trimmingCharacters(in: .whitespaces)
        switch self {
        case .off:
            parts = ["claude"]
        case .dockerSbx:
            parts = ["sbx run"]
            let sbx = sbxFlags.trimmingCharacters(in: .whitespaces)
            if !sbx.isEmpty {
                parts.append(sbx)
            }
            parts.append("claude --")
        case .appleContainer:
            var run = #"mkdir -p "$HOME/.claude"; [ -f "$HOME/.claude.json" ] || printf '{}' > "$HOME/.claude.json"; [ -f "$HOME/.gitconfig" ] || touch "$HOME/.gitconfig"; container run -it --rm --env TERM=xterm-256color --env COLORTERM=truecolor --env LANG=C.UTF-8 --env LC_ALL=C.UTF-8 --env DISABLE_AUTOUPDATER=1 --volume "$PWD":"$PWD""#
            for path in extraMountPaths {
                // Mount the path git recorded: macOS /tmp-style symlinks must
                // resolve or the in-container path won't match .git contents.
                let resolved = Self.realResolvedPath(path)
                if !resolved.isEmpty {
                    run += #" --volume "\#(resolved)":"\#(resolved)""#
                }
            }
            run += #" --volume "$HOME/.claude":/root/.claude --volume "$HOME/.claude.json":/root/.claude.json --volume "$HOME/.gitconfig":/root/.gitconfig --workdir "$PWD""#
            parts = [run]
            let extra = containerFlags.trimmingCharacters(in: .whitespaces)
            if !extra.isEmpty {
                parts.append(extra)
            }
            let image = containerImage.trimmingCharacters(in: .whitespaces)
            if !image.isEmpty {
                parts.append(image)
            }
            let claudeInvocation = flags.isEmpty ? "claude" : "claude \(flags)"
            parts.append(#"sh -c 'i=0; while [ "$(stty size 2>/dev/null)" = "0 0" ] && [ $i -lt 100 ]; do sleep 0.05; i=$((i+1)); done; exec \#(claudeInvocation) "$@"' claude"#)
            return parts.joined(separator: " ")
        }
        if !flags.isEmpty {
            parts.append(flags)
        }
        return parts.joined(separator: " ")
    }

    /// Whether a sandboxed container session may run in this directory.
    /// Mounting $HOME (or an ancestor of it) overlaps the ~/.claude state
    /// mounts: observed to silently drop the workdir mount -- claude sees an
    /// empty project -- or hang the VM unkillably.
    static func isUnsafeContainerWorkingDirectory(_ path: String, home: String = NSHomeDirectory()) -> Bool {
        let resolved = realResolvedPath(path)
        let resolvedHome = realResolvedPath(home)
        if resolved == "/" { return true }
        return resolved == resolvedHome || resolvedHome.hasPrefix(resolved + "/")
    }

    /// realpath(3): resolves symlinks the way git records paths (e.g.
    /// /tmp -> /private/tmp). NSString.resolvingSymlinksInPath is unsuitable
    /// here -- it strips the /private prefix instead of adding it. Returns
    /// the input unchanged when the path doesn't exist.
    static func realResolvedPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}

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

    /// Which sandbox backend (if any) Claude Code sessions run inside.
    var sandboxBackend: SandboxBackend

    /// Additional flags passed to `sbx run` (e.g. "--memory 8g").
    var sbxFlags: String

    /// OCI image used by the Apple container backend. The default is built
    /// in-app (Settings > Build Image) from `ContainerImageBuilder.dockerfile`.
    var containerImage: String

    /// Additional flags passed to `container run` (e.g. "--memory 8g --cpus 8").
    var containerFlags: String

    /// Path to the GitHub CLI (`gh`). Used for PR status in the status bar.
    var ghPath: String

    /// Path to the sandbox CLI (`sbx`). Used for sandboxed sessions.
    var sbxPath: String

    /// Path to Apple's `container` CLI. Used by the Apple container backend.
    var containerPath: String

    var ideName: String {
        ((idePath as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    var terminalName: String {
        ((terminalPath as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    init(autoStartClaude: Bool = true, claudeFlags: String = "--permission-mode auto", confirmBeforeClosing: Bool = true, idePath: String = "/Applications/Cursor.app", terminalPath: String = "/System/Applications/Utilities/Terminal.app", notifyOnFinish: Bool = true, checkForUpdatesOnLaunch: Bool = true, sandboxBackend: SandboxBackend = .off, sbxFlags: String = "", containerImage: String = "canopy-claude", containerFlags: String = "", ghPath: String? = nil, sbxPath: String? = nil, containerPath: String? = nil) {
        self.autoStartClaude = autoStartClaude
        self.claudeFlags = claudeFlags
        self.confirmBeforeClosing = confirmBeforeClosing
        self.idePath = idePath
        self.terminalPath = terminalPath
        self.notifyOnFinish = notifyOnFinish
        self.checkForUpdatesOnLaunch = checkForUpdatesOnLaunch
        self.sandboxBackend = sandboxBackend
        self.sbxFlags = sbxFlags
        self.containerImage = containerImage
        self.containerFlags = containerFlags
        self.ghPath = ghPath ?? Self.detectCLI("gh")
        self.sbxPath = sbxPath ?? Self.detectCLI("sbx")
        self.containerPath = containerPath ?? Self.detectCLI("container")
    }

    /// Detects a CLI tool by checking common Homebrew and system paths.
    private static func detectCLI(_ name: String) -> String {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? ""
    }

    /// Key used by versions before the backend enum existed. Decode-only.
    private enum LegacyCodingKeys: String, CodingKey {
        case useSandbox
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
        if let raw = try container.decodeIfPresent(String.self, forKey: .sandboxBackend) {
            // Tolerant of unknown rawValues (config written by a newer
            // version): throwing here would fail the whole-file decode and
            // load()'s fallback would silently factory-reset all settings.
            sandboxBackend = SandboxBackend(rawValue: raw) ?? .off
        } else {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            let useSandbox = try legacy.decodeIfPresent(Bool.self, forKey: .useSandbox) ?? false
            sandboxBackend = useSandbox ? .dockerSbx : .off
        }
        sbxFlags = try container.decodeIfPresent(String.self, forKey: .sbxFlags) ?? ""
        containerImage = try container.decodeIfPresent(String.self, forKey: .containerImage) ?? "canopy-claude"
        containerFlags = try container.decodeIfPresent(String.self, forKey: .containerFlags) ?? ""
        ghPath = try container.decodeIfPresent(String.self, forKey: .ghPath) ?? Self.detectCLI("gh")
        sbxPath = try container.decodeIfPresent(String.self, forKey: .sbxPath) ?? Self.detectCLI("sbx")
        containerPath = try container.decodeIfPresent(String.self, forKey: .containerPath) ?? Self.detectCLI("container")
    }

    /// The full command sent to the terminal when auto-starting.
    /// See `SandboxBackend.claudeCommand` for the per-backend shapes.
    var claudeCommand: String {
        sandboxBackend.claudeCommand(
            claudeFlags: claudeFlags,
            sbxFlags: sbxFlags,
            containerImage: containerImage,
            containerFlags: containerFlags
        )
    }

    // MARK: - Persistence

    /// The real config file. Tests pass an explicit path instead so they
    /// never clobber the user's settings.
    private static var defaultFilePath: String {
        let configDir = (NSHomeDirectory() as NSString).appendingPathComponent(".config/canopy")
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        return (configDir as NSString).appendingPathComponent("settings.json")
    }

    static func load(from path: String = CanopySettings.defaultFilePath) -> CanopySettings {
        guard let data = FileManager.default.contents(atPath: path),
              let decoded = try? JSONDecoder().decode(CanopySettings.self, from: data) else {
            return CanopySettings()
        }
        return decoded
    }

    func save(to path: String = CanopySettings.defaultFilePath) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        FileManager.default.createFile(atPath: path, contents: data)
    }
}
