import Testing
import Foundation
@testable import Canopy

@Suite("CanopySettings")
struct SettingsTests {

    // MARK: - Defaults

    @Test func defaultValues() {
        let settings = CanopySettings()
        #expect(settings.autoStartClaude == true)
        #expect(settings.claudeFlags == "--permission-mode auto")
        #expect(settings.confirmBeforeClosing == true)
        #expect(settings.idePath == "/Applications/Cursor.app")
        #expect(settings.terminalPath == "/System/Applications/Utilities/Terminal.app")
        #expect(settings.sandboxBackend == .off)
        #expect(settings.sbxFlags == "")
        #expect(settings.containerImage == "canopy-claude")
        #expect(settings.containerFlags == "")
    }

    @Test func containerImageDefaultsWhenMissingFromJSON() throws {
        // Users who saved settings before the field existed get the default
        // image, so the Apple container backend works without configuration.
        let decoded = try JSONDecoder().decode(CanopySettings.self, from: "{}".data(using: .utf8)!)
        #expect(decoded.containerImage == "canopy-claude")
    }

    // MARK: - Claude Command

    @Test func claudeCommandDefault() {
        let settings = CanopySettings()
        #expect(settings.claudeCommand == "claude --permission-mode auto")
    }

    @Test func claudeCommandWithFlags() {
        var settings = CanopySettings()
        settings.claudeFlags = "--model sonnet --verbose"
        #expect(settings.claudeCommand == "claude --model sonnet --verbose")
    }

    @Test func claudeCommandTrimsWhitespace() {
        var settings = CanopySettings()
        settings.claudeFlags = "  --model opus  "
        #expect(settings.claudeCommand == "claude --model opus")
    }

    @Test func claudeCommandEmptyFlags() {
        var settings = CanopySettings()
        settings.claudeFlags = "   "
        #expect(settings.claudeCommand == "claude")
    }

    @Test func claudeCommandWithDangerousFlags() {
        var settings = CanopySettings()
        settings.claudeFlags = "--dangerously-skip-permissions"
        #expect(settings.claudeCommand == "claude --dangerously-skip-permissions")
    }

    // MARK: - Codable Round-Trip

    @Test func codableRoundTrip() throws {
        var original = CanopySettings()
        original.autoStartClaude = true
        original.claudeFlags = "--model sonnet --verbose"

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CanopySettings.self, from: data)

