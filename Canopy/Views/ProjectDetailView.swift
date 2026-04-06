import SwiftUI

/// Shown in the right panel when a project is selected but no session is active.
/// Displays project summary info and a prominent "New Worktree Session" button.
struct ProjectDetailView: View {
    let project: Project
    @EnvironmentObject var appState: AppState
    @State private var worktrees: [WorktreeInfo] = []
    @State private var branches: [BranchInfo] = []
    @State private var currentBranch: String = ""
    @State private var isLoading = true
    @State private var worktreeToDelete: WorktreeInfo?
    @State private var deleteWarning: String = ""
    @State private var deleteError: String?
    @State private var showNewWorktree = false

    private let git = GitService()

    var projectSessions: [SessionInfo] {
        appState.sessions.filter { $0.projectId == project.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(project.repositoryPath)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                // Primary action
                Button(action: { showNewWorktree = true }) {
                    Label("New Worktree Session", systemImage: "arrow.triangle.branch")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Divider()

                // Git info
                if isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading repository info...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    gitInfoSection
                }

                if let error = deleteError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                // Configuration
                configSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
        .task {
            await loadGitInfo()
        }
        .sheet(isPresented: $showNewWorktree) {
            WorktreeSheet(preselectedProjectId: project.id)
                .environmentObject(appState)
        }
        .alert("Delete Worktree?", isPresented: Binding(
            get: { worktreeToDelete != nil },
            set: { if !$0 { worktreeToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let wt = worktreeToDelete {
                    deleteWorktree(wt)
                }
            }
            Button("Cancel", role: .cancel) { worktreeToDelete = nil }
        } message: {
            Text("This will permanently remove the worktree at:\n\(worktreeToDelete?.path ?? "")\n\n\(deleteWarning)")
        }
    }

    private func prepareDelete(_ wt: WorktreeInfo) {
        Task {
            var warnings: [String] = []

            let hasChanges = await git.worktreeHasChanges(worktreePath: wt.path)
            if hasChanges {
                warnings.append("⚠️ This worktree has uncommitted changes that will be lost.")
            }

            if let branch = wt.branch {
                let unmerged = await git.branchHasUnmergedCommits(
                    repoPath: project.repositoryPath,
                    branch: branch
                )
                if unmerged {
                    warnings.append("⚠️ Branch \"\(branch)\" has commits not merged into main.")
                }
            }

            await MainActor.run {
                deleteWarning = warnings.isEmpty
                    ? "This cannot be undone."
                    : warnings.joined(separator: "\n") + "\n\nThis cannot be undone."
                worktreeToDelete = wt
            }
        }
    }

    private func deleteWorktree(_ wt: WorktreeInfo) {
        // Close any session using this worktree
        if let session = sessionForWorktree(wt) {
            appState.performCloseSession(id: session.id)
        }

        Task {
            do {
                try await git.removeWorktree(repoPath: project.repositoryPath, worktreePath: wt.path)
                // Also delete the branch
                if let branch = wt.branch {
                    try? await git.deleteBranch(repoPath: project.repositoryPath, branch: branch)
                }
                await MainActor.run {
                    worktrees.removeAll { $0.id == wt.id }
                    deleteError = nil
                }
            } catch {
                await MainActor.run {
                    deleteError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Git Info

    private var gitInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Repository", icon: "arrow.triangle.branch")

            if !currentBranch.isEmpty {
                infoRow("Current branch", currentBranch)
            }

            infoRow("Branches", "\(branches.count)")

            if !worktrees.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Worktrees")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(worktrees) { wt in
                        worktreeRow(wt)
                    }
                }
            }
        }
    }

    // MARK: - Configuration

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Worktree Configuration", icon: "gearshape")

            if !project.filesToCopy.isEmpty {
                configRow("Files to copy", project.filesToCopy)
            }
            if !project.symlinkPaths.isEmpty {
                configRow("Symlinked dirs", project.symlinkPaths)
            }
            if !project.setupCommands.isEmpty {
                configRow("Setup commands", project.setupCommands)
            }
            if project.filesToCopy.isEmpty && project.symlinkPaths.isEmpty && project.setupCommands.isEmpty {
                Text("No worktree configuration set.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Worktree Row

    /// Returns the active session for a worktree path, if any.
    private func sessionForWorktree(_ wt: WorktreeInfo) -> SessionInfo? {
        appState.sessions.first { $0.worktreePath == wt.path }
    }

    /// Returns true if a session exists for this worktree's branch (matched by path).
    private func isMainWorktree(_ wt: WorktreeInfo) -> Bool {
        wt.path == project.repositoryPath
    }

    @ViewBuilder
    private func worktreeRow(_ wt: WorktreeInfo) -> some View {
        let existingSession = sessionForWorktree(wt)
        let isMain = isMainWorktree(wt)

        HStack(spacing: 8) {
            Image(systemName: isMain ? "house" : "arrow.triangle.branch")
                .font(.system(size: 10))
                .foregroundStyle(existingSession != nil ? .green : .blue)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(wt.branch ?? "detached")
                        .font(.system(size: 12, weight: .medium))
                    if isMain {
                        Text("main")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(3)
                    }
                }
                HStack(spacing: 4) {
                    if let base = wt.baseBranch {
                        Text("from \(base)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Text(abbreviatePath(wt.path))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(wt.path, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy path")
                }
            }

            Spacer()

            if existingSession != nil {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("Running")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(action: { resumeWorktree(wt) }) {
                    Label("Open", systemImage: "play.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // Delete button (not for main worktree)
                if !isMain {
                    Button(role: .destructive, action: { prepareDelete(wt) }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(existingSession != nil ? Color.green.opacity(0.05) : Color.clear)
        )
    }

    /// Creates a session in an existing worktree directory (no git worktree add).
    private func resumeWorktree(_ wt: WorktreeInfo) {
        // Look up the most recent Claude session for this worktree
        let sessionId = ClaudeSessionFinder.findLatestSessionId(for: wt.path)

        let session = SessionInfo(
            name: wt.branch ?? "session",
            workingDirectory: wt.path,
            projectId: project.id,
            branchName: wt.branch,
            worktreePath: wt.path,
            claudeSessionId: sessionId
        )
        appState.sessions.append(session)
        appState.selectSession(session.id)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    private func configRow(_ label: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(items.joined(separator: ", "))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var display = path
        if display.hasPrefix(home) {
            display = "~" + display.dropFirst(home.count)
        }
        return display
    }

    private func loadGitInfo() async {
        do {
            async let w = git.listWorktrees(repoPath: project.repositoryPath)
            async let b = git.listBranches(repoPath: project.repositoryPath)
            async let c = git.currentBranch(repoPath: project.repositoryPath)

            var wts = try await w
            branches = try await b
            currentBranch = try await c

            // Resolve base branches for non-main worktrees
            for i in wts.indices {
                if let branch = wts[i].branch, branch != currentBranch {
                    wts[i].baseBranch = await git.baseBranch(for: branch, repoPath: project.repositoryPath)
                }
            }
            worktrees = wts
        } catch {
            // Silently handle — repo might not be accessible
        }
        isLoading = false
    }
}
