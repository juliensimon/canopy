import Testing
import Foundation
@testable import Canopy

@Suite("UpdateChecker")
struct UpdateCheckerTests {

    // MARK: - compareSemver

    @Test func patchVersionAscending() {
        #expect(UpdateChecker.compareSemver("0.9.0", "0.9.1") == .orderedAscending)
    }

    @Test func equalVersions() {
        #expect(UpdateChecker.compareSemver("0.9.1", "0.9.1") == .orderedSame)
    }

    @Test func leadingVStripped() {
        #expect(UpdateChecker.compareSemver("v0.9.1", "0.9.1") == .orderedSame)
        #expect(UpdateChecker.compareSemver("v0.9.0", "v0.9.1") == .orderedAscending)
        // Nonzero major: with broken stripping, Int("v0") ?? 0 == 0 masks the
        // bug for 0.x versions, so only this case proves the prefix is dropped.
        #expect(UpdateChecker.compareSemver("v1.2.3", "1.2.3") == .orderedSame)
    }

    @Test func numericNotLexicalCompare() {
        // Critical: "0.10.0" must be greater than "0.9.0", not less.
        #expect(UpdateChecker.compareSemver("0.9.0", "0.10.0") == .orderedAscending)
        #expect(UpdateChecker.compareSemver("0.10.0", "0.9.0") == .orderedDescending)
    }

    @Test func majorVersionDominates() {
        #expect(UpdateChecker.compareSemver("1.0.0", "0.9.9") == .orderedDescending)
    }

    @Test func prereleaseSuffixDropped() {
        // Simplification: "0.9.1-beta" is treated as "0.9.1". Documented in compareSemver.
        #expect(UpdateChecker.compareSemver("0.9.1-beta", "0.9.1") == .orderedSame)
    }

    @Test func missingComponentsTreatedAsZero() {
        #expect(UpdateChecker.compareSemver("1.0", "1.0.0") == .orderedSame)
        #expect(UpdateChecker.compareSemver("1", "1.0.1") == .orderedAscending)
    }

    // MARK: - LatestRelease decoding

    @Test func decodesGitHubReleasePayload() throws {
        let json = """
        {
            "tag_name": "v0.9.1",
            "name": "Canopy 0.9.1",
            "html_url": "https://github.com/juliensimon/canopy/releases/tag/v0.9.1"
        }
        """.data(using: .utf8)!

        let release = try JSONDecoder().decode(LatestRelease.self, from: json)
        #expect(release.tagName == "v0.9.1")
        #expect(release.name == "Canopy 0.9.1")
        #expect(release.htmlUrl.absoluteString == "https://github.com/juliensimon/canopy/releases/tag/v0.9.1")
    }

    @Test func decodesPayloadWithoutName() throws {
        let json = """
        {
            "tag_name": "v0.9.1",
            "html_url": "https://github.com/juliensimon/canopy/releases/tag/v0.9.1"
        }
        """.data(using: .utf8)!

        let release = try JSONDecoder().decode(LatestRelease.self, from: json)
        #expect(release.name == nil)
    }
}
