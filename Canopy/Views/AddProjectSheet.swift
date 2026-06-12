import SwiftUI

/// Sheet for adding a new project (git repository) to Canopy.
/// The user picks a repo directory and configures which files
/// to copy and symlink when creating worktrees.
struct AddProjectSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var repoPath = ""
    @State private var projectName = ""
    @State private var filesToCopy = ".env, .env.local"
    @State private var symlinkPaths = ""
    @State private var setupCommands = ""
    @State private var overrideClaude = false
    @State private var autoStartClaude: Bool
    @State private var claudeFlags: String
    @State private var sandboxBackend: SandboxBackend
    @State private var sbxFlags: String
    @State private var containerImage = ""
    @State private var containerFlags = ""

    init(settings: CanopySettings) {
        // Seed from the global values so enabling the override changes
        // nothing until the user actually changes a field.
        let seeds = ClaudeOverrideDefaults(project: nil, settings: settings)
        self._autoStartClaude = State(initialValue: seeds.autoStartClaude)
        self._claudeFlags = State(initialValue: seeds.claudeFlags)
        self._sandboxBackend = State(initialValue: seeds.sandboxBackend)
        self._sbxFlags = State(initialValue: seeds.sbxFlags)
    }
    @State private var sandboxStatus: SandboxChecker.Status?
    @State private var checkingSandbox = false
    @State private var isValidRepo = false
    @State private var validationMessage = ""
    @State private var selectedColorIndex: Int = 0

    private let git = GitService()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Add Project")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.bottom, 12)

            // Scrollable form content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Repository path
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Repository Path")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        HStack {
                            TextField("/path/to/your/repo", text: $repoPath)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: repoPath) { _, newValue in
                                    validateRepo(newValue)
                                }
                            Button("Browse...") {
                                browseForRepo()
                            }
                        }
                        if !validationMessage.isEmpty {
                            Text(validationMessage)
                                .font(.caption)
                                .foregroundStyle(isValidRepo ? .green : .red)
                        }
                    }

                    // Project name
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

                    // Files to copy
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Files to copy into worktrees")
                            .font(.subheadline)
                        TextField(".env, .env.local, .env.development", text: $filesToCopy)
                            .textFieldStyle(.roundedBorder)
                        Text("Comma-separated. These files are gitignored but needed for dev.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    // Symlink paths
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Directories to symlink (not copy)")
                            .font(.subheadline)
                        TextField("node_modules, .venv, vendor", text: $symlinkPaths)
                            .textFieldStyle(.roundedBorder)
                        Text("Heavy directories shared across worktrees via symlinks.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    // Setup commands
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Setup commands (run after worktree creation)")
                            .font(.subheadline)
                        TextField("npm install, bundle install", text: $setupCommands)
                            .textFieldStyle(.roundedBorder)
                        Text("Comma-separated shell commands.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Divider()

                    // Claude Code overrides
                    Text("Claude Code")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    Toggle("Override global Claude settings for this project", isOn: $overrideClaude)
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
                                TextField("blank = use global image", text: $containerImage)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                                Text("Container flags")
                                    .font(.subheadline)
                                TextField("blank = use global flags", text: $containerFlags)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                            }
                            .padding(.leading, 16)
                        }
                    }
                }
            }

            Divider()
                .padding(.vertical, 8)

            // Pinned action buttons
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Project") { addProject() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValidRepo || projectName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 500)
        .frame(minHeight: 400, idealHeight: 520)
    }

    private func browseForRepo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a git repository"

        if panel.runModal() == .OK, let url = panel.url {
            repoPath = url.path
        }
    }

    private func validateRepo(_ path: String) {
        guard !path.isEmpty else {
            isValidRepo = false
            validationMessage = ""
            return
        }

        Task {
            let valid = await git.isGitRepo(path: path)
            await MainActor.run {
                isValidRepo = valid
                if valid {
                    validationMessage = "Valid git repository"
                    if projectName.isEmpty {
                        projectName = (path as NSString).lastPathComponent
                    }
                    selectedColorIndex = ProjectColor.nextIndex(
                        existingIndices: appState.projects.compactMap(\.colorIndex)
                    )
                } else {
                    validationMessage = "Not a git repository"
                }
            }
        }
    }

    private func addProject() {
        var project = Project(
            name: projectName,
            repositoryPath: repoPath,
            filesToCopy: parseCommaSeparated(filesToCopy),
            symlinkPaths: parseCommaSeparated(symlinkPaths),
            setupCommands: parseCommaSeparated(setupCommands),
            autoStartClaude: overrideClaude ? autoStartClaude : nil,
            claudeFlags: overrideClaude ? claudeFlags : nil,
            sandboxBackend: overrideClaude ? sandboxBackend : nil,
            sbxFlags: overrideClaude ? sbxFlags : nil,
            // Blank image/flags mean "inherit global", so store nil rather than
            // letting an empty string override a configured global value.
            containerImage: overrideClaude ? nilIfBlank(containerImage) : nil,
            containerFlags: overrideClaude ? nilIfBlank(containerFlags) : nil
        )
        project.colorIndex = selectedColorIndex
        appState.addProject(project)
        dismiss()
    }

    private func parseCommaSeparated(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func nilIfBlank(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
