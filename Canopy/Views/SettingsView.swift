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
    @State private var sandboxBackend: SandboxBackend
    @State private var sbxFlags: String
    @State private var containerImage: String
    @State private var containerFlags: String
    @State private var sandboxStatus: SandboxChecker.Status?
    @State private var checkingSandbox = false
    @State private var imageExists: Bool?
    @State private var buildingImage = false
    @State private var buildError: String?
    @State private var saveError: String?
    @State private var ghPath: String
    @State private var sbxPath: String
    @State private var containerPath: String
    @State private var claudeVersion: String?
    @State private var versionChecked = false

    init(settings: CanopySettings) {
        self._autoStartClaude = State(initialValue: settings.autoStartClaude)
        self._claudeFlags = State(initialValue: settings.claudeFlags)
        self._confirmBeforeClosing = State(initialValue: settings.confirmBeforeClosing)
        self._idePath = State(initialValue: settings.idePath)
        self._terminalPath = State(initialValue: settings.terminalPath)
        self._notifyOnFinish = State(initialValue: settings.notifyOnFinish)
        self._checkForUpdatesOnLaunch = State(initialValue: settings.checkForUpdatesOnLaunch)
        self._sandboxBackend = State(initialValue: settings.sandboxBackend)
        self._sbxFlags = State(initialValue: settings.sbxFlags)
        self._containerImage = State(initialValue: settings.containerImage)
        self._containerFlags = State(initialValue: settings.containerFlags)
        self._ghPath = State(initialValue: settings.ghPath)
        self._sbxPath = State(initialValue: settings.sbxPath)
        self._containerPath = State(initialValue: settings.containerPath)
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            PromptLibrarySettingsView()
                .tabItem { Label("Prompt Library", systemImage: "text.book.closed") }
        }
        .padding(20)
        .frame(width: 500)
        .frame(minHeight: 480, idealHeight: 540)
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Claude Code section
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Auto-start Claude Code in new sessions", isOn: $autoStartClaude)

                            HStack(spacing: 4) {
                                Text("Host CLI version:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(claudeVersion ?? (versionChecked ? "not found" : "checking…"))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(claudeVersion == nil ? .tertiary : .primary)
                            }
                            // One element: a label on the value Text alone
                            // would replace the version for VoiceOver.
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Claude Code CLI version")
                            .accessibilityValue(claudeVersion ?? (versionChecked ? "not found" : "checking"))

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

                                Picker("Sandbox", selection: Binding(
                                    get: { sandboxBackend },
                                    set: { newValue in
                                        if newValue == .off {
                                            sandboxBackend = .off
                                            sandboxStatus = nil
                                        } else {
                                            verifySandbox(newValue)
                                        }
                                    }
                                )) {
                                    Text("Off").tag(SandboxBackend.off)
                                    Text("Docker Sandbox (sbx)").tag(SandboxBackend.dockerSbx)
                                    Text("Apple container").tag(SandboxBackend.appleContainer)
                                }
                                .disabled(checkingSandbox)

                                if let status = sandboxStatus, status != .available {
                                    Text(sandboxWarning(for: status))
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }

                                if sandboxBackend == .dockerSbx {
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

                                if sandboxBackend == .appleContainer {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Container image")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        HStack {
                                            TextField("canopy-claude", text: $containerImage)
                                                .textFieldStyle(.roundedBorder)
                                                .font(.system(size: 12, design: .monospaced))
                                                .onChange(of: containerImage) { _, _ in
                                                    imageExists = nil
                                                    buildError = nil
                                                }
                                            Button(buildingImage ? "Building…" : "Build Image") {
                                                buildImage()
                                            }
                                            .disabled(buildingImage || containerImage.trimmingCharacters(in: .whitespaces).isEmpty)
                                            Button("Update") {
                                                buildImage(noCache: true)
                                            }
                                            .disabled(buildingImage || imageExists != true || containerImage.trimmingCharacters(in: .whitespaces).isEmpty)
                                            .help("Rebuild from scratch to pull the latest Claude Code")
                                        }
                                        Text("OCI image with claude, node, and git installed. Build Image creates it from Canopy's built-in recipe (a few minutes on first build). Update rebuilds it from scratch to pull the latest Claude Code.")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                        if containerImage.trimmingCharacters(in: .whitespaces).isEmpty {
                                            Text("An image is required to start sandboxed sessions.")
                                                .font(.caption)
                                                .foregroundStyle(.red)
                                        } else if buildingImage {
                                            Text("Building image -- this can take a few minutes…")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else if let error = buildError {
                                            Text("Build failed: \(error)")
                                                .font(.caption)
                                                .foregroundStyle(.red)
                                                .lineLimit(6)
                                        } else if imageExists == false {
                                            Text("Image not found locally. Click Build Image to create it.")
                                                .font(.caption)
                                                .foregroundStyle(.orange)
                                        } else if imageExists == true {
                                            Text("Image found locally.")
                                                .font(.caption)
                                                .foregroundStyle(.green)
                                        }
                                    }
                                    // Re-check when the image NAME changes too,
                                    // not just the backend -- otherwise the
                                    // found/not-found status goes blank after
                                    // editing the field.
                                    .task(id: "\(sandboxBackend.rawValue)|\(containerImage)") { await refreshImageStatus() }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Container flags")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        TextField("e.g. --memory 8g --cpus 8", text: $containerFlags)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 12, design: .monospaced))
                                        Text("Additional flags passed to `container run`.")
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
                                Text("Used for PR status indicators. Auto-detected from common install locations.")
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

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Apple container CLI")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                HStack {
                                    TextField("/usr/local/bin/container", text: $containerPath)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12, design: .monospaced))
                                    cliStatusDot(containerPath)
                                }
                                Text("Used by the Apple container sandbox backend.")
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
            .task {
                claudeVersion = await ClaudeVersionChecker.hostVersion()
                versionChecked = true
            }

            Divider()
                .padding(.vertical, 8)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if let saveError {
                    Text(saveError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    // While a backend check is in flight the picker state is
                    // stale; saving then would persist the old backend. An
                    // empty image would generate a baffling `container run`
                    // failure ("failed to pull image sh").
                    .disabled(checkingSandbox
                        || (sandboxBackend == .appleContainer
                            && containerImage.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
    }

    private var previewCommand: String {
        sandboxBackend.claudeCommand(
            claudeFlags: claudeFlags,
            sbxFlags: sbxFlags,
            containerImage: containerImage,
            containerFlags: containerFlags
        )
    }

    private func refreshImageStatus() async {
        // Debounce keystrokes; .task(id:) cancels the previous check.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let image = containerImage
        let exists = await ContainerImageBuilder.imageExists(image)
        if containerImage == image {
            imageExists = exists
        }
    }

    private func buildImage(noCache: Bool = false) {
        buildingImage = true
        buildError = nil
        let tag = containerImage.trimmingCharacters(in: .whitespaces)
        Task.detached(priority: .utility) {
            let result = await ContainerImageBuilder.build(tag: tag, noCache: noCache)
            await MainActor.run {
                buildingImage = false
                switch result {
                case .success:
                    imageExists = true
                case .failure(let output):
                    buildError = output
                    imageExists = false
                }
            }
        }
    }

    private func verifySandbox(_ backend: SandboxBackend) {
        checkingSandbox = true
        sandboxStatus = nil
        Task.detached(priority: .utility) {
            let status = await SandboxChecker.check(backend: backend)
            await MainActor.run {
                sandboxStatus = status
                sandboxBackend = status == .available ? backend : .off
                checkingSandbox = false
            }
        }
    }

    private func sandboxWarning(for status: SandboxChecker.Status) -> String {
        SandboxBackendUI.warning(for: status)
    }

    private func cliStatusDot(_ path: String) -> some View {
        let isFound = !path.isEmpty && FileManager.default.isExecutableFile(atPath: path)
        return Image(systemName: isFound ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(isFound ? Color.green : Color.red)
            .font(.system(size: 10))
            .help(isFound ? "Found" : "Not found at this path")
            .accessibilityLabel("CLI status")
            .accessibilityValue(isFound ? "Found" : "Not found")
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
        settings.sandboxBackend = sandboxBackend
        settings.sbxFlags = sbxFlags
        settings.containerImage = containerImage
        settings.containerFlags = containerFlags
        settings.ghPath = ghPath
        settings.sbxPath = sbxPath
        settings.containerPath = containerPath
        // A failed write must keep the sheet open: dismissing would let the
        // user believe their (possibly security-relevant) choice persisted.
        guard settings.save() else {
            saveError = "Could not write ~/.config/canopy/settings.json"
            return
        }
        appState.settings = settings
        dismiss()
    }
}
