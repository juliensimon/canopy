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
    @State private var autoStartClaude = false
    @State private var claudeFlags = ""
    @State private var isValidRepo = false
    @State private var validationMessage = ""

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
                } else {
                    validationMessage = "Not a git repository"
                }
            }
        }
    }

    private func addProject() {
        let project = Project(
            name: projectName,
            repositoryPath: repoPath,
            filesToCopy: parseCommaSeparated(filesToCopy),
            symlinkPaths: parseCommaSeparated(symlinkPaths),
            setupCommands: parseCommaSeparated(setupCommands),
            autoStartClaude: overrideClaude ? autoStartClaude : nil,
            claudeFlags: overrideClaude ? claudeFlags : nil
        )
        appState.addProject(project)
        dismiss()
    }

    private func parseCommaSeparated(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
