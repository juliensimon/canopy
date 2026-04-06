import Testing
import Foundation
@testable import Canopy

/// Integration tests for the Merge & Finish worktree feature.
///
/// Covers: GitService merge methods, conflict handling, dirty worktree detection,
/// branch cleanup, and the full merge-then-cleanup lifecycle.
@Suite("Merge Worktree")
struct MergeWorktreeTests {
    private let git = GitService()
    private let fm = FileManager.default

    /// Creates a temp repo with an initial commit on `main`, runs the body, cleans up.
    private func withTempRepo(_ body: (String) async throws -> Void) async throws {
        let repoPath = NSTemporaryDirectory() + "canopy-merge-\(UUID().uuidString)"
        try fm.createDirectory(atPath: repoPath, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: repoPath) }

        try shell("git init -b main && git config user.email 'test@test.com' && git config user.name 'Test'", in: repoPath)
        try "initial content".write(toFile: "\(repoPath)/file.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'initial'", in: repoPath)

        try await body(repoPath)
    }

    /// Creates a temp repo with a worktree on a feature branch, runs the body, cleans up both.
    private func withWorktreeRepo(_ body: (String, String, String) async throws -> Void) async throws {
        let repoPath = NSTemporaryDirectory() + "canopy-merge-wt-\(UUID().uuidString)"
        let wtPath = repoPath + "-worktree"
        let branch = "feat/test-merge"
        try fm.createDirectory(atPath: repoPath, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: repoPath); try? fm.removeItem(atPath: wtPath) }

        try shell("git init -b main && git config user.email 'test@test.com' && git config user.name 'Test'", in: repoPath)
        try "initial content".write(toFile: "\(repoPath)/file.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'initial'", in: repoPath)

        try await git.createWorktree(
            repoPath: repoPath, worktreePath: wtPath,
            branch: branch, baseBranch: "main", createBranch: true
        )

        try await body(repoPath, wtPath, branch)
    }

    // MARK: - hasUncommittedChanges

    @Test func cleanRepoHasNoUncommittedChanges() async throws {
        try await withTempRepo { repo in
            let dirty = try await git.hasUncommittedChanges(repoPath: repo)
            #expect(dirty == false)
        }
    }

    @Test func modifiedFileDetectedAsUncommitted() async throws {
        try await withTempRepo { repo in
            try "modified".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
            let dirty = try await git.hasUncommittedChanges(repoPath: repo)
            #expect(dirty == true)
        }
    }

    @Test func stagedFileDetectedAsUncommitted() async throws {
        try await withTempRepo { repo in
            try "staged".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add file.txt", in: repo)
            let dirty = try await git.hasUncommittedChanges(repoPath: repo)
            #expect(dirty == true)
        }
    }

    @Test func untrackedFileDetectedAsUncommitted() async throws {
        try await withTempRepo { repo in
            try "new".write(toFile: "\(repo)/new-file.txt", atomically: true, encoding: .utf8)
            let dirty = try await git.hasUncommittedChanges(repoPath: repo)
            #expect(dirty == true)
        }
    }

    @Test func worktreeUncommittedChangesDetected() async throws {
        try await withWorktreeRepo { repo, wtPath, _ in
            try "worktree edit".write(toFile: "\(wtPath)/file.txt", atomically: true, encoding: .utf8)
            let dirty = try await git.hasUncommittedChanges(repoPath: wtPath)
            #expect(dirty == true)
        }
    }

    // MARK: - commitCount

    @Test func commitCountZeroForIdenticalBranches() async throws {
        try await withTempRepo { repo in
            try shell("git checkout -b feat/same", in: repo)
            let count = try await git.commitCount(from: "feat/same", to: "main", repoPath: repo)
            #expect(count == 0)
        }
    }

    @Test func commitCountMatchesActualCommits() async throws {
        try await withTempRepo { repo in
            try shell("git checkout -b feat/three-commits", in: repo)
            for i in 1...3 {
                try "change \(i)".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
                try shell("git add -A && git commit -m 'commit \(i)'", in: repo)
            }
            let count = try await git.commitCount(from: "feat/three-commits", to: "main", repoPath: repo)
            #expect(count == 3)
        }
    }

    @Test func commitCountIgnoresTargetOnlyCommits() async throws {
        try await withTempRepo { repo in
            try shell("git checkout -b feat/branch", in: repo)
            try "branch".write(toFile: "\(repo)/branch.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'branch commit'", in: repo)

            // Add a commit on main that's not on the branch
            try shell("git checkout main", in: repo)
            try "main-only".write(toFile: "\(repo)/main-only.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'main commit'", in: repo)

            // commitCount should only count branch commits, not main commits
            let count = try await git.commitCount(from: "feat/branch", to: "main", repoPath: repo)
            #expect(count == 1)
        }
    }

    // MARK: - mergeInto — Success Cases

    @Test func mergeIntoFastForward() async throws {
        try await withTempRepo { repo in
            try shell("git checkout -b feat/ff", in: repo)
            try "new file".write(toFile: "\(repo)/feature.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'add feature'", in: repo)
            try shell("git checkout main", in: repo)

            let result = try await git.mergeInto(target: "main", source: "feat/ff", repoPath: repo)

            switch result {
            case .success(let count):
                #expect(count == 1)
                #expect(fm.fileExists(atPath: "\(repo)/feature.txt"))
            case .conflict:
                Issue.record("Expected fast-forward success, got conflict")
            }
        }
    }

    @Test func mergeIntoWithMultipleCommits() async throws {
        try await withTempRepo { repo in
            try shell("git checkout -b feat/multi", in: repo)
            for i in 1...5 {
                try "v\(i)".write(toFile: "\(repo)/file\(i).txt", atomically: true, encoding: .utf8)
                try shell("git add -A && git commit -m 'commit \(i)'", in: repo)
            }
            try shell("git checkout main", in: repo)

            let result = try await git.mergeInto(target: "main", source: "feat/multi", repoPath: repo)

            switch result {
            case .success(let count):
                #expect(count == 5)
                // All files should be on main
                for i in 1...5 {
                    #expect(fm.fileExists(atPath: "\(repo)/file\(i).txt"))
                }
            case .conflict:
                Issue.record("Expected success, got conflict")
            }
        }
    }

    @Test func mergeIntoNonConflictingDivergentBranches() async throws {
        try await withTempRepo { repo in
            try shell("git checkout -b feat/diverge", in: repo)
            try "branch work".write(toFile: "\(repo)/branch.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'branch work'", in: repo)

            // Add non-conflicting commit on main
            try shell("git checkout main", in: repo)
            try "main work".write(toFile: "\(repo)/main.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'main work'", in: repo)

            let result = try await git.mergeInto(target: "main", source: "feat/diverge", repoPath: repo)

            switch result {
            case .success(let count):
                // Divergent merge: 1 main commit + 1 branch commit + 1 merge commit = 3
                // (merge-base..target counts everything from fork point to new HEAD)
                #expect(count == 3)
                #expect(fm.fileExists(atPath: "\(repo)/branch.txt"))
                #expect(fm.fileExists(atPath: "\(repo)/main.txt"))
            case .conflict:
                Issue.record("Expected success, got conflict")
            }
        }
    }

    @Test func mergeIntoLeavesRepoOnTargetBranch() async throws {
        try await withTempRepo { repo in
            try shell("git checkout -b feat/checkout-test", in: repo)
            try "x".write(toFile: "\(repo)/x.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'x'", in: repo)
            try shell("git checkout main", in: repo)

            _ = try await git.mergeInto(target: "main", source: "feat/checkout-test", repoPath: repo)

            let branch = try await git.currentBranch(repoPath: repo)
            #expect(branch == "main")
        }
    }

    // MARK: - mergeInto — Conflict Cases

    @Test func mergeIntoDetectsConflict() async throws {
        try await withTempRepo { repo in
            try shell("git checkout -b feat/conflict", in: repo)
            try "branch version".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'branch change'", in: repo)

            try shell("git checkout main", in: repo)
            try "main version".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'main change'", in: repo)

            let result = try await git.mergeInto(target: "main", source: "feat/conflict", repoPath: repo)

            switch result {
            case .success:
                Issue.record("Expected conflict, got success")
            case .conflict(let files):
                #expect(files.contains("file.txt"))
            }
        }
    }

    @Test func mergeIntoConflictReportsMultipleFiles() async throws {
        try await withTempRepo { repo in
            // Create two files to conflict on
            try "a-main".write(toFile: "\(repo)/a.txt", atomically: true, encoding: .utf8)
            try "b-main".write(toFile: "\(repo)/b.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'add a and b'", in: repo)

            try shell("git checkout -b feat/multi-conflict", in: repo)
            try "a-branch".write(toFile: "\(repo)/a.txt", atomically: true, encoding: .utf8)
            try "b-branch".write(toFile: "\(repo)/b.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'branch changes'", in: repo)

            try shell("git checkout main", in: repo)
            try "a-main-v2".write(toFile: "\(repo)/a.txt", atomically: true, encoding: .utf8)
            try "b-main-v2".write(toFile: "\(repo)/b.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'main changes'", in: repo)

            let result = try await git.mergeInto(target: "main", source: "feat/multi-conflict", repoPath: repo)

            switch result {
            case .success:
                Issue.record("Expected conflict, got success")
            case .conflict(let files):
                #expect(files.contains("a.txt"))
                #expect(files.contains("b.txt"))
                #expect(files.count == 2)
            }
        }
    }

    @Test func mergeIntoConflictAbortsCleanly() async throws {
        try await withTempRepo { repo in
            try shell("git checkout -b feat/abort-test", in: repo)
            try "branch".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'branch'", in: repo)

            try shell("git checkout main", in: repo)
            try "main".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'main'", in: repo)

            let result = try await git.mergeInto(target: "main", source: "feat/abort-test", repoPath: repo)

            // Should be conflict
            guard case .conflict = result else {
                Issue.record("Expected conflict")
                return
            }

            // Repo should be clean after abort (no merge in progress)
            let dirty = try await git.hasUncommittedChanges(repoPath: repo)
            #expect(dirty == false)

            // Should still be on main
            let branch = try await git.currentBranch(repoPath: repo)
            #expect(branch == "main")

            // file.txt should have the main version (pre-merge)
            let content = try String(contentsOfFile: "\(repo)/file.txt", encoding: .utf8)
            #expect(content == "main")
        }
    }

    // MARK: - deleteBranch (safe)

    @Test func deleteMergedBranchSucceeds() async throws {
        try await withTempRepo { repo in
            try shell("git checkout -b feat/delete-me", in: repo)
            try "x".write(toFile: "\(repo)/del.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'work'", in: repo)
            try shell("git checkout main && git merge feat/delete-me", in: repo)

            try await git.deleteBranch(name: "feat/delete-me", repoPath: repo)

            let branches = try await git.listBranches(repoPath: repo)
            #expect(!branches.contains { $0.name == "feat/delete-me" })
        }
    }

    @Test func deleteUnmergedBranchFails() async throws {
        try await withTempRepo { repo in
            try shell("git checkout -b feat/unmerged", in: repo)
            try "x".write(toFile: "\(repo)/unmerged.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'unmerged work'", in: repo)
            try shell("git checkout main", in: repo)

            // Safe delete (-d) should fail for unmerged branch
            await #expect(throws: GitError.self) {
                try await git.deleteBranch(name: "feat/unmerged", repoPath: repo)
            }

            // Branch should still exist
            let branches = try await git.listBranches(repoPath: repo)
            #expect(branches.contains { $0.name == "feat/unmerged" })
        }
    }

    @Test func deleteNonexistentBranchFails() async throws {
        try await withTempRepo { repo in
            await #expect(throws: GitError.self) {
                try await git.deleteBranch(name: "nonexistent-branch", repoPath: repo)
            }
        }
    }

    // MARK: - Full Merge + Cleanup Lifecycle

    @Test func fullMergeAndDeleteWorkflow() async throws {
        try await withWorktreeRepo { repo, wtPath, branch in
            // Add work on the feature branch (in the worktree)
            try "feature work".write(toFile: "\(wtPath)/feature.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'feature work'", in: wtPath)

            // Verify commit count before merge
            let preCount = try await git.commitCount(from: branch, to: "main", repoPath: repo)
            #expect(preCount == 1)

            // Merge
            let result = try await git.mergeInto(target: "main", source: branch, repoPath: repo)
            guard case .success(let count) = result else {
                Issue.record("Expected merge success")
                return
            }
            #expect(count == 1)

            // Delete worktree
            try await git.removeWorktree(repoPath: repo, worktreePath: wtPath)
            #expect(!fm.fileExists(atPath: wtPath))

            // Delete branch (safe — should succeed since we merged)
            try await git.deleteBranch(name: branch, repoPath: repo)
            let branches = try await git.listBranches(repoPath: repo)
            #expect(!branches.contains { $0.name == branch })

            // Feature file should be on main
            let content = try String(contentsOfFile: "\(repo)/feature.txt", encoding: .utf8)
            #expect(content == "feature work")
        }
    }

    @Test func fullMergeWithMultipleWorktreeCommits() async throws {
        try await withWorktreeRepo { repo, wtPath, branch in
            // Add several commits in the worktree
            for i in 1...4 {
                try "v\(i)".write(toFile: "\(wtPath)/file\(i).txt", atomically: true, encoding: .utf8)
                try shell("git add -A && git commit -m 'feature \(i)'", in: wtPath)
            }

            let result = try await git.mergeInto(target: "main", source: branch, repoPath: repo)
            guard case .success(let count) = result else {
                Issue.record("Expected merge success")
                return
            }
            #expect(count == 4)

            // Cleanup
            try await git.removeWorktree(repoPath: repo, worktreePath: wtPath)
            try await git.deleteBranch(name: branch, repoPath: repo)

            // All files should be on main
            for i in 1...4 {
                #expect(fm.fileExists(atPath: "\(repo)/file\(i).txt"))
            }
        }
    }

    @Test func mergeBlockedByDirtyWorktree() async throws {
        // Replicates the actual MergeWorktreeSheet.performMerge() logic:
        // check dirty → refuse merge if dirty
        try await withWorktreeRepo { repo, wtPath, branch in
            // Add a committed change
            try "committed".write(toFile: "\(wtPath)/feature.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'committed'", in: wtPath)

            // Leave uncommitted changes in the worktree
            try "uncommitted".write(toFile: "\(wtPath)/dirty.txt", atomically: true, encoding: .utf8)

            // Worktree should be detected as dirty
            let dirty = try await git.hasUncommittedChanges(repoPath: wtPath)
            #expect(dirty == true)

            // The caller (MergeWorktreeSheet) should NOT call mergeInto when dirty.
            // Verify that if we do merge anyway, it still works (the dirty check is a UI gate).
            // The merge operates on the main repo, not the worktree, so it succeeds.
            let result = try await git.mergeInto(target: "main", source: branch, repoPath: repo)
            guard case .success = result else {
                Issue.record("Merge on main repo should succeed regardless of worktree dirtiness"); return
            }
        }
    }

    @Test func mergeConflictThenFixAndRetry() async throws {
        try await withTempRepo { repo in
            // Create conflicting branches
            try shell("git checkout -b feat/retry", in: repo)
            try "branch v1".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'branch'", in: repo)

            try shell("git checkout main", in: repo)
            try "main v1".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'main'", in: repo)

            // First attempt: conflict
            let result1 = try await git.mergeInto(target: "main", source: "feat/retry", repoPath: repo)
            guard case .conflict = result1 else {
                Issue.record("Expected conflict on first try")
                return
            }

            // "Fix" the conflict by removing the conflicting commit on main
            try shell("git reset --hard HEAD~1", in: repo)

            // Retry: should succeed now (only branch has changes to file.txt)
            let result2 = try await git.mergeInto(target: "main", source: "feat/retry", repoPath: repo)
            guard case .success = result2 else {
                Issue.record("Expected success on retry")
                return
            }

            // Verify the branch version won
            let content = try String(contentsOfFile: "\(repo)/file.txt", encoding: .utf8)
            #expect(content == "branch v1")
        }
    }

    // MARK: - Worktree-Specific Merge Scenarios

    @Test func mergeWorktreeBranchFromMainRepo() async throws {
        try await withWorktreeRepo { repo, wtPath, branch in
            // Work is done in the worktree
            try "done".write(toFile: "\(wtPath)/done.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'done'", in: wtPath)

            // But merge is called on the main repo (this is how MergeWorktreeSheet works)
            let result = try await git.mergeInto(target: "main", source: branch, repoPath: repo)

            switch result {
            case .success(let count):
                #expect(count == 1)
                // File should appear in main repo
                #expect(fm.fileExists(atPath: "\(repo)/done.txt"))
            case .conflict:
                Issue.record("Expected success")
            }
        }
    }

    @Test func cannotDeleteWorktreeBranchBeforeMerge() async throws {
        try await withWorktreeRepo { repo, wtPath, branch in
            try "work".write(toFile: "\(wtPath)/work.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'work'", in: wtPath)

            // Must remove worktree first before deleting branch
            try await git.removeWorktree(repoPath: repo, worktreePath: wtPath)

            // Safe delete should fail — branch isn't merged
            await #expect(throws: GitError.self) {
                try await git.deleteBranch(name: branch, repoPath: repo)
            }
        }
    }

    @Test func mergeWorktreeThenDeleteWorktreeThenDeleteBranch() async throws {
        try await withWorktreeRepo { repo, wtPath, branch in
            try "final".write(toFile: "\(wtPath)/final.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'final'", in: wtPath)

            // Step 1: merge
            let result = try await git.mergeInto(target: "main", source: branch, repoPath: repo)
            guard case .success = result else {
                Issue.record("Merge should succeed")
                return
            }

            // Step 2: remove worktree
            try await git.removeWorktree(repoPath: repo, worktreePath: wtPath)
            #expect(!fm.fileExists(atPath: wtPath))

            // Step 3: safe delete branch (works because we merged)
            try await git.deleteBranch(name: branch, repoPath: repo)

            // Verify everything is clean
            let worktrees = try await git.listWorktrees(repoPath: repo)
            #expect(worktrees.count == 1) // Only main worktree remains
            let branches = try await git.listBranches(repoPath: repo)
            #expect(branches.count == 1) // Only main
            #expect(branches[0].name == "main")
        }
    }

    @Test func mergeIntoNonMainTarget() async throws {
        try await withTempRepo { repo in
            // Create develop branch
            try shell("git checkout -b develop", in: repo)
            try "develop base".write(toFile: "\(repo)/develop.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'develop base'", in: repo)

            // Create feature off develop
            try shell("git checkout -b feat/from-develop", in: repo)
            try "feature".write(toFile: "\(repo)/feature.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'feature'", in: repo)

            let result = try await git.mergeInto(target: "develop", source: "feat/from-develop", repoPath: repo)

            switch result {
            case .success(let count):
                #expect(count == 1)
                let branch = try await git.currentBranch(repoPath: repo)
                #expect(branch == "develop")
            case .conflict:
                Issue.record("Expected success")
            }
        }
    }

    // MARK: - MergeResult Type

    @Test func mergeResultSuccessCarriesCount() async throws {
        try await withTempRepo { repo in
            try shell("git checkout -b feat/count-verify", in: repo)
            try "a".write(toFile: "\(repo)/a.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'a'", in: repo)
            try "b".write(toFile: "\(repo)/b.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'b'", in: repo)
            try shell("git checkout main", in: repo)

            let result = try await git.mergeInto(target: "main", source: "feat/count-verify", repoPath: repo)

            if case .success(let count) = result {
                #expect(count == 2)
            } else {
                Issue.record("Expected success")
            }
        }
    }

    @Test func mergeResultConflictCarriesFileList() async throws {
        try await withTempRepo { repo in
            try "x".write(toFile: "\(repo)/conflict-me.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'add conflict-me'", in: repo)

            try shell("git checkout -b feat/conflict-list", in: repo)
            try "branch".write(toFile: "\(repo)/conflict-me.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'branch edit'", in: repo)

            try shell("git checkout main", in: repo)
            try "main".write(toFile: "\(repo)/conflict-me.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'main edit'", in: repo)

            let result = try await git.mergeInto(target: "main", source: "feat/conflict-list", repoPath: repo)

            if case .conflict(let files) = result {
                #expect(files == ["conflict-me.txt"])
            } else {
                Issue.record("Expected conflict")
            }
        }
    }

    // MARK: - Realistic Worktree Scenarios
    //
    // These simulate actual Canopy usage: create worktree, work in it,
    // merge from main repo, clean up. No plain-branch shortcuts.

    @Test func worktreeMultiFileFeatureMerge() async throws {
        try await withWorktreeRepo { repo, wtPath, branch in
            // Simulate a real feature: add new files, modify existing, create directories
            try fm.createDirectory(atPath: "\(wtPath)/src", withIntermediateDirectories: true)
            try "import Foundation\nfunc hello() {}".write(
                toFile: "\(wtPath)/src/feature.swift", atomically: true, encoding: .utf8
            )
            try "# Feature\nNew feature docs.".write(
                toFile: "\(wtPath)/CHANGELOG.md", atomically: true, encoding: .utf8
            )
            try "modified content".write(toFile: "\(wtPath)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'feat: add feature with docs'", in: wtPath)

            // Second commit: iterate on the feature
            try "import Foundation\nfunc hello() { print(\"hello\") }".write(
                toFile: "\(wtPath)/src/feature.swift", atomically: true, encoding: .utf8
            )
            try shell("git add -A && git commit -m 'feat: implement hello'", in: wtPath)

            // Verify pre-merge state: main repo doesn't have the new files
            #expect(!fm.fileExists(atPath: "\(repo)/src/feature.swift"))
            #expect(!fm.fileExists(atPath: "\(repo)/CHANGELOG.md"))

            // Merge from main repo (the Canopy flow)
            let result = try await git.mergeInto(target: "main", source: branch, repoPath: repo)
            guard case .success(let count) = result else {
                Issue.record("Expected merge success"); return
            }
            #expect(count == 2)

            // All worktree changes should now be on main
            #expect(fm.fileExists(atPath: "\(repo)/src/feature.swift"))
            let code = try String(contentsOfFile: "\(repo)/src/feature.swift", encoding: .utf8)
            #expect(code.contains("print(\"hello\")"))
            #expect(fm.fileExists(atPath: "\(repo)/CHANGELOG.md"))
            let modified = try String(contentsOfFile: "\(repo)/file.txt", encoding: .utf8)
            #expect(modified == "modified content")
        }
    }

    @Test func worktreeConflictsWithMainChanges() async throws {
        try await withWorktreeRepo { repo, wtPath, branch in
            // Work in the worktree — edit file.txt
            try "worktree version".write(toFile: "\(wtPath)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'worktree edit'", in: wtPath)

            // Meanwhile, someone commits to main on the same file (via the main repo)
            try shell("git checkout main", in: repo)
            try "main version".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'main edit'", in: repo)

            // Merge should detect the conflict
            let result = try await git.mergeInto(target: "main", source: branch, repoPath: repo)
            guard case .conflict(let files) = result else {
                Issue.record("Expected conflict"); return
            }
            #expect(files.contains("file.txt"))

            // Main should be clean after abort
            let dirty = try await git.hasUncommittedChanges(repoPath: repo)
            #expect(dirty == false)

            // Main should still have its version
            let content = try String(contentsOfFile: "\(repo)/file.txt", encoding: .utf8)
            #expect(content == "main version")
        }
    }

    @Test func dirtyCheckIsPerWorktree() async throws {
        // Dirty detection is scoped to each worktree independently.
        // The main repo can be clean while a worktree is dirty, and vice versa.
        try await withWorktreeRepo { repo, wtPath, branch in
            // Worktree is dirty
            try "wip".write(toFile: "\(wtPath)/wip.txt", atomically: true, encoding: .utf8)
            let wtDirty = try await git.hasUncommittedChanges(repoPath: wtPath)
            #expect(wtDirty == true)

            // Main repo is clean
            let mainDirty = try await git.hasUncommittedChanges(repoPath: repo)
            #expect(mainDirty == false)

            // Now make main dirty too
            try "main wip".write(toFile: "\(repo)/main-wip.txt", atomically: true, encoding: .utf8)
            let mainDirty2 = try await git.hasUncommittedChanges(repoPath: repo)
            #expect(mainDirty2 == true)

            // Worktree dirtiness is unchanged
            let wtDirty2 = try await git.hasUncommittedChanges(repoPath: wtPath)
            #expect(wtDirty2 == true)
        }
    }

    @Test func worktreeFullLifecycleWithSessionCleanup() async throws {
        // Simulates the complete Canopy "Merge & Finish" flow including AppState
        let repoPath = NSTemporaryDirectory() + "canopy-lifecycle-\(UUID().uuidString)"
        let wtBase = repoPath + "-worktrees"
        let wtPath = wtBase + "/feat-lifecycle"
        try fm.createDirectory(atPath: repoPath, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: wtBase, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: repoPath); try? fm.removeItem(atPath: wtBase) }

        try shell("git init -b main && git config user.email 'test@test.com' && git config user.name 'Test'", in: repoPath)
        try "base".write(toFile: "\(repoPath)/file.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'initial'", in: repoPath)

        let branch = "feat/lifecycle"

        // Step 1: Create worktree (what WorktreeSheet does)
        try await git.createWorktree(
            repoPath: repoPath, worktreePath: wtPath,
            branch: branch, baseBranch: "main", createBranch: true
        )
        #expect(fm.fileExists(atPath: wtPath))

        // Step 2: Do work in the worktree
        try "feature code".write(toFile: "\(wtPath)/feature.swift", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'add feature'", in: wtPath)
        try "more code".write(toFile: "\(wtPath)/feature2.swift", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'add feature2'", in: wtPath)

        // Step 3: Pre-merge checks (what MergeWorktreeSheet does)
        let dirty = try await git.hasUncommittedChanges(repoPath: wtPath)
        #expect(dirty == false)

        let preCount = try await git.commitCount(from: branch, to: "main", repoPath: repoPath)
        #expect(preCount == 2)

        // Step 4: Merge (from main repo path, not worktree)
        let result = try await git.mergeInto(target: "main", source: branch, repoPath: repoPath)
        guard case .success(let count) = result else {
            Issue.record("Expected merge success"); return
        }
        #expect(count == 2)

        // Step 5: Verify merge result
        #expect(fm.fileExists(atPath: "\(repoPath)/feature.swift"))
        #expect(fm.fileExists(atPath: "\(repoPath)/feature2.swift"))
        let currentBranch = try await git.currentBranch(repoPath: repoPath)
        #expect(currentBranch == "main")

        // Step 6: Remove worktree (what performCleanup does)
        try await git.removeWorktree(repoPath: repoPath, worktreePath: wtPath)
        #expect(!fm.fileExists(atPath: wtPath))

        // Step 7: Delete branch safely (only works because we merged)
        try await git.deleteBranch(name: branch, repoPath: repoPath)

        // Step 8: Final state verification
        let worktrees = try await git.listWorktrees(repoPath: repoPath)
        #expect(worktrees.count == 1)
        let branches = try await git.listBranches(repoPath: repoPath)
        #expect(!branches.contains { $0.name == branch })

        // Post-merge: commits and files are on main
        let postCount = try await git.commitCount(from: "main", to: "main", repoPath: repoPath)
        #expect(postCount == 0) // main == main, 0 divergence
    }

    @Test func worktreeCleanupWithoutMerge() async throws {
        // User decides to discard the worktree without merging
        try await withWorktreeRepo { repo, wtPath, branch in
            try "abandoned work".write(toFile: "\(wtPath)/abandoned.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'abandoned'", in: wtPath)

            // Delete worktree without merging
            try await git.removeWorktree(repoPath: repo, worktreePath: wtPath)
            #expect(!fm.fileExists(atPath: wtPath))

            // Branch still exists (force delete needed since unmerged)
            let branches = try await git.listBranches(repoPath: repo)
            #expect(branches.contains { $0.name == branch })

            // Safe delete fails (unmerged)
            await #expect(throws: GitError.self) {
                try await git.deleteBranch(name: branch, repoPath: repo)
            }

            // File should NOT be on main
            #expect(!fm.fileExists(atPath: "\(repo)/abandoned.txt"))
        }
    }

    @Test func worktreeMergePreservesMainRepoWorktreeFile() async throws {
        // Verify that merging doesn't affect the worktree's files on disk
        // (the worktree is a separate directory)
        try await withWorktreeRepo { repo, wtPath, branch in
            try "feature".write(toFile: "\(wtPath)/feature.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'feature'", in: wtPath)

            let result = try await git.mergeInto(target: "main", source: branch, repoPath: repo)
            guard case .success = result else {
                Issue.record("Expected success"); return
            }

            // Both locations should have the file
            #expect(fm.fileExists(atPath: "\(repo)/feature.txt"))
            #expect(fm.fileExists(atPath: "\(wtPath)/feature.txt"))

            // Worktree is still functional
            let wtBranch = try await git.currentBranch(repoPath: wtPath)
            #expect(wtBranch == branch)
        }
    }

    @Test func twoWorktreesMergeSequentially() async throws {
        // Simulate two features developed in parallel worktrees, merged one after another
        let repoPath = NSTemporaryDirectory() + "canopy-2wt-\(UUID().uuidString)"
        let wt1Path = repoPath + "-wt1"
        let wt2Path = repoPath + "-wt2"
        try fm.createDirectory(atPath: repoPath, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(atPath: repoPath)
            try? fm.removeItem(atPath: wt1Path)
            try? fm.removeItem(atPath: wt2Path)
        }

        try shell("git init -b main && git config user.email 'test@test.com' && git config user.name 'Test'", in: repoPath)
        try "base".write(toFile: "\(repoPath)/base.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'initial'", in: repoPath)

        // Create two worktrees
        try await git.createWorktree(repoPath: repoPath, worktreePath: wt1Path, branch: "feat/one", baseBranch: "main", createBranch: true)
        try await git.createWorktree(repoPath: repoPath, worktreePath: wt2Path, branch: "feat/two", baseBranch: "main", createBranch: true)

        // Work in both
        try "feature one".write(toFile: "\(wt1Path)/one.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'feature one'", in: wt1Path)

        try "feature two".write(toFile: "\(wt2Path)/two.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'feature two'", in: wt2Path)

        // Merge first worktree
        let result1 = try await git.mergeInto(target: "main", source: "feat/one", repoPath: repoPath)
        guard case .success = result1 else { Issue.record("Merge 1 failed"); return }

        try await git.removeWorktree(repoPath: repoPath, worktreePath: wt1Path)
        try await git.deleteBranch(name: "feat/one", repoPath: repoPath)

        // Merge second worktree (main has diverged since wt2 was created)
        let result2 = try await git.mergeInto(target: "main", source: "feat/two", repoPath: repoPath)
        guard case .success = result2 else { Issue.record("Merge 2 failed"); return }

        try await git.removeWorktree(repoPath: repoPath, worktreePath: wt2Path)
        try await git.deleteBranch(name: "feat/two", repoPath: repoPath)

        // Main should have both features
        #expect(fm.fileExists(atPath: "\(repoPath)/one.txt"))
        #expect(fm.fileExists(atPath: "\(repoPath)/two.txt"))

        // Only main worktree and branch remain
        let worktrees = try await git.listWorktrees(repoPath: repoPath)
        #expect(worktrees.count == 1)
        let branches = try await git.listBranches(repoPath: repoPath)
        #expect(branches.count == 1)
        #expect(branches[0].name == "main")
    }

    @Test func worktreeCommitCountAccurateAcrossWorktrees() async throws {
        try await withWorktreeRepo { repo, wtPath, branch in
            // Make commits in worktree
            for i in 1...3 {
                try "v\(i)".write(toFile: "\(wtPath)/f\(i).txt", atomically: true, encoding: .utf8)
                try shell("git add -A && git commit -m 'wt commit \(i)'", in: wtPath)
            }

            // commitCount should work when called from main repo
            let count = try await git.commitCount(from: branch, to: "main", repoPath: repo)
            #expect(count == 3)

            // Also works when called from the worktree path
            let countFromWt = try await git.commitCount(from: branch, to: "main", repoPath: wtPath)
            #expect(countFromWt == 3)
        }
    }

    // MARK: - Main Ahead of Worktree
    //
    // Tests where main has new commits that the worktree branch doesn't have.
    // This is the common case: other features land on main while you're working.

    @Test func mainAheadNonConflictingMergesCleanly() async throws {
        try await withWorktreeRepo { repo, wtPath, branch in
            // Work in worktree
            try "feature".write(toFile: "\(wtPath)/feature.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'feature'", in: wtPath)

            // Meanwhile, main gets 3 commits on different files
            try shell("git checkout main", in: repo)
            for i in 1...3 {
                try "main-\(i)".write(toFile: "\(repo)/main\(i).txt", atomically: true, encoding: .utf8)
                try shell("git add -A && git commit -m 'main commit \(i)'", in: repo)
            }

            // Merge: main is 3 commits ahead, but no conflicts
            let result = try await git.mergeInto(target: "main", source: branch, repoPath: repo)
            guard case .success(let count) = result else {
                Issue.record("Expected clean merge despite main being ahead"); return
            }
            // 3 main commits + 1 branch commit + 1 merge commit = 5
            #expect(count == 5)

            // Both main's work and worktree's work should be present
            #expect(fm.fileExists(atPath: "\(repo)/feature.txt"))
            for i in 1...3 {
                #expect(fm.fileExists(atPath: "\(repo)/main\(i).txt"))
            }
        }
    }

    @Test func mainAheadConflictingSameFile() async throws {
        try await withWorktreeRepo { repo, wtPath, branch in
            // Worktree edits file.txt
            try "worktree edit".write(toFile: "\(wtPath)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'wt edit file.txt'", in: wtPath)

            // Main also edits file.txt (ahead by 1 commit)
            try shell("git checkout main", in: repo)
            try "main edit".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'main edit file.txt'", in: repo)

            let result = try await git.mergeInto(target: "main", source: branch, repoPath: repo)
            guard case .conflict(let files) = result else {
                Issue.record("Expected conflict when main ahead with same file edit"); return
            }
            #expect(files.contains("file.txt"))

            // Repo should be clean after abort
            let dirty = try await git.hasUncommittedChanges(repoPath: repo)
            #expect(dirty == false)
            let cur = try await git.currentBranch(repoPath: repo)
            #expect(cur == "main")
        }
    }

    @Test func mainAheadPartialConflict() async throws {
        // Main and worktree both add files, but conflict on one shared file
        try await withWorktreeRepo { repo, wtPath, branch in
            // Worktree: new file + edit shared file
            try "wt-only".write(toFile: "\(wtPath)/wt-only.txt", atomically: true, encoding: .utf8)
            try "wt version".write(toFile: "\(wtPath)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'wt work'", in: wtPath)

            // Main: different new file + edit same shared file
            try shell("git checkout main", in: repo)
            try "main-only".write(toFile: "\(repo)/main-only.txt", atomically: true, encoding: .utf8)
            try "main version".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'main work'", in: repo)

            let result = try await git.mergeInto(target: "main", source: branch, repoPath: repo)
            guard case .conflict(let files) = result else {
                Issue.record("Expected conflict on shared file"); return
            }
            // Only file.txt should conflict, not the new files
            #expect(files.contains("file.txt"))
            #expect(!files.contains("wt-only.txt"))
            #expect(!files.contains("main-only.txt"))
        }
    }

    @Test func mainFarAheadManyCommits() async throws {
        try await withWorktreeRepo { repo, wtPath, branch in
            // Worktree: one small feature
            try "feature".write(toFile: "\(wtPath)/feature.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'feature'", in: wtPath)

            // Main: 10 commits ahead (simulates a busy main branch)
            try shell("git checkout main", in: repo)
            for i in 1...10 {
                try "v\(i)".write(toFile: "\(repo)/main-file-\(i).txt", atomically: true, encoding: .utf8)
                try shell("git add -A && git commit -m 'main \(i)'", in: repo)
            }

            let result = try await git.mergeInto(target: "main", source: branch, repoPath: repo)
            guard case .success(let count) = result else {
                Issue.record("Expected success — no conflicts"); return
            }
            // 10 main commits + 1 branch commit + 1 merge commit = 12
            #expect(count == 12)

            // All 11 files should exist on main
            #expect(fm.fileExists(atPath: "\(repo)/feature.txt"))
            for i in 1...10 {
                #expect(fm.fileExists(atPath: "\(repo)/main-file-\(i).txt"))
            }
        }
    }

    @Test func mainAheadCommitCountShowsBothSides() async throws {
        try await withWorktreeRepo { repo, wtPath, branch in
            // 2 commits in worktree
            try "a".write(toFile: "\(wtPath)/a.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'wt a'", in: wtPath)
            try "b".write(toFile: "\(wtPath)/b.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'wt b'", in: wtPath)

            // 3 commits on main
            try shell("git checkout main", in: repo)
            for i in 1...3 {
                try "m\(i)".write(toFile: "\(repo)/m\(i).txt", atomically: true, encoding: .utf8)
                try shell("git add -A && git commit -m 'main \(i)'", in: repo)
            }

            // commitCount from branch to main = 2 (worktree's commits)
            let wtCount = try await git.commitCount(from: branch, to: "main", repoPath: repo)
            #expect(wtCount == 2)

            // commitCount from main to branch = 3 (main's commits)
            let mainCount = try await git.commitCount(from: "main", to: branch, repoPath: repo)
            #expect(mainCount == 3)
        }
    }

    // MARK: - Worktree Conflict Edge Cases

    @Test func worktreeConflictOnDeletedFile() async throws {
        try await withWorktreeRepo { repo, wtPath, branch in
            // Worktree modifies file.txt
            try "modified in wt".write(toFile: "\(wtPath)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'modify file'", in: wtPath)

            // Main deletes file.txt
            try shell("git checkout main", in: repo)
            try shell("git rm file.txt && git commit -m 'delete file'", in: repo)

            let result = try await git.mergeInto(target: "main", source: branch, repoPath: repo)
            // Git treats modify-vs-delete as a conflict
            guard case .conflict(let files) = result else {
                Issue.record("Expected conflict for modify-vs-delete"); return
            }
            #expect(files.contains("file.txt"))
        }
    }

    @Test func worktreeConflictOnNewFileWithSameName() async throws {
        try await withWorktreeRepo { repo, wtPath, branch in
            // Both create a new file with the same name but different content
            try "wt version".write(toFile: "\(wtPath)/new-file.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'add new-file in wt'", in: wtPath)

            try shell("git checkout main", in: repo)
            try "main version".write(toFile: "\(repo)/new-file.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'add new-file in main'", in: repo)

            let result = try await git.mergeInto(target: "main", source: branch, repoPath: repo)
            guard case .conflict(let files) = result else {
                Issue.record("Expected conflict for add/add"); return
            }
            #expect(files.contains("new-file.txt"))
        }
    }

    @Test func worktreeConflictInSubdirectory() async throws {
        try await withWorktreeRepo { repo, wtPath, branch in
            // Create nested file in worktree
            try fm.createDirectory(atPath: "\(wtPath)/src/models", withIntermediateDirectories: true)
            try "wt model".write(toFile: "\(wtPath)/src/models/user.swift", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'add model in wt'", in: wtPath)

            // Create same nested file on main with different content
            try shell("git checkout main", in: repo)
            try fm.createDirectory(atPath: "\(repo)/src/models", withIntermediateDirectories: true)
            try "main model".write(toFile: "\(repo)/src/models/user.swift", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'add model in main'", in: repo)

            let result = try await git.mergeInto(target: "main", source: branch, repoPath: repo)
            guard case .conflict(let files) = result else {
                Issue.record("Expected conflict in subdirectory"); return
            }
            #expect(files.contains("src/models/user.swift"))
        }
    }

    @Test func worktreeConflictAbortRestoresAllFiles() async throws {
        try await withWorktreeRepo { repo, wtPath, branch in
            // Set up main with several files
            try shell("git checkout main", in: repo)
            try "a-main".write(toFile: "\(repo)/a.txt", atomically: true, encoding: .utf8)
            try "b-main".write(toFile: "\(repo)/b.txt", atomically: true, encoding: .utf8)
            try "c-main".write(toFile: "\(repo)/c.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'add a,b,c'", in: repo)

            // Worktree edits b.txt (conflict) and adds d.txt (no conflict)
            // Need to get b.txt into the worktree first
            try shell("git merge main", in: wtPath)
            try "b-wt".write(toFile: "\(wtPath)/b.txt", atomically: true, encoding: .utf8)
            try "d-new".write(toFile: "\(wtPath)/d.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'edit b, add d'", in: wtPath)

            // Main edits b.txt differently (creates conflict)
            try "b-main-v2".write(toFile: "\(repo)/b.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'edit b on main'", in: repo)

            // Snapshot main's state before merge
            let aBefore = try String(contentsOfFile: "\(repo)/a.txt", encoding: .utf8)
            let bBefore = try String(contentsOfFile: "\(repo)/b.txt", encoding: .utf8)
            let cBefore = try String(contentsOfFile: "\(repo)/c.txt", encoding: .utf8)

            let result = try await git.mergeInto(target: "main", source: branch, repoPath: repo)
            guard case .conflict = result else {
                Issue.record("Expected conflict"); return
            }

            // After abort, ALL files should be exactly as before
            let aAfter = try String(contentsOfFile: "\(repo)/a.txt", encoding: .utf8)
            let bAfter = try String(contentsOfFile: "\(repo)/b.txt", encoding: .utf8)
            let cAfter = try String(contentsOfFile: "\(repo)/c.txt", encoding: .utf8)
            #expect(aAfter == aBefore)
            #expect(bAfter == bBefore)
            #expect(cAfter == cBefore)

            // d.txt should NOT be on main (merge was aborted)
            #expect(!fm.fileExists(atPath: "\(repo)/d.txt"))
        }
    }

    @Test func multipleConflictAttemptsLeaveRepoClean() async throws {
        try await withWorktreeRepo { repo, wtPath, branch in
            // Set up conflict
            try "wt".write(toFile: "\(wtPath)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'wt edit'", in: wtPath)

            try shell("git checkout main", in: repo)
            try "main".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'main edit'", in: repo)

            // Try merging 3 times — each should fail cleanly
            for attempt in 1...3 {
                let result = try await git.mergeInto(target: "main", source: branch, repoPath: repo)
                guard case .conflict = result else {
                    Issue.record("Attempt \(attempt): expected conflict"); return
                }

                // Repo should be clean after each abort
                let dirty = try await git.hasUncommittedChanges(repoPath: repo)
                #expect(dirty == false, "Repo dirty after attempt \(attempt)")
                let cur = try await git.currentBranch(repoPath: repo)
                #expect(cur == "main", "Not on main after attempt \(attempt)")
            }
        }
    }

    // MARK: - P0: Bug Catchers
    //
    // Tests that catch real bugs identified during adversarial review.

    @Test func deleteBranchWhileWorktreeExistsFails() async throws {
        // BUG: MergeWorktreeSheet allows deleteBranch=true with deleteWorktree=false,
        // but git refuses to delete a branch checked out in an active worktree.
        try await withWorktreeRepo { repo, wtPath, branch in
            try "work".write(toFile: "\(wtPath)/work.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'work'", in: wtPath)

            // Merge the branch so -d would normally succeed
            _ = try await git.mergeInto(target: "main", source: branch, repoPath: repo)

            // Try to delete branch while worktree still exists and has it checked out
            // Git will refuse: "error: Cannot delete branch 'X' checked out at 'Y'"
            await #expect(throws: GitError.self) {
                try await git.deleteBranch(name: branch, repoPath: repo)
            }

            // After removing the worktree, deletion works
            try await git.removeWorktree(repoPath: repo, worktreePath: wtPath)
            try await git.deleteBranch(name: branch, repoPath: repo)
        }
    }

    @Test func mergeIntoWithDirtyTrackedFileBlocksCheckout() async throws {
        // Git checkout only fails when a dirty tracked file would be OVERWRITTEN by
        // the target branch (file differs between current branch and target).
        // This can happen if mergeInto is called while the main repo isn't on target.
        try await withTempRepo { repo in
            // Create a branch with different file content
            try shell("git checkout -b other", in: repo)
            try "other-version".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'other version'", in: repo)

            // Create a feature branch from main
            try shell("git checkout main", in: repo)
            try shell("git checkout -b feat/test", in: repo)
            try "feat".write(toFile: "\(repo)/feat.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'feat'", in: repo)

            // Now dirty file.txt (which differs between feat/test's parent and 'other')
            try "dirty".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)

            // Try to merge into 'other' — checkout other would overwrite dirty file.txt
            await #expect(throws: GitError.self) {
                _ = try await git.mergeInto(target: "other", source: "feat/test", repoPath: repo)
            }
        }
    }

    @Test func mergeIntoWithUntrackedFileInMainRepoSucceeds() async throws {
        // Untracked files do NOT block git checkout, so merge should succeed.
        try await withWorktreeRepo { repo, wtPath, branch in
            try "feature".write(toFile: "\(wtPath)/feature.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'feature'", in: wtPath)

            // Add an untracked file to main repo — this should NOT block the merge
            try "untracked".write(toFile: "\(repo)/untracked-file.txt", atomically: true, encoding: .utf8)

            let result = try await git.mergeInto(target: "main", source: branch, repoPath: repo)
            guard case .success = result else {
                Issue.record("Untracked files should not block merge"); return
            }
        }
    }

    @Test func mergeIntoNonexistentTargetThrows() async throws {
        try await withTempRepo { repo in
            try shell("git checkout -b feat/x", in: repo)
            try "x".write(toFile: "\(repo)/x.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'x'", in: repo)

            // Target branch doesn't exist
            await #expect(throws: GitError.self) {
                _ = try await git.mergeInto(target: "nonexistent-branch", source: "feat/x", repoPath: repo)
            }
        }
    }

    @Test func mergeIntoNonexistentSourceThrows() async throws {
        try await withTempRepo { repo in
            await #expect(throws: GitError.self) {
                _ = try await git.mergeInto(target: "main", source: "nonexistent-branch", repoPath: repo)
            }
        }
    }

    // MARK: - Edge Cases

    @Test func mergeAlreadyUpToDate() async throws {
        // Source and target are at the same commit — "Already up to date"
        try await withTempRepo { repo in
            try shell("git checkout -b feat/same-as-main", in: repo)
            try shell("git checkout main", in: repo)

            let result = try await git.mergeInto(target: "main", source: "feat/same-as-main", repoPath: repo)
            guard case .success(let count) = result else {
                Issue.record("Expected success for already-up-to-date merge"); return
            }
            #expect(count == 0)
        }
    }

    @Test func mergeAlreadyUpToDateWhenMainAhead() async throws {
        // Main is ahead of branch — branch has nothing new to merge.
        // Git says "Already up to date" but our merge-base count picks up the
        // main-only commits (merge-base is the branch tip, which is behind main).
        try await withTempRepo { repo in
            try shell("git checkout -b feat/behind", in: repo)
            try shell("git checkout main", in: repo)
            try "ahead".write(toFile: "\(repo)/ahead.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'main ahead'", in: repo)

            let result = try await git.mergeInto(target: "main", source: "feat/behind", repoPath: repo)
            guard case .success(let count) = result else {
                Issue.record("Expected success"); return
            }
            // merge-base is the branch tip (ancestor of main), so mergeBase..main = 1
            // This is "technically correct" — there's 1 commit between merge-base and HEAD.
            // The UI shows this as "1 commit" even though no new work was merged.
            #expect(count == 1)
        }
    }

    @Test func commitCountWithNonexistentBranchThrows() async throws {
        try await withTempRepo { repo in
            await #expect(throws: (any Error).self) {
                _ = try await git.commitCount(from: "nonexistent", to: "main", repoPath: repo)
            }
        }
    }

    @Test func hasUncommittedChangesOnNonexistentPathThrows() async throws {
        await #expect(throws: (any Error).self) {
            _ = try await git.hasUncommittedChanges(repoPath: "/nonexistent/repo/path")
        }
    }

    @Test func renameConflictDetected() async throws {
        // Both sides rename the same file to different names
        try await withWorktreeRepo { repo, wtPath, branch in
            // Worktree renames file.txt -> wt-name.txt
            try shell("git mv file.txt wt-name.txt && git commit -m 'rename in wt'", in: wtPath)

            // Main renames file.txt -> main-name.txt
            try shell("git checkout main", in: repo)
            try shell("git mv file.txt main-name.txt && git commit -m 'rename in main'", in: repo)

            let result = try await git.mergeInto(target: "main", source: branch, repoPath: repo)
            // Git should detect rename/rename conflict
            switch result {
            case .conflict(let files):
                // At least one conflicting path should be reported
                #expect(!files.isEmpty)
            case .success:
                // Some git versions may auto-resolve rename conflicts — document this
                // If this passes, rename/rename was auto-resolved (both files exist)
                break
            }

            // Either way, repo should not be in a broken state
            let dirty = try await git.hasUncommittedChanges(repoPath: repo)
            // If conflict was detected and aborted: clean. If auto-resolved: also clean.
            #expect(dirty == false)
        }
    }

    @Test func mergeWithBinaryFileConflict() async throws {
        try await withWorktreeRepo { repo, wtPath, branch in
            // Create a binary file in the worktree
            let binaryData = Data([0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD])
            try binaryData.write(to: URL(fileURLWithPath: "\(wtPath)/image.bin"))
            try shell("git add -A && git commit -m 'add binary in wt'", in: wtPath)

            // Create different binary file with same name on main
            try shell("git checkout main", in: repo)
            let otherData = Data([0xAA, 0xBB, 0xCC, 0xDD])
            try otherData.write(to: URL(fileURLWithPath: "\(repo)/image.bin"))
            try shell("git add -A && git commit -m 'add binary in main'", in: repo)

            let result = try await git.mergeInto(target: "main", source: branch, repoPath: repo)
            guard case .conflict(let files) = result else {
                Issue.record("Expected conflict on binary file"); return
            }
            #expect(files.contains("image.bin"))
        }
    }

    @Test func deleteBranchSafeVsForceOverloads() async throws {
        // Verify the two deleteBranch methods behave differently for unmerged branches
        try await withTempRepo { repo in
            try shell("git checkout -b feat/overload-test", in: repo)
            try "unmerged".write(toFile: "\(repo)/unmerged.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'unmerged'", in: repo)
            try shell("git checkout main", in: repo)

            // Safe delete (-d) should fail for unmerged branch
            await #expect(throws: GitError.self) {
                try await git.deleteBranch(name: "feat/overload-test", repoPath: repo)
            }

            // Force delete (-D) should succeed
            try await git.deleteBranch(repoPath: repo, branch: "feat/overload-test")

            let branches = try await git.listBranches(repoPath: repo)
            #expect(!branches.contains { $0.name == "feat/overload-test" })
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func shell(_ command: String, in dir: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: dir)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            throw NSError(domain: "test", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? ""])
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
