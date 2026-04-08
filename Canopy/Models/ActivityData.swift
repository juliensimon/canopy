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

/// Time granularity for the activity heatmap.
enum Granularity: String, CaseIterable {
    case day, week, month

    var label: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        }
    }

    var periodLabel: String {
        switch self {
        case .day: "Last 7 Days"
        case .week: "Last 12 Weeks"
        case .month: "Last 12 Months"
        }
    }
}

/// Persistent cache for scanned JSONL data.
struct ActivityCache: Codable {
    static let currentVersion = 1

    var version: Int = ActivityCache.currentVersion
    var lastScanTimestamp: Date = .distantPast
    /// Tracks which files have been scanned and their state at scan time.
    var scannedFiles: [String: ScannedFileInfo] = [:]
    /// Date string "yyyy-MM-dd" → daily bucket.
    var dailyBuckets: [String: DailyBucket] = [:]
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

/// Formats a token count as an abbreviated string: 142.3M, 24.7K, 850.
func abbreviatedTokenCount(_ count: Int) -> String {
    if count >= 1_000_000 {
        let millions = Double(count) / 1_000_000.0
        return String(format: "%.1fM", millions)
    } else if count >= 1_000 {
        let thousands = Double(count) / 1_000.0
        return String(format: "%.1fK", thousands)
    } else {
        return "\(count)"
    }
}
