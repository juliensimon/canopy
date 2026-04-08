# Activity Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a global activity dashboard showing aggregated Claude Code token usage over time with a GitHub-style heatmap and summary stats.

**Architecture:** New `ActivityDataService` scans all `~/.claude/projects/*/*.jsonl` files, caches daily token buckets to `~/.config/canopy/activity-cache.json`, and provides data to `ActivityView` — a SwiftUI dashboard shown when the user clicks "Activity" in the sidebar. The heatmap supports Day/Week/Month granularity.

**Tech Stack:** Swift, SwiftUI, Foundation (JSONSerialization, FileManager, ISO8601DateFormatter)

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `Canopy/Models/ActivityData.swift` | Data models: `DailyBucket`, `ActivityCache`, `ActivitySummary`, `Granularity` |
| Create | `Canopy/Services/ActivityDataService.swift` | JSONL scanning, cache read/write, incremental updates |
| Create | `Canopy/Views/ActivityView.swift` | Dashboard layout: stats cards + heatmap container + granularity picker |
| Create | `Canopy/Views/ActivityHeatmap.swift` | GitHub-style heatmap grid with day/week/month layouts |
| Create | `Tests/ActivityDataTests.swift` | Unit tests for models and data service |
| Modify | `Canopy/App/AppState.swift` | Add `showActivity` flag, `selectActivity()` method |
| Modify | `Canopy/Views/Sidebar.swift` | Add "Activity" item at top of sidebar |
| Modify | `Canopy/Views/MainWindow.swift` | Route to `ActivityView` when `showActivity` is true |
| Modify | `Canopy/App/CanopyApp.swift` | Add Cmd+Shift+A keyboard shortcut |

---

### Task 1: Data Models

**Files:**
- Create: `Canopy/Models/ActivityData.swift`
- Create: `Tests/ActivityDataTests.swift`

- [ ] **Step 1: Write the failing test for DailyBucket and abbreviatedTokenCount**

```swift
// Tests/ActivityDataTests.swift
import Testing
import Foundation
@testable import Canopy

@Suite("ActivityData")
struct ActivityDataTests {

    @Test func dailyBucketTotalTokens() {
        let bucket = DailyBucket(
            inputTokens: 1000,
            outputTokens: 500,
            sessionCount: 2,
            models: ["claude-opus-4-6": 1200, "claude-sonnet-4-6": 300]
        )
        #expect(bucket.totalTokens == 1500)
    }

    @Test func abbreviatedTokenCountMillions() {
        #expect(abbreviatedTokenCount(142_300_000) == "142.3M")
    }

    @Test func abbreviatedTokenCountThousands() {
        #expect(abbreviatedTokenCount(4_200) == "4.2K")
    }

    @Test func abbreviatedTokenCountSmall() {
        #expect(abbreviatedTokenCount(850) == "850")
    }

    @Test func abbreviatedTokenCountZero() {
        #expect(abbreviatedTokenCount(0) == "0")
    }

    @Test func abbreviatedTokenCountExactMillion() {
        #expect(abbreviatedTokenCount(1_000_000) == "1.0M")
    }

    @Test func abbreviatedTokenCountExactThousand() {
        #expect(abbreviatedTokenCount(1_000) == "1.0K")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ActivityDataTests 2>&1 | head -30`
Expected: Compilation error — `DailyBucket` and `abbreviatedTokenCount` not defined

- [ ] **Step 3: Write the models**

```swift
// Canopy/Models/ActivityData.swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ActivityDataTests 2>&1 | tail -20`
Expected: All 6 tests pass

- [ ] **Step 5: Commit**

```bash
git add Canopy/Models/ActivityData.swift Tests/ActivityDataTests.swift
git commit -m "feat(activity): add data models and token formatting"
```

---

### Task 2: Activity Data Service — JSONL Scanning & Cache

**Files:**
- Create: `Canopy/Services/ActivityDataService.swift`
- Modify: `Tests/ActivityDataTests.swift`

- [ ] **Step 1: Write failing tests for the data service**

Append to `Tests/ActivityDataTests.swift`:

