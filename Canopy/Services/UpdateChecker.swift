import Foundation

/// One release entry from the GitHub Releases API.
struct LatestRelease: Decodable {
    let tagName: String
    let htmlUrl: URL
    let name: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case name
    }
}

/// Result of an update check, surfaced to the UI via AppState.
enum UpdateStatus: Equatable {
    case unknown
    case checking
    case upToDate
    case available(version: String, url: URL)
    case failed(String)
}

/// Fetches the latest Canopy release from GitHub and compares versions.
/// Stateless — rate-limiting and persistence live in AppState.
enum UpdateChecker {
    private static let releaseURL = URL(string: "https://api.github.com/repos/juliensimon/canopy/releases/latest")!

    static func fetchLatest() async throws -> LatestRelease {
        var request = URLRequest(url: releaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub rejects unauthenticated requests with no User-Agent.
        request.setValue("Canopy/\(BuildInfo.version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(LatestRelease.self, from: data)
    }

    /// Compare two version strings of the form `[v]MAJOR.MINOR.PATCH[-prerelease]`.
    /// Prerelease suffixes are dropped (treated as the underlying release), and
    /// missing components are treated as zero. Numeric, not lexical.
    static func compareSemver(_ a: String, _ b: String) -> ComparisonResult {
        let lhs = parts(a)
        let rhs = parts(b)
        let count = max(lhs.count, rhs.count)
        for i in 0..<count {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func parts(_ version: String) -> [Int] {
        var v = version
        if v.hasPrefix("v") || v.hasPrefix("V") { v.removeFirst() }
        if let dash = v.firstIndex(of: "-") { v = String(v[..<dash]) }
        return v.split(separator: ".").map { Int($0) ?? 0 }
    }
}