        #expect(decoded.autoStartClaude == true)
        #expect(decoded.claudeFlags == "--model sonnet --verbose")
    }

    @Test func decodesWithMissingFields() throws {
        let json = "{}"
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(CanopySettings.self, from: data)
        #expect(decoded.autoStartClaude == true)
        #expect(decoded.claudeFlags == "--permission-mode auto")
        #expect(decoded.confirmBeforeClosing == true)
        #expect(decoded.terminalPath == "/System/Applications/Utilities/Terminal.app")
        #expect(decoded.sandboxBackend == .off)
        #expect(decoded.sbxFlags == "")
    }

    // MARK: - IDE / Terminal Names

    @Test func ideNameExtracted() {
        var settings = CanopySettings()
        settings.idePath = "/Applications/Cursor.app"
        #expect(settings.ideName == "Cursor")
    }

    @Test func terminalNameExtracted() {
        var settings = CanopySettings()
        settings.terminalPath = "/Applications/iTerm.app"
        #expect(settings.terminalName == "iTerm")
    }

    @Test func terminalNameDefault() {
        let settings = CanopySettings()
        #expect(settings.terminalName == "Terminal")
    }

    @Test func terminalPathRoundTrip() throws {
        var original = CanopySettings()
        original.terminalPath = "/Applications/iTerm.app"

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CanopySettings.self, from: data)

        #expect(decoded.terminalPath == "/Applications/iTerm.app")
    }

    // MARK: - notifyOnFinish

    @Test func notifyOnFinishDefaultTrue() {
        let settings = CanopySettings()
        #expect(settings.notifyOnFinish == true)
    }

    @Test func notifyOnFinishCodableRoundTrip() throws {
        var settings = CanopySettings()
        settings.notifyOnFinish = false
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(CanopySettings.self, from: data)
        #expect(decoded.notifyOnFinish == false)
    }

    @Test func notifyOnFinishDecodesFromEmpty() throws {
        let json = "{}"
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(CanopySettings.self, from: data)
        #expect(decoded.notifyOnFinish == true)
    }

    // MARK: - Sandbox (Docker sbx backend)

    @Test func claudeCommandWithSandbox() {
        var settings = CanopySettings()
        settings.sandboxBackend = .dockerSbx
        #expect(settings.claudeCommand == "sbx run claude -- --permission-mode auto")
    }

    @Test func claudeCommandWithSandboxFlags() {
        var settings = CanopySettings()
        settings.sandboxBackend = .dockerSbx
        settings.sbxFlags = "--memory 8g"
        #expect(settings.claudeCommand == "sbx run --memory 8g claude -- --permission-mode auto")
    }

    @Test func claudeCommandSandboxOffIgnoresSbxFlags() {
        var settings = CanopySettings()
        settings.sandboxBackend = .off
        settings.sbxFlags = "--memory 8g"
        #expect(settings.claudeCommand == "claude --permission-mode auto")
    }

    @Test func sandboxCodableRoundTrip() throws {
        var original = CanopySettings()
        original.sandboxBackend = .dockerSbx
        original.sbxFlags = "--memory 8g"

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CanopySettings.self, from: data)

        #expect(decoded.sandboxBackend == .dockerSbx)
        #expect(decoded.sbxFlags == "--memory 8g")
    }

    @Test func claudeCommandSandboxTrimsWhitespace() {
        var settings = CanopySettings()
        settings.sandboxBackend = .dockerSbx
        settings.sbxFlags = "  --memory 8g  "
        #expect(settings.claudeCommand == "sbx run --memory 8g claude -- --permission-mode auto")
    }

    @Test func claudeCommandSandboxEmptyFlags() {
        var settings = CanopySettings()
        settings.sandboxBackend = .dockerSbx
        settings.sbxFlags = "   "
        settings.claudeFlags = ""
        #expect(settings.claudeCommand == "sbx run claude --")
    }

    // MARK: - Sandbox (Apple container backend)

    /// The full golden command. Structure, in order:
    /// 1. Host-side guards so fresh machines (no ~/.claude yet) can mount.
    /// 2. `container run` with env propagated: the runtime forces TERM=xterm
    ///    and strips COLORTERM/LANG, which degrades Claude Code's renderer;
    ///    slim images only ship the C.UTF-8 locale. DISABLE_AUTOUPDATER stops
    ///    claude self-updating into the ephemeral container layer every run.
    /// 3. Worktree mounted at its host path + ~/.claude state mounts.
    /// 4. A sh wrapper that waits for the container PTY to receive its real
    ///    window size before exec'ing claude (it briefly reads 0x0 at start,
    ///    making claude lay out for 80 columns and garble the terminal), and
    ///    forwards externally appended args (--resume) to claude via "$@".
    @Test func claudeCommandWithAppleContainer() {
        var settings = CanopySettings()
        settings.sandboxBackend = .appleContainer
        settings.containerImage = "canopy-claude"
        #expect(settings.claudeCommand == #"mkdir -p "$HOME/.claude"; [ -f "$HOME/.claude.json" ] || printf '{}' > "$HOME/.claude.json"; [ -f "$HOME/.gitconfig" ] || touch "$HOME/.gitconfig"; container run -it --rm --env TERM=xterm-256color --env COLORTERM=truecolor --env LANG=C.UTF-8 --env LC_ALL=C.UTF-8 --env DISABLE_AUTOUPDATER=1 --volume "$PWD":"$PWD" --volume "$HOME/.claude":/root/.claude --volume "$HOME/.claude.json":/root/.claude.json --volume "$HOME/.gitconfig":/root/.gitconfig --workdir "$PWD" canopy-claude sh -c 'i=0; while [ "$(stty size 2>/dev/null)" = "0 0" ] && [ $i -lt 100 ]; do sleep 0.05; i=$((i+1)); done; exec claude --permission-mode auto "$@"' claude"#)
    }

    @Test func claudeCommandAppleContainerExtraMountsResolveSymlinks() throws {
        // The extra mount is the worktree's MAIN repo (its .git file points
        // there). git records the RESOLVED path, so /tmp must mount as
        // /private/tmp or the in-container lookup fails.
        let dir = "/tmp/canopy-mount-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let backend = SandboxBackend.appleContainer
        let command = backend.claudeCommand(
            claudeFlags: "", sbxFlags: "", containerImage: "img", containerFlags: "",
            extraMountPaths: [dir]
        )
        #expect(command.contains(#"--volume "/private\#(dir)":"/private\#(dir)""#))
    }

    @Test func unsafeContainerWorkingDirectories() {
        // $HOME (or an ancestor) overlaps the ~/.claude mounts: the workdir
        // mount is silently dropped or the VM hangs.
        #expect(SandboxBackend.isUnsafeContainerWorkingDirectory("/Users/x", home: "/Users/x"))
        #expect(SandboxBackend.isUnsafeContainerWorkingDirectory("/Users", home: "/Users/x"))
        #expect(SandboxBackend.isUnsafeContainerWorkingDirectory("/", home: "/Users/x"))
        #expect(!SandboxBackend.isUnsafeContainerWorkingDirectory("/Users/x/dev/proj", home: "/Users/x"))
        #expect(!SandboxBackend.isUnsafeContainerWorkingDirectory("/Users/xyz", home: "/Users/x"))
    }

    @Test func claudeCommandAppleContainerWithFlags() {
        var settings = CanopySettings()
        settings.sandboxBackend = .appleContainer
        settings.containerImage = "canopy-claude:latest"
        settings.containerFlags = "--memory 8g --cpus 8"
        let command = settings.claudeCommand
        // Container flags go before the image; image before the wrapper.
        #expect(command.contains(#"--workdir "$PWD" --memory 8g --cpus 8 canopy-claude:latest sh -c"#))
    }

    @Test func claudeCommandAppleContainerEmptyClaudeFlags() {
        var settings = CanopySettings()
        settings.sandboxBackend = .appleContainer
        settings.containerImage = "canopy-claude"
        settings.claudeFlags = "   "
        #expect(settings.claudeCommand.contains(#"exec claude "$@""#))
    }

    @Test func claudeCommandAppleContainerTrimsImageAndFlags() {
        var settings = CanopySettings()
        settings.sandboxBackend = .appleContainer
        settings.containerImage = "  canopy-claude  "
        settings.containerFlags = "  --memory 8g  "
        #expect(settings.claudeCommand.contains(#"--workdir "$PWD" --memory 8g canopy-claude sh -c"#))
    }

    @Test func claudeCommandAppleContainerEscapesSingleQuotesInFlags() {
        // The claude invocation lives inside the wrapper's single-quoted
        // sh -c string: an unescaped quote in user flags would terminate it
        // early and leak the rest as shell tokens (injection).
        var settings = CanopySettings()
        settings.sandboxBackend = .appleContainer
        settings.containerImage = "canopy-claude"
        settings.claudeFlags = "--append-system-prompt 'be nice'"
        #expect(settings.claudeCommand.contains(#"exec claude --append-system-prompt '\''be nice'\'' "$@""#))
    }

    @Test func claudeCommandAppleContainerResumeAppendReachesClaude() {
        // MainWindow appends " --resume <id>" to the command. The wrapper's
        // trailing $0 word is `claude`, so appended text becomes positional
        // args forwarded to claude via "$@" inside the container.
        var settings = CanopySettings()
        settings.sandboxBackend = .appleContainer
        settings.containerImage = "canopy-claude"
        let command = settings.claudeCommand + " --resume abc-123"
        #expect(command.hasSuffix(#"' claude --resume abc-123"#))
        #expect(command.contains(#"exec claude --permission-mode auto "$@""#))
    }

    @Test func claudeCommandAppleContainerEmptyImageNeverRunsOnHost() {
        // An empty image is a misconfiguration (the UI prevents it), but the
        // command must still target the container runtime: silently falling
        // back to an unsandboxed `claude` would drop isolation the user asked for.
        var settings = CanopySettings()
        settings.sandboxBackend = .appleContainer
        settings.containerImage = ""
        #expect(settings.claudeCommand.contains("container run"))
        #expect(!settings.claudeCommand.hasPrefix("claude"))
    }

    @Test func unknownBackendRawValueDecodesAsOffWithoutLosingOtherSettings() throws {
        // A config written by a NEWER Canopy (with a backend this build
        // doesn't know) must not throw: load()'s try? fallback would
        // silently factory-reset the user's entire settings file.
        let json = #"{"sandboxBackend": "futureBackend", "claudeFlags": "--model opus"}"#
        let decoded = try JSONDecoder().decode(CanopySettings.self, from: json.data(using: .utf8)!)
        #expect(decoded.sandboxBackend == .off)
        #expect(decoded.claudeFlags == "--model opus")
    }

    @Test func appleContainerCodableRoundTrip() throws {
        var original = CanopySettings()
        original.sandboxBackend = .appleContainer
        original.containerImage = "canopy-claude"
        original.containerFlags = "--memory 8g"

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CanopySettings.self, from: data)

        #expect(decoded.sandboxBackend == .appleContainer)
        #expect(decoded.containerImage == "canopy-claude")
        #expect(decoded.containerFlags == "--memory 8g")
    }

    // MARK: - Legacy useSandbox Migration

    @Test func legacyUseSandboxTrueMigratesToDockerSbx() throws {
        // Settings saved before the backend enum existed used a boolean.
        let json = #"{"useSandbox": true, "sbxFlags": "--memory 8g"}"#
        let decoded = try JSONDecoder().decode(CanopySettings.self, from: json.data(using: .utf8)!)
        #expect(decoded.sandboxBackend == .dockerSbx)
        #expect(decoded.sbxFlags == "--memory 8g")
    }

    @Test func legacyUseSandboxFalseMigratesToOff() throws {
        let json = #"{"useSandbox": false}"#
        let decoded = try JSONDecoder().decode(CanopySettings.self, from: json.data(using: .utf8)!)
        #expect(decoded.sandboxBackend == .off)
    }

    @Test func explicitBackendWinsOverLegacyKey() throws {
        let json = #"{"useSandbox": true, "sandboxBackend": "appleContainer"}"#
        let decoded = try JSONDecoder().decode(CanopySettings.self, from: json.data(using: .utf8)!)
        #expect(decoded.sandboxBackend == .appleContainer)
    }

    // MARK: - Persistence

    // Persists to a temp path: tests must never touch the user's real
    // ~/.config/canopy/settings.json (this test used to reset it to
    // defaults on every run).
    @Test func saveAndLoad() throws {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("canopy-settings-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = (dir as NSString).appendingPathComponent("settings.json")

        var settings = CanopySettings()
        settings.autoStartClaude = true
        settings.claudeFlags = "--model haiku"
        settings.save(to: path)

        let loaded = CanopySettings.load(from: path)
        #expect(loaded.autoStartClaude == true)
        #expect(loaded.claudeFlags == "--model haiku")
    }

    @Test func loadFromMissingPathReturnsDefaults() {
        let loaded = CanopySettings.load(from: "/nonexistent/canopy/settings.json")
        #expect(loaded.claudeFlags == "--permission-mode auto")
        #expect(loaded.sandboxBackend == .off)
    }

    @Test func loadFromCorruptFileBacksItUpBeforeResetting() throws {
        // A corrupt file must not silently flatten the user's config (which
        // would also silently turn sandboxing OFF) -- keep the evidence.
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("canopy-settings-corrupt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = (dir as NSString).appendingPathComponent("settings.json")
        try "{not json".write(toFile: path, atomically: true, encoding: .utf8)

        let loaded = CanopySettings.load(from: path)

        #expect(loaded.sandboxBackend == .off) // defaults
        #expect(FileManager.default.fileExists(atPath: path + ".corrupt"))
    }

    @Test func saveReportsFailure() {
        let settings = CanopySettings()
        #expect(settings.save(to: "/nonexistent-dir-xyz/settings.json") == false)

        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("canopy-save-ok-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(settings.save(to: (dir as NSString).appendingPathComponent("settings.json")) == true)
    }
}
