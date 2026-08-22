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
    /// Claude Code's own Bash sandbox, built on macOS Seatbelt. Nothing to
    /// install, no image, no daemon.
    ///
    /// Weaker than a microVM and deliberately so: only Bash is sandboxed
    /// (Read/Edit/Write go through the permission system instead), reads
    /// default to the whole machine including ~/.ssh and ~/.aws/credentials,
    /// and it shares the kernel, user session and TCC context. Upstream is
    /// explicit that it "reduces risk but is not a complete isolation
    /// boundary", so `.appleContainer` remains the paranoid option.
    case claudeNative

    /// The `--settings` payload enabling Claude Code's own Bash sandbox.
    ///
    /// `allowUnsandboxedCommands` is explicitly false because the CLI defaults
    /// it to TRUE: with `enabled` alone, the model may retry any blocked
    /// command via `dangerouslyDisableSandbox`, and Canopy's default
    /// `--permission-mode auto` auto-approves that retry. Observed end to end:
    /// a `touch ~/probe.txt` denied by the sandbox succeeded immediately on
    /// the unsandboxed retry, so the picker was promising isolation it did not
    /// deliver.
    ///
    /// This is a different thing from inventing an allowlist. `allowedDomains`
    /// and `excludedCommands` are user preferences and are deliberately left
    /// to merge from the user's own settings; this key is the difference
    /// between "sandboxed" and "sandboxed unless the agent asks nicely", and
    /// the user picked a sandbox.
    private var sandboxSettingsJSON: String {
        #"{"sandbox":{"enabled":true,"allowUnsandboxedCommands":false}}"#
    }

    /// Human-readable name, so the four sandbox pickers and Session Info
    /// stop each carrying their own copy of these strings -- that duplication
    /// is why `.claudeNative` reached only two of the four pickers.
    var displayName: String {
        switch self {
        case .off: return "Off"
        case .claudeNative: return "Claude sandbox (Bash only)"
        case .dockerSbx: return "Docker Sandbox (sbx)"
        case .appleContainer: return "Apple container"
        }
    }

    /// Whether `claude` runs as a plain host process, so the host's
    /// `claude agents --json` registry actually describes it.
    ///
    /// `.claudeNative` qualifies: Seatbelt confines what Bash may touch, but
    /// the process is an ordinary host grandchild of Canopy's PTY shell.
    /// `.appleContainer` does not -- it writes its registry entry into the
    /// bind-mounted host ~/.claude, but the pid is a guest-namespace pid and
    /// the peer socket is unreachable from the host. `.dockerSbx` shares
    /// nothing of ~/.claude at all.
    var reportsToHostAgentRegistry: Bool { self == .off || self == .claudeNative }

    /// Whether the registry entry this backend writes can be trusted to say
    /// *which conversation* a session is running, as opposed to how busy it is.
    ///
    /// A wider set than `reportsToHostAgentRegistry`, because that gate covers
    /// only half of what it was doing. `.appleContainer` bind-mounts
    /// ~/.claude, so its entry and its transcript both land on the host --
    /// which is precisely why Canopy can read its transcript at all. What
    /// cannot be trusted there is status: the peer socket is unreachable.
    ///
    /// The guest-namespace pid is no obstacle to identity. Nothing here
    /// resolves a pid to a host process; it only compares one against a pid
    /// the same entry reported earlier, and a guest pid is stable for the
    /// process that owns it. `startedAt` is namespace-independent, so the pair
    /// works as an opaque equality token inside a container exactly as outside.
    ///
    /// `.dockerSbx` shares nothing of ~/.claude, so nothing about it can be
    /// believed -- not status, and not identity either.
    var reportsHostRegistryIdentity: Bool {
        reportsToHostAgentRegistry || self == .appleContainer
    }

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
    /// `disableAltScreen`: containers don't inherit the host PTY environment,
    /// so the alternate-screen opt-out (see `CanopySettings.disableAltScreen`)
    /// must be injected as a `--env` flag here.
    func claudeCommand(claudeFlags: String, sbxFlags: String, containerImage: String, containerFlags: String, extraMountPaths: [String] = [], disableAltScreen: Bool) -> String {
        var parts: [String]
        let flags = claudeFlags.trimmingCharacters(in: .whitespaces)
        switch self {
        case .off:
            parts = ["claude"]
        case .claudeNative:
            // --settings takes inline JSON as well as a path (verified on
            // 2.1.224), so nothing is written to disk. A file would be the
            // wrong answer twice over: a .claude/settings.local.json in the
            // worktree is a PROJECT-scope source, which per the docs cannot
            // set the sandbox keys at all, and it would litter the user's repo
            // beyond the session.
            //
            // Payload is the minimum on purpose: --settings MERGES with the
            // user's own settings, so their allowedDomains, credentials and
            // excludedCommands still apply. Canopy inventing an allowlist here
            // would fight their configuration.
            //
            // One shell token: the blob contains {, } and " and must not split.
            parts = ["claude", "--settings", Self.shellSingleQuoted(sandboxSettingsJSON)]
        case .dockerSbx:
            parts = ["sbx run"]
            let sbx = sbxFlags.trimmingCharacters(in: .whitespaces)
            if !sbx.isEmpty {
                parts.append(sbx)
            }
            parts.append("claude")
            // Extra workspaces are POSITIONAL arguments to `sbx run`
            // (`sbx run [AGENT] [PATH...]`), and naming any of them means
            // naming the cwd as "." too. Without this the worktree's `.git`
            // pointer dangles inside the sandbox and every git command fails
            // with "not a git repository" (reproduced on sbx 0.38.0).
            //
            // Writable, NOT ":ro": a worktree commit writes objects into the
            // main repo's .git, so a read-only mount would break committing.
            let workspaces = extraMountPaths
                .map { Self.realResolvedPath($0) }
                .filter { !$0.isEmpty }
            if !workspaces.isEmpty {
                parts.append(".")
                parts.append(contentsOf: workspaces.map { Self.shellSingleQuoted($0) })
            }
            // Everything after this reaches claude, not sbx.
            parts.append("--")
        case .appleContainer:
            var run = #"mkdir -p "$HOME/.claude"; [ -f "$HOME/.claude.json" ] || printf '{}' > "$HOME/.claude.json"; [ -f "$HOME/.gitconfig" ] || touch "$HOME/.gitconfig"; container run -it --rm --env TERM=xterm-256color --env COLORTERM=truecolor --env LANG=C.UTF-8 --env LC_ALL=C.UTF-8 --env DISABLE_AUTOUPDATER=1"#
            if disableAltScreen {
                run += " --env CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1"
            }
            run += #" --volume "$PWD":"$PWD""#
            for path in extraMountPaths {
                // Mount the path git recorded: macOS /tmp-style symlinks must
                // resolve or the in-container path won't match .git contents.
                let resolved = Self.realResolvedPath(path)
                if !resolved.isEmpty {
                    run += #" --volume "\#(resolved)":"\#(resolved)""#
                }
            }
            // .gitconfig is read-only: a sandboxed agent writing an alias or
            // core.hooksPath there would execute on the HOST the next time
            // the user runs git. The other mounts must stay writable
            // (sessions land in ~/.claude; worktree commits write objects
            // into the main repo's .git).
            run += #" --volume "$HOME/.claude":/root/.claude --volume "$HOME/.claude.json":/root/.claude.json --volume "$HOME/.gitconfig":/root/.gitconfig:ro --workdir "$PWD""#
            parts = [run]
            let extra = containerFlags.trimmingCharacters(in: .whitespaces)
            if !extra.isEmpty {
                parts.append(extra)
            }
            let image = containerImage.trimmingCharacters(in: .whitespaces)
            if !image.isEmpty {
                // One shell token: spaces/metacharacters in the user-supplied
                // image name must not split or inject.
                parts.append(Self.shellSingleQuoted(image))
            }
            // The invocation lives inside the wrapper's single quotes: a
            // single quote in user flags would terminate the string early
            // and leak tokens into the shell. POSIX-escape them.
            let escapedFlags = flags.replacingOccurrences(of: "'", with: #"'\''"#)
            let claudeInvocation = escapedFlags.isEmpty ? "claude" : "claude \(escapedFlags)"
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

    /// Wraps a user-supplied value as ONE shell token, escaping embedded
    /// single quotes (which would otherwise terminate the quoting and leak
    /// the rest as shell tokens).
    static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
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

    /// Notify when a session becomes blocked waiting on the user. Separate
    /// from notifyOnFinish because it is the more urgent of the two: a
    /// finished session costs you nothing, a stalled one costs you the turn.
    var notifyOnNeedsInput: Bool

    /// Keep the terminal scroll bar by opting Claude Code out of the
    /// alternate screen buffer (CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1).
    /// Claude Code ≥ 2.1.206 renders in the alt buffer, where SwiftTerm has
    /// no scrollback and disables its scroller (#40).
    var disableAltScreen: Bool

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

    init(autoStartClaude: Bool = true, claudeFlags: String = "--permission-mode auto", confirmBeforeClosing: Bool = true, idePath: String = "/Applications/Cursor.app", terminalPath: String = "/System/Applications/Utilities/Terminal.app", notifyOnFinish: Bool = true, notifyOnNeedsInput: Bool = true, disableAltScreen: Bool = true, checkForUpdatesOnLaunch: Bool = true, sandboxBackend: SandboxBackend = .off, sbxFlags: String = "", containerImage: String = "canopy-claude", containerFlags: String = "", ghPath: String? = nil, sbxPath: String? = nil, containerPath: String? = nil) {
        self.autoStartClaude = autoStartClaude
        self.claudeFlags = claudeFlags
        self.confirmBeforeClosing = confirmBeforeClosing
        self.idePath = idePath
        self.terminalPath = terminalPath
        self.notifyOnFinish = notifyOnFinish
        self.notifyOnNeedsInput = notifyOnNeedsInput
        self.disableAltScreen = disableAltScreen
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
        // Absent in settings saved before this existed -> default on.
        notifyOnNeedsInput = try container.decodeIfPresent(Bool.self, forKey: .notifyOnNeedsInput) ?? true
        disableAltScreen = try container.decodeIfPresent(Bool.self, forKey: .disableAltScreen) ?? true
        checkForUpdatesOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .checkForUpdatesOnLaunch) ?? true
        if let raw = try container.decodeIfPresent(String.self, forKey: .sandboxBackend) {
            // Tolerant of unknown rawValues (config written by a newer
            // version): throwing here would fail the whole-file decode and
            // load()'s fallback would silently factory-reset all settings.
            let decodedBackend = SandboxBackend(rawValue: raw)
            sandboxBackend = decodedBackend ?? .off
            if decodedBackend == nil {
                // Fail-safe direction, but not a silent one: a user who picked
                // a sandbox and then downgraded Canopy ends up UNSANDBOXED,
                // which is exactly what the save() return-value guard exists
                // to prevent elsewhere.
                NSLog("Canopy: unknown sandboxBackend %@ in settings; falling back to off (unsandboxed)", raw)
            }
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
            containerFlags: containerFlags,
            disableAltScreen: disableAltScreen
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
        guard let data = FileManager.default.contents(atPath: path) else {
            return CanopySettings() // no file yet: defaults are correct
        }
        do {
            return try JSONDecoder().decode(CanopySettings.self, from: data)
        } catch {
            // Corrupt file: returning defaults silently flattens the user's
            // config (including turning sandboxing OFF). Keep the evidence.
            NSLog("Canopy: settings.json failed to decode (%@); backing up to settings.json.corrupt", "\(error)")
            try? FileManager.default.removeItem(atPath: path + ".corrupt")
            try? FileManager.default.copyItem(atPath: path, toPath: path + ".corrupt")
            return CanopySettings()
        }
    }

    /// Returns false when the settings could not be written -- callers must
    /// surface that: a user who picked a sandbox and "saved" must not
    /// silently end up unsandboxed on next launch.
    @discardableResult
    func save(to path: String = CanopySettings.defaultFilePath) -> Bool {
        guard let data = try? JSONEncoder().encode(self) else {
            NSLog("Canopy: failed to encode settings")
            return false
        }
        do {
            // Atomic: a crash mid-write must not leave a truncated file.
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            NSLog("Canopy: failed to write %@ (%@)", path, "\(error)")
            return false
        }
    }
}
