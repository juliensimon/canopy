import Foundation

/// A set of watchdog rules that can be attached to a session or project.
struct WatchdogConfig: Identifiable, Codable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var rules: [WatchdogRule]

    init(name: String, isEnabled: Bool = true, rules: [WatchdogRule] = []) {
        self.id = UUID()
        self.name = name
        self.isEnabled = isEnabled
        self.rules = rules
    }

    /// Built-in preset: auto-approve all tool use
    static var autoApproveAll: WatchdogConfig {
        WatchdogConfig(name: "Auto-approve all", rules: [
            WatchdogRule(name: "Approve everything", trigger: .permissionPrompt, toolPattern: nil, response: .approve),
        ])
    }

    /// Built-in preset: approve reads, deny shell commands
    static var safeMode: WatchdogConfig {
        WatchdogConfig(name: "Safe mode", rules: [
            WatchdogRule(name: "Approve Read", trigger: .permissionPrompt, toolPattern: "Read", response: .approve),
            WatchdogRule(name: "Approve Glob", trigger: .permissionPrompt, toolPattern: "Glob", response: .approve),
            WatchdogRule(name: "Approve Grep", trigger: .permissionPrompt, toolPattern: "Grep", response: .approve),
            WatchdogRule(name: "Approve Write", trigger: .permissionPrompt, toolPattern: "Write", response: .approve),
            WatchdogRule(name: "Approve Edit", trigger: .permissionPrompt, toolPattern: "Edit", response: .approve),
            WatchdogRule(name: "Deny Bash", trigger: .permissionPrompt, toolPattern: "Bash", response: .deny),
        ])
    }

    /// Built-in preset: approve only read operations
    static var readOnly: WatchdogConfig {
        WatchdogConfig(name: "Read-only", rules: [
            WatchdogRule(name: "Approve Read", trigger: .permissionPrompt, toolPattern: "Read", response: .approve),
            WatchdogRule(name: "Approve Glob", trigger: .permissionPrompt, toolPattern: "Glob", response: .approve),
            WatchdogRule(name: "Approve Grep", trigger: .permissionPrompt, toolPattern: "Grep", response: .approve),
        ])
    }
}

/// A single watchdog rule: when a trigger matches, execute a response.
struct WatchdogRule: Identifiable, Codable {
    let id: UUID
    var name: String

    /// What triggers this rule.
    var trigger: WatchdogTrigger

    /// Optional regex/substring to further filter the trigger.
    /// For permissionPrompt: matches against the tool name (e.g. "Read", "Bash").
    /// For question/error: matches against the full line text.
    var toolPattern: String?

    /// What to do when the rule triggers.
    var response: WatchdogResponse

    /// Max times this rule can auto-respond per session (safety limit). 0 = unlimited.
    var maxResponses: Int

    /// Whether this rule is active.
    var isEnabled: Bool

    init(
        name: String,
        trigger: WatchdogTrigger,
        toolPattern: String? = nil,
        response: WatchdogResponse,
        maxResponses: Int = 0,
        isEnabled: Bool = true
    ) {
        self.id = UUID()
        self.name = name
        self.trigger = trigger
        self.toolPattern = toolPattern
        self.response = response
        self.maxResponses = maxResponses
        self.isEnabled = isEnabled
    }
}

/// What terminal event triggers a watchdog rule.
enum WatchdogTrigger: String, Codable, CaseIterable {
    case permissionPrompt   // Claude asks to use a tool
    case question           // Claude asks a general question
    case error              // An error appears in output

    var label: String {
        switch self {
        case .permissionPrompt: return "Permission prompt"
        case .question: return "Question"
        case .error: return "Error"
        }
    }
}

/// What the watchdog does when a rule matches.
enum WatchdogResponse: String, Codable, CaseIterable {
    case approve    // Send "y\n"
    case deny       // Send "n\n"
    case notify     // macOS notification only (no terminal input)
    case custom     // Send custom text

    var label: String {
        switch self {
        case .approve: return "Approve (y)"
        case .deny: return "Deny (n)"
        case .notify: return "Notify only"
        case .custom: return "Custom text"
        }
    }
}
