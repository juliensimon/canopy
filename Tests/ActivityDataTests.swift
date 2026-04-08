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

    @Test func abbreviatedTokenCountBillions() {
        #expect(abbreviatedTokenCount(2_500_000_000) == "2.5G")
    }

    @Test func abbreviatedTokenCountTrillions() {
        #expect(abbreviatedTokenCount(1_200_000_000_000) == "1.2T")
    }

    @Test func abbreviatedTokenCountExactBillion() {
        #expect(abbreviatedTokenCount(1_000_000_000) == "1.0G")
    }
}

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
        #expect(buckets.count == 2)

        let apr7 = buckets["2026-04-07"]!
        #expect(apr7.inputTokens == 375) // 100+50+25 + 200
        #expect(apr7.outputTokens == 175) // 75 + 100
        #expect(apr7.sessionCount == 1)
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
}
