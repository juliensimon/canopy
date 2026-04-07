import Testing
import Foundation
@testable import Canopy

@Suite("SessionCostService")
struct SessionCostServiceTests {

    @Test func parseEmptyFile() {
        let usage = SessionCostService.parseTokenUsage(from: "")
        #expect(usage.inputTokens == 0)
        #expect(usage.outputTokens == 0)
        #expect(usage.cacheCreationTokens == 0)
        #expect(usage.cacheReadTokens == 0)
    }

    @Test func parseSingleAssistantMessage() {
        let jsonl = """
        {"type":"assistant","message":{"model":"claude-opus-4-6","usage":{"input_tokens":100,"cache_creation_input_tokens":500,"cache_read_input_tokens":200,"output_tokens":50}}}
        """
        let usage = SessionCostService.parseTokenUsage(from: jsonl)
        #expect(usage.inputTokens == 100)
        #expect(usage.outputTokens == 50)
        #expect(usage.cacheCreationTokens == 500)
        #expect(usage.cacheReadTokens == 200)
        #expect(usage.model == "claude-opus-4-6")
    }

    @Test func parseMultipleMessages() {
        let jsonl = """
        {"type":"user","message":{"role":"user","content":"hello"}}
        {"type":"assistant","message":{"model":"claude-opus-4-6","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":50}}}
        {"type":"assistant","message":{"model":"claude-opus-4-6","usage":{"input_tokens":200,"cache_creation_input_tokens":100,"cache_read_input_tokens":300,"output_tokens":75}}}
        """
        let usage = SessionCostService.parseTokenUsage(from: jsonl)
        #expect(usage.inputTokens == 300)
        #expect(usage.outputTokens == 125)
        #expect(usage.cacheCreationTokens == 100)
        #expect(usage.cacheReadTokens == 300)
    }

    @Test func parseMalformedLineSkipped() {
        let jsonl = """
        not json at all
        {"type":"assistant","message":{"model":"claude-opus-4-6","usage":{"input_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":25}}}
        """
        let usage = SessionCostService.parseTokenUsage(from: jsonl)
        #expect(usage.inputTokens == 50)
        #expect(usage.outputTokens == 25)
    }

    @Test func parseNonAssistantTypesIgnored() {
        let jsonl = """
        {"type":"permission-mode","permissionMode":"default"}
        {"type":"user","message":{"role":"user","content":"hi"}}
        {"type":"attachment","attachment":{"type":"deferred_tools_delta"}}
        """
        let usage = SessionCostService.parseTokenUsage(from: jsonl)
        #expect(usage.inputTokens == 0)
        #expect(usage.outputTokens == 0)
    }

    @Test func costCalculationOpus() {
        var usage = TokenUsage()
        usage.inputTokens = 1_000_000
        usage.outputTokens = 1_000_000
        usage.cacheCreationTokens = 0
        usage.cacheReadTokens = 0
        usage.model = "claude-opus-4-6"
        let cost = usage.estimatedCost
        #expect(abs(cost - 90.0) < 0.01)
    }

    @Test func costCalculationSonnet() {
        var usage = TokenUsage()
        usage.inputTokens = 1_000_000
        usage.outputTokens = 1_000_000
        usage.cacheCreationTokens = 0
        usage.cacheReadTokens = 0
        usage.model = "claude-sonnet-4-6"
        let cost = usage.estimatedCost
        #expect(abs(cost - 18.0) < 0.01)
    }

    @Test func costCalculationWithCache() {
        var usage = TokenUsage()
        usage.inputTokens = 0
        usage.outputTokens = 0
        usage.cacheCreationTokens = 1_000_000
        usage.cacheReadTokens = 1_000_000
        usage.model = "claude-sonnet-4-6"
        let cost = usage.estimatedCost
        #expect(abs(cost - 4.05) < 0.01)
    }

    @Test func totalTokens() {
        var usage = TokenUsage()
        usage.inputTokens = 100
        usage.outputTokens = 200
        usage.cacheCreationTokens = 300
        usage.cacheReadTokens = 400
        #expect(usage.totalTokens == 1000)
    }

    @Test func formattedCost() {
        var usage = TokenUsage()
        usage.inputTokens = 1000
        usage.outputTokens = 500
        usage.model = "claude-sonnet-4-6"
        let formatted = usage.formattedCost
        #expect(formatted.hasPrefix("$"))
    }

    @Test func claudeProjectDirEncoding() {
        let dir = SessionCostService.claudeProjectDir(for: "/Users/julien/my-project")
        let home = NSHomeDirectory()
        #expect(dir == "\(home)/.claude/projects/-Users-julien-my-project")
    }
}