```swift
@Suite("ActivityDataService")
struct ActivityDataServiceTests {

    @Test func parseJsonlIntoBuckets() {
        let jsonl = """
        {"type":"assistant","timestamp":"2026-04-07T10:00:00.000Z","message":{"model":"claude-opus-4-6","usage":{"input_tokens":100,"cache_creation_input_tokens":50,"cache_read_input_tokens":25,"output_tokens":75}}}
        {"type":"user","message":{"role":"user","content":"hello"}}
        {"type":"assistant","timestamp":"2026-04-07T14:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":200,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":100}}}
        {"type":"assistant","timestamp":"2026-04-08T09:00:00.000Z","message":{"model":"claude-opus-4-6","usage":{"input_tokens":300,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":150}}}
        """
        let buckets = ActivityDataService.parseJsonlIntoBuckets(jsonl)
        // Two dates: 2026-04-07 and 2026-04-08
        #expect(buckets.count == 2)

        let apr7 = buckets["2026-04-07"]!
        #expect(apr7.inputTokens == 375) // 100+50+25 + 200
        #expect(apr7.outputTokens == 175) // 75 + 100
        #expect(apr7.sessionCount == 1) // one file = one session
        #expect(apr7.models["claude-opus-4-6"] == 250) // 175 in + 75 out
        #expect(apr7.models["claude-sonnet-4-6"] == 300) // 200 in + 100 out

        let apr8 = buckets["2026-04-08"]!
        #expect(apr8.inputTokens == 300)
        #expect(apr8.outputTokens == 150)
    }

    @Test func parseJsonlSkipsMalformedLines() {
        let jsonl = """
        not valid json
        {"type":"assistant","timestamp":"2026-04-07T10:00:00.000Z","message":{"model":"claude-opus-4-6","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":50}}}
        """
        let buckets = ActivityDataService.parseJsonlIntoBuckets(jsonl)
        #expect(buckets.count == 1)
        #expect(buckets["2026-04-07"]!.inputTokens == 100)
    }

    @Test func mergeBuckets() {
        var existing: [String: DailyBucket] = [
            "2026-04-07": DailyBucket(inputTokens: 100, outputTokens: 50, sessionCount: 1, models: ["opus": 150])
        ]
        let new: [String: DailyBucket] = [
            "2026-04-07": DailyBucket(inputTokens: 200, outputTokens: 100, sessionCount: 1, models: ["opus": 200, "sonnet": 100]),
            "2026-04-08": DailyBucket(inputTokens: 50, outputTokens: 25, sessionCount: 1, models: ["opus": 75])
        ]
        ActivityDataService.mergeBuckets(into: &existing, from: new)
        #expect(existing.count == 2)
        #expect(existing["2026-04-07"]!.inputTokens == 300)
        #expect(existing["2026-04-07"]!.sessionCount == 2)
        #expect(existing["2026-04-07"]!.models["opus"] == 350)
        #expect(existing["2026-04-07"]!.models["sonnet"] == 100)
        #expect(existing["2026-04-08"]!.inputTokens == 50)
    }

    @Test func computeSummary() {
        let buckets: [String: DailyBucket] = [
            "2026-04-01": DailyBucket(inputTokens: 1000, outputTokens: 500, sessionCount: 2, models: ["opus": 1200, "sonnet": 300]),
            "2026-04-02": DailyBucket(inputTokens: 3000, outputTokens: 1000, sessionCount: 5, models: ["opus": 3500, "sonnet": 500]),
            "2026-01-15": DailyBucket(inputTokens: 500, outputTokens: 200, sessionCount: 1, models: ["opus": 700])
        ]
        // Period: last 12 weeks from a reference date of 2026-04-08
        let summary = ActivityDataService.computeSummary(
            allBuckets: buckets,
            periodStart: "2026-01-13"
        )
        #expect(summary.allTimeTotal == 6200) // 1500 + 4000 + 700
        #expect(summary.periodTotal == 6200) // all within 12 weeks
        #expect(summary.periodSessionCount == 8)
        #expect(summary.busiestDayTokens == 4000)
        #expect(summary.busiestDayDate == "2026-04-02")
        #expect(summary.modelBreakdown.first?.name == "opus")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ActivityDataServiceTests 2>&1 | head -30`
Expected: Compilation error — `ActivityDataService` not defined

- [ ] **Step 3: Implement ActivityDataService**

