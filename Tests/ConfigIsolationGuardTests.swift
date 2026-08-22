import Testing
import Foundation
@testable import Canopy

/// `AppState(configDir:)` exists so tests never touch the developer's real
/// `~/.config/canopy`, but the parameter defaults to that very directory
/// (`AppState.swift`), so a bare `AppState()` in a test that then writes is
/// silently destructive. Issue #18 fixed the settings half of this; sessions
/// were never covered, and `swift test` was appending fake sessions to the
/// real `sessions.json` -- they showed up in Canopy's sidebar on next launch,
/// pointing at temp directories the tests had already deleted.
///
/// Converting the call sites fixes today's leak; only a check keeps it fixed,
/// because the failure is invisible in CI (a fresh runner has no real config
/// to corrupt) and shows up only on a contributor's own machine.
@Suite("Config isolation guard")
struct ConfigIsolationGuardTests {

    /// Derived from this file's location, not the process working directory --
    /// the Xcode test target runs from DerivedData. Same reasoning as
    /// `BundleScriptTests.repoRoot`.
    private var testsDir: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
    }

    /// A bare `AppState()`, not any identifier that merely ends in one --
    /// the lookbehind is what stops this matching `isolatedAppState()`, the
    /// very helper the fix introduces.
    private static let defaultConstruction = try! NSRegularExpression(
        pattern: "(?<![A-Za-z0-9_])AppState\\(\\)"
    )

    /// Anything that ends in a write to disk.
    private let writeCalls = [
        "createSession(", "saveSessions(", "saveProjects(",
        "saveSettings(", "savePrompts(", "addProject(",
    ]

    @Test func noTestFileBothDefaultConstructsAppStateAndWrites() throws {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(atPath: testsDir)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        try #require(!files.isEmpty)

        var offenders: [String] = []
        // This file names the markers it searches for, so it matches itself.
        let selfName = URL(fileURLWithPath: #filePath).lastPathComponent
        for file in files where file != selfName {
            let source = try String(contentsOfFile: (testsDir as NSString)
                .appendingPathComponent(file), encoding: .utf8)
            guard Self.defaultConstruction.firstMatch(
                in: source, range: NSRange(source.startIndex..., in: source)
            ) != nil else { continue }
            let writes = writeCalls.filter { source.contains($0) }
            if !writes.isEmpty {
                offenders.append("\(file) -- bare AppState() alongside \(writes.joined(separator: ", "))")
            }
        }

        #expect(offenders.isEmpty, """
            These test files default-construct AppState and also write, so they \
            persist into the developer's real ~/.config/canopy:
            \(offenders.joined(separator: "\n"))
            Use AppState(configDir:) with a temp directory instead.
            """)
    }
}
