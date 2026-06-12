import Testing
import Foundation
@testable import Canopy

/// Tests for GitService branch operations: changes detection, unmerged commits,
/// branch deletion, and base branch inference.
@Suite("GitService Branch Operations")
struct GitServiceBranchTests {
    private let git = GitService()
    private let fm = FileManager.default

    private func withTempRepo(_ body: (String) async throws -> Void) async throws {
        let repoPath = NSTemporaryDirectory() + "canopy-branch-\(UUID().uuidString)"
        try fm.createDirectory(atPath: repoPath, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: repoPath) }

        try shell("git init -b main && git config user.email 'test@test.com' && git config user.name 'Test'", in: repoPath)
        try "hello".write(toFile: "\(repoPath)/file.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'initial'", in: repoPath)

        try await body(repoPath)
    }

    private func withTempRepo(defaultBranch: String, _ body: (String) async throws -> Void) async throws {
        let repoPath = NSTemporaryDirectory() + "canopy-branch-\(UUID().uuidString)"
        try fm.createDirectory(atPath: repoPath, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: repoPath) }

        try shell("git init -b \(defaultBranch) && git config user.email 'test@test.com' && git config user.name 'Test'", in: repoPath)
        try "hello".write(toFile: "\(repoPath)/file.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'initial'", in: repoPath)

        try await body(repoPath)
    }

    // MARK: - Unmerged detection on master-default repos

    @Test func unmergedCommitsDetectedOnMasterDefaultRepo() async throws {
        // The old hardcoded baseBranch: "main" default made rev-list fail on
        // master-default repos, count as 0, and let users delete branches
        // with unmerged work without any warning.
        try await withTempRepo(defaultBranch: "master") { repo in
            try shell("git checkout -b feature && echo x > f2.txt && git add -A && git commit -m 'work'", in: repo)
            try shell("git checkout master", in: repo)

            let unmerged = await git.branchHasUnmergedCommits(repoPath: repo, branch: "feature")
            #expect(unmerged == true)
        }
    }

    @Test func mergedBranchReportsNoUnmergedCommits() async throws {
        try await withTempRepo(defaultBranch: "master") { repo in
            try shell("git checkout -b feature && echo x > f2.txt && git add -A && git commit -m 'work'", in: repo)
            try shell("git checkout master && git merge feature", in: repo)

            let unmerged = await git.branchHasUnmergedCommits(repoPath: repo, branch: "feature")
            #expect(unmerged == false)
        }
    }

    // MARK: - mergeInto restores the original checkout

    @Test func mergeIntoRestoresOriginalBranch() async throws {
        // The merge checks out the target in the user's MAIN repo; leaving
        // it switched silently changed what the user had checked out.
        try await withTempRepo { repo in
            try shell("git checkout -b feature && echo x > f2.txt && git add -A && git commit -m 'work'", in: repo)
            try shell("git checkout -b elsewhere main", in: repo)

            let result = try await git.mergeInto(target: "main", source: "feature", repoPath: repo)

            if case .success = result {} else {
                Issue.record("expected merge success, got \(result)")
            }
            let current = try await git.currentBranch(repoPath: repo)
            #expect(current == "elsewhere")
        }
    }

    // MARK: - worktreeHasChanges

    @Test func cleanWorktreeHasNoChanges() async throws {
        try await withTempRepo { repo in
            let hasChanges = await git.worktreeHasChanges(worktreePath: repo)
            #expect(hasChanges == false)
        }
    }

    @Test func dirtyWorktreeHasChanges() async throws {
        try await withTempRepo { repo in
            try "modified".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
            let hasChanges = await git.worktreeHasChanges(worktreePath: repo)
            #expect(hasChanges == true)
        }
    }

    @Test func untrackedFileCountsAsChange() async throws {
        try await withTempRepo { repo in
            try "new".write(toFile: "\(repo)/untracked.txt", atomically: true, encoding: .utf8)
            let hasChanges = await git.worktreeHasChanges(worktreePath: repo)
            #expect(hasChanges == true)
        }
    }

    @Test func stagedFileCountsAsChange() async throws {
        try await withTempRepo { repo in
            try "staged".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add file.txt", in: repo)
            let hasChanges = await git.worktreeHasChanges(worktreePath: repo)
            #expect(hasChanges == true)
        }
    }

    @Test func invalidPathReturnsNoChanges() async {
        let hasChanges = await git.worktreeHasChanges(worktreePath: "/nonexistent/\(UUID().uuidString)")
        #expect(hasChanges == false)
    }

    // MARK: - branchHasUnmergedCommits

    @Test func noBranchDivergence() async throws {
        try await withTempRepo { repo in
            try shell("git checkout -b feat/same", in: repo)
            // No new commits on feat/same beyond main
            let hasUnmerged = await git.branchHasUnmergedCommits(repoPath: repo, branch: "feat/same", baseBranch: "main")
            #expect(hasUnmerged == false)
        }
    }

    @Test func branchWithUnmergedCommits() async throws {
        try await withTempRepo { repo in
            try shell("git checkout -b feat/ahead", in: repo)
            try "new content".write(toFile: "\(repo)/new.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'ahead'", in: repo)

            let hasUnmerged = await git.branchHasUnmergedCommits(repoPath: repo, branch: "feat/ahead", baseBranch: "main")
            #expect(hasUnmerged == true)
        }
    }

    @Test func unmergedWithNonexistentBase() async throws {
        try await withTempRepo { repo in
            // A failed check must warn (true), not silently clear the way
            // for deleting a branch whose merge state is unknown.
            let hasUnmerged = await git.branchHasUnmergedCommits(repoPath: repo, branch: "main", baseBranch: "nonexistent")
            #expect(hasUnmerged == true)
        }
    }

    // MARK: - deleteBranch

    @Test func deleteBranch() async throws {
        try await withTempRepo { repo in
            try shell("git branch to-delete", in: repo)
            let branches = try await git.listBranches(repoPath: repo)
            #expect(branches.contains { $0.name == "to-delete" })

            try await git.deleteBranch(repoPath: repo, branch: "to-delete")
            let after = try await git.listBranches(repoPath: repo)
            #expect(!after.contains { $0.name == "to-delete" })
        }
    }

    @Test func deleteCurrentBranchThrows() async throws {
        try await withTempRepo { repo in
            await #expect(throws: GitError.self) {
                try await git.deleteBranch(repoPath: repo, branch: "main")
            }
        }
    }

    @Test func deleteNonexistentBranchThrows() async throws {
        try await withTempRepo { repo in
            await #expect(throws: GitError.self) {
                try await git.deleteBranch(repoPath: repo, branch: "no-such-branch")
            }
        }
    }

    // MARK: - baseBranch

    @Test func baseBranchFindsMain() async throws {
        try await withTempRepo { repo in
            try shell("git checkout -b feat/test", in: repo)
            let base = await git.baseBranch(for: "feat/test", repoPath: repo)
            #expect(base == "main")
        }
    }

    @Test func baseBranchReturnsNilWhenNoCandidates() async throws {
        // Create a repo with a non-standard default branch
        let repoPath = NSTemporaryDirectory() + "canopy-nobase-\(UUID().uuidString)"
        try fm.createDirectory(atPath: repoPath, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: repoPath) }

        try shell("git init -b trunk && git config user.email 'test@test.com' && git config user.name 'Test'", in: repoPath)
        try "hello".write(toFile: "\(repoPath)/file.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'initial'", in: repoPath)
        try shell("git checkout -b feat/orphan", in: repoPath)

        let base = await git.baseBranch(for: "feat/orphan", repoPath: repoPath)
        #expect(base == nil)
    }

    @Test func baseBranchPrefersClosest() async throws {
        try await withTempRepo { repo in
            // Create develop branch with extra commit
            try shell("git checkout -b develop", in: repo)
            try "dev".write(toFile: "\(repo)/dev.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'dev commit'", in: repo)

            // Create feature from develop (closer to develop than main)
            try shell("git checkout -b feat/from-dev", in: repo)

            let base = await git.baseBranch(for: "feat/from-dev", repoPath: repo)
            // develop has 0 distance, main has 1+ distance
            #expect(base == "develop")
        }
    }

    // MARK: - Worktree parseWorktreeList (via listWorktrees)

    @Test func worktreeInfoHasCorrectBranch() async throws {
        try await withTempRepo { repo in
            let wtPath = repo + "-wt-info"
            defer { try? fm.removeItem(atPath: wtPath) }

            try await git.createWorktree(
                repoPath: repo, worktreePath: wtPath,
                branch: "feat/info-test", createBranch: true
            )

            let worktrees = try await git.listWorktrees(repoPath: repo)
            let wt = worktrees.first { $0.branch == "feat/info-test" }
            #expect(wt != nil)
            #expect(wt?.isBare == false)
            let resolved = (wtPath as NSString).resolvingSymlinksInPath
            #expect((wt?.path as? NSString)?.resolvingSymlinksInPath == resolved)
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
