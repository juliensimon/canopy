import SwiftUI

/// Sheet for editing an existing project's configuration.
struct EditProjectSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    let project: Project

    @State private var projectName: String
    @State private var filesToCopy: String
    @State private var symlinkPaths: String
    @State private var setupCommands: String
    @State private var overrideClaude: Bool
    @State private var autoStartClaude: Bool
    @State private var claudeFlags: String
    @State private var selectedColorIndex: Int

    init(project: Project) {
        self.project = project
        self._projectName = State(initialValue: project.name)
        self._filesToCopy = State(initialValue: project.filesToCopy.joined(separator: ", "))
        self._symlinkPaths = State(initialValue: project.symlinkPaths.joined(separator: ", "))
        self._setupCommands = State(initialValue: project.setupCommands.joined(separator: ", "))
        self._overrideClaude = State(initialValue: project.autoStartClaude != nil || project.claudeFlags != nil)
        self._autoStartClaude = State(initialValue: project.autoStartClaude ?? false)
        self._claudeFlags = State(initialValue: project.claudeFlags ?? "")
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
                    .disabled(projectName.isEmpty)
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
        updated.colorIndex = selectedColorIndex
        appState.updateProject(updated)
        dismiss()
    }

    private func parseCSV(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
