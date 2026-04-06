import Testing
import Foundation
@testable import Tempo

@Suite("WatchdogEngine")
struct WatchdogEngineTests {

    // MARK: - Rule Matching

    @Test @MainActor func approveAllPermissions() {
        let engine = WatchdogEngine()
        var sentText: [String] = []
        engine.sendToTerminal = { sentText.append($0) }
        engine.config = .autoApproveAll
        engine.isActive = true

        let actions = engine.evaluate(events: [
            .permissionPrompt(tool: "Read", fullLine: "? Allow Read tool? (y/n)")
        ])

        #expect(actions.count == 1)
        #expect(actions[0].response == .approve)
        #expect(sentText == ["y\n"])
    }

    @Test @MainActor func denyBashInSafeMode() {
        let engine = WatchdogEngine()
        var sentText: [String] = []
        engine.sendToTerminal = { sentText.append($0) }
        engine.config = .safeMode
        engine.isActive = true

        let actions = engine.evaluate(events: [
            .permissionPrompt(tool: "Bash(git status)", fullLine: "? Allow Bash(git status) tool? (y/n)")
        ])

        #expect(actions.count == 1)
        #expect(actions[0].response == .deny)
        #expect(sentText == ["n\n"])
    }

    @Test @MainActor func approveReadInSafeMode() {
        let engine = WatchdogEngine()
        var sentText: [String] = []
        engine.sendToTerminal = { sentText.append($0) }
        engine.config = .safeMode
        engine.isActive = true

        let actions = engine.evaluate(events: [
            .permissionPrompt(tool: "Read", fullLine: "? Allow Read tool? (y/n)")
        ])

        #expect(actions.count == 1)
        #expect(actions[0].response == .approve)
        #expect(sentText == ["y\n"])
    }

    @Test @MainActor func readOnlyDeniesWrite() {
        let engine = WatchdogEngine()
        var sentText: [String] = []
        engine.sendToTerminal = { sentText.append($0) }
        engine.config = .readOnly
        engine.isActive = true

        let actions = engine.evaluate(events: [
            .permissionPrompt(tool: "Write", fullLine: "? Allow Write tool? (y/n)")
        ])

        // Read-only config only has approve rules for Read/Glob/Grep
        // Write doesn't match any rule, so no action
        #expect(actions.isEmpty)
        #expect(sentText.isEmpty)
    }

    // MARK: - Safety Limits

    @Test @MainActor func respectsMaxResponses() {
        let engine = WatchdogEngine()
        var sentCount = 0
        engine.sendToTerminal = { _ in sentCount += 1 }

        let rule = WatchdogRule(
            name: "Limited approve",
            trigger: .permissionPrompt,
            response: .approve,
            maxResponses: 2
        )
        engine.config = WatchdogConfig(name: "test", rules: [rule])
        engine.isActive = true

        let event = TerminalEvent.permissionPrompt(tool: "Read", fullLine: "? Allow Read tool? (y/n)")

        // First two should work
        #expect(engine.evaluate(events: [event]).count == 1)
        #expect(engine.evaluate(events: [event]).count == 1)
        // Third should be blocked
        #expect(engine.evaluate(events: [event]).isEmpty)
        #expect(sentCount == 2)
    }

    @Test @MainActor func unlimitedWhenMaxIsZero() {
        let engine = WatchdogEngine()
        engine.sendToTerminal = { _ in }

        let rule = WatchdogRule(
            name: "Unlimited",
            trigger: .permissionPrompt,
            response: .approve,
            maxResponses: 0
        )
        engine.config = WatchdogConfig(name: "test", rules: [rule])
        engine.isActive = true

        let event = TerminalEvent.permissionPrompt(tool: "Read", fullLine: "? Allow Read tool? (y/n)")

        // Should keep working indefinitely
        for _ in 0..<100 {
            #expect(engine.evaluate(events: [event]).count == 1)
        }
    }

    @Test @MainActor func resetCountsAllowsMore() {
        let engine = WatchdogEngine()
        engine.sendToTerminal = { _ in }

        let rule = WatchdogRule(
            name: "Limited",
            trigger: .permissionPrompt,
            response: .approve,
            maxResponses: 1
        )
        engine.config = WatchdogConfig(name: "test", rules: [rule])
        engine.isActive = true

        let event = TerminalEvent.permissionPrompt(tool: "Read", fullLine: "? Allow Read tool? (y/n)")

        #expect(engine.evaluate(events: [event]).count == 1)
        #expect(engine.evaluate(events: [event]).isEmpty)

        engine.resetCounts()
        #expect(engine.evaluate(events: [event]).count == 1)
    }

    // MARK: - Disabled States

    @Test @MainActor func inactiveEngineDoesNothing() {
        let engine = WatchdogEngine()
        engine.sendToTerminal = { _ in }
        engine.config = .autoApproveAll
        engine.isActive = false

        let actions = engine.evaluate(events: [
            .permissionPrompt(tool: "Read", fullLine: "? Allow Read tool? (y/n)")
        ])
        #expect(actions.isEmpty)
    }

