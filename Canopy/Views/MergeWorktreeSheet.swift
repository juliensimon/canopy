import SwiftUI

/// Two-phase sheet for merging a worktree branch and cleaning up.
///
/// Phase 1: User confirms source/target branches, sees commit count, clicks "Merge & Finish"
/// Phase 2: After successful merge, user chooses whether to delete worktree and branch
struct MergeWorktreeSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    let project: Project
    let worktreePath: String
    let branchName: String
    /// Session ID if triggered from an active session (sidebar context menu)
    var sessionId: UUID?

    @State private var targetBranch = ""
    @State private var branches: [BranchInfo] = []
    @State private var commitCount: Int?
    @State private var isLoading = true
    @State private var isMerging = false
    @State private var errorMessage: String?

    // Phase 2 state
    @State private var mergeComplete = false
    @State private var mergedCommitCount = 0
    @State private var deleteWorktree = true
    @State private var deleteBranch = true
    @State private var isCleaningUp = false

    private let git = GitService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mergeComplete ? "Merge Successful" : "Merge & Finish")
                .font(.title2)
                .fontWeight(.bold)

            if mergeComplete {
                cleanupPhase
            } else {
                mergePhase
            }
        }
        .padding(20)
        .frame(width: 450, height: mergeComplete ? 300 : 380)
        .task { await loadInfo() }
    }

    // MARK: - Phase 1: Merge

    private var mergePhase: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Source branch (read-only)
            VStack(alignment: .leading, spacing: 4) {
                Text("Source Branch")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(branchName)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
            }

            // Target branch picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Merge Into")
                    .font(.subheadline)
                    .fontWeight(.medium)
                if branches.isEmpty {
                    TextField("main", text: $targetBranch)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("", selection: $targetBranch) {
                        ForEach(branches.filter { $0.name != branchName }) { branch in
                            Text(branch.name).tag(branch.name)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: targetBranch) { _, _ in
                        Task { await loadCommitCount() }
                    }
                }
            }

            // Commit count
            if let count = commitCount {
                HStack(spacing: 6) {
                    Image(systemName: "number")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("\(count) commit\(count == 1 ? "" : "s") to merge")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            if isMerging {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Merging...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isMerging)
                Spacer()
                Button("Merge & Finish") { performMerge() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        isLoading || isMerging || targetBranch.isEmpty || targetBranch == branchName
                    )
            }
        }
    }

    // MARK: - Phase 2: Cleanup

    private var cleanupPhase: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Success summary
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.green)
                Text("Merged **\(branchName)** into **\(targetBranch)** (\(mergedCommitCount) commit\(mergedCommitCount == 1 ? "" : "s"))")
                    .font(.subheadline)
            }

            Divider()

            // Cleanup options
            VStack(alignment: .leading, spacing: 8) {
                Text("Cleanup")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Toggle("Delete worktree directory", isOn: $deleteWorktree)
                    .font(.subheadline)
                Toggle("Delete branch \"\(branchName)\"", isOn: $deleteBranch)
                    .font(.subheadline)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            if isCleaningUp {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Cleaning up...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isCleaningUp)
                Spacer()
                Button("Finish") { performCleanup() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isCleaningUp || (!deleteWorktree && !deleteBranch))
            }
        }
    }

    // MARK: - Actions

    private func loadInfo() async {
        do {
            let branchList = try await git.listBranches(repoPath: project.repositoryPath)
            let detected = await git.baseBranch(for: branchName, repoPath: project.repositoryPath)

            branches = branchList
            targetBranch = detected
                ?? branchList.first(where: { $0.name == "main" })?.name
                ?? branchList.first?.name
                ?? "main"

            await loadCommitCount()
        } catch {
            errorMessage = "Failed to load repository info"
        }
        isLoading = false
    }

    private func loadCommitCount() async {
        guard !targetBranch.isEmpty else { return }
        commitCount = try? await git.commitCount(
            from: branchName,
            to: targetBranch,
            repoPath: project.repositoryPath
        )
    }

    private func performMerge() {
        isMerging = true
        errorMessage = nil

        Task {
            do {
                // Check for uncommitted changes in the worktree
                let dirty = try await git.hasUncommittedChanges(repoPath: worktreePath)
                if dirty {
                    errorMessage = "Worktree has uncommitted changes. Commit or stash them first."
                    isMerging = false
                    return
                }

                let result = try await git.mergeInto(
                    target: targetBranch,
                    source: branchName,
                    repoPath: project.repositoryPath
                )

                switch result {
                case .success(let count):
                    mergedCommitCount = count
                    mergeComplete = true
                case .conflict(let files):
                    errorMessage = "Merge conflict in: \(files.joined(separator: ", "))\nResolve conflicts manually and try again."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isMerging = false
        }
    }

    private func performCleanup() {
        isCleaningUp = true
        errorMessage = nil

        Task {
            // Close session if active
            if let sid = sessionId {
                appState.performCloseSession(id: sid)
            } else if let session = appState.sessions.first(where: { $0.worktreePath == worktreePath }) {
                appState.performCloseSession(id: session.id)
            }

            do {
                if deleteWorktree {
                    try await git.removeWorktree(
                        repoPath: project.repositoryPath,
                        worktreePath: worktreePath
                    )
                }

                if deleteBranch {
                    try await git.deleteBranch(name: branchName, repoPath: project.repositoryPath)
                }

                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCleaningUp = false
            }
        }
    }
}
