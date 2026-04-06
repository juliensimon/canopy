import SwiftUI

/// Sheet for creating a new worktree-backed session.
/// The user picks a project, names a branch, and chooses a base branch.
/// Canopy then creates the worktree, copies configs, and opens a session.
struct WorktreeSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    /// If set, the project picker is hidden and this project is used.
    let preselectedProjectId: UUID?

    @State private var selectedProjectId: UUID?
    @State private var branchName = ""
    @State private var baseBranch = ""
    @State private var branches: [BranchInfo] = []
    @State private var errorMessage: String?
    @State private var isCreating = false

    private let git = GitService()

    init(preselectedProjectId: UUID? = nil) {
        self.preselectedProjectId = preselectedProjectId
    }

    var selectedProject: Project? {
        appState.projects.first { $0.id == selectedProjectId }
    }

    private var isProjectLocked: Bool { preselectedProjectId != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Worktree Session")
                .font(.title2)
                .fontWeight(.bold)

            if appState.projects.isEmpty {
                noProjectsView
            } else {
                formView
            }
        }
        .padding(20)
        .frame(width: 450, height: 380)
        .onAppear {
            if let preId = preselectedProjectId {
                selectedProjectId = preId
                loadBranches()
            }
        }
    }

    private var noProjectsView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No projects configured")
                .font(.headline)
            Text("Add a project first to create worktree sessions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
    }

    private var formView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Project picker (hidden when preselected)
            if !isProjectLocked {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Picker("", selection: $selectedProjectId) {
                        Text("Select a project...").tag(nil as UUID?)
                        ForEach(appState.projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: selectedProjectId) { _, _ in
                        loadBranches()
                    }
                }
            } else if let project = selectedProject {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.orange)
                    Text(project.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }

            // Base branch
            VStack(alignment: .leading, spacing: 4) {
                Text("Base Branch")
                    .font(.subheadline)
                    .fontWeight(.medium)
                if branches.isEmpty {
                    TextField("main", text: $baseBranch)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("", selection: $baseBranch) {
                        ForEach(branches) { branch in
                            Text(branch.name).tag(branch.name)
                        }
                    }
                    .labelsHidden()
                }
            }

            // New branch name
            VStack(alignment: .leading, spacing: 4) {
                Text("New Branch Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField("feat/my-feature", text: $branchName)
                    .textFieldStyle(.roundedBorder)
            }

            // Config summary
            if let project = selectedProject {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Will be set up with:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !project.filesToCopy.isEmpty {
                        Label("Copy: \(project.filesToCopy.joined(separator: ", "))", systemImage: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if !project.symlinkPaths.isEmpty {
                        Label("Symlink: \(project.symlinkPaths.joined(separator: ", "))", systemImage: "link")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if !project.setupCommands.isEmpty {
                        Label("Run: \(project.setupCommands.joined(separator: ", "))", systemImage: "terminal")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            // Progress or actions
            if isCreating {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(appState.worktreeSetupStatus ?? "Setting up...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isCreating)
                Spacer()
                Button("Create Session") { createWorktree() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedProject == nil || branchName.isEmpty || baseBranch.isEmpty || isCreating)
            }
        }
    }

    private func loadBranches() {
        guard let project = selectedProject else {
            branches = []
            return
        }
        Task {
            do {
                let result = try await git.listBranches(repoPath: project.repositoryPath)
                await MainActor.run {
                    branches = result
                    // Default to current branch or "main"
                    baseBranch = result.first(where: { $0.isCurrent })?.name
                        ?? result.first(where: { $0.name == "main" })?.name
                        ?? result.first?.name
                        ?? "main"
                }
            } catch {
                await MainActor.run { branches = [] }
            }
        }
    }

    private func createWorktree() {
        guard let project = selectedProject else { return }

        isCreating = true
        errorMessage = nil

        Task {
            do {
                try await appState.createWorktreeSession(
                    project: project,
                    branchName: branchName,
                    baseBranch: baseBranch
                )
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
