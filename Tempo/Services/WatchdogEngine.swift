import Foundation
import UserNotifications

/// Evaluates watchdog rules against terminal events and executes responses.
///
/// The engine sits between the TerminalOutputParser (which detects events)
/// and the TerminalSession (which can send keystrokes). When a rule matches,
/// the engine either sends a response to the terminal, shows a notification,
/// or both.
///
/// Safety: each rule tracks how many times it has responded in this session.
/// If maxResponses > 0 and the count exceeds it, the rule stops firing.
@MainActor
final class WatchdogEngine: ObservableObject {
    @Published var config: WatchdogConfig?
    @Published var isActive: Bool = false
    @Published var lastMatchedRule: String?
    @Published var totalResponses: Int = 0

    /// Tracks response counts per rule ID for safety limits.
    private var responseCounts: [UUID: Int] = [:]

    /// Callback to send text to the terminal.
    var sendToTerminal: ((String) -> Void)?

    /// Evaluates a list of terminal events against the current config.
    /// Returns the actions taken (for logging/display).
    func evaluate(events: [TerminalEvent]) -> [WatchdogAction] {
        guard let config = config, config.isEnabled, isActive else { return [] }

        var actions: [WatchdogAction] = []

        for event in events {
            for rule in config.rules where rule.isEnabled {
                if let action = matchRule(rule, against: event) {
                    actions.append(action)
                }
            }
        }

        return actions
    }

    /// Resets response counts (e.g., when starting a new session).
    func resetCounts() {
        responseCounts.removeAll()
        totalResponses = 0
        lastMatchedRule = nil
    }

    // MARK: - Private

    private func matchRule(_ rule: WatchdogRule, against event: TerminalEvent) -> WatchdogAction? {
        switch (rule.trigger, event) {
        case (.permissionPrompt, .permissionPrompt(let tool, _)):
            if let pattern = rule.toolPattern, !pattern.isEmpty {
                // Check if the tool name matches the pattern (case-insensitive substring)
                guard tool.localizedCaseInsensitiveContains(pattern) else { return nil }
            }
            return executeRule(rule, context: "Permission: \(tool)")

        case (.question, .question(let text)):
            if let pattern = rule.toolPattern, !pattern.isEmpty {
                guard text.localizedCaseInsensitiveContains(pattern) else { return nil }
            }
            return executeRule(rule, context: "Question")

        case (.error, .error(let message)):
            if let pattern = rule.toolPattern, !pattern.isEmpty {
                guard message.localizedCaseInsensitiveContains(pattern) else { return nil }
            }
            return executeRule(rule, context: "Error: \(message.prefix(50))")

        default:
            return nil
        }
    }

    private func executeRule(_ rule: WatchdogRule, context: String) -> WatchdogAction? {
        // Check safety limit
        let count = responseCounts[rule.id, default: 0]
        if rule.maxResponses > 0 && count >= rule.maxResponses {
            return nil
        }

        // Record the response
        responseCounts[rule.id, default: 0] += 1
        totalResponses += 1
        lastMatchedRule = rule.name

        switch rule.response {
        case .approve:
            sendToTerminal?("y\n")
            return WatchdogAction(ruleName: rule.name, response: .approve, context: context)

        case .deny:
            sendToTerminal?("n\n")
            return WatchdogAction(ruleName: rule.name, response: .deny, context: context)

        case .notify:
            sendNotification(title: "Watchdog: \(rule.name)", body: context)
            return WatchdogAction(ruleName: rule.name, response: .notify, context: context)

        case .custom:
            // Custom text is stored in toolPattern field (reused for simplicity)
            // In a future version this would be a separate field
            if let text = rule.toolPattern, !text.isEmpty {
                sendToTerminal?(text + "\n")
            }
            return WatchdogAction(ruleName: rule.name, response: .custom, context: context)
        }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

/// Record of a watchdog action taken.
struct WatchdogAction: Identifiable {
    let id = UUID()
    let ruleName: String
    let response: WatchdogResponse
    let context: String
    let timestamp = Date()
}
