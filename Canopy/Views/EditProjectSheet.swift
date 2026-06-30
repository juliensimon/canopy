import SwiftUI

/// Sheet for editing an existing project's configuration.
struct EditProjectSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    let project: Project
    private let globalSettings: CanopySettings

    @State private var projectName: String
    @State private var filesToCopy: String
    @State private var symlinkPaths: String
    @State private var setupCommands: String
    @State private var overrideClaude: Bool
    @State private var autoStartClaude: Bool
    @State private var claudeFlags: String
    @State private var sandboxBackend: SandboxBackend
    @State private var sbxFlags: String
    @State private var containerImage: String
    @State private var containerFlags: String
    @State private var sandboxStatus: SandboxChecker.Status?
    @State private var checkingSandbox = false
    @State private var selectedColorIndex: Int

    init(project: Project, settings: CanopySettings) {
        self.project = project
        self.globalSettings = settings
        self._projectName = State(initialValue: project.name)
        self._filesToCopy = State(initialValue: project.filesToCopy.joined(separator: ", "))
        self._symlinkPaths = State(initialValue: project.symlinkPaths.joined(separator: ", "))
        self._setupCommands = State(initialValue: project.setupCommands.joined(separator: ", "))
        self._overrideClaude = State(initialValue:
            project.autoStartClaude != nil || project.claudeFlags != nil
            || project.sandboxBackend != nil || project.sbxFlags != nil
            || project.containerImage != nil || project.containerFlags != nil)
        // Seed from effective values so enabling the override changes
        // nothing until the user actually changes a field.
        let seeds = ClaudeOverrideDefaults(project: project, settings: settings)
        self._autoStartClaude = State(initialValue: seeds.autoStartClaude)
        self._claudeFlags = State(initialValue: seeds.claudeFlags)
        self._sandboxBackend = State(initialValue: seeds.sandboxBackend)
        self._sbxFlags = State(initialValue: seeds.sbxFlags)
        self._containerImage = State(initialValue: project.containerImage ?? "")
        self._containerFlags = State(initialValue: project.containerFlags ?? "")
        self._selectedColorIndex = State(initialValue: project.colorIndex ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit Project")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Repository Path")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(project.repositoryPath)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Project Name")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        TextField("my-project", text: $projectName)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Project color
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Project Color")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        HStack(spacing: 8) {
                            ForEach(0..<ProjectColor.allColors.count, id: \.self) { index in
                                Circle()
                                    .fill(ProjectColor.allColors[index])
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: selectedColorIndex == index ? 2 : 0)
                                            .padding(selectedColorIndex == index ? -2 : 0)
                                    )
                                    .onTapGesture { selectedColorIndex = index }
                            }
                        }
                    }

                    Divider()

                    Text("Worktree Configuration")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Files to copy")
                            .font(.subheadline)
                        TextField(".env, .env.local", text: $filesToCopy)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Directories to symlink")
                            .font(.subheadline)
                        TextField("node_modules, .venv", text: $symlinkPaths)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Setup commands")
                            .font(.subheadline)
                        TextField("npm install", text: $setupCommands)
                            .textFieldStyle(.roundedBorder)
                    }

                    Divider()

                    Text("Claude Code")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    Toggle("Override global Claude settings", isOn: $overrideClaude)
                        .font(.subheadline)

                    if overrideClaude {
                        Toggle("Auto-start Claude Code", isOn: $autoStartClaude)
                            .font(.subheadline)
                            .padding(.leading, 16)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("CLI flags")
                                .font(.subheadline)
                            TextField("e.g. --model sonnet", text: $claudeFlags)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }
                        .padding(.leading, 16)

                        Picker("Sandbox", selection: Binding(
                            get: { sandboxBackend },
                            set: { newValue in
                                if newValue == .off {
                                    sandboxBackend = .off
                                    sandboxStatus = nil
                                } else {
                                    checkingSandbox = true
                                    Task.detached(priority: .utility) {
                                        let status = await SandboxChecker.check(backend: newValue)
                                        await MainActor.run {
                                            sandboxStatus = status
                                            sandboxBackend = status == .available ? newValue : .off
                                            checkingSandbox = false
                                        }
                                    }
                                }
                            }
                        )) {
                            Text("Off").tag(SandboxBackend.off)
                            Text("Docker Sandbox (sbx)").tag(SandboxBackend.dockerSbx)
                            Text("Apple container").tag(SandboxBackend.appleContainer)
                        }
                            .font(.subheadline)
                            .padding(.leading, 16)
                            .disabled(checkingSandbox)

                        if let status = sandboxStatus, status != .available {
                            Text(SandboxBackendUI.warning(for: status))
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.leading, 16)
                        }

                        if sandboxBackend == .dockerSbx {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Sandbox flags")
                                    .font(.subheadline)
                                TextField("e.g. --memory 8g", text: $sbxFlags)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                            }
                            .padding(.leading, 16)
                        }

                        if sandboxBackend == .appleContainer {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Container image")
                                    .font(.subheadline)
                                TextField("blank = use global (\(globalSettings.containerImage))", text: $containerImage)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                                Text("Container flags")
                                    .font(.subheadline)
                                TextField(containerFlagsPlaceholder, text: $containerFlags)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                                Text("Leave blank to inherit the global values.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.leading, 16)
                        }
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
                    .disabled(projectName.isEmpty || checkingSandbox)
            }
        }
        .padding(20)
        .frame(width: 480)
        .frame(minHeight: 380, idealHeight: 520)
    }

    private func save() {
        var updated = project
        updated.name = projectName
        updated.filesToCopy = parseCSV(filesToCopy)
        updated.symlinkPaths = parseCSV(symlinkPaths)
        updated.setupCommands = parseCSV(setupCommands)
        updated.autoStartClaude = overrideClaude ? autoStartClaude : nil
        updated.claudeFlags = overrideClaude ? claudeFlags : nil
        updated.sandboxBackend = overrideClaude ? sandboxBackend : nil
        updated.sbxFlags = overrideClaude ? sbxFlags : nil
        // Blank image/flags mean "inherit global", so store nil rather than
        // letting an empty string override a configured global value.
        updated.containerImage = overrideClaude ? nilIfBlank(containerImage) : nil
        updated.containerFlags = overrideClaude ? nilIfBlank(containerFlags) : nil
        updated.colorIndex = selectedColorIndex
        appState.updateProject(updated)
        dismiss()
    }

    private func parseCSV(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func nilIfBlank(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var containerFlagsPlaceholder: String {
        let global = globalSettings.containerFlags.trimmingCharacters(in: .whitespaces)
        return global.isEmpty ? "blank = use global flags" : "blank = use global (\(global))"
    }
}

/// Shared user-facing strings for sandbox backend validation.
enum SandboxBackendUI {
    static func warning(for status: SandboxChecker.Status) -> String {
        switch status {
        case .missingDocker:
            return "Docker not found. Install Docker Desktop from docker.com."
        case .missingSbx:
            return "sbx not found. Install with: brew install docker/tap/sbx"
        case .missingContainer:
            return "container not found. Requires macOS 26+ on Apple silicon -- install with: brew install container"
        case .containerSystemStopped:
            return "container runtime is not running. Start it with: container system start"
        case .missingKernel:
            return "container runtime has no Linux kernel installed. Run: container system kernel set --recommended"
        case .available:
            return ""
        }
    }

    /// The command to send to a session's terminal at launch, given the sandbox
    /// preflight result. When the backend is ready, run Claude as built;
    /// otherwise echo the actionable warning instead of firing the command and
    /// letting the runtime print a cryptic error (e.g. an XPC connection error
    /// when the container daemon is stopped).
    static func launchCommand(for status: SandboxChecker.Status, command: String) -> String {
        guard status != .available else { return command }
        return "echo " + SandboxBackend.shellSingleQuoted("⚠️  Canopy: " + warning(for: status))
    }
}
