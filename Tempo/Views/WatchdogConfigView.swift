import SwiftUI

/// Sheet for configuring watchdog rules on a session.
struct WatchdogConfigView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    let sessionId: UUID
    @State private var config: WatchdogConfig
    @State private var editingRule: WatchdogRule?

    init(sessionId: UUID, config: WatchdogConfig?) {
        self.sessionId = sessionId
        self._config = State(initialValue: config ?? WatchdogConfig(name: "Watchdog"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Watchdog")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Toggle("Enabled", isOn: $config.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .padding(.bottom, 12)

            // Presets
            HStack(spacing: 8) {
                Text("Presets:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Auto-approve all") { config = .autoApproveAll }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Safe mode") { config = .safeMode }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Read-only") { config = .readOnly }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.bottom, 12)

            Divider()

            // Rules list
            if config.rules.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No rules configured")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Add a rule or pick a preset above.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(config.rules) { rule in
                            ruleRow(rule)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            Divider()

            // Actions
            HStack {
                Button(action: addRule) {
                    Label("Add Rule", systemImage: "plus")
                }
                .controlSize(.small)

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 520)
        .frame(minHeight: 400, idealHeight: 500)
        .sheet(item: $editingRule) { rule in
            RuleEditorView(rule: rule) { updated in
                if let index = config.rules.firstIndex(where: { $0.id == updated.id }) {
                    config.rules[index] = updated
                }
                editingRule = nil
            }
        }
    }

    // MARK: - Rule Row

    private func ruleRow(_ rule: WatchdogRule) -> some View {
        HStack(spacing: 8) {
            // Enabled toggle
            Image(systemName: rule.isEnabled ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(rule.isEnabled ? .green : .secondary)
                .onTapGesture {
                    if let i = config.rules.firstIndex(where: { $0.id == rule.id }) {
                        config.rules[i].isEnabled.toggle()
                    }
                }

            // Rule info
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .font(.system(size: 12, weight: .medium))
                HStack(spacing: 4) {
                    Text(rule.trigger.label)
                        .font(.system(size: 10))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(3)
                    if let pattern = rule.toolPattern, !pattern.isEmpty {
                        Text(pattern)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Text("→")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(rule.response.label)
                        .font(.system(size: 10))
                        .foregroundStyle(rule.response == .approve ? .green : rule.response == .deny ? .red : .secondary)
                }
            }

            Spacer()

            // Edit
            Button(action: { editingRule = rule }) {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            // Delete
            Button(action: {
                config.rules.removeAll { $0.id == rule.id }
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red.opacity(0.7))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    private func addRule() {
        let rule = WatchdogRule(
            name: "New Rule",
            trigger: .permissionPrompt,
            response: .approve
        )
        config.rules.append(rule)
        editingRule = rule
    }

    private func save() {
        // Apply config to the terminal session
        if let ts = appState.terminalSessions[sessionId] {
            ts.setWatchdogConfig(config)
        }
        dismiss()
    }
}

// MARK: - Rule Editor

/// Sheet for editing a single watchdog rule.
struct RuleEditorView: View {
    @State private var rule: WatchdogRule
    @Environment(\.dismiss) var dismiss
    let onSave: (WatchdogRule) -> Void

    init(rule: WatchdogRule, onSave: @escaping (WatchdogRule) -> Void) {
        self._rule = State(initialValue: rule)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Rule")
                .font(.title3)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.subheadline)
                TextField("Rule name", text: $rule.name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Trigger")
                    .font(.subheadline)
                Picker("", selection: $rule.trigger) {
                    ForEach(WatchdogTrigger.allCases, id: \.self) { trigger in
                        Text(trigger.label).tag(trigger)
                    }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(rule.trigger == .permissionPrompt ? "Tool filter (optional)" : "Text filter (optional)")
                    .font(.subheadline)
                TextField(
                    rule.trigger == .permissionPrompt ? "e.g. Read, Bash, Edit" : "e.g. error pattern",
                    text: Binding(
                        get: { rule.toolPattern ?? "" },
                        set: { rule.toolPattern = $0.isEmpty ? nil : $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                Text("Leave empty to match all. Substring match, case-insensitive.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Response")
                    .font(.subheadline)
                Picker("", selection: $rule.response) {
                    ForEach(WatchdogResponse.allCases, id: \.self) { response in
                        Text(response.label).tag(response)
                    }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Max responses (0 = unlimited)")
                    .font(.subheadline)
                TextField("0", value: $rule.maxResponses, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(rule.name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400, height: 420)
    }
}
