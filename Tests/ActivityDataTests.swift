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

@Suite("ActivityDataService — Parsing")
struct ActivityParsingTests {

    // MARK: - Basic parsing

    @Test func parseSingleAssistantEntry() {
        let jsonl = """
        {"type":"assistant","timestamp":"2026-04-07T10:00:00.000Z","message":{"model":"claude-opus-4-6","usage":{"input_tokens":100,"cache_creation_input_tokens":50,"cache_read_input_tokens":25,"output_tokens":75}}}
        """
        let buckets = ActivityDataService.parseJsonlIntoBuckets(jsonl)
        #expect(buckets.count == 1)
        let bucket = buckets["2026-04-07"]!
        #expect(bucket.inputTokens == 175) // 100+50+25
        #expect(bucket.outputTokens == 75)
        #expect(bucket.sessionCount == 1)
        #expect(bucket.models["claude-opus-4-6"] == 250) // 175+75
    }

    @Test func parseMultipleEntriesSameDay() {
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
        #expect(apr8.sessionCount == 0) // session counted on earliest day only
    }

    // MARK: - Robustness

    @Test func skipsMalformedLines() {
        let jsonl = """
        not valid json
        {"type":"assistant","timestamp":"2026-04-07T10:00:00.000Z","message":{"model":"opus","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":50}}}
        """
        let buckets = ActivityDataService.parseJsonlIntoBuckets(jsonl)
        #expect(buckets.count == 1)
        #expect(buckets["2026-04-07"]!.inputTokens == 100)
    }

    @Test func emptyInputReturnsEmpty() {
        #expect(ActivityDataService.parseJsonlIntoBuckets("").isEmpty)
    }

    @Test func onlyNonAssistantEntriesReturnsEmpty() {
        let jsonl = """
        {"type":"user","message":{"role":"user","content":"hello"}}
        {"type":"permission-mode","permissionMode":"default"}
        {"type":"result","result":"something"}
        """
        #expect(ActivityDataService.parseJsonlIntoBuckets(jsonl).isEmpty)
    }

    // MARK: - Timestamp handling

    @Test func timestampWithoutFractionalSeconds() {
        let jsonl = """
        {"type":"assistant","timestamp":"2026-04-07T10:00:00Z","message":{"model":"opus","usage":{"input_tokens":100,"output_tokens":50}}}
        """
        let buckets = ActivityDataService.parseJsonlIntoBuckets(jsonl)
        #expect(buckets.count == 1)
        #expect(buckets["2026-04-07"]?.inputTokens == 100)
    }

    @Test func timestampWithTimezoneOffset() {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: "2026-04-07T23:00:00.000-05:00")!
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"
        dayFmt.timeZone = .current
        let expectedKey = dayFmt.string(from: date)

