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
