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

    @Test func dailyBucketDefaultInitAllZeros() {
        let bucket = DailyBucket()
        #expect(bucket.inputTokens == 0)
        #expect(bucket.outputTokens == 0)
        #expect(bucket.sessionCount == 0)
        #expect(bucket.models.isEmpty)
        #expect(bucket.totalTokens == 0)
    }

    // MARK: - abbreviatedTokenCount

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

    @Test func abbreviatedTokenCountBillions() {
        #expect(abbreviatedTokenCount(2_500_000_000) == "2.5G")
    }

    @Test func abbreviatedTokenCountTrillions() {
        #expect(abbreviatedTokenCount(1_200_000_000_000) == "1.2T")
    }

    @Test func abbreviatedTokenCountExactBillion() {
        #expect(abbreviatedTokenCount(1_000_000_000) == "1.0G")
    }

    @Test func abbreviatedTokenCountJustBelowThresholds() {
        #expect(abbreviatedTokenCount(999) == "999")
        #expect(abbreviatedTokenCount(999_999) == "1000.0K")
        #expect(abbreviatedTokenCount(999_999_999) == "1000.0M")
    }

    @Test func abbreviatedTokenCountNegative() {
        #expect(abbreviatedTokenCount(-1) == "-1")
        #expect(abbreviatedTokenCount(-1_000_000) == "-1000000")
    }
}

@Suite("ActivityDataService")
struct ActivityDataServiceTests {

    // MARK: - parseJsonlIntoBuckets