        let jsonl = """
        {"type":"assistant","timestamp":"2026-04-07T23:00:00.000-05:00","message":{"model":"opus","usage":{"input_tokens":200,"output_tokens":100}}}
        """
        let buckets = ActivityDataService.parseJsonlIntoBuckets(jsonl)
        #expect(buckets.count == 1)
        #expect(buckets[expectedKey] != nil)
        #expect(buckets[expectedKey]!.inputTokens == 200)
    }

    @Test func missingTimestampSkipsEntry() {
        let jsonl = """
        {"type":"assistant","message":{"model":"opus","usage":{"input_tokens":100,"output_tokens":50}}}
        """
        #expect(ActivityDataService.parseJsonlIntoBuckets(jsonl).isEmpty)
    }

    @Test func invalidTimestampSkipsEntry() {
        let jsonl = """
        {"type":"assistant","timestamp":"not-a-date","message":{"model":"opus","usage":{"input_tokens":100,"output_tokens":50}}}
        """
        #expect(ActivityDataService.parseJsonlIntoBuckets(jsonl).isEmpty)
    }

    // MARK: - Missing/malformed fields

    @Test func missingCacheTokenFieldsDefaultToZero() {
        let jsonl = """
        {"type":"assistant","timestamp":"2026-04-07T10:00:00.000Z","message":{"model":"opus","usage":{"input_tokens":500,"output_tokens":250}}}
        """
        let bucket = ActivityDataService.parseJsonlIntoBuckets(jsonl).values.first!
        #expect(bucket.inputTokens == 500)
        #expect(bucket.outputTokens == 250)
        #expect(bucket.totalTokens == 750)
    }

    @Test func missingModelDefaultsToUnknown() {
        let jsonl = """
        {"type":"assistant","timestamp":"2026-04-07T10:00:00.000Z","message":{"usage":{"input_tokens":100,"output_tokens":50}}}
        """
        let bucket = ActivityDataService.parseJsonlIntoBuckets(jsonl).values.first!
        #expect(bucket.models["unknown"] == 150)
    }

    @Test func nonIntegerTokenValues() {
        let jsonl = """
        {"type":"assistant","timestamp":"2026-04-07T10:00:00.000Z","message":{"model":"opus","usage":{"output_tokens":"abc","cache_creation_input_tokens":null}}}
        """
        let bucket = ActivityDataService.parseJsonlIntoBuckets(jsonl).values.first!
        #expect(bucket.outputTokens == 0)
    }

    @Test func missingUsageDictSkipsEntry() {
        let jsonl = """
        {"type":"assistant","timestamp":"2026-04-07T10:00:00.000Z","message":{"model":"opus"}}
        """
        #expect(ActivityDataService.parseJsonlIntoBuckets(jsonl).isEmpty)
    }

    @Test func emptyUsageDictProducesZeroTokenBucket() {
        let jsonl = """
        {"type":"assistant","timestamp":"2026-04-07T10:00:00.000Z","message":{"model":"opus","usage":{}}}
        """
        let bucket = ActivityDataService.parseJsonlIntoBuckets(jsonl).values.first!
        #expect(bucket.inputTokens == 0)
        #expect(bucket.outputTokens == 0)
        #expect(bucket.models["opus"] == 0)
        #expect(bucket.sessionCount == 1) // still counts as a session
    }

    // MARK: - Session count attribution

    @Test func sessionCountOnEarliestDay() {
        let jsonl = """
        {"type":"assistant","timestamp":"2026-04-08T09:00:00.000Z","message":{"model":"opus","usage":{"input_tokens":100,"output_tokens":50}}}
        {"type":"assistant","timestamp":"2026-04-07T10:00:00.000Z","message":{"model":"opus","usage":{"input_tokens":200,"output_tokens":100}}}
        """
        let buckets = ActivityDataService.parseJsonlIntoBuckets(jsonl)
        #expect(buckets["2026-04-07"]!.sessionCount == 1)
        #expect(buckets["2026-04-08"]!.sessionCount == 0)
    }

    @Test func singleEntryGetsSessionCount() {
        let jsonl = """
        {"type":"assistant","timestamp":"2026-04-07T10:00:00.000Z","message":{"model":"opus","usage":{"input_tokens":100,"output_tokens":50}}}
        """
        #expect(ActivityDataService.parseJsonlIntoBuckets(jsonl)["2026-04-07"]!.sessionCount == 1)
    }

    // MARK: - Fast-path marker correctness

    @Test func assistantInMessageContentDoesNotConfuseParser() {
        // The string "type":"assistant" appears in the user message content.
        // The fast-path marker check should let it through, but JSON parsing
        // should correctly identify it as type:"user", not type:"assistant".
        let jsonl = """
        {"type":"user","message":{"content":"the type is \\"type\\":\\"assistant\\" here"}}
        {"type":"assistant","timestamp":"2026-04-07T10:00:00.000Z","message":{"model":"opus","usage":{"input_tokens":100,"output_tokens":50}}}
        """
        let buckets = ActivityDataService.parseJsonlIntoBuckets(jsonl)
        #expect(buckets.count == 1)
        #expect(buckets["2026-04-07"]!.inputTokens == 100)
    }

    // MARK: - Line ending edge cases

    @Test func trailingNewline() {
        let jsonl = """
        {"type":"assistant","timestamp":"2026-04-07T10:00:00.000Z","message":{"model":"opus","usage":{"input_tokens":100,"output_tokens":50}}}

        """
        let buckets = ActivityDataService.parseJsonlIntoBuckets(jsonl)
        #expect(buckets.count == 1)
        #expect(buckets["2026-04-07"]!.inputTokens == 100)
    }

    @Test func windowsLineEndings() {
        let jsonl = "{\"type\":\"assistant\",\"timestamp\":\"2026-04-07T10:00:00.000Z\",\"message\":{\"model\":\"opus\",\"usage\":{\"input_tokens\":100,\"output_tokens\":50}}}\r\n{\"type\":\"assistant\",\"timestamp\":\"2026-04-08T10:00:00.000Z\",\"message\":{\"model\":\"opus\",\"usage\":{\"input_tokens\":200,\"output_tokens\":75}}}\r\n"
        let buckets = ActivityDataService.parseJsonlIntoBuckets(jsonl)
        // \r at end of each line is part of the JSON data — JSONSerialization should
        // still parse it (whitespace is ignored). Verify both entries are captured.
        #expect(buckets.count == 2)
        #expect(buckets["2026-04-07"]!.inputTokens == 100)
        #expect(buckets["2026-04-08"]!.inputTokens == 200)
    }

    // MARK: - Model token consistency

    @Test func modelTokensEqualInputPlusOutput() {
        let jsonl = """
        {"type":"assistant","timestamp":"2026-04-07T10:00:00.000Z","message":{"model":"opus","usage":{"input_tokens":100,"cache_creation_input_tokens":50,"cache_read_input_tokens":25,"output_tokens":75}}}
        """
        let bucket = ActivityDataService.parseJsonlIntoBuckets(jsonl)["2026-04-07"]!
        // Model tokens should equal inputTokens + outputTokens
        #expect(bucket.models["opus"] == bucket.totalTokens)
    }

    @Test func multipleModelsSameDayTokensAddUp() {
        let jsonl = """
        {"type":"assistant","timestamp":"2026-04-07T10:00:00.000Z","message":{"model":"opus","usage":{"input_tokens":100,"output_tokens":50}}}
        {"type":"assistant","timestamp":"2026-04-07T14:00:00.000Z","message":{"model":"sonnet","usage":{"input_tokens":200,"output_tokens":75}}}
        """
        let bucket = ActivityDataService.parseJsonlIntoBuckets(jsonl)["2026-04-07"]!
        let modelTotal = bucket.models.values.reduce(0, +)
        #expect(modelTotal == bucket.totalTokens)
    }

    // MARK: - Real-world JSONL format test

    @Test func realWorldJsonlFormat() {
        // Test against actual Claude Code JSONL format with all field types
        let jsonl = """
        {"type":"system","message":{"role":"system","content":"system prompt here"},"timestamp":"2026-04-07T10:00:00.000Z"}
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":"help me"}]},"timestamp":"2026-04-07T10:00:01.000Z"}
        {"type":"assistant","message":{"id":"msg_abc","type":"message","role":"assistant","content":[{"type":"text","text":"sure"}],"model":"claude-opus-4-6","stop_reason":"end_turn","usage":{"input_tokens":15000,"cache_creation_input_tokens":80000,"cache_read_input_tokens":120000,"output_tokens":500}},"timestamp":"2026-04-07T10:00:05.123Z"}
        {"type":"result","result":{"type":"success"},"timestamp":"2026-04-07T10:00:06.000Z"}
        """
        let buckets = ActivityDataService.parseJsonlIntoBuckets(jsonl)
        #expect(buckets.count == 1)
        let bucket = buckets["2026-04-07"]!
        #expect(bucket.inputTokens == 215000) // 15000+80000+120000
        #expect(bucket.outputTokens == 500)
        #expect(bucket.sessionCount == 1)
        #expect(bucket.models["claude-opus-4-6"] == 215500)
    }
}

