import Foundation

/// Scans Claude Code JSONL session files and manages a cached activity index.
enum ActivityDataService {

    // MARK: - Shared formatters (created once per loadData call, passed around)

    struct Formatters {
        let iso8601: ISO8601DateFormatter
        let iso8601NoFrac: ISO8601DateFormatter
        let dayFmt: DateFormatter
        let hourFmt: DateFormatter

        init() {
            iso8601 = ISO8601DateFormatter()
            iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            iso8601NoFrac = ISO8601DateFormatter()
            iso8601NoFrac.formatOptions = [.withInternetDateTime]
            dayFmt = DateFormatter()
            dayFmt.dateFormat = "yyyy-MM-dd"
            dayFmt.timeZone = .current
            hourFmt = DateFormatter()
            hourFmt.dateFormat = "yyyy-MM-dd-HH"
            hourFmt.timeZone = .current
        }
    }

    /// Result of parsing a single file: daily buckets + hourly buckets.
    struct FileParsed {
        var dailyBuckets: [String: DailyBucket] = [:]
        var hourlyBuckets: [String: HourlyBucket] = [:] // key: "yyyy-MM-dd-HH"
    }

    // MARK: - Public API

    struct ActivityResult {
        var summary: ActivitySummary
        var dailyBuckets: [String: DailyBucket]
        var hourlyBuckets: [String: HourlyBucket]
    }

    /// Load activity data, using cache for incremental updates.
    /// Call from a background thread.
    static func loadData() -> ActivityResult {
        var cache = loadCache() ?? ActivityCache()
        if cache.version != ActivityCache.currentVersion {
            cache = ActivityCache()
        }

        let formatters = Formatters()
        let allJsonlFiles = Set(findAllJsonlFiles())
        let toScan = filesToScan(allFiles: Array(allJsonlFiles), cache: cache)

        // Remove deleted files from cache
        let staleFiles = cache.scannedFiles.keys.filter { !allJsonlFiles.contains($0) }
        let cacheChanged = !staleFiles.isEmpty || !toScan.isEmpty
        for stale in staleFiles {
            cache.scannedFiles.removeValue(forKey: stale)
            cache.fileBuckets.removeValue(forKey: stale)
            cache.fileHourlyBuckets.removeValue(forKey: stale)
        }

        // Scan new/changed files — REPLACE per-file buckets
        for filePath in toScan {
            let parsed = parseJsonlFile(atPath: filePath, formatters: formatters)
            cache.fileBuckets[filePath] = parsed.dailyBuckets
            cache.fileHourlyBuckets[filePath] = parsed.hourlyBuckets

            let attrs = try? FileManager.default.attributesOfItem(atPath: filePath)
            cache.scannedFiles[filePath] = ScannedFileInfo(
                lastModified: attrs?[.modificationDate] as? Date ?? Date(),
                byteSize: (attrs?[.size] as? Int) ?? 0
            )
        }

        // Re-aggregate only if something changed
        let aggregatedDaily: [String: DailyBucket]
        let aggregatedHourly: [String: HourlyBucket]
        if cacheChanged || cache.aggregatedBuckets == nil {
            aggregatedDaily = aggregateBuckets(cache.fileBuckets)
            aggregatedHourly = aggregateHourlyBuckets(cache.fileHourlyBuckets)
            cache.aggregatedBuckets = aggregatedDaily
            cache.aggregatedHourlyBuckets = aggregatedHourly
        } else {
            aggregatedDaily = cache.aggregatedBuckets!
            aggregatedHourly = cache.aggregatedHourlyBuckets ?? [:]
        }

        if cacheChanged {
            cache.lastScanTimestamp = Date()
            saveCache(cache)
        }

        let periodStart = periodStartDate()
        let summary = computeSummary(allBuckets: aggregatedDaily, periodStart: periodStart)
        return ActivityResult(summary: summary, dailyBuckets: aggregatedDaily, hourlyBuckets: aggregatedHourly)
    }