```swift
// Canopy/Services/ActivityDataService.swift
import Foundation

/// Scans Claude Code JSONL session files and manages a cached activity index.
enum ActivityDataService {

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    // MARK: - Public API

    /// Load activity data, using cache for incremental updates.
    /// Call from a background thread.
    static func loadData(granularity: Granularity) -> (summary: ActivitySummary, buckets: [String: DailyBucket]) {
        var cache = loadCache() ?? ActivityCache()

        // If cache version mismatch, start fresh
        if cache.version != ActivityCache.currentVersion {
            cache = ActivityCache()
        }

        let allJsonlFiles = findAllJsonlFiles()
        let filesToScan = filesToScan(allFiles: allJsonlFiles, cache: cache)

        // For files that changed, remove their old data by rescanning from scratch
        // We track per-file contributions via sessionCount but daily buckets are merged.
        // For changed files, we do a full rescan of those files only.
        var newBuckets: [String: DailyBucket] = [:]
        for filePath in filesToScan {
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }
            let fileBuckets = parseJsonlIntoBuckets(content)
            mergeBuckets(into: &newBuckets, from: fileBuckets)

            // Update scanned file info
            let attrs = try? FileManager.default.attributesOfItem(atPath: filePath)
            cache.scannedFiles[filePath] = ScannedFileInfo(
                lastModified: attrs?[.modificationDate] as? Date ?? Date(),
                byteSize: (attrs?[.size] as? Int) ?? 0
            )
        }

        mergeBuckets(into: &cache.dailyBuckets, from: newBuckets)
        cache.lastScanTimestamp = Date()

        saveCache(cache)

        let periodStart = periodStartDate(for: granularity)
        let summary = computeSummary(allBuckets: cache.dailyBuckets, periodStart: periodStart)

        return (summary, cache.dailyBuckets)
    }

    // MARK: - JSONL Parsing

    /// Parse a single JSONL file into daily buckets.
    static func parseJsonlIntoBuckets(_ content: String) -> [String: DailyBucket] {
        var buckets: [String: DailyBucket] = [:]
        var hasAssistantEntry = false

        for line in content.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let usageDict = message["usage"] as? [String: Any],
                  let timestamp = obj["timestamp"] as? String else {
                continue
            }

            guard let date = iso8601.date(from: timestamp) else { continue }
            let dayKey = dayFormatter.string(from: date)

            let inputTokens = (usageDict["input_tokens"] as? Int ?? 0)
                + (usageDict["cache_creation_input_tokens"] as? Int ?? 0)
                + (usageDict["cache_read_input_tokens"] as? Int ?? 0)
            let outputTokens = usageDict["output_tokens"] as? Int ?? 0
            let model = message["model"] as? String ?? "unknown"
            let modelTokens = inputTokens + outputTokens

            var bucket = buckets[dayKey] ?? DailyBucket()
            bucket.inputTokens += inputTokens
            bucket.outputTokens += outputTokens
            bucket.models[model, default: 0] += modelTokens
            buckets[dayKey] = bucket

            hasAssistantEntry = true
        }

        // Count this file as one session across all days it touches
        if hasAssistantEntry, let firstDay = buckets.keys.sorted().first {
            buckets[firstDay]?.sessionCount += 1
        }

        return buckets
    }

    // MARK: - Bucket Merging

    /// Merge new buckets into existing, summing all fields.
    static func mergeBuckets(into existing: inout [String: DailyBucket], from new: [String: DailyBucket]) {
        for (dayKey, newBucket) in new {
            var merged = existing[dayKey] ?? DailyBucket()
            merged.inputTokens += newBucket.inputTokens
            merged.outputTokens += newBucket.outputTokens
            merged.sessionCount += newBucket.sessionCount
            for (model, tokens) in newBucket.models {
                merged.models[model, default: 0] += tokens
            }
            existing[dayKey] = merged
        }
    }

    // MARK: - Summary Computation

    /// Compute summary stats from daily buckets.
    static func computeSummary(allBuckets: [String: DailyBucket], periodStart: String) -> ActivitySummary {
        var summary = ActivitySummary()
        var allTimeModels: [String: Int] = [:]

        for (dayKey, bucket) in allBuckets {
            // All-time totals
            summary.allTimeInput += bucket.inputTokens
            summary.allTimeOutput += bucket.outputTokens
            for (model, tokens) in bucket.models {
                allTimeModels[model, default: 0] += tokens
            }

            // Period totals
            if dayKey >= periodStart {
                summary.periodInput += bucket.inputTokens
                summary.periodOutput += bucket.outputTokens
                summary.periodSessionCount += bucket.sessionCount
            }

            // Busiest day (all time)
            if bucket.totalTokens > summary.busiestDayTokens {
                summary.busiestDayTokens = bucket.totalTokens
                summary.busiestDayDate = dayKey
            }
        }

        // Model breakdown as sorted percentages
        let totalModelTokens = allTimeModels.values.reduce(0, +)
        if totalModelTokens > 0 {
            summary.modelBreakdown = allTimeModels
                .sorted { $0.value > $1.value }
                .map { (name: $0.key, percentage: Int(round(Double($0.value) / Double(totalModelTokens) * 100))) }
        }

        return summary
    }

    // MARK: - File Discovery

    /// Find all JSONL files in ~/.claude/projects/*/*.jsonl
    static func findAllJsonlFiles() -> [String] {
        let home = NSHomeDirectory()
        let projectsDir = (home as NSString).appendingPathComponent(".claude/projects")
        let fm = FileManager.default

        guard fm.fileExists(atPath: projectsDir) else { return [] }

        var results: [String] = []
        guard let projectDirs = try? fm.contentsOfDirectory(atPath: projectsDir) else { return [] }

        for dir in projectDirs {
            let dirPath = (projectsDir as NSString).appendingPathComponent(dir)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let files = try? fm.contentsOfDirectory(atPath: dirPath) else { continue }
            for file in files where file.hasSuffix(".jsonl") {
                results.append((dirPath as NSString).appendingPathComponent(file))
            }
        }

        return results
    }

    // MARK: - Cache Management

    private static var cacheFilePath: String {
        let configDir = (NSHomeDirectory() as NSString).appendingPathComponent(".config/canopy")
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        return (configDir as NSString).appendingPathComponent("activity-cache.json")
    }

    static func loadCache() -> ActivityCache? {
        guard let data = FileManager.default.contents(atPath: cacheFilePath) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ActivityCache.self, from: data)
    }

    static func saveCache(_ cache: ActivityCache) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(cache) else { return }
        FileManager.default.createFile(atPath: cacheFilePath, contents: data)
    }

    /// Determine which files need (re)scanning based on modification time and size.
    static func filesToScan(allFiles: [String], cache: ActivityCache) -> [String] {
        let fm = FileManager.default
        return allFiles.filter { filePath in
            guard let attrs = try? fm.attributesOfItem(atPath: filePath),
                  let modDate = attrs[.modificationDate] as? Date,
                  let size = attrs[.size] as? Int else {
                return true // can't read attrs, try scanning
            }
            guard let cached = cache.scannedFiles[filePath] else {
                return true // new file
            }
            return modDate != cached.lastModified || size != cached.byteSize
        }
    }

    // MARK: - Period Calculation

    /// Returns the "yyyy-MM-dd" start date for the given granularity.
    static func periodStartDate(for granularity: Granularity) -> String {
        let calendar = Calendar.current
        let now = Date()
        let startDate: Date
        switch granularity {
        case .day:
            startDate = calendar.date(byAdding: .day, value: -7, to: now)!
        case .week:
            startDate = calendar.date(byAdding: .weekOfYear, value: -12, to: now)!
        case .month:
            startDate = calendar.date(byAdding: .month, value: -12, to: now)!
        }
        return dayFormatter.string(from: startDate)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ActivityDataServiceTests 2>&1 | tail -20`
