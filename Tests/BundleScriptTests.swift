import Testing
import Foundation
@testable import Canopy

/// `scripts/bundle.sh` regenerates the tracked `Canopy/App/BuildInfo.swift`
/// from git, and CLAUDE.md tells contributors to run it after every change.
/// Those two facts together guarantee a dirty working tree on every build,
/// which `git add -A` then sweeps into whatever commit is being authored --
/// it baked an unrelated commit's hash into PR #50 and had to be reverted.
///
/// The script restores the committed copy on exit unless `--release` is
/// passed. Without a check, that restore can be removed and the trap silently
/// returns, so this suite pins it.
@Suite("bundle.sh BuildInfo handling")
struct BundleScriptTests {

    /// Derived from this file's location, not the process working directory.
    /// `swift test` happens to run from the package root, but the Xcode test
    /// target runs from DerivedData, where `scripts/bundle.sh` and
    /// `BuildInfo.swift` would not be found and every test here would fail
    /// for a reason unrelated to what it checks.
    private var repoRoot: String {
        URL(fileURLWithPath: #filePath)   // <repo>/Tests/BundleScriptTests.swift
            .deletingLastPathComponent()  // <repo>/Tests
            .deletingLastPathComponent()  // <repo>
            .path
    }

    @Test func dryRunLeavesBuildInfoUnchangedInGit() throws {
        let script = "\(repoRoot)/scripts/bundle.sh"
        try #require(FileManager.default.fileExists(atPath: script))

        // Only meaningful inside a git checkout; skip on exported sources.
        guard try shell("git rev-parse --is-inside-work-tree", in: repoRoot).status == 0 else { return }

        let before = try #require(try? String(contentsOfFile: "\(repoRoot)/Canopy/App/BuildInfo.swift",
                                              encoding: .utf8))

        let run = try shell("'\(script)' --dry-run", in: repoRoot)
        #expect(run.status == 0, "bundle.sh --dry-run failed: \(run.output)")

        let after = try #require(try? String(contentsOfFile: "\(repoRoot)/Canopy/App/BuildInfo.swift",
                                             encoding: .utf8))
        #expect(after == before, "bundle.sh must restore BuildInfo.swift byte-for-byte")

        let status = try shell("git status --porcelain -- Canopy/App/BuildInfo.swift", in: repoRoot)
        #expect(status.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "bundle.sh left BuildInfo.swift dirty: \(status.output)")
    }

    @Test func releaseModeIsOptIn() throws {
        // The regeneration must still be reachable -- a release build has to
        // update the committed file, and release.yml hard-fails when its
        // version disagrees with VERSION.
        let source = try String(contentsOfFile: "\(repoRoot)/scripts/bundle.sh", encoding: .utf8)
        #expect(source.contains("--release"))
        #expect(source.contains("RELEASE_MODE"))
    }

    @Test func unknownArgumentIsRejected() throws {
        // Silent arg-dropping is how `--release` would become a no-op.
        let run = try shell("'\(repoRoot)/scripts/bundle.sh' --not-a-flag", in: repoRoot)
        #expect(run.status != 0)
    }

    private func shell(_ command: String, in dir: String) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: dir)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        // Drain before waiting: a full pipe buffer would deadlock the child.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
