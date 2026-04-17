import Testing
import Foundation
@testable import Canopy

/// Tests for GitService git status methods: diffStat, commitsAhead, openPRs.
@Suite("GitService Status")
struct GitServiceStatusTests {
    private let git = GitService()
    private let fm = FileManager.default

    /// Creates a temporary git repo with an initial commit, runs the body, cleans up.
    private func withTempRepo(_ body: (String) async throws -> Void) async throws {
        let repoPath = NSTemporaryDirectory() + "canopy-status-\(UUID().uuidString)"
        try fm.createDirectory(atPath: repoPath, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: repoPath) }

        try shell("git init -b main && git config user.email 'test@test.com' && git config user.name 'Test'", in: repoPath)
        try "hello".write(toFile: "\(repoPath)/file.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'initial'", in: repoPath)

        try await body(repoPath)
    }

    // MARK: - diffStat: clean repo

    @Test func diffStatCleanRepo() async throws {
        try await withTempRepo { repo in
            let stat = await git.diffStat(repoPath: repo)
            #expect(stat != nil)
            #expect(stat!.isClean)
            #expect(stat!.filesChanged == 0)
            #expect(stat!.insertions == 0)
            #expect(stat!.deletions == 0)
            #expect(stat!.changedFiles.isEmpty)
        }
    }

    // MARK: - diffStat: unstaged modifications

    @Test func diffStatWithUnstagedChanges() async throws {
        try await withTempRepo { repo in
            // Modify existing file (1 insertion, 1 deletion since it replaces the line)
            try "modified content\nand a new line".write(
                toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8
            )

            let stat = await git.diffStat(repoPath: repo)
            #expect(stat != nil)
            #expect(!stat!.isClean)
            #expect(stat!.filesChanged == 1)
            #expect(stat!.insertions > 0)
            #expect(stat!.changedFiles.contains("file.txt"))
        }
    }

    // MARK: - diffStat: staged changes

    @Test func diffStatWithStagedChanges() async throws {
        try await withTempRepo { repo in
            try "staged content".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add file.txt", in: repo)

            let stat = await git.diffStat(repoPath: repo)
            #expect(stat != nil)
            #expect(!stat!.isClean)
            #expect(stat!.filesChanged >= 1)
        }
    }

    // MARK: - diffStat: new untracked file (should NOT appear in diff --shortstat)

    @Test func diffStatIgnoresUntrackedFiles() async throws {
        try await withTempRepo { repo in
            try "new file".write(toFile: "\(repo)/untracked.txt", atomically: true, encoding: .utf8)

            let stat = await git.diffStat(repoPath: repo)
            #expect(stat != nil)
            // Untracked files don't show in git diff HEAD
            #expect(stat!.isClean)
        }
    }

    // MARK: - diffStat: multiple files changed

    @Test func diffStatMultipleFiles() async throws {
        try await withTempRepo { repo in
            try "a".write(toFile: "\(repo)/a.txt", atomically: true, encoding: .utf8)
            try "b".write(toFile: "\(repo)/b.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'add files'", in: repo)

            // Now modify both
            try "aa".write(toFile: "\(repo)/a.txt", atomically: true, encoding: .utf8)
            try "bb".write(toFile: "\(repo)/b.txt", atomically: true, encoding: .utf8)

            let stat = await git.diffStat(repoPath: repo)
            #expect(stat != nil)
            #expect(stat!.filesChanged == 2)
            #expect(stat!.changedFiles.count == 2)
            #expect(stat!.changedFiles.contains("a.txt"))
            #expect(stat!.changedFiles.contains("b.txt"))
        }
    }

    // MARK: - diffStat: deletions only

    @Test func diffStatDeletionsOnly() async throws {
        try await withTempRepo { repo in
            try "line1\nline2\nline3".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'multiline'", in: repo)

            // Delete the file content
            try "".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)

            let stat = await git.diffStat(repoPath: repo)
            #expect(stat != nil)
            #expect(stat!.deletions > 0)
            #expect(stat!.insertions == 0 || stat!.insertions == 0)
        }
    }

    // MARK: - diffStat: non-git directory returns nil

    @Test func diffStatNonGitDir() async {
        let tempDir = NSTemporaryDirectory() + "canopy-nongit-\(UUID().uuidString)"
        try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let stat = await git.diffStat(repoPath: tempDir)
        #expect(stat == nil)
    }

    // MARK: - diffStat: repo with no commits

    @Test func diffStatNoCommits() async throws {
        let repoPath = NSTemporaryDirectory() + "canopy-nocommit-\(UUID().uuidString)"
        try fm.createDirectory(atPath: repoPath, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: repoPath) }

        try shell("git init -b main && git config user.email 'test@test.com' && git config user.name 'Test'", in: repoPath)
        // No commits yet — HEAD doesn't exist
        try "file".write(toFile: "\(repoPath)/file.txt", atomically: true, encoding: .utf8)

        let stat = await git.diffStat(repoPath: repoPath)
        // Should return nil since HEAD doesn't exist
        #expect(stat == nil)
    }

    // MARK: - diffStat: works in worktree

    @Test func diffStatInWorktree() async throws {
        try await withTempRepo { repo in
            let wtPath = repo + "-wt-diffstat"
            defer { try? fm.removeItem(atPath: wtPath) }

            try await git.createWorktree(
                repoPath: repo, worktreePath: wtPath,
                branch: "feat/diffstat-wt", createBranch: true
            )

            // Modify a file in the worktree
            try "worktree change".write(toFile: "\(wtPath)/file.txt", atomically: true, encoding: .utf8)

            let stat = await git.diffStat(repoPath: wtPath)
            #expect(stat != nil)
            #expect(!stat!.isClean)
            #expect(stat!.filesChanged == 1)

            // Main repo should still be clean
            let mainStat = await git.diffStat(repoPath: repo)
            #expect(mainStat != nil)
            #expect(mainStat!.isClean)
        }
    }

    // MARK: - diffStat: mixed staged and unstaged

    @Test func diffStatMixedStagedAndUnstaged() async throws {
        try await withTempRepo { repo in
            try "a".write(toFile: "\(repo)/a.txt", atomically: true, encoding: .utf8)
            try "b".write(toFile: "\(repo)/b.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'add ab'", in: repo)

            // Stage change to a.txt
            try "a-modified".write(toFile: "\(repo)/a.txt", atomically: true, encoding: .utf8)
            try shell("git add a.txt", in: repo)

            // Unstaged change to b.txt
            try "b-modified".write(toFile: "\(repo)/b.txt", atomically: true, encoding: .utf8)

            let stat = await git.diffStat(repoPath: repo)
            #expect(stat != nil)
            #expect(stat!.filesChanged == 2)
            #expect(stat!.changedFiles.contains("a.txt"))
            #expect(stat!.changedFiles.contains("b.txt"))
        }
    }

    // MARK: - commitsAhead: no upstream

    @Test func commitsAheadNoUpstreamOnMain() async throws {
        try await withTempRepo { repo in
            // On main with no upstream — no base branch to compare against
            let ahead = await git.commitsAhead(repoPath: repo)
            #expect(ahead == nil)
        }
    }

    // MARK: - commitsAhead: fallback to base branch for feature branches

    @Test func commitsAheadFallsBackToBaseBranch() async throws {
        try await withTempRepo { repo in
            // Create a feature branch with 2 commits, no upstream
            try shell("git checkout -b feat/no-upstream", in: repo)
            for i in 1...2 {
                try "change \(i)".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
                try shell("git add -A && git commit -m 'feat \(i)'", in: repo)
            }

            let ahead = await git.commitsAhead(repoPath: repo)
            // Should fall back to counting commits vs main
            #expect(ahead == 2)
        }
    }

    @Test func commitsAheadFallbackInWorktree() async throws {
        try await withTempRepo { repo in
            let wtPath = repo + "-wt-ahead-fb"
            defer { try? fm.removeItem(atPath: wtPath) }

            try await git.createWorktree(
                repoPath: repo, worktreePath: wtPath,
                branch: "feat/wt-fallback", createBranch: true
            )

            // Make commits in the worktree
            for i in 1...3 {
                try "wt \(i)".write(toFile: "\(wtPath)/file.txt", atomically: true, encoding: .utf8)
                try shell("git add -A && git commit -m 'wt \(i)'", in: wtPath)
            }

            let ahead = await git.commitsAhead(repoPath: wtPath)
            #expect(ahead == 3)
        }
    }

    // MARK: - commitsAhead: 0 ahead (in sync with remote)

    @Test func commitsAheadZero() async throws {
        try await withTempRepo { repo in
            // Create a bare remote and push to it
            let remotePath = repo + "-remote"
            defer { try? fm.removeItem(atPath: remotePath) }
            try shell("git clone --bare \(repo) \(remotePath)", in: repo)
            try shell("git remote add origin \(remotePath)", in: repo)
            try shell("git push -u origin main", in: repo)

            let ahead = await git.commitsAhead(repoPath: repo)
            #expect(ahead == 0)
        }
    }

    // MARK: - commitsAhead: N commits ahead

    @Test func commitsAheadMultiple() async throws {
        try await withTempRepo { repo in
            // Set up remote
            let remotePath = repo + "-remote"
            defer { try? fm.removeItem(atPath: remotePath) }
            try shell("git clone --bare \(repo) \(remotePath)", in: repo)
            try shell("git remote add origin \(remotePath)", in: repo)
            try shell("git push -u origin main", in: repo)

            // Make 3 local commits
            for i in 1...3 {
                try "change \(i)".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
                try shell("git add -A && git commit -m 'local \(i)'", in: repo)
            }

            let ahead = await git.commitsAhead(repoPath: repo)
            #expect(ahead == 3)
        }
    }

    // MARK: - commitsAhead: detached HEAD

    @Test func commitsAheadDetachedHead() async throws {
        try await withTempRepo { repo in
            // Detach HEAD
            let sha = try shell("git rev-parse HEAD", in: repo).trimmingCharacters(in: .whitespacesAndNewlines)
            try shell("git checkout \(sha)", in: repo)

            let ahead = await git.commitsAhead(repoPath: repo)
            // Detached HEAD: currentBranch returns "HEAD", no base branch found → nil
            // (unless baseBranch happens to match, in which case 0)
            #expect(ahead == nil || ahead == 0)
        }
    }

    // MARK: - commitsAhead: works in worktree

    @Test func commitsAheadInWorktree() async throws {
        try await withTempRepo { repo in
            // Set up remote
            let remotePath = repo + "-remote"
            defer { try? fm.removeItem(atPath: remotePath) }
            try shell("git clone --bare \(repo) \(remotePath)", in: repo)
            try shell("git remote add origin \(remotePath)", in: repo)
            try shell("git push -u origin main", in: repo)

            let wtPath = repo + "-wt-ahead"
            defer { try? fm.removeItem(atPath: wtPath) }
            try await git.createWorktree(
                repoPath: repo, worktreePath: wtPath,
                branch: "feat/ahead-wt", createBranch: true
            )

            // Push the branch so it has an upstream
            try shell("git push -u origin feat/ahead-wt", in: wtPath)

            // Make commits in worktree
            try "wt1".write(toFile: "\(wtPath)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'wt commit 1'", in: wtPath)
            try "wt2".write(toFile: "\(wtPath)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'wt commit 2'", in: wtPath)

            let ahead = await git.commitsAhead(repoPath: wtPath)
            #expect(ahead == 2)
        }
    }

    // MARK: - commitsAhead: non-git directory

    @Test func commitsAheadNonGitDir() async {
        let tempDir = NSTemporaryDirectory() + "canopy-nongit2-\(UUID().uuidString)"
        try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let ahead = await git.commitsAhead(repoPath: tempDir)
        #expect(ahead == nil)
    }

    // MARK: - openPRs: JSON parsing

    @Test func openPRsParsesValidJSON() {
        let json = """
        [
          {"number":142,"title":"Add git status indicators","url":"https://github.com/owner/repo/pull/142","isDraft":false,"headRefName":"feature/status-bar"},
          {"number":138,"title":"Fix terminal resize","url":"https://github.com/owner/repo/pull/138","isDraft":true,"headRefName":"fix/resize"}
        ]
        """
        let prs = GitPRInfo.parseGHJSON(json)
        #expect(prs.count == 2)
        #expect(prs[0].number == 142)
        #expect(prs[0].title == "Add git status indicators")
        #expect(prs[0].isDraft == false)
        #expect(prs[0].headBranch == "feature/status-bar")
        #expect(prs[1].number == 138)
        #expect(prs[1].isDraft == true)
        #expect(prs[1].headBranch == "fix/resize")
    }

    @Test func openPRsParsesEmptyArray() {
        let prs = GitPRInfo.parseGHJSON("[]")
        #expect(prs.isEmpty)
    }

    @Test func openPRsHandlesInvalidJSON() {
        let prs = GitPRInfo.parseGHJSON("not json")
        #expect(prs.isEmpty)
    }

    @Test func openPRsHandlesEmptyString() {
        let prs = GitPRInfo.parseGHJSON("")
        #expect(prs.isEmpty)
    }

    @Test func openPRsHandlesMissingFields() {
        // Missing isDraft and headRefName — should still parse with defaults
        let json = """
        [{"number":1,"title":"PR","url":"https://example.com/1"}]
        """
        let prs = GitPRInfo.parseGHJSON(json)
        #expect(prs.count == 1)
        #expect(prs[0].isDraft == false)
        #expect(prs[0].headBranch == "")
    }

    // MARK: - openPRs: gh CLI not available

    @Test func openPRsReturnsEmptyWhenGHNotAvailable() async throws {
        try await withTempRepo { repo in
            // This repo has no GitHub remote, so gh will fail
            let prs = await git.openPRs(repoPath: repo)
            #expect(prs.isEmpty)
        }
    }

    @Test func openPRsNonGitDir() async {
        let tempDir = NSTemporaryDirectory() + "canopy-nongit3-\(UUID().uuidString)"
        try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let prs = await git.openPRs(repoPath: tempDir)
        #expect(prs.isEmpty)
    }

    // MARK: - openPRs: project-scoped variant

    @Test func openPRsProjectScopedReturnsEmptyForLocalRepo() async throws {
        try await withTempRepo { repo in
            let prs = await git.openPRs(repoPath: repo, branch: nil)
            #expect(prs.isEmpty)
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