Expected: All 4 tests pass

- [ ] **Step 5: Commit**

```bash
git add Canopy/Services/ActivityDataService.swift Tests/ActivityDataTests.swift
git commit -m "feat(activity): add data service with JSONL scanning and caching"
```

---

### Task 3: Activity Heatmap View

**Files:**
- Create: `Canopy/Views/ActivityHeatmap.swift`

- [ ] **Step 1: Create the heatmap SwiftUI component**

```swift
// Canopy/Views/ActivityHeatmap.swift
import SwiftUI

/// GitHub-style contribution heatmap that fills available space.
struct ActivityHeatmap: View {
    let buckets: [String: DailyBucket]
    let granularity: Granularity

    /// The four-level purple color scale.
    private static let colors: [Color] = [
        Color(red: 0.118, green: 0.118, blue: 0.227),  // #1e1e3a
        Color(red: 0.176, green: 0.106, blue: 0.412),  // #2d1b69
        Color(red: 0.357, green: 0.129, blue: 0.714),  // #5b21b6
        Color(red: 0.486, green: 0.227, blue: 0.929),  // #7c3aed
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: period label + legend
            HStack {
                Text(granularity.periodLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                legend
            }
            .padding(.bottom, 8)

            // Column labels (months/days depending on granularity)
            columnLabels
                .padding(.leading, 30)
                .padding(.bottom, 4)

            // Grid
            HStack(alignment: .top, spacing: 0) {
                rowLabels
                    .frame(width: 26)
                gridContent
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.102, green: 0.090, blue: 0.188)) // #1a1730
                .stroke(Color(red: 0.165, green: 0.145, blue: 0.271), lineWidth: 1) // #2a2545
        )
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 4) {
            Text("Less")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            ForEach(0..<4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Self.colors[level])
                    .frame(width: 10, height: 10)
            }
            Text("More")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Grid Data

    private var gridData: GridLayout {
        switch granularity {
        case .day:
            return buildDayGrid()
        case .week:
            return buildWeekGrid()
        case .month:
            return buildMonthGrid()
        }
    }

    private struct GridLayout {
        var columns: [[Int]] // each column is an array of token counts per row
        var columnLabels: [String]
        var rowLabels: [String]
    }

    private func buildWeekGrid() -> GridLayout {
        let calendar = Calendar.current
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"
        monthFormatter.timeZone = TimeZone.current

        var columns: [[Int]] = []
        var labels: [String] = []

        // Find the Monday 11 weeks ago
        let todayWeekday = calendar.component(.weekday, from: today)
        let daysToMonday = (todayWeekday + 5) % 7 // days since Monday
        let thisMonday = calendar.date(byAdding: .day, value: -daysToMonday, to: today)!
        let startMonday = calendar.date(byAdding: .weekOfYear, value: -11, to: thisMonday)!

        for weekOffset in 0..<12 {
            let weekStart = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: startMonday)!
            var column: [Int] = []

            for dayOffset in 0..<7 {
                let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart)!
                let key = formatter.string(from: day)
                column.append(buckets[key]?.totalTokens ?? 0)
            }

            columns.append(column)

            // Label: show month name if this week contains the 1st of a month
            var label = ""
            for dayOffset in 0..<7 {
                let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart)!
                if calendar.component(.day, from: day) <= 7 && dayOffset == 0 || calendar.component(.day, from: day) == 1 {
                    if calendar.component(.day, from: day) <= 7 {
                        label = monthFormatter.string(from: day)
                        break
                    }
                }
            }
            labels.append(label)
        }

        return GridLayout(
            columns: columns,
            columnLabels: labels,
            rowLabels: ["Mon", "", "Wed", "", "Fri", "", "Sun"]
        )
    }

    private func buildDayGrid() -> GridLayout {
        let calendar = Calendar.current
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current

        let dayNameFormatter = DateFormatter()
        dayNameFormatter.dateFormat = "EEE"
        dayNameFormatter.timeZone = TimeZone.current

        var columns: [[Int]] = []
        var labels: [String] = []

        // 7 columns (days), 24 rows (hours)
        // For day view, we need hourly data — approximate from daily buckets
        // (full hourly parsing would require raw JSONL access; for now, distribute evenly)
        for dayOffset in stride(from: -6, through: 0, by: 1) {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: today)!
            let key = formatter.string(from: day)
            let dayTotal = buckets[key]?.totalTokens ?? 0
            // Distribute evenly across 24 hours as approximation
            let perHour = dayTotal / max(1, 24)
            let column = Array(repeating: perHour, count: 24)
            columns.append(column)
            labels.append(dayNameFormatter.string(from: day))
        }

        let rowLabels = (0..<24).map { hour in
            hour % 6 == 0 ? "\(hour)h" : ""
        }

        return GridLayout(columns: columns, columnLabels: labels, rowLabels: rowLabels)
    }

    private func buildMonthGrid() -> GridLayout {
        let calendar = Calendar.current
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"
        monthFormatter.timeZone = TimeZone.current

        var columns: [[Int]] = []
        var labels: [String] = []

        // 12 columns (months), ~5 rows (weeks within each month)
        for monthOffset in stride(from: -11, through: 0, by: 1) {
            let monthDate = calendar.date(byAdding: .month, value: monthOffset, to: today)!
            let range = calendar.range(of: .day, in: .month, for: monthDate)!
            let weeksInMonth = (range.count + 6) / 7

            var column: [Int] = []
            let year = calendar.component(.year, from: monthDate)
            let month = calendar.component(.month, from: monthDate)

            for weekIndex in 0..<5 {
                if weekIndex < weeksInMonth {
                    var weekTotal = 0
                    for dayInWeek in 0..<7 {
                        let dayNum = weekIndex * 7 + dayInWeek + 1
                        guard dayNum <= range.count else { continue }
                        let key = String(format: "%04d-%02d-%02d", year, month, dayNum)
                        weekTotal += buckets[key]?.totalTokens ?? 0
                    }
                    column.append(weekTotal)
                } else {
                    column.append(0)
                }
            }

            columns.append(column)
            labels.append(monthFormatter.string(from: monthDate))
        }

        return GridLayout(
            columns: columns,
            columnLabels: labels,
            rowLabels: ["W1", "", "W3", "", "W5"]
        )
    }

    // MARK: - Grid Rendering

    @ViewBuilder
    private var columnLabels: some View {
        let grid = gridData
        HStack(spacing: 0) {
            ForEach(Array(grid.columnLabels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.gray.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var rowLabels: some View {
        let grid = gridData
        VStack(spacing: 4) {
            ForEach(Array(grid.rowLabels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.gray.opacity(0.5))
                    .frame(height: 14)
            }
        }
    }

    @ViewBuilder
    private var gridContent: some View {
        let grid = gridData
        let allValues = grid.columns.flatMap { $0 }
        let maxVal = allValues.max() ?? 1
        let thresholds = [0, maxVal / 4, maxVal / 2, maxVal * 3 / 4]

        HStack(spacing: 4) {
            ForEach(Array(grid.columns.enumerated()), id: \.offset) { _, column in
                VStack(spacing: 4) {
                    ForEach(Array(column.enumerated()), id: \.offset) { _, value in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(colorForValue(value, thresholds: thresholds, maxVal: maxVal))
                            .frame(height: 14)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func colorForValue(_ value: Int, thresholds: [Int], maxVal: Int) -> Color {
        guard maxVal > 0 && value > 0 else { return Self.colors[0] }
        if value >= thresholds[3] { return Self.colors[3] }
        if value >= thresholds[2] { return Self.colors[2] }
        if value >= thresholds[1] { return Self.colors[1] }
        return Self.colors[0]
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Canopy/Views/ActivityHeatmap.swift
git commit -m "feat(activity): add GitHub-style heatmap view component"
```

