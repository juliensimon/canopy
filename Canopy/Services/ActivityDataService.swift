import Foundation

/// Scans Claude Code JSONL session files and manages a cached activity index.
enum ActivityDataService {

    // MARK: - Public API

    /// Load activity data, using cache for incremental updates.
    /// Call from a background thread.
    static func loadData(granularity: Granularity) -> (summary: ActivitySummary, buckets: [String: DailyBucket]) {
        var cache = loadCache() ?? ActivityCache()
        if cache.version != ActivityCache.currentVersion {
            cache = ActivityCache()
        }

        let allJsonlFiles = Set(findAllJsonlFiles())
        let toScan = filesToScan(allFiles: Array(allJsonlFiles), cache: cache)

        // Remove deleted files from cache
        let staleFiles = cache.scannedFiles.keys.filter { !allJsonlFiles.contains($0) }
        for stale in staleFiles {
            cache.scannedFiles.removeValue(forKey: stale)
            cache.fileBuckets.removeValue(forKey: stale)
        }

        // Scan new/changed files — REPLACE per-file buckets (no additive merge)
        for filePath in toScan {
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }
            let fileBuckets = parseJsonlIntoBuckets(content)
            cache.fileBuckets[filePath] = fileBuckets

            let attrs = try? FileManager.default.attributesOfItem(atPath: filePath)
            cache.scannedFiles[filePath] = ScannedFileInfo(
                lastModified: attrs?[.modificationDate] as? Date ?? Date(),
                byteSize: (attrs?[.size] as? Int) ?? 0
            )
        }

        cache.lastScanTimestamp = Date()
        saveCache(cache)

        // Aggregate all per-file buckets into a single daily bucket dictionary
        let aggregated = aggregateBuckets(cache.fileBuckets)

        let periodStart = periodStartDate(for: granularity)
        let summary = computeSummary(allBuckets: aggregated, periodStart: periodStart)
        return (summary, aggregated)
    }

    // MARK: - JSONL Parsing

    /// Parse a single JSONL file into daily buckets.
    /// Creates formatters locally per call to avoid thread-safety issues.
    static func parseJsonlIntoBuckets(_ content: String) -> [String: DailyBucket] {
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let iso8601NoFrac = ISO8601DateFormatter()
        iso8601NoFrac.formatOptions = [.withInternetDateTime]

        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"
        dayFmt.timeZone = .current

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

            // Try fractional seconds first, then without
            guard let date = iso8601.date(from: timestamp) ?? iso8601NoFrac.date(from: timestamp) else {
                continue
            }
            let dayKey = dayFmt.string(from: date)

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

        // Count one session per file, attributed to the earliest day
        if hasAssistantEntry, let firstDay = buckets.keys.sorted().first {
            buckets[firstDay]?.sessionCount += 1
        }

        return buckets
    }

    // MARK: - Bucket Aggregation

    /// Aggregate per-file buckets into a single daily bucket dictionary.
    static func aggregateBuckets(_ fileBuckets: [String: [String: DailyBucket]]) -> [String: DailyBucket] {
        var result: [String: DailyBucket] = [:]
        for (_, dailyBuckets) in fileBuckets {
            mergeBuckets(into: &result, from: dailyBuckets)
        }
        return result
    }

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
            summary.allTimeInput += bucket.inputTokens
            summary.allTimeOutput += bucket.outputTokens
            for (model, tokens) in bucket.models {
                allTimeModels[model, default: 0] += tokens
            }

            if dayKey >= periodStart {
                summary.periodInput += bucket.inputTokens
                summary.periodOutput += bucket.outputTokens
                summary.periodSessionCount += bucket.sessionCount
            }

            if bucket.totalTokens > summary.busiestDayTokens {
                summary.busiestDayTokens = bucket.totalTokens
                summary.busiestDayDate = dayKey
            }
        }

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
                return true
            }
            guard let cached = cache.scannedFiles[filePath] else {
                return true
            }
            return modDate != cached.lastModified || size != cached.byteSize
        }
    }

    // MARK: - Period Calculation

    /// Returns the "yyyy-MM-dd" start date for the given granularity, in local time.
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
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        return fmt.string(from: startDate)
    }
}
