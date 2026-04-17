import SwiftUI

/// Settings sheet for configuring Canopy behavior.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var autoStartClaude: Bool
    @State private var claudeFlags: String
    @State private var confirmBeforeClosing: Bool
    @State private var idePath: String
    @State private var terminalPath: String
    @State private var notifyOnFinish: Bool
    @State private var checkForUpdatesOnLaunch: Bool
    @State private var useSandbox: Bool
    @State private var sbxFlags: String
    @State private var sandboxStatus: SandboxChecker.Status?
    @State private var checkingSandbox = false
    @State private var ghPath: String
    @State private var sbxPath: String

    init(settings: CanopySettings) {
        self._autoStartClaude = State(initialValue: settings.autoStartClaude)
        self._claudeFlags = State(initialValue: settings.claudeFlags)
        self._confirmBeforeClosing = State(initialValue: settings.confirmBeforeClosing)
        self._idePath = State(initialValue: settings.idePath)
        self._terminalPath = State(initialValue: settings.terminalPath)
        self._notifyOnFinish = State(initialValue: settings.notifyOnFinish)
        self._checkForUpdatesOnLaunch = State(initialValue: settings.checkForUpdatesOnLaunch)
        self._useSandbox = State(initialValue: settings.useSandbox)
        self._sbxFlags = State(initialValue: settings.sbxFlags)
        self._ghPath = State(initialValue: settings.ghPath)
        self._sbxPath = State(initialValue: settings.sbxPath)
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

                                Divider()

                                Toggle("Run in Docker Sandbox (sbx)", isOn: Binding(
                                    get: { useSandbox },
                                    set: { newValue in
                                        if newValue {
                                            verifySandbox()
                                        } else {
                                            useSandbox = false
                                            sandboxStatus = nil
                                        }
                                    }
                                ))
                                .disabled(checkingSandbox)

                                if let status = sandboxStatus, status != .available {
                                    Text(sandboxWarning(for: status))
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }

                                if useSandbox {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Sandbox flags")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        TextField("e.g. --memory 8g", text: $sbxFlags)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 12, design: .monospaced))
                                        Text("Additional flags passed to `sbx run`.")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
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

                    // Notifications section
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Notify when sessions finish", isOn: $notifyOnFinish)
                            Text("Show a macOS notification when a session transitions from working to idle while Canopy is in the background.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(4)
                    } label: {
                        Label("Notifications", systemImage: "bell")
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

                    // Terminal section
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("/System/Applications/Utilities/Terminal.app", text: $terminalPath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                                Button("Browse...") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = true
                                    panel.canChooseDirectories = false
                                    panel.allowedContentTypes = [.application]
                                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                                    if panel.runModal() == .OK, let url = panel.url {
                                        terminalPath = url.path
                                    }
                                }
                            }
                            Text("Used for \"Open in Terminal\" in context menus.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(4)
                    } label: {
                        Label("Terminal", systemImage: "terminal")
                    }

                    // CLI Tools section
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("GitHub CLI (gh)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                HStack {
                                    TextField("/opt/homebrew/bin/gh", text: $ghPath)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12, design: .monospaced))
                                    cliStatusDot(ghPath)
                                }
                                Text("Used for PR status indicators. Auto-detected from Homebrew.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Sandbox CLI (sbx)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                HStack {
                                    TextField("/opt/homebrew/bin/sbx", text: $sbxPath)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12, design: .monospaced))
                                    cliStatusDot(sbxPath)
                                }
                                Text("Used for sandboxed sessions.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(4)
                    } label: {
                        Label("CLI Tools", systemImage: "wrench")
                    }

                    // Updates section
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Check for updates on launch", isOn: $checkForUpdatesOnLaunch)
                            Text("Canopy will check GitHub once per day for a newer release.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Button("Check for Updates Now") {
                                Task { await appState.checkForUpdatesNow() }
                            }
                            .disabled(appState.updateStatus == .checking)
                        }
                        .padding(4)
                    } label: {
                        Label("Updates", systemImage: "arrow.down.circle")
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
        var parts: [String] = []
        if useSandbox {
            parts.append("sbx run")
            let trimmedSbx = sbxFlags.trimmingCharacters(in: .whitespaces)
            if !trimmedSbx.isEmpty {
                parts.append(trimmedSbx)
            }
            parts.append("claude --")
            let trimmed = claudeFlags.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                parts.append(trimmed)
            }
        } else {
            parts.append("claude")
            let trimmed = claudeFlags.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                parts.append(trimmed)
            }
        }
        return parts.joined(separator: " ")
    }

    private func verifySandbox() {
        checkingSandbox = true
        sandboxStatus = nil
        Task.detached(priority: .utility) {
            let status = await SandboxChecker.check()
            await MainActor.run {
                sandboxStatus = status
                useSandbox = status == .available
                checkingSandbox = false
            }
        }
    }

    private func sandboxWarning(for status: SandboxChecker.Status) -> String {
        switch status {
        case .missingDocker:
            return "Docker not found. Install Docker Desktop from docker.com."
        case .missingSbx:
            return "sbx not found. Install with: brew install docker/tap/sbx"
        case .available:
            return ""
        }
    }

    private func cliStatusDot(_ path: String) -> some View {
        Circle()
            .fill(FileManager.default.isExecutableFile(atPath: path) ? Color.green : Color.red)
            .frame(width: 8, height: 8)
            .help(FileManager.default.isExecutableFile(atPath: path) ? "Found" : "Not found at this path")
    }

    private func save() {
        var settings = appState.settings
        settings.autoStartClaude = autoStartClaude
        settings.claudeFlags = claudeFlags
        settings.confirmBeforeClosing = confirmBeforeClosing
        settings.idePath = idePath
        settings.terminalPath = terminalPath
        settings.notifyOnFinish = notifyOnFinish
        settings.checkForUpdatesOnLaunch = checkForUpdatesOnLaunch
        settings.useSandbox = useSandbox
        settings.sbxFlags = sbxFlags
        settings.ghPath = ghPath
        settings.sbxPath = sbxPath
        settings.save()
        appState.settings = settings
        dismiss()
    }
}