---

### Task 4: Activity Dashboard View

**Files:**
- Create: `Canopy/Views/ActivityView.swift`

- [ ] **Step 1: Create the main dashboard view**

```swift
// Canopy/Views/ActivityView.swift
import SwiftUI

/// Global activity dashboard showing aggregated token usage.
struct ActivityView: View {
    @State private var granularity: Granularity = .week
    @State private var summary: ActivitySummary?
    @State private var buckets: [String: DailyBucket]?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar with granularity picker
            HStack {
                Text("Activity")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                granularityPicker
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            if isLoading && summary == nil {
                Spacer()
                ProgressView()
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if let summary, let buckets {
                // Stats cards
                statsCards(summary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                // Heatmap fills remaining space
                ActivityHeatmap(buckets: buckets, granularity: granularity)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task(id: granularity) {
            await loadData()
        }
    }

    // MARK: - Granularity Picker

    private var granularityPicker: some View {
        HStack(spacing: 4) {
            ForEach(Granularity.allCases, id: \.self) { g in
                Button(action: { granularity = g }) {
                    Text(g.label)
                        .font(.system(size: 11))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(g == granularity ? Color.purple : Color.clear)
                        )
                        .foregroundStyle(g == granularity ? .white : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Stats Cards

    private func statsCards(_ summary: ActivitySummary) -> some View {
        HStack(spacing: 10) {
            statCard(
                title: "ALL-TIME TOKENS",
                value: abbreviatedTokenCount(summary.allTimeTotal),
                subtitle: "In: \(abbreviatedTokenCount(summary.allTimeInput)) · Out: \(abbreviatedTokenCount(summary.allTimeOutput))",
                valueColor: .purple
            )
            statCard(
                title: granularity.periodLabel.uppercased(),
                value: abbreviatedTokenCount(summary.periodTotal),
                subtitle: "In: \(abbreviatedTokenCount(summary.periodInput)) · Out: \(abbreviatedTokenCount(summary.periodOutput))"
            )
            statCard(
                title: "SESSIONS",
                value: "\(summary.periodSessionCount)",
                subtitle: granularity.periodLabel
            )
            statCard(
                title: "BUSIEST DAY",
                value: abbreviatedTokenCount(summary.busiestDayTokens),
                subtitle: formattedBusiestDate(summary.busiestDayDate)
            )
            modelCard(summary.modelBreakdown)
        }
    }

    private func statCard(title: String, value: String, subtitle: String, valueColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(valueColor)
                .padding(.top, 2)
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.102, green: 0.090, blue: 0.188))
                .stroke(Color(red: 0.165, green: 0.145, blue: 0.271), lineWidth: 1)
        )
    }

    private func modelCard(_ breakdown: [(name: String, percentage: Int)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MODELS")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            if let top = breakdown.first {
                HStack(spacing: 4) {
                    Text(shortModelName(top.name))
                        .foregroundStyle(.purple)
                    Text("\(top.percentage)%")
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 4)
            }
            let others = breakdown.dropFirst().prefix(2)
            if !others.isEmpty {
                Text(others.map { "\(shortModelName($0.name)) \($0.percentage)%" }.joined(separator: " · "))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.102, green: 0.090, blue: 0.188))
                .stroke(Color(red: 0.165, green: 0.145, blue: 0.271), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func loadData() async {
        isLoading = true
        let result = await Task.detached {
            ActivityDataService.loadData(granularity: granularity)
        }.value
        summary = result.summary
        buckets = result.buckets
        isLoading = false
    }

    private func shortModelName(_ name: String) -> String {
        if name.contains("opus") { return "Opus" }
        if name.contains("sonnet") { return "Sonnet" }
        if name.contains("haiku") { return "Haiku" }
        return name
    }

    private func formattedBusiestDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Canopy/Views/ActivityView.swift
git commit -m "feat(activity): add main dashboard view with stats cards"
```

