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
    @State private var collision: WorktreeCollisionReport?
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

    private var hasCollisions: Bool { !(collision?.isEmpty ?? true) }

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
        .frame(width: 450, height: mergeComplete ? 300 : (hasCollisions ? 480 : 380))
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
                        Task {
                            await loadCommitCount()
                            await loadCollisions()
                        }
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

            collisionPanel

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

    // MARK: - Collision pre-flight panel

    @ViewBuilder
    private var collisionPanel: some View {
        if let collision, !collision.isEmpty {
            let accent: Color = collision.hardCount > 0 ? .red : .orange
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(accent)
                    Text("Also being edited in \(collision.collisions.count) other worktree\(collision.collisions.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                // Scrolls rather than clipping when many worktrees collide.
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(collision.collisions) { c in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.branch)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                if !c.conflictingFiles.isEmpty {
                                    collisionLine("will conflict", c.conflictingFiles, .red)
                                }
                                if !c.sharedSurfaceFiles.isEmpty {
                                    collisionLine("shared surface", c.sharedSurfaceFiles, .orange)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
                if !collision.textualCheckAvailable {
                    Text("Couldn't run the textual conflict check — showing shared-surface overlaps only.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(accent.opacity(0.08)))
        }
    }

    private func collisionLine(_ label: String, _ files: [String], _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Capsule().fill(color.opacity(0.15)))
            Text(files.joined(separator: ", "))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
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
            await loadCollisions()
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

    /// Cross-worktree pre-flight: how the branch being merged collides with the
    /// project's *other* worktree branches, evaluated against the merge target.
    /// Advisory only — never blocks the merge.
    private func loadCollisions() async {
        guard !targetBranch.isEmpty else { collision = nil; return }
        let worktrees = (try? await git.listWorktrees(repoPath: project.repositoryPath)) ?? []
        let siblings = worktrees
            .compactMap(\.branch)
            .filter { $0 != branchName && $0 != targetBranch }
        guard !siblings.isEmpty else { collision = nil; return }
        collision = await git.collisionReport(
            for: branchName, against: siblings, base: targetBranch,
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

                // The merge checks out the target branch in the MAIN repo:
                // uncommitted changes there would be dragged onto the target
                // branch (or collide) with no warning.
                let mainDirty = try await git.hasUncommittedChanges(repoPath: project.repositoryPath)
                if mainDirty {
                    errorMessage = "The main repository has uncommitted changes. Commit or stash them there first -- merging switches its checked-out branch."
                    isMerging = false
                    return
                }

                // Check if branch is already merged (0 commits ahead of target)
                let ahead = try await git.commitCount(
                    from: branchName,
                    to: targetBranch,
                    repoPath: project.repositoryPath
                )
                if ahead == 0 {
                    errorMessage = "Branch \"\(branchName)\" is already fully merged into \"\(targetBranch)\". Nothing to merge — you can delete the worktree directly."
                    isMerging = false
                    return
                }

                // Pause git-status polling around the destructive merge: the poll
                // loop shells read commands against this same repo and can collide
                // with the merge's writes on index.lock, surfacing as a spurious
                // "merge failed". Restart it however the merge ends.
                appState.stopGitStatusPolling()
                defer { appState.startGitStatusPolling() }

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
            do {
                // Resolve which session to close BEFORE deleting the worktree:
                // afterwards the directory no longer exists, so samePath's
                // realpath(3) can't resolve /tmp vs /private/tmp and the lookup
                // would miss, leaking the session's shell + claude processes.
                let sessionToClose = sessionId ?? appState.session(forWorktreePath: worktreePath)?.id

                if deleteWorktree {
                    try await git.removeWorktree(
                        repoPath: project.repositoryPath,
                        worktreePath: worktreePath
                    )
                }

                if deleteBranch {
                    try await git.deleteBranch(name: branchName, repoPath: project.repositoryPath)
                }

                // Close the session only after cleanup succeeded -- on a git
                // failure the user keeps their tab instead of losing it and
                // then seeing an error.
                if let sessionToClose {
                    appState.performCloseSession(id: sessionToClose)
                }

                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCleaningUp = false
            }
        }
    }
}
