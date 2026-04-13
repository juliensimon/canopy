import Testing
import Foundation
@testable import Canopy

@Suite("UpdateChecker")
struct UpdateCheckerTests {

    // MARK: - Semver comparison

    @Test func semverEqualIsNotNewer() {
        #expect(UpdateChecker.isNewer(remote: "0.9.0", than: "0.9.0") == false)
    }

    @Test func semverPatchBumpIsNewer() {
        #expect(UpdateChecker.isNewer(remote: "0.9.1", than: "0.9.0") == true)
    }

    @Test func semverMinorBumpIsNewer() {
        #expect(UpdateChecker.isNewer(remote: "0.10.0", than: "0.9.0") == true)
    }

    @Test func semverMajorBumpIsNewer() {
        #expect(UpdateChecker.isNewer(remote: "1.0.0", than: "0.9.99") == true)
    }

    @Test func semverOlderIsNotNewer() {
        #expect(UpdateChecker.isNewer(remote: "0.8.9", than: "0.9.0") == false)
    }

    @Test func semverStripsVPrefix() {
        #expect(UpdateChecker.isNewer(remote: "v0.10.0", than: "0.9.0") == true)
        #expect(UpdateChecker.isNewer(remote: "v0.9.0", than: "v0.9.0") == false)
    }

    @Test func semverShorterVersionZeroPads() {
        #expect(UpdateChecker.isNewer(remote: "0.10", than: "0.9.0") == true)
        #expect(UpdateChecker.isNewer(remote: "1", than: "0.9.99") == true)
    }

    @Test func semverIgnoresPreReleaseSuffix() {
        // We treat pre-release tags as equal to their base version (conservative — don't notify).
        #expect(UpdateChecker.isNewer(remote: "0.9.0-beta1", than: "0.9.0") == false)
    }

    @Test func semverMalformedReturnsFalse() {
        #expect(UpdateChecker.isNewer(remote: "not-a-version", than: "0.9.0") == false)
    }

    // MARK: - GitHub release JSON decoding

    @Test func decodesGitHubReleaseJSON() throws {
        let json = """
        {
            "tag_name": "v0.10.0",
            "html_url": "https://github.com/juliensimon/canopy/releases/tag/v0.10.0",
            "name": "Canopy 0.10.0",
            "body": "Release notes here"
        }
        """.data(using: .utf8)!
        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
        #expect(release.tagName == "v0.10.0")
        #expect(release.htmlURL == "https://github.com/juliensimon/canopy/releases/tag/v0.10.0")
    }

    // MARK: - checkForUpdates

    @Test func checkReturnsAvailableWhenRemoteNewer() async throws {
        let checker = UpdateChecker(currentVersion: "0.9.0") { _ in
            """
            {"tag_name": "v0.10.0", "html_url": "https://example.com/v0.10.0"}
            """.data(using: .utf8)!
        }
        let result = await checker.checkForUpdates()
        guard case .available(let version, let url) = result else {
            Issue.record("expected .available, got \(result)")
            return
        }
        #expect(version == "0.10.0")
        #expect(url.absoluteString == "https://example.com/v0.10.0")
    }

    @Test func checkReturnsUpToDateWhenSameVersion() async throws {
        let checker = UpdateChecker(currentVersion: "0.9.0") { _ in
            """
            {"tag_name": "v0.9.0", "html_url": "https://example.com/v0.9.0"}
            """.data(using: .utf8)!
        }
        let result = await checker.checkForUpdates()
        if case .upToDate = result { return }
        Issue.record("expected .upToDate, got \(result)")
    }

    @Test func checkReturnsFailedOnNetworkError() async throws {
        struct BoomError: Error {}
        let checker = UpdateChecker(currentVersion: "0.9.0") { _ in
            throw BoomError()
        }
        let result = await checker.checkForUpdates()
        if case .failed = result { return }
        Issue.record("expected .failed, got \(result)")
    }

    // MARK: - Throttle

    @Test func shouldAutoCheckWhenNeverChecked() {
        #expect(UpdateChecker.shouldAutoCheck(lastCheck: nil, now: Date()) == true)
    }

    @Test func shouldNotAutoCheckWithinThrottleWindow() {
        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)
        #expect(UpdateChecker.shouldAutoCheck(lastCheck: oneHourAgo, now: now) == false)
    }

    @Test func shouldAutoCheckAfterThrottleWindow() {
        let now = Date()
        let twoDaysAgo = now.addingTimeInterval(-2 * 86400)
        #expect(UpdateChecker.shouldAutoCheck(lastCheck: twoDaysAgo, now: now) == true)
    }
}