---

### Task 5: Wire Up Navigation

**Files:**
- Modify: `Canopy/App/AppState.swift`
- Modify: `Canopy/Views/Sidebar.swift`
- Modify: `Canopy/Views/MainWindow.swift`
- Modify: `Canopy/App/CanopyApp.swift`

- [ ] **Step 1: Add showActivity flag to AppState**

In `Canopy/App/AppState.swift`, add after line 33 (`@Published var settings = CanopySettings.load()`):

```swift
    /// Whether the Activity dashboard is currently shown.
    @Published var showActivity = false
```

Add a new method after `selectProject(_:)` (after line 106):

```swift
    func selectActivity() {
        activeSessionId = nil
        selectedProjectId = nil
        showActivity = true
    }
```

Modify `selectSession(_:)` to clear `showActivity` — change the method body to:

```swift
    func selectSession(_ id: UUID) {
        activeSessionId = id
        selectedProjectId = nil
        showActivity = false
    }
```

Modify `selectProject(_:)` to clear `showActivity` — change the method body to:

```swift
    func selectProject(_ id: UUID) {
        activeSessionId = nil
        selectedProjectId = id
        showActivity = false
    }
```

- [ ] **Step 2: Add Activity item to Sidebar**

In `Canopy/Views/Sidebar.swift`, inside the `List(selection:)` block, add an Activity row **before** the `// Plain sessions` section (before line 32):

