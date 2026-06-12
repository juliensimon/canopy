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
        #expect(settings.containerImage == "")
        #expect(settings.containerFlags == "")
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

    @Test func claudeCommandWithAppleContainer() {
        var settings = CanopySettings()
        settings.sandboxBackend = .appleContainer
        settings.containerImage = "canopy-claude"
        #expect(settings.claudeCommand == #"container run -it --rm --volume "$PWD":"$PWD" --volume "$HOME/.claude":/root/.claude --volume "$HOME/.claude.json":/root/.claude.json --workdir "$PWD" canopy-claude claude --permission-mode auto"#)
    }

    @Test func claudeCommandAppleContainerWithFlags() {
        var settings = CanopySettings()
        settings.sandboxBackend = .appleContainer
        settings.containerImage = "canopy-claude:latest"
        settings.containerFlags = "--memory 8g --cpus 8"
        #expect(settings.claudeCommand == #"container run -it --rm --volume "$PWD":"$PWD" --volume "$HOME/.claude":/root/.claude --volume "$HOME/.claude.json":/root/.claude.json --workdir "$PWD" --memory 8g --cpus 8 canopy-claude:latest claude --permission-mode auto"#)
    }

    @Test func claudeCommandAppleContainerEmptyClaudeFlags() {
        var settings = CanopySettings()
        settings.sandboxBackend = .appleContainer
        settings.containerImage = "canopy-claude"
        settings.claudeFlags = "   "
        #expect(settings.claudeCommand == #"container run -it --rm --volume "$PWD":"$PWD" --volume "$HOME/.claude":/root/.claude --volume "$HOME/.claude.json":/root/.claude.json --workdir "$PWD" canopy-claude claude"#)
    }

    @Test func claudeCommandAppleContainerTrimsImageAndFlags() {
        var settings = CanopySettings()
        settings.sandboxBackend = .appleContainer
        settings.containerImage = "  canopy-claude  "
        settings.containerFlags = "  --memory 8g  "
        #expect(settings.claudeCommand == #"container run -it --rm --volume "$PWD":"$PWD" --volume "$HOME/.claude":/root/.claude --volume "$HOME/.claude.json":/root/.claude.json --workdir "$PWD" --memory 8g canopy-claude claude --permission-mode auto"#)
    }

    @Test func claudeCommandAppleContainerEmptyImageNeverRunsOnHost() {
        // An empty image is a misconfiguration (the UI prevents it), but the
        // command must still target the container runtime: silently falling
        // back to an unsandboxed `claude` would drop isolation the user asked for.
        var settings = CanopySettings()
        settings.sandboxBackend = .appleContainer
        settings.containerImage = ""
        #expect(settings.claudeCommand.hasPrefix("container run"))
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

    @Test func saveAndLoad() {
        var settings = CanopySettings()
        settings.autoStartClaude = true
        settings.claudeFlags = "--model haiku"
        settings.save()

        let loaded = CanopySettings.load()
        #expect(loaded.autoStartClaude == true)
        #expect(loaded.claudeFlags == "--model haiku")

        // Reset to defaults
        var reset = CanopySettings()
        reset.save()
    }
}