    // MARK: - JSONL Parsing

    /// Parse a JSONL file into daily + hourly buckets.
    static func parseJsonlFile(atPath path: String, formatters: Formatters) -> FileParsed {
        guard let fileHandle = FileHandle(forReadingAtPath: path) else { return FileParsed() }
        defer { fileHandle.closeFile() }
        let data = fileHandle.readDataToEndOfFile()
        return parseJsonlData(data, formatters: formatters)
    }

    /// Parse JSONL data into daily + hourly buckets.
    static func parseJsonlData(_ data: Data, formatters: Formatters) -> FileParsed {
        var result = FileParsed()
        var hasAssistantEntry = false

        let assistantMarker = Data("\"type\":\"assistant\"".utf8)

        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let count = buffer.count
            var lineStart = 0

            for i in 0...count {
                let isEnd = (i == count) || (base[i] == UInt8(ascii: "\n"))
                guard isEnd, i > lineStart else {
                    if isEnd { lineStart = i + 1 }
                    continue
                }

                let lineData = Data(bytes: base + lineStart, count: i - lineStart)
                lineStart = i + 1

                guard lineData.range(of: assistantMarker) != nil else { continue }

                guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      obj["type"] as? String == "assistant",
                      let message = obj["message"] as? [String: Any],
                      let usageDict = message["usage"] as? [String: Any],
                      let timestamp = obj["timestamp"] as? String else {
                    continue
                }

                guard let date = formatters.iso8601.date(from: timestamp)
                        ?? formatters.iso8601NoFrac.date(from: timestamp) else {
                    continue
                }
                let dayKey = formatters.dayFmt.string(from: date)
                let hourKey = formatters.hourFmt.string(from: date)

                let inputTokens = (usageDict["input_tokens"] as? Int ?? 0)
                    + (usageDict["cache_creation_input_tokens"] as? Int ?? 0)
                    + (usageDict["cache_read_input_tokens"] as? Int ?? 0)
                let outputTokens = usageDict["output_tokens"] as? Int ?? 0
                let model = message["model"] as? String ?? "unknown"
                let modelTokens = inputTokens + outputTokens
                let totalTokens = inputTokens + outputTokens

                var bucket = result.dailyBuckets[dayKey] ?? DailyBucket()
                bucket.inputTokens += inputTokens
                bucket.outputTokens += outputTokens
                bucket.models[model, default: 0] += modelTokens
                result.dailyBuckets[dayKey] = bucket

                result.hourlyBuckets[hourKey, default: HourlyBucket()].totalTokens += totalTokens

                hasAssistantEntry = true
            }
        }

        if hasAssistantEntry, let firstDay = result.dailyBuckets.keys.sorted().first {
            result.dailyBuckets[firstDay]?.sessionCount += 1
        }

        return result
    }

    /// Parse from String content (for tests). Returns daily buckets only.
    static func parseJsonlIntoBuckets(_ content: String) -> [String: DailyBucket] {
        guard let data = content.data(using: .utf8) else { return [:] }
        return parseJsonlData(data, formatters: Formatters()).dailyBuckets
    }

    // MARK: - Bucket Aggregation

    static func aggregateBuckets(_ fileBuckets: [String: [String: DailyBucket]]) -> [String: DailyBucket] {
        var result: [String: DailyBucket] = [:]
        for (_, dailyBuckets) in fileBuckets {
            mergeBuckets(into: &result, from: dailyBuckets)
        }
        return result
    }

    static func aggregateHourlyBuckets(_ fileHourly: [String: [String: HourlyBucket]]) -> [String: HourlyBucket] {
        var result: [String: HourlyBucket] = [:]
        for (_, hourly) in fileHourly {
            for (key, bucket) in hourly {
                result[key, default: HourlyBucket()].totalTokens += bucket.totalTokens
            }
        }
        return result
    }

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

    static func periodStartDate() -> String {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .weekOfYear, value: -12, to: Date())!
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        return fmt.string(from: startDate)
    }
}