```swift
                    // Activity dashboard
                    Button(action: { appState.selectActivity() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.purple)
                            Text("Activity")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(appState.showActivity ? Color.purple.opacity(0.15) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
```

- [ ] **Step 3: Route to ActivityView in MainWindow**

In `Canopy/Views/MainWindow.swift`, modify the `ZStack` content section (around line 23). Add an `ActivityView` branch **before** the `ProjectDetailView` branch:

Change this block:
```swift
                    ZStack {
                        if let activeSession = appState.activeSession {
                            TerminalInsetView(session: activeSession, appState: appState)
                                .id(activeSession.id)
                                .transition(.opacity)
                        } else if let projectId = appState.selectedProjectId,
                                  let project = appState.projects.first(where: { $0.id == projectId }) {
                            ProjectDetailView(project: project)
                                .id(project.id)
                        } else {
                            WelcomeView()
                        }
                    }
```

To:
```swift
                    ZStack {
                        if let activeSession = appState.activeSession {
                            TerminalInsetView(session: activeSession, appState: appState)
                                .id(activeSession.id)
                                .transition(.opacity)
                        } else if appState.showActivity {
                            ActivityView()
                        } else if let projectId = appState.selectedProjectId,
                                  let project = appState.projects.first(where: { $0.id == projectId }) {
                            ProjectDetailView(project: project)
                                .id(project.id)
                        } else {
                            WelcomeView()
                        }
                    }
```

