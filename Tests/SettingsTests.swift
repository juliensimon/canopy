import Testing
import Foundation
@testable import Tempo

@Suite("TempoSettings")
struct SettingsTests {

    // MARK: - Defaults

    @Test func defaultValues() {
        let settings = TempoSettings()
        #expect(settings.autoStartClaude == false)
        #expect(settings.claudeFlags == "")
    }

    // MARK: - Claude Command

    @Test func claudeCommandDefault() {
        let settings = TempoSettings()
        #expect(settings.claudeCommand == "claude")
    }

    @Test func claudeCommandWithFlags() {
        var settings = TempoSettings()
        settings.claudeFlags = "--model sonnet --verbose"
        #expect(settings.claudeCommand == "claude --model sonnet --verbose")
    }

    @Test func claudeCommandTrimsWhitespace() {
        var settings = TempoSettings()
        settings.claudeFlags = "  --model opus  "
        #expect(settings.claudeCommand == "claude --model opus")
    }

    @Test func claudeCommandEmptyFlags() {
        var settings = TempoSettings()
        settings.claudeFlags = "   "
        #expect(settings.claudeCommand == "claude")
    }

    @Test func claudeCommandWithDangerousFlags() {
        var settings = TempoSettings()
        settings.claudeFlags = "--dangerously-skip-permissions"
        #expect(settings.claudeCommand == "claude --dangerously-skip-permissions")
    }

    // MARK: - Codable Round-Trip

    @Test func codableRoundTrip() throws {
        var original = TempoSettings()
        original.autoStartClaude = true
        original.claudeFlags = "--model sonnet --verbose"

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TempoSettings.self, from: data)

        #expect(decoded.autoStartClaude == true)
        #expect(decoded.claudeFlags == "--model sonnet --verbose")
    }

    @Test func decodesWithMissingFields() throws {
        // Simulate an older settings file that doesn't have all fields
        let json = "{}"
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TempoSettings.self, from: data)
        #expect(decoded.autoStartClaude == false)
        #expect(decoded.claudeFlags == "")
    }

    // MARK: - Persistence

    @Test func saveAndLoad() {
        var settings = TempoSettings()
        settings.autoStartClaude = true
        settings.claudeFlags = "--model haiku"
        settings.save()

        let loaded = TempoSettings.load()
        #expect(loaded.autoStartClaude == true)
        #expect(loaded.claudeFlags == "--model haiku")

        // Reset to defaults
        var reset = TempoSettings()
        reset.save()
    }
}