    @Test @MainActor func nilConfigDoesNothing() {
        let engine = WatchdogEngine()
        engine.sendToTerminal = { _ in }
        engine.config = nil
        engine.isActive = true

        let actions = engine.evaluate(events: [
            .permissionPrompt(tool: "Read", fullLine: "? Allow Read tool? (y/n)")
        ])
        #expect(actions.isEmpty)
    }

    @Test @MainActor func disabledRuleSkipped() {
        let engine = WatchdogEngine()
        engine.sendToTerminal = { _ in }

        var rule = WatchdogRule(name: "Disabled", trigger: .permissionPrompt, response: .approve)
        rule.isEnabled = false
        engine.config = WatchdogConfig(name: "test", rules: [rule])
        engine.isActive = true

        let actions = engine.evaluate(events: [
            .permissionPrompt(tool: "Read", fullLine: "? Allow Read tool? (y/n)")
        ])
        #expect(actions.isEmpty)
    }

    @Test @MainActor func disabledConfigDoesNothing() {
        let engine = WatchdogEngine()
        engine.sendToTerminal = { _ in }
        engine.config = WatchdogConfig(name: "test", isEnabled: false, rules: [
            WatchdogRule(name: "Approve", trigger: .permissionPrompt, response: .approve)
        ])
        engine.isActive = true

        let actions = engine.evaluate(events: [
            .permissionPrompt(tool: "Read", fullLine: "? Allow Read tool? (y/n)")
        ])
        #expect(actions.isEmpty)
    }

    // MARK: - Tool Pattern Filtering

    @Test @MainActor func toolPatternFilters() {
        let engine = WatchdogEngine()
        var sentText: [String] = []
        engine.sendToTerminal = { sentText.append($0) }

        let rule = WatchdogRule(
            name: "Only Read",
            trigger: .permissionPrompt,
            toolPattern: "Read",
            response: .approve
        )
        engine.config = WatchdogConfig(name: "test", rules: [rule])
        engine.isActive = true

        // Should match
        let a1 = engine.evaluate(events: [.permissionPrompt(tool: "Read", fullLine: "")])
        #expect(a1.count == 1)

        // Should not match
        let a2 = engine.evaluate(events: [.permissionPrompt(tool: "Write", fullLine: "")])
        #expect(a2.isEmpty)
    }

    @Test @MainActor func toolPatternCaseInsensitive() {
        let engine = WatchdogEngine()
        engine.sendToTerminal = { _ in }

        let rule = WatchdogRule(
            name: "bash",
            trigger: .permissionPrompt,
            toolPattern: "bash",
            response: .deny
        )
        engine.config = WatchdogConfig(name: "test", rules: [rule])
        engine.isActive = true

        let actions = engine.evaluate(events: [
            .permissionPrompt(tool: "Bash(git status)", fullLine: "")
        ])
        #expect(actions.count == 1)
    }

    // MARK: - Error and Question Triggers

    @Test @MainActor func errorTrigger() {
        let engine = WatchdogEngine()
        engine.sendToTerminal = { _ in }

        let rule = WatchdogRule(name: "Notify on error", trigger: .error, response: .notify)
        engine.config = WatchdogConfig(name: "test", rules: [rule])
        engine.isActive = true

        let actions = engine.evaluate(events: [.error(message: "Error: something broke")])
        #expect(actions.count == 1)
        #expect(actions[0].response == .notify)
    }

    @Test @MainActor func questionTrigger() {
        let engine = WatchdogEngine()
        var sentText: [String] = []
        engine.sendToTerminal = { sentText.append($0) }

        let rule = WatchdogRule(name: "Auto-yes questions", trigger: .question, response: .approve)
        engine.config = WatchdogConfig(name: "test", rules: [rule])
        engine.isActive = true

        let actions = engine.evaluate(events: [
            .question(text: "Would you like me to continue?")
        ])
        #expect(actions.count == 1)
        #expect(sentText == ["y\n"])
    }

    // MARK: - Multiple Events

    @Test @MainActor func multipleEventsProcessed() {
        let engine = WatchdogEngine()
        engine.sendToTerminal = { _ in }
        engine.config = .autoApproveAll
        engine.isActive = true

        let actions = engine.evaluate(events: [
            .permissionPrompt(tool: "Read", fullLine: ""),
            .permissionPrompt(tool: "Write", fullLine: ""),
            .permissionPrompt(tool: "Edit", fullLine: ""),
        ])
        #expect(actions.count == 3)
        #expect(engine.totalResponses == 3)
    }

    // MARK: - Tracking

    @Test @MainActor func tracksLastMatchedRule() {
        let engine = WatchdogEngine()
        engine.sendToTerminal = { _ in }
        engine.config = .autoApproveAll
        engine.isActive = true

        _ = engine.evaluate(events: [.permissionPrompt(tool: "Read", fullLine: "")])
        #expect(engine.lastMatchedRule == "Approve everything")
    }

    @Test @MainActor func tracksTotalResponses() {
        let engine = WatchdogEngine()
        engine.sendToTerminal = { _ in }
        engine.config = .autoApproveAll
        engine.isActive = true

        _ = engine.evaluate(events: [.permissionPrompt(tool: "Read", fullLine: "")])
        _ = engine.evaluate(events: [.permissionPrompt(tool: "Write", fullLine: "")])
        #expect(engine.totalResponses == 2)
    }
}