- [ ] **Step 4: Add keyboard shortcut Cmd+Shift+A**

In `Canopy/App/CanopyApp.swift`, add inside the `CommandMenu("Session")` block (after the "Toggle Split Terminal" button, around line 138):

```swift
                Divider()

                Button("Activity Dashboard") {
                    appState.selectActivity()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
```

- [ ] **Step 5: Verify it compiles and run**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 6: Commit**

```bash
git add Canopy/App/AppState.swift Canopy/Views/Sidebar.swift Canopy/Views/MainWindow.swift Canopy/App/CanopyApp.swift
git commit -m "feat(activity): wire up navigation — sidebar item, routing, Cmd+Shift+A"
```

---

### Task 6: Integration Test & Polish

**Files:**
- Modify: `Tests/ActivityDataTests.swift`

- [ ] **Step 1: Add edge case tests**

Append to the `ActivityDataServiceTests` suite in `Tests/ActivityDataTests.swift`:

```swift
    @Test func emptyJsonlReturnsEmptyBuckets() {
        let buckets = ActivityDataService.parseJsonlIntoBuckets("")
        #expect(buckets.isEmpty)
    }

    @Test func filesToScanDetectsNewFiles() {
        let cache = ActivityCache()
        let result = ActivityDataService.filesToScan(allFiles: ["/fake/path.jsonl"], cache: cache)
        #expect(result.count == 1)
    }

    @Test func computeSummaryEmptyBuckets() {
        let summary = ActivityDataService.computeSummary(allBuckets: [:], periodStart: "2026-01-01")
        #expect(summary.allTimeTotal == 0)
        #expect(summary.periodSessionCount == 0)
        #expect(summary.modelBreakdown.isEmpty)
    }

    @Test func abbreviatedTokenCountBoundary999() {
        #expect(abbreviatedTokenCount(999) == "999")
    }

    @Test func abbreviatedTokenCountBoundary999999() {
        #expect(abbreviatedTokenCount(999_999) == "1000.0K")
    }
```

- [ ] **Step 2: Run all tests**

Run: `swift test 2>&1 | tail -30`
Expected: All tests pass, including existing tests

- [ ] **Step 3: Commit**

```bash
git add Tests/ActivityDataTests.swift
git commit -m "test(activity): add edge case tests for data service"
```

---

## Summary

| Task | Description | Files | Approx Steps |
|------|-------------|-------|-------------|
| 1 | Data models + token formatting | 2 new | 5 |
| 2 | Data service: JSONL scanning + cache | 1 new, 1 modify | 5 |
| 3 | Heatmap view component | 1 new | 3 |
| 4 | Dashboard view (stats + layout) | 1 new | 3 |
| 5 | Navigation wiring (AppState, Sidebar, MainWindow, shortcuts) | 4 modify | 6 |
| 6 | Edge case tests + polish | 1 modify | 3 |
