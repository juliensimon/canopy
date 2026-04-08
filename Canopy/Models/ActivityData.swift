import Foundation

/// Token usage totals for a single day.
struct DailyBucket: Codable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var sessionCount: Int = 0
    /// Model name → total tokens (input + output) attributed to that model.
    var models: [String: Int] = [:]

    var totalTokens: Int { inputTokens + outputTokens }
}

/// Time granularity for period calculations.
enum Granularity {
    case week
}

/// Persistent cache for scanned JSONL data.
struct ActivityCache: Codable {
    static let currentVersion = 3

    var version: Int = ActivityCache.currentVersion
    var lastScanTimestamp: Date = .distantPast
    /// Tracks which files have been scanned and their state at scan time.
    var scannedFiles: [String: ScannedFileInfo] = [:]
    /// Per-file daily buckets. Key is the file path, value is date→bucket.
    /// This allows replacing a file's contribution on re-scan without double-counting.
    var fileBuckets: [String: [String: DailyBucket]] = [:]
    /// Pre-computed aggregate of all fileBuckets. Avoids re-aggregating when nothing changed.
    var aggregatedBuckets: [String: DailyBucket]?
}

/// Metadata about a scanned JSONL file for incremental cache updates.
struct ScannedFileInfo: Codable {
    var lastModified: Date
    var byteSize: Int
}

/// Computed summary for the UI, derived from cached buckets.
struct ActivitySummary {
    var allTimeInput: Int = 0
    var allTimeOutput: Int = 0
    var periodInput: Int = 0
    var periodOutput: Int = 0
    var periodSessionCount: Int = 0
    var busiestDayTokens: Int = 0
    var busiestDayDate: String = ""
    var modelBreakdown: [(name: String, percentage: Int)] = []

    var allTimeTotal: Int { allTimeInput + allTimeOutput }
    var periodTotal: Int { periodInput + periodOutput }
}

/// Formats a token count as an abbreviated string: 1.2T, 2.5G, 142.3M, 24.7K, 850.
func abbreviatedTokenCount(_ count: Int) -> String {
    if count >= 1_000_000_000_000 {
        return String(format: "%.1fT", Double(count) / 1_000_000_000_000.0)
    } else if count >= 1_000_000_000 {
        return String(format: "%.1fG", Double(count) / 1_000_000_000.0)
    } else if count >= 1_000_000 {
        return String(format: "%.1fM", Double(count) / 1_000_000.0)
    } else if count >= 1_000 {
        return String(format: "%.1fK", Double(count) / 1_000.0)
    } else {
        return "\(count)"
    }
}
