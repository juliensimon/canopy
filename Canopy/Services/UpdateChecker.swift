import Foundation

/// Minimal GitHub release payload — we only need the tag and the browser URL.
struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

/// Result of an update check. `.failed` carries the error message for display.
enum UpdateCheckResult: Sendable {
    case upToDate
    case available(version: String, url: URL)
    case failed(message: String)
}

/// Checks GitHub Releases for a newer Canopy version.
///
/// Deliberately a simple check — no auto-install, no signing, no appcast.
/// The UI opens the release URL in the browser and the user downloads the DMG.
actor UpdateChecker {
    typealias Fetcher = @Sendable (URL) async throws -> Data

    /// Throttle window for startup auto-checks: one check per day at most.
    static let autoCheckInterval: TimeInterval = 24 * 3600

    private let currentVersion: String
    private let fetcher: Fetcher
    private let releasesURL = URL(string: "https://api.github.com/repos/juliensimon/canopy/releases/latest")!

    init(currentVersion: String = BuildInfo.version, fetcher: @escaping Fetcher = UpdateChecker.defaultFetcher) {
        self.currentVersion = currentVersion
        self.fetcher = fetcher
    }

    private static let defaultFetcher: Fetcher = { url in
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    func checkForUpdates() async -> UpdateCheckResult {
        do {
            let data = try await fetcher(releasesURL)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let normalized = Self.stripVPrefix(release.tagName)
            guard Self.isNewer(remote: release.tagName, than: currentVersion) else {
                return .upToDate
            }
            guard let url = URL(string: release.htmlURL) else {
                return .failed(message: "Invalid release URL")
            }
            return .available(version: normalized, url: url)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    // MARK: - Pure helpers (tested directly)

    /// Returns true if `remote` is strictly newer than `local`.
    /// Pre-release suffixes (`-beta1`) are stripped, then both versions are
    /// zero-padded to equal length and compared component-wise.
    static func isNewer(remote: String, than local: String) -> Bool {
        let r = parse(remote)
        let l = parse(local)
        guard !r.isEmpty, !l.isEmpty else { return false }
        let width = max(r.count, l.count)
        let rPadded = r + Array(repeating: 0, count: width - r.count)
        let lPadded = l + Array(repeating: 0, count: width - l.count)
        for (rc, lc) in zip(rPadded, lPadded) {
            if rc != lc { return rc > lc }
        }
        return false
    }

    static func shouldAutoCheck(lastCheck: Date?, now: Date = Date()) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= autoCheckInterval
    }

    private static func parse(_ version: String) -> [Int] {
        let stripped = stripVPrefix(version)
        // Drop pre-release / build metadata after `-` or `+`.
        let base = stripped.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? stripped
        let parts = base.split(separator: ".").compactMap { Int($0) }
        // Must be non-empty and only contain numeric components.
        let expected = base.split(separator: ".").count
        return parts.count == expected ? parts : []
    }

    private static func stripVPrefix(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }
}