@Suite("ActivityDataService — Aggregation & Summary")
struct ActivityAggregationTests {

    // MARK: - mergeBuckets

    @Test func mergeAddsTokensAndSessions() {
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

    @Test func mergeEmptyFromIsNoop() {
        var existing: [String: DailyBucket] = [
            "2026-04-07": DailyBucket(inputTokens: 500, outputTokens: 200, sessionCount: 2, models: ["opus": 700])
        ]
        ActivityDataService.mergeBuckets(into: &existing, from: [:])
        #expect(existing.count == 1)
        #expect(existing["2026-04-07"]!.inputTokens == 500)
    }

    @Test func mergeIntoEmptyProducesFrom() {
        var existing: [String: DailyBucket] = [:]
        let from: [String: DailyBucket] = [
            "2026-04-07": DailyBucket(inputTokens: 100, outputTokens: 50, sessionCount: 1, models: ["opus": 150])
        ]
        ActivityDataService.mergeBuckets(into: &existing, from: from)
        #expect(existing.count == 1)
        #expect(existing["2026-04-07"]!.inputTokens == 100)
    }

    // MARK: - aggregateBuckets

    @Test func aggregateMultipleFiles() {
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

    @Test func aggregateEmptyFileBuckets() {
        let result = ActivityDataService.aggregateBuckets([:])
        #expect(result.isEmpty)
    }

    @Test func aggregateReplacementNotAdditive() {
        // Simulate: file1 was scanned, then re-scanned with new data.
        // The per-file bucket should REPLACE, not accumulate.
        var fileBuckets: [String: [String: DailyBucket]] = [
            "/file1.jsonl": [
                "2026-04-07": DailyBucket(inputTokens: 100, outputTokens: 50, sessionCount: 1, models: ["opus": 150])
            ]
        ]
        // First aggregate
        let first = ActivityDataService.aggregateBuckets(fileBuckets)
        #expect(first["2026-04-07"]!.inputTokens == 100)

        // "Re-scan" file1 with updated data (file grew)
        fileBuckets["/file1.jsonl"] = [
            "2026-04-07": DailyBucket(inputTokens: 300, outputTokens: 150, sessionCount: 1, models: ["opus": 450])
        ]
        // Second aggregate should show 300, NOT 100+300=400
        let second = ActivityDataService.aggregateBuckets(fileBuckets)
        #expect(second["2026-04-07"]!.inputTokens == 300)
    }

    // MARK: - computeSummary

    @Test func summaryBasic() {
        let buckets: [String: DailyBucket] = [
            "2026-04-01": DailyBucket(inputTokens: 1000, outputTokens: 500, sessionCount: 2, models: ["opus": 1200, "sonnet": 300]),
            "2026-04-02": DailyBucket(inputTokens: 3000, outputTokens: 1000, sessionCount: 5, models: ["opus": 3500, "sonnet": 500]),
            "2026-01-15": DailyBucket(inputTokens: 500, outputTokens: 200, sessionCount: 1, models: ["opus": 700])
        ]
        let summary = ActivityDataService.computeSummary(allBuckets: buckets, periodStart: "2026-01-13")
        #expect(summary.allTimeTotal == 6200)
        #expect(summary.allTimeInput == 4500)
        #expect(summary.allTimeOutput == 1700)
        #expect(summary.periodTotal == 6200)
        #expect(summary.periodSessionCount == 8)
        #expect(summary.busiestDayTokens == 4000)
        #expect(summary.busiestDayDate == "2026-04-02")
        #expect(summary.modelBreakdown.first?.name == "Opus")
    }

    @Test func summaryEmpty() {
        let summary = ActivityDataService.computeSummary(allBuckets: [:], periodStart: "2026-01-01")
        #expect(summary.allTimeTotal == 0)
        #expect(summary.periodTotal == 0)
        #expect(summary.periodSessionCount == 0)
        #expect(summary.busiestDayTokens == 0)
        #expect(summary.busiestDayDate == "")
        #expect(summary.modelBreakdown.isEmpty)
    }

    @Test func summaryAllBucketsOutsidePeriod() {
        let buckets: [String: DailyBucket] = [
            "2020-01-01": DailyBucket(inputTokens: 1000, outputTokens: 500, sessionCount: 3, models: ["opus": 1500]),
            "2020-06-15": DailyBucket(inputTokens: 2000, outputTokens: 1000, sessionCount: 2, models: ["opus": 3000]),
        ]
        let summary = ActivityDataService.computeSummary(allBuckets: buckets, periodStart: "2026-01-01")
        #expect(summary.allTimeTotal == 4500)
        #expect(summary.periodTotal == 0)
        #expect(summary.periodSessionCount == 0)
        // Busiest day is still computed from all-time
        #expect(summary.busiestDayTokens == 3000)
    }

    @Test func summaryPeriodStartExactMatchIncluded() {
        let buckets: [String: DailyBucket] = [
            "2026-04-01": DailyBucket(inputTokens: 1000, outputTokens: 500, sessionCount: 2, models: ["opus": 1500]),
        ]
        let summary = ActivityDataService.computeSummary(allBuckets: buckets, periodStart: "2026-04-01")
        #expect(summary.periodTotal == 1500) // >= comparison includes exact match
        #expect(summary.periodSessionCount == 2)
    }

    @Test func summarySingleModel100Percent() {
        let buckets: [String: DailyBucket] = [
            "2026-04-01": DailyBucket(inputTokens: 100, outputTokens: 50, sessionCount: 1, models: ["opus": 150]),
        ]
        let summary = ActivityDataService.computeSummary(allBuckets: buckets, periodStart: "2026-01-01")
        #expect(summary.modelBreakdown.count == 1)
        #expect(summary.modelBreakdown.first?.name == "Opus")
        #expect(summary.modelBreakdown.first?.percentage == 100)
    }

    @Test func summaryModelBreakdownSortedByUsage() {
        let buckets: [String: DailyBucket] = [
            "2026-04-01": DailyBucket(inputTokens: 100, outputTokens: 50, sessionCount: 1,
                                       models: ["haiku": 50, "opus": 80, "sonnet": 20]),
        ]
        let summary = ActivityDataService.computeSummary(allBuckets: buckets, periodStart: "2026-01-01")
        #expect(summary.modelBreakdown[0].name == "Opus")
        #expect(summary.modelBreakdown[1].name == "Haiku")
        #expect(summary.modelBreakdown[2].name == "Sonnet")
    }

    @Test func summaryZeroTokenBucketsDoNotAffectBusiestDay() {
        let buckets: [String: DailyBucket] = [
            "2026-04-01": DailyBucket(inputTokens: 0, outputTokens: 0, sessionCount: 1, models: [:]),
            "2026-04-02": DailyBucket(inputTokens: 100, outputTokens: 50, sessionCount: 1, models: ["opus": 150]),
        ]
        let summary = ActivityDataService.computeSummary(allBuckets: buckets, periodStart: "2026-01-01")
        #expect(summary.busiestDayDate == "2026-04-02")
        #expect(summary.busiestDayTokens == 150)
    }
}

@Suite("ActivityDataService — Cache & Files")
struct ActivityCacheTests {

    @Test func filesToScanDetectsNewFiles() {
        let cache = ActivityCache()
        let result = ActivityDataService.filesToScan(allFiles: ["/fake/path.jsonl"], cache: cache)
        #expect(result.count == 1)
    }

    @Test func filesToScanWithNonexistentFileReturnsTrueDefensively() {
        var cache = ActivityCache()
        cache.scannedFiles["/fake/path.jsonl"] = ScannedFileInfo(lastModified: Date(), byteSize: 1024)
        // File doesn't exist on disk → attributesOfItem fails → treated as needing scan
        let result = ActivityDataService.filesToScan(allFiles: ["/fake/path.jsonl"], cache: cache)
        #expect(result.count == 1)
    }

    @Test func filesToScanWithRealUnchangedFile() throws {
        // Create a temp file, scan it, then check it's skipped on second scan
        let tmpDir = NSTemporaryDirectory()
        let tmpFile = (tmpDir as NSString).appendingPathComponent("test-\(UUID()).jsonl")
        FileManager.default.createFile(atPath: tmpFile, contents: Data("test".utf8))
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }

        let attrs = try FileManager.default.attributesOfItem(atPath: tmpFile)
        var cache = ActivityCache()
        cache.scannedFiles[tmpFile] = ScannedFileInfo(
            lastModified: attrs[.modificationDate] as! Date,
            byteSize: attrs[.size] as! Int
        )

        let result = ActivityDataService.filesToScan(allFiles: [tmpFile], cache: cache)
        #expect(result.isEmpty) // file unchanged → skip
    }

    @Test func cacheCodeableRoundTrip() throws {
        var cache = ActivityCache()
        cache.scannedFiles["/test.jsonl"] = ScannedFileInfo(lastModified: Date(timeIntervalSince1970: 1000), byteSize: 512)
        cache.fileBuckets["/test.jsonl"] = [
            "2026-04-07": DailyBucket(inputTokens: 100, outputTokens: 50, sessionCount: 1, models: ["opus": 150])
        ]
        cache.aggregatedBuckets = [
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
        #expect(decoded.aggregatedBuckets?["2026-04-07"]?.inputTokens == 100)
    }

    @Test func cacheVersionMismatchResetsToFresh() {
        var cache = ActivityCache()
        cache.version = 999 // bogus version
        cache.fileBuckets["/old.jsonl"] = ["2020-01-01": DailyBucket(inputTokens: 9999)]

        // Simulate what loadData does
        if cache.version != ActivityCache.currentVersion {
            cache = ActivityCache()
        }
        #expect(cache.fileBuckets.isEmpty)
        #expect(cache.scannedFiles.isEmpty)
    }

    @Test func periodStartDateReturnsValidFormat() {
        let result = ActivityDataService.periodStartDate()
        // Must be yyyy-MM-dd format
        let parts = result.split(separator: "-")
        #expect(parts.count == 3)
        #expect(parts[0].count == 4) // year
        #expect(parts[1].count == 2) // month
        #expect(parts[2].count == 2) // day

        // Must be approximately 12 weeks ago
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        let parsed = fmt.date(from: result)!
        let daysAgo = Calendar.current.dateComponents([.day], from: parsed, to: Date()).day!
        #expect(daysAgo >= 82 && daysAgo <= 86) // 12 weeks = 84 days, ±2 for edge
    }
}
