import SwiftUI

/// Settings sheet for configuring Tempo behavior.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var autoStartClaude: Bool
    @State private var claudeFlags: String
    @State private var confirmBeforeClosing: Bool
    @State private var idePath: String

    init(settings: TempoSettings) {
        self._autoStartClaude = State(initialValue: settings.autoStartClaude)
        self._claudeFlags = State(initialValue: settings.claudeFlags)
        self._confirmBeforeClosing = State(initialValue: settings.confirmBeforeClosing)
        self._idePath = State(initialValue: settings.idePath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Claude Code section
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Auto-start Claude Code in new sessions", isOn: $autoStartClaude)

                            if autoStartClaude {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Default CLI flags")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    TextField("e.g. --model sonnet --verbose", text: $claudeFlags)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12, design: .monospaced))
                                    Text("These flags are appended to the `claude` command. Per-project overrides take precedence.")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }

                                HStack(spacing: 4) {
                                    Text("Command:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(previewCommand)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.primary)
                                }
                                .padding(.top, 4)
                            }
                        }
                        .padding(4)
                    } label: {
                        Label("Claude Code", systemImage: "terminal")
                    }

                    // Sessions section
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Confirm before closing a session", isOn: $confirmBeforeClosing)
                            Text("When enabled, closing a running session will ask for confirmation.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(4)
                    } label: {
                        Label("Sessions", systemImage: "rectangle.stack")
                    }

                    // IDE section
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("/Applications/Cursor.app", text: $idePath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                                Button("Browse...") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = true
                                    panel.canChooseDirectories = false
                                    panel.allowedContentTypes = [.application]
                                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                                    if panel.runModal() == .OK, let url = panel.url {
                                        idePath = url.path
                                    }
                                }
                            }
                            Text("Used for \"Open in IDE\" in session context menus.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(4)
                    } label: {
                        Label("IDE", systemImage: "hammer")
                    }
                }
            }

            Divider()
                .padding(.vertical, 8)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .frame(minHeight: 340, idealHeight: 400)
    }

    private var previewCommand: String {
        var cmd = "claude"
        let trimmed = claudeFlags.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            cmd += " " + trimmed
        }
        return cmd
    }

    private func save() {
        var settings = appState.settings
        settings.autoStartClaude = autoStartClaude
        settings.claudeFlags = claudeFlags
        settings.confirmBeforeClosing = confirmBeforeClosing
        settings.idePath = idePath
        settings.save()
        appState.settings = settings
        dismiss()
    }
}
