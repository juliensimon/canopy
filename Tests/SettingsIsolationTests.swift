import Testing
import Foundation
@testable import Canopy

/// `AppState(configDir:)` must isolate ALL three config files, not just two.
///
/// `settings` was initialised as a stored-property default, which cannot see
/// the injected `configDir` and so always resolved the real
/// `~/.config/canopy/settings.json`. That made every test that did not
/// explicitly assign `state.settings.…` run against whatever the developer
/// happened to have configured -- a test could pass locally and fail in CI
/// (where no settings file exists) for reasons invisible in its body, and
/// changing your own sandbox preference could turn the suite red.
///
/// `CanopySettings.defaultFilePath` already documents the intent: "Tests pass
/// an explicit path instead so they never clobber the user's settings." The
/// AppState property initializer defeated it.
@Suite("Settings isolation")
@MainActor
struct SettingsIsolationTests {

    private func tempDir() -> String {
        NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)"
    }

    /// The regression test: an empty config dir must yield DEFAULTS, not the
    /// developer's real configuration. This fails on any machine whose real
    /// settings.json differs from the defaults.
    @Test func emptyConfigDirYieldsDefaultsNotTheRealFile() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let state = AppState(configDir: dir)

        #expect(state.settings.sandboxBackend == CanopySettings().sandboxBackend)
        #expect(state.settings.claudeFlags == CanopySettings().claudeFlags)
        #expect(state.settings.containerImage == CanopySettings().containerImage)
    }

    @Test func settingsAreLoadedFromInjectedConfigDir() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        var written = CanopySettings()
        written.sandboxBackend = .appleContainer
        written.claudeFlags = "--model fable"
        #expect(written.save(to: (dir as NSString).appendingPathComponent("settings.json")))

        let state = AppState(configDir: dir)
        #expect(state.settings.sandboxBackend == .appleContainer)
        #expect(state.settings.claudeFlags == "--model fable")
    }

    /// Saving must land in the injected dir too, or a test that saves would
    /// overwrite the developer's real settings.
    @Test func settingsSaveRoundTripsThroughInjectedConfigDir() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let state = AppState(configDir: dir)
        state.settings.claudeFlags = "--effort xhigh"
        #expect(state.settings.save(to: state.settingsFilePath))

        let reloaded = AppState(configDir: dir)
        #expect(reloaded.settings.claudeFlags == "--effort xhigh")
    }

    /// The injected path must be inside the injected dir -- not merely
    /// different from the default.
    @Test func settingsFilePathIsInsideTheConfigDir() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let state = AppState(configDir: dir)
        #expect(state.settingsFilePath == (dir as NSString).appendingPathComponent("settings.json"))
    }

    /// Two states on different dirs must not see each other's settings.
    @Test func twoConfigDirsAreIndependent() {
        let dirA = tempDir(), dirB = tempDir()
        defer {
            try? FileManager.default.removeItem(atPath: dirA)
            try? FileManager.default.removeItem(atPath: dirB)
        }

        let a = AppState(configDir: dirA)
        a.settings.claudeFlags = "--from-a"
        #expect(a.settings.save(to: a.settingsFilePath))

        let b = AppState(configDir: dirB)
        #expect(b.settings.claudeFlags == CanopySettings().claudeFlags)
    }

    /// Production behaviour must be unchanged: no configDir means the real
    /// file, which is what the shipping app relies on.
    @Test func defaultInitStillUsesTheRealConfigDirectory() {
        let state = AppState()
        let expected = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".config/canopy/settings.json")
        #expect(state.settingsFilePath == expected)
    }
}
