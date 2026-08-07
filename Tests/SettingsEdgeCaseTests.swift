import Testing
import Foundation
@testable import Canopy

/// Additional edge case tests for CanopySettings.
@Suite("CanopySettings Edge Cases")
struct SettingsEdgeCaseTests {

    // MARK: - IDE Name

    @Test func ideNameFromPath() {
        var settings = CanopySettings()
        settings.idePath = "/Applications/Cursor.app"
        #expect(settings.ideName == "Cursor")
    }

    @Test func ideNameFromVSCode() {
        var settings = CanopySettings()
        settings.idePath = "/Applications/Visual Studio Code.app"
        #expect(settings.ideName == "Visual Studio Code")
    }

    @Test func ideNameFromNestedPath() {
        var settings = CanopySettings()
        settings.idePath = "/usr/local/bin/code"
        #expect(settings.ideName == "code")
    }

    // MARK: - Custom Initialization

    @Test func customInit() {
        let settings = CanopySettings(
            autoStartClaude: false,
            claudeFlags: "--verbose",
            confirmBeforeClosing: false,
            idePath: "/Applications/Zed.app"
        )
        #expect(settings.autoStartClaude == false)
        #expect(settings.claudeFlags == "--verbose")
        #expect(settings.confirmBeforeClosing == false)
        #expect(settings.idePath == "/Applications/Zed.app")
        #expect(settings.ideName == "Zed")
    }

    // MARK: - Decoding with Partial JSON

    @Test func decodesWithOnlySomeFields() throws {
        let json = """
        {"autoStartClaude": false, "idePath": "/Applications/Zed.app"}
        """
        let data = json.data(using: .utf8)!
        let settings = try JSONDecoder().decode(CanopySettings.self, from: data)

        #expect(settings.autoStartClaude == false)
        #expect(settings.idePath == "/Applications/Zed.app")
        // Defaults for missing fields
        #expect(settings.claudeFlags == "--permission-mode auto")
        #expect(settings.confirmBeforeClosing == true)
    }

    @Test func decodesWithExtraFields() throws {
        // Forward compatibility: unknown keys should be ignored
        let json = """
        {"autoStartClaude": true, "futureField": "value", "anotherNew": 42}
        """
        let data = json.data(using: .utf8)!
        let settings = try JSONDecoder().decode(CanopySettings.self, from: data)
        #expect(settings.autoStartClaude == true)
    }

    // MARK: - Claude Command Edge Cases

    @Test func claudeCommandWithMultipleSpaces() {
        var settings = CanopySettings()
        settings.claudeFlags = "--model   opus   --verbose"
        // trimmingCharacters only trims leading/trailing
        #expect(settings.claudeCommand == "claude --model   opus   --verbose")
    }

    @Test func claudeCommandWithNewlines() {
        var settings = CanopySettings()
        settings.claudeFlags = "\n"
        // Newline is not whitespace in trimmingCharacters(in: .whitespaces)
        // .whitespaces only includes space and tab
        #expect(settings.claudeCommand == "claude \n")
    }

    /// Settings saved before the toggle existed must default it ON -- the
    /// whole point is that a blocked session is the thing you most need told
    /// about, so silence-by-default would be the wrong failure direction.
    @Test func notifyOnNeedsInputDefaultsTrueWhenAbsent() throws {
        let decoded = try JSONDecoder().decode(
            CanopySettings.self, from: Data("{}".utf8)
        )
        #expect(decoded.notifyOnNeedsInput)
    }

    @Test func notifyOnNeedsInputRoundTrips() throws {
        var settings = CanopySettings()
        settings.notifyOnNeedsInput = false
        let decoded = try JSONDecoder().decode(
            CanopySettings.self, from: try JSONEncoder().encode(settings)
        )
        #expect(!decoded.notifyOnNeedsInput)
    }

}
