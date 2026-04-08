import Foundation

/// Scans Claude Code JSONL session files and manages a cached activity index.
enum ActivityDataService {

    private nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private nonisolated(unsafe) static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")!
        return f
    }()

    // MARK: - Public API

    static func loadData(granularity: Granularity) -> (summary: ActivitySummary, buckets: [String: DailyBucket]) {
        var cache = loadCache() ?? ActivityCache()
        if cache.version != ActivityCache.currentVersion {
            cache = ActivityCache()
        }

        let allJsonlFiles = findAllJsonlFiles()
        let toScan = filesToScan(allFiles: allJsonlFiles, cache: cache)

        var newBuckets: [String: DailyBucket] = [:]
        for filePath in toScan {
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }
            let fileBuckets = parseJsonlIntoBuckets(content)
            mergeBuckets(into: &newBuckets, from: fileBuckets)

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

        if hasAssistantEntry, let firstDay = buckets.keys.sorted().first {
            buckets[firstDay]?.sessionCount += 1
        }

        return buckets
    }

    // MARK: - Bucket Merging

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