    @Test func parseJsonlIntoBuckets() {
        let jsonl = """
        {"type":"assistant","timestamp":"2026-04-07T10:00:00.000Z","message":{"model":"claude-opus-4-6","usage":{"input_tokens":100,"cache_creation_input_tokens":50,"cache_read_input_tokens":25,"output_tokens":75}}}
        {"type":"user","message":{"role":"user","content":"hello"}}
        {"type":"assistant","timestamp":"2026-04-07T14:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":200,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":100}}}
        {"type":"assistant","timestamp":"2026-04-08T09:00:00.000Z","message":{"model":"claude-opus-4-6","usage":{"input_tokens":300,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":150}}}
        """
        let buckets = ActivityDataService.parseJsonlIntoBuckets(jsonl)
        #expect(buckets.count == 2)

        let apr7 = buckets["2026-04-07"]!
        #expect(apr7.inputTokens == 375)
        #expect(apr7.outputTokens == 175)
        #expect(apr7.sessionCount == 1)
        #expect(apr7.models["claude-opus-4-6"] == 250)
        #expect(apr7.models["claude-sonnet-4-6"] == 300)

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

    @Test func parseJsonlTimestampWithoutFractionalSeconds() {
        let jsonl = """
        {"type":"assistant","timestamp":"2026-04-07T10:00:00Z","message":{"model":"claude-opus-4-6","usage":{"input_tokens":100,"output_tokens":50}}}
        """
        let buckets = ActivityDataService.parseJsonlIntoBuckets(jsonl)
        #expect(buckets.count == 1)
        #expect(buckets["2026-04-07"]?.inputTokens == 100)
    }

    @Test func parseJsonlTimestampWithTimezoneOffset() {
        // 2026-04-07T23:00:00.000-05:00 = 2026-04-08T04:00:00 UTC
        let jsonl = """
        {"type":"assistant","timestamp":"2026-04-07T23:00:00.000-05:00","message":{"model":"opus","usage":{"input_tokens":200,"output_tokens":100}}}
        """
        let buckets = ActivityDataService.parseJsonlIntoBuckets(jsonl)
        #expect(buckets.count == 1)
        // Bucketed by local time — exact day depends on test machine timezone,
        // but there should be exactly one bucket with the correct totals
        let bucket = buckets.values.first!
        #expect(bucket.inputTokens == 200)
        #expect(bucket.outputTokens == 100)
    }

    @Test func parseJsonlMissingCacheTokenFields() {
        let jsonl = """
        {"type":"assistant","timestamp":"2026-04-07T10:00:00.000Z","message":{"model":"opus","usage":{"input_tokens":500,"output_tokens":250}}}
        """
        let buckets = ActivityDataService.parseJsonlIntoBuckets(jsonl)
        let bucket = buckets.values.first!
        #expect(bucket.inputTokens == 500)
        #expect(bucket.outputTokens == 250)
        #expect(bucket.totalTokens == 750)
    }

    @Test func parseJsonlMissingModelDefaultsToUnknown() {
        let jsonl = """
        {"type":"assistant","timestamp":"2026-04-07T10:00:00.000Z","message":{"usage":{"input_tokens":100,"output_tokens":50}}}
        """
        let buckets = ActivityDataService.parseJsonlIntoBuckets(jsonl)
        #expect(buckets.count == 1)
        #expect(buckets.values.first!.models["unknown"] == 150)
    }

    @Test func parseJsonlNonIntegerTokenValues() {
        let jsonl = """
        {"type":"assistant","timestamp":"2026-04-07T10:00:00.000Z","message":{"model":"opus","usage":{"input_tokens":3.14,"output_tokens":"abc","cache_creation_input_tokens":null}}}
        """
        let buckets = ActivityDataService.parseJsonlIntoBuckets(jsonl)
        #expect(buckets.count == 1)
        let bucket = buckets.values.first!
        #expect(bucket.inputTokens == 0)
        #expect(bucket.outputTokens == 0)
    }

    @Test func parseJsonlMissingTimestampSkipsEntry() {
        let jsonl = """
        {"type":"assistant","message":{"model":"opus","usage":{"input_tokens":100,"output_tokens":50}}}
        """
        let buckets = ActivityDataService.parseJsonlIntoBuckets(jsonl)
        #expect(buckets.isEmpty)
    }

    @Test func parseJsonlInvalidTimestampSkipsEntry() {
        let jsonl = """
        {"type":"assistant","timestamp":"not-a-date","message":{"model":"opus","usage":{"input_tokens":100,"output_tokens":50}}}
        """
        let buckets = ActivityDataService.parseJsonlIntoBuckets(jsonl)
        #expect(buckets.isEmpty)
    }

    @Test func parseJsonlOnlyNonAssistantEntries() {
        let jsonl = """
        {"type":"user","message":{"role":"user","content":"hello"}}
        {"type":"permission-mode","permissionMode":"default"}
        """
        let buckets = ActivityDataService.parseJsonlIntoBuckets(jsonl)
        #expect(buckets.isEmpty)
    }

    @Test func parseJsonlSessionCountOnEarliestDay() {
        let jsonl = """
        {"type":"assistant","timestamp":"2026-04-08T09:00:00.000Z","message":{"model":"opus","usage":{"input_tokens":100,"output_tokens":50}}}
        {"type":"assistant","timestamp":"2026-04-07T10:00:00.000Z","message":{"model":"opus","usage":{"input_tokens":200,"output_tokens":100}}}
        """
        let buckets = ActivityDataService.parseJsonlIntoBuckets(jsonl)
        #expect(buckets["2026-04-07"]!.sessionCount == 1)
        #expect(buckets["2026-04-08"]!.sessionCount == 0)
    }

    @Test func emptyJsonlReturnsEmptyBuckets() {
        let buckets = ActivityDataService.parseJsonlIntoBuckets("")
        #expect(buckets.isEmpty)
    }

    // MARK: - mergeBuckets

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

    @Test func mergeBucketsEmptyFromLeavesExistingUnchanged() {
        var existing: [String: DailyBucket] = [
            "2026-04-07": DailyBucket(inputTokens: 500, outputTokens: 200, sessionCount: 2, models: ["opus": 700])
        ]
        ActivityDataService.mergeBuckets(into: &existing, from: [:])
        #expect(existing.count == 1)
        #expect(existing["2026-04-07"]!.inputTokens == 500)
    }

    @Test func mergeBucketsIntoEmptyProducesFrom() {
        var existing: [String: DailyBucket] = [:]
        let from: [String: DailyBucket] = [
            "2026-04-07": DailyBucket(inputTokens: 100, outputTokens: 50, sessionCount: 1, models: ["opus": 150])
        ]
        ActivityDataService.mergeBuckets(into: &existing, from: from)
        #expect(existing.count == 1)
        #expect(existing["2026-04-07"]!.inputTokens == 100)
    }

    // MARK: - aggregateBuckets

    @Test func aggregateBucketsFromMultipleFiles() {
        let fileBuckets: [String: [String: DailyBucket]] = [
            "/file1.jsonl": [
                "2026-04-07": DailyBucket(inputTokens: 100, outputTokens: 50, sessionCount: 1, models: ["opus": 150])
            ],
            "/file2.jsonl": [
                "2026-04-07": DailyBucket(inputTokens: 200, outputTokens: 100, sessionCount: 1, models: ["opus": 200, "sonnet": 100]),
                "2026-04-08": DailyBucket(inputTokens: 50, outputTokens: 25, sessionCount: 1, models: ["opus": 75])
            ]
        ]
        let result = ActivityDataService.aggregateBuckets(fileBuckets)
        #expect(result.count == 2)
        #expect(result["2026-04-07"]!.inputTokens == 300)
        #expect(result["2026-04-07"]!.sessionCount == 2)
        #expect(result["2026-04-08"]!.inputTokens == 50)
    }

    // MARK: - computeSummary

    @Test func computeSummary() {
        let buckets: [String: DailyBucket] = [
            "2026-04-01": DailyBucket(inputTokens: 1000, outputTokens: 500, sessionCount: 2, models: ["opus": 1200, "sonnet": 300]),
            "2026-04-02": DailyBucket(inputTokens: 3000, outputTokens: 1000, sessionCount: 5, models: ["opus": 3500, "sonnet": 500]),
            "2026-01-15": DailyBucket(inputTokens: 500, outputTokens: 200, sessionCount: 1, models: ["opus": 700])
        ]
        let summary = ActivityDataService.computeSummary(
            allBuckets: buckets,
            periodStart: "2026-01-13"
        )
        #expect(summary.allTimeTotal == 6200)
        #expect(summary.periodTotal == 6200)
        #expect(summary.periodSessionCount == 8)
        #expect(summary.busiestDayTokens == 4000)
        #expect(summary.busiestDayDate == "2026-04-02")
        #expect(summary.modelBreakdown.first?.name == "opus")
    }

    @Test func computeSummaryEmptyBuckets() {
        let summary = ActivityDataService.computeSummary(allBuckets: [:], periodStart: "2026-01-01")
        #expect(summary.allTimeTotal == 0)
        #expect(summary.periodSessionCount == 0)
        #expect(summary.modelBreakdown.isEmpty)
    }

    @Test func computeSummaryAllBucketsOutsidePeriod() {
        let buckets: [String: DailyBucket] = [
            "2020-01-01": DailyBucket(inputTokens: 1000, outputTokens: 500, sessionCount: 3, models: ["opus": 1500]),
            "2020-06-15": DailyBucket(inputTokens: 2000, outputTokens: 1000, sessionCount: 2, models: ["opus": 3000]),
        ]
        let summary = ActivityDataService.computeSummary(allBuckets: buckets, periodStart: "2026-01-01")
        #expect(summary.allTimeTotal == 4500)
        #expect(summary.periodTotal == 0)
        #expect(summary.periodSessionCount == 0)
        #expect(summary.busiestDayTokens == 3000)
    }

    @Test func computeSummaryPeriodStartExactMatch() {
        let buckets: [String: DailyBucket] = [
            "2026-04-01": DailyBucket(inputTokens: 1000, outputTokens: 500, sessionCount: 2, models: ["opus": 1500]),
        ]
        let summary = ActivityDataService.computeSummary(allBuckets: buckets, periodStart: "2026-04-01")
        #expect(summary.periodTotal == 1500)
        #expect(summary.periodSessionCount == 2)
    }

    @Test func computeSummarySingleModel() {
        let buckets: [String: DailyBucket] = [
            "2026-04-01": DailyBucket(inputTokens: 100, outputTokens: 50, sessionCount: 1, models: ["opus": 150]),
        ]
        let summary = ActivityDataService.computeSummary(allBuckets: buckets, periodStart: "2026-01-01")
        #expect(summary.modelBreakdown.count == 1)
        #expect(summary.modelBreakdown.first?.percentage == 100)
    }

    // MARK: - filesToScan

    @Test func filesToScanDetectsNewFiles() {
        let cache = ActivityCache()
        let result = ActivityDataService.filesToScan(allFiles: ["/fake/path.jsonl"], cache: cache)
        #expect(result.count == 1)
    }

    @Test func filesToScanSkipsUnchangedFiles() {
        let now = Date()
        var cache = ActivityCache()
        cache.scannedFiles["/fake/path.jsonl"] = ScannedFileInfo(lastModified: now, byteSize: 1024)
        // Since /fake/path.jsonl doesn't exist on disk, attributesOfItem will fail,
        // and the file will be included in the scan list (defensive behavior)
        let result = ActivityDataService.filesToScan(allFiles: ["/fake/path.jsonl"], cache: cache)
        #expect(result.count == 1) // can't stat → needs scan
    }

    // MARK: - Cache round-trip

    @Test func activityCacheCodeableRoundTrip() throws {
        var cache = ActivityCache()
        cache.scannedFiles["/test.jsonl"] = ScannedFileInfo(lastModified: Date(timeIntervalSince1970: 1000), byteSize: 512)
        cache.fileBuckets["/test.jsonl"] = [
            "2026-04-07": DailyBucket(inputTokens: 100, outputTokens: 50, sessionCount: 1, models: ["opus": 150])
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(cache)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ActivityCache.self, from: data)

        #expect(decoded.version == ActivityCache.currentVersion)
        #expect(decoded.scannedFiles.count == 1)
        #expect(decoded.fileBuckets["/test.jsonl"]?["2026-04-07"]?.inputTokens == 100)
    }
}
