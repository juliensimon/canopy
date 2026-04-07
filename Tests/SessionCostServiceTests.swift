import Testing
import Foundation
@testable import Canopy

@Suite("SessionCostService")
struct SessionCostServiceTests {

    @Test func parseEmptyFile() {
        let usage = SessionCostService.parseTokenUsage(from: "")
        #expect(usage.inputTokens == 0)
        #expect(usage.outputTokens == 0)
    }

    @Test func parseSingleAssistantMessage() {
        let jsonl = """
        {"type":"assistant","message":{"model":"claude-opus-4-6","usage":{"input_tokens":100,"cache_creation_input_tokens":500,"cache_read_input_tokens":200,"output_tokens":50}}}
        """
        let usage = SessionCostService.parseTokenUsage(from: jsonl)
        // Input = input_tokens + cache_creation + cache_read
        #expect(usage.inputTokens == 800)
        #expect(usage.outputTokens == 50)
        #expect(usage.models.contains("claude-opus-4-6"))
    }

    @Test func parseMultipleMessages() {
        let jsonl = """
        {"type":"user","message":{"role":"user","content":"hello"}}
        {"type":"assistant","message":{"model":"claude-opus-4-6","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":50}}}
        {"type":"assistant","message":{"model":"claude-opus-4-6","usage":{"input_tokens":200,"cache_creation_input_tokens":100,"cache_read_input_tokens":300,"output_tokens":75}}}
        """
        let usage = SessionCostService.parseTokenUsage(from: jsonl)
        #expect(usage.inputTokens == 700)
        #expect(usage.outputTokens == 125)
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

    @Test func totalTokens() {
        var usage = TokenUsage()
        usage.inputTokens = 100
        usage.outputTokens = 200
        #expect(usage.totalTokens == 300)
    }

    @Test func multipleModelsTracked() {
        let jsonl = """
        {"type":"assistant","message":{"model":"claude-opus-4-6","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":50}}}
        {"type":"assistant","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":50}}}
        """
        let usage = SessionCostService.parseTokenUsage(from: jsonl)
        #expect(usage.models.count == 2)
        #expect(usage.models.contains("claude-opus-4-6"))
        #expect(usage.models.contains("claude-sonnet-4-6"))
    }

    @Test func claudeProjectDirEncoding() {
        let dir = SessionCostService.claudeProjectDir(for: "/Users/julien/my-project")
        let home = NSHomeDirectory()
        #expect(dir == "\(home)/.claude/projects/-Users-julien-my-project")
    }
}
