import Testing
import Foundation
@testable import Tempo

@Suite("TerminalOutputParser")
struct TerminalOutputParserTests {

    private func parse(_ text: String) -> [TerminalEvent] {
        let parser = TerminalOutputParser()
        return parser.feed(text.data(using: .utf8)!)
    }

    // MARK: - Permission Prompts

    @Test func detectsSimplePermissionPrompt() {
        let events = parse("? Allow Read tool? (y/n)")
        #expect(events.contains { if case .permissionPrompt(let tool, _) = $0 { return tool == "Read" } else { return false } })
    }

    @Test func detectsBashPermissionPrompt() {
        let events = parse("? Allow Bash(git status) tool? (y/n)")
        #expect(events.contains { if case .permissionPrompt(let tool, _) = $0 { return tool.contains("Bash") } else { return false } })
    }

    @Test func detectsEditPermissionPrompt() {
        let events = parse("? Allow Edit tool? (y/n)")
        #expect(events.contains { if case .permissionPrompt(let tool, _) = $0 { return tool == "Edit" } else { return false } })
    }

    @Test func detectsYNBracketFormat() {
        let events = parse("? Allow Write tool? [Y/n]")
        #expect(events.contains { if case .permissionPrompt = $0 { return true } else { return false } })
    }

    @Test func permissionPromptWithAnsiCodes() {
        let input = "\u{1B}[1;33m?\u{1B}[0m Allow \u{1B}[1mRead\u{1B}[0m tool? \u{1B}[2m(y/n)\u{1B}[0m"
        let events = parse(input)
        #expect(events.contains { if case .permissionPrompt(let tool, _) = $0 { return tool == "Read" } else { return false } })
    }

    @Test func nonPermissionLineIgnored() {
        let events = parse("Hello world, this is just text")
        #expect(events.isEmpty)
    }

    // MARK: - Tool Use

    @Test func detectsToolUse() {
        let events = parse("⏺ Using tool: Read file.txt")
        #expect(events.contains { if case .toolUse(let detail) = $0 { return detail == "Read file.txt" } else { return false } })
    }

    // MARK: - Errors

    @Test func detectsErrorPrefix() {
        let events = parse("Error: something went wrong")
        #expect(events.contains { if case .error = $0 { return true } else { return false } })
    }

    @Test func detectsFatalError() {
        let events = parse("fatal: not a git repository")
        #expect(events.contains { if case .error = $0 { return true } else { return false } })
    }

    // MARK: - Questions

    @Test func detectsQuestion() {
        let events = parse("Would you like me to continue with this approach?")
        #expect(events.contains { if case .question = $0 { return true } else { return false } })
    }

    @Test func ignoresShortQuestionMark() {
        let events = parse("?")
        #expect(!events.contains { if case .question = $0 { return true } else { return false } })
    }

    @Test func ignoresPermissionAsQuestion() {
        let events = parse("? Allow Read tool? (y/n)")
        // Should be permissionPrompt, not question
        #expect(!events.contains { if case .question = $0 { return true } else { return false } })
    }

    // MARK: - Multiple Events

    @Test func multipleEventsInOneChunk() {
        let input = "? Allow Read tool? (y/n)\nError: file not found\nWould you like me to try another approach?"
        let events = parse(input)
        #expect(events.count == 3)
    }

    // MARK: - Incremental Parsing

    @Test func incrementalFeeding() {
        let parser = TerminalOutputParser()
        let events1 = parser.feed("Some output\n".data(using: .utf8)!)
        #expect(events1.isEmpty)

        let events2 = parser.feed("? Allow Read tool? (y/n)\n".data(using: .utf8)!)
        #expect(events2.count == 1)
    }

    @Test func resetClearsState() {
        let parser = TerminalOutputParser()
        _ = parser.feed("some text\n".data(using: .utf8)!)
        parser.reset()
        // After reset, parser should work normally
        let events = parser.feed("? Allow Edit tool? (y/n)\n".data(using: .utf8)!)
        #expect(events.count == 1)
    }
}
