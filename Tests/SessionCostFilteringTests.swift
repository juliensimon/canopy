import Testing
import Foundation
@testable import Canopy

/// SessionCostService must mirror ActivityDataService's filtering: skip
/// `<synthetic>` harness entries (not real token spend), and when a `since`
/// cutoff is set, exclude entries whose timestamp is missing/unparseable — they
/// can't be confirmed in-window, so counting them over-reports recent usage.
@Suite("Session Cost Filtering")
struct SessionCostFilteringTests {

    @Test func skipsSyntheticModelEntries() {
        let jsonl = """
        {"type":"assistant","timestamp":"2026-06-01T00:00:00.000Z","message":{"model":"<synthetic>","usage":{"output_tokens":999}}}
        {"type":"assistant","timestamp":"2026-06-01T00:00:00.000Z","message":{"model":"claude-opus","usage":{"output_tokens":10}}}
        """
        let usage = SessionCostService.parseTokenUsage(from: jsonl)
        #expect(usage.outputTokens == 10)
        #expect(usage.models == ["claude-opus"])
    }

    @Test func excludesUnparseableTimestampWhenSinceSet() {
        // No timestamp; with a cutoff active the entry can't be confirmed
        // in-window, so it must not be counted.
        let jsonl = """
        {"type":"assistant","message":{"model":"claude-opus","usage":{"output_tokens":5}}}
        """
        let usage = SessionCostService.parseTokenUsage(
            from: jsonl, since: Date(timeIntervalSince1970: 0)
        )
        #expect(usage.outputTokens == 0)
    }

    @Test func countsInWindowTimestampedEntries() {
        // Sanity: a valid, in-window entry is still counted (the fix must not
        // over-filter).
        let jsonl = """
        {"type":"assistant","timestamp":"2026-06-01T00:00:00.000Z","message":{"model":"claude-opus","usage":{"output_tokens":7}}}
        """
        let usage = SessionCostService.parseTokenUsage(
            from: jsonl, since: Date(timeIntervalSince1970: 0)
        )
        #expect(usage.outputTokens == 7)
    }

    @Test func countsInWindowEntryWithoutFractionalSeconds() {
        // Real Claude JSONL timestamps sometimes lack fractional seconds. With a
        // cutoff active, such an in-window entry must still be counted (matching
        // ActivityDataService's fallback) — not dropped as "unparseable".
        let jsonl = """
        {"type":"assistant","timestamp":"2026-06-01T00:00:00Z","message":{"model":"claude-opus","usage":{"output_tokens":7}}}
        """
        let usage = SessionCostService.parseTokenUsage(
            from: jsonl, since: Date(timeIntervalSince1970: 0)
        )
        #expect(usage.outputTokens == 7)
    }
}
