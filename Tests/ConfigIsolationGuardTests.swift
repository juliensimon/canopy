import Testing
import Foundation
@testable import Canopy

/// `AppState(configDir:)` exists so tests never touch the developer's real
/// `~/.config/canopy`, but the parameter defaults to that very directory, so a
/// bare `AppState()` in a test that then writes is silently destructive.
/// Issue #18 fixed the settings half of this; sessions were never covered, and
/// `swift test` was appending fake sessions to the real `sessions.json` -- they
/// showed up in Canopy's sidebar on next launch, pointing at temp directories
/// the tests had already deleted.
///
/// Converting the call sites fixes today's leak; only a check keeps it fixed,
/// because the failure is invisible in CI -- a fresh runner has no real config
/// to corrupt -- and shows up only on a contributor's own machine.
@Suite("Config isolation guard")
struct ConfigIsolationGuardTests {

    /// Derived from this file's location, not the process working directory --
    /// the Xcode test target runs from DerivedData. Same reasoning as
    /// `BundleScriptTests.repoRoot`.
    private var testsDir: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
    }

    /// A bare `AppState()`, not any identifier that merely ends in one -- the
    /// lookbehind is what stops this matching `isolatedAppState()`, the very
    /// helper the fix introduces.
    private static let defaultConstruction = try! NSRegularExpression(
        pattern: "(?<![A-Za-z0-9_])AppState\\(\\)"
    )

    /// The one place a default-constructed AppState is the point: it asserts
    /// that omitting `configDir` still resolves to the real file, which is what
    /// the shipping app relies on. It never writes.
    private let allowed: Set<String> = ["SettingsIsolationTests.swift"]

    /// Bans the bare initialiser outright rather than trying to spot the
    /// writes.
    ///
    /// An earlier version of this test paired `AppState()` with a list of
    /// write calls -- `createSession(`, `saveSessions(` and so on -- and would
    /// have missed most of them. Persistence is frequently a side effect the
    /// call site does not mention: `renameSession` and `assignClaudeSessionId`
    /// end in `saveSessions()`, `updateProject` in `saveProjects()`,
    /// `openWorktreeSession` in `saveSessions()`. Any such list is a snapshot
    /// of today's API that silently stops covering tomorrow's, so the rule is
    /// the constructor, which is one thing and cannot drift.
    @Test func testsDoNotDefaultConstructAppState() throws {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(atPath: testsDir)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        try #require(!files.isEmpty)

        let selfName = URL(fileURLWithPath: #filePath).lastPathComponent
        var offenders: [String] = []
        for file in files where file != selfName && !allowed.contains(file) {
            let source = try String(contentsOfFile: (testsDir as NSString)
                .appendingPathComponent(file), encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            let hits = Self.defaultConstruction.numberOfMatches(in: source, range: range)
            if hits > 0 { offenders.append("\(file) (\(hits))") }
        }

        #expect(offenders.isEmpty, """
            These test files default-construct AppState, so anything they \
            persist lands in the developer's real ~/.config/canopy:
            \(offenders.joined(separator: ", "))
            Use isolatedAppState() instead.
            """)
    }
}
