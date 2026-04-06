import Testing
import Foundation
@testable import Tempo

/// Edge case tests for GitService — covers untested paths and error conditions.
@Suite("GitService Edge Cases")
struct GitServiceEdgeCaseTests {
    private let git = GitService()
    private let fm = FileManager.default

    private func withTempRepo(_ body: (String) async throws -> Void) async throws {
        let repoPath = NSTemporaryDirectory() + "tempo-edge-\(UUID().uuidString)"
        try fm.createDirectory(atPath: repoPath, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: repoPath) }

        try shell("git init && git config user.email 'test@test.com' && git config user.name 'Test'", in: repoPath)
        try "content".write(toFile: "\(repoPath)/file.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'initial'", in: repoPath)

        try await body(repoPath)
    }

    // MARK: - Worktree Edge Cases

    @Test func createWorktreeWithoutBaseBranch() async throws {
        try await withTempRepo { repo in
            let wtPath = repo + "-wt-nobase"
            defer { try? fm.removeItem(atPath: wtPath) }

            // baseBranch=nil should use HEAD
            try await git.createWorktree(
                repoPath: repo, worktreePath: wtPath,
                branch: "feat/no-base", baseBranch: nil, createBranch: true
            )
            #expect(fm.fileExists(atPath: wtPath))
            #expect(fm.fileExists(atPath: "\(wtPath)/file.txt"))
        }
    }

    @Test func createWorktreeCheckoutExistingBranch() async throws {
        try await withTempRepo { repo in
            // Create a branch first
            try shell("git branch existing-branch", in: repo)

            let wtPath = repo + "-wt-existing"
            defer { try? fm.removeItem(atPath: wtPath) }

            try await git.createWorktree(
                repoPath: repo, worktreePath: wtPath,
                branch: "existing-branch", createBranch: false
            )
            #expect(fm.fileExists(atPath: wtPath))
        }
    }

    @Test func createWorktreeFailsForDuplicateBranch() async throws {
        try await withTempRepo { repo in
            let wtPath1 = repo + "-wt-dup1"
            let wtPath2 = repo + "-wt-dup2"
            defer { try? fm.removeItem(atPath: wtPath1); try? fm.removeItem(atPath: wtPath2) }

            try await git.createWorktree(
                repoPath: repo, worktreePath: wtPath1,
                branch: "feat/dup", createBranch: true
            )

            // Second worktree with same branch should fail
            await #expect(throws: GitError.self) {
                try await git.createWorktree(
                    repoPath: repo, worktreePath: wtPath2,
                    branch: "feat/dup", createBranch: true
                )
            }
        }
    }

    @Test func removeNonexistentWorktreeThrows() async throws {
        try await withTempRepo { repo in
            await #expect(throws: GitError.self) {
                try await git.removeWorktree(repoPath: repo, worktreePath: "/nonexistent/path")
            }
        }
    }

    @Test func listWorktreesOnFreshRepo() async throws {
        try await withTempRepo { repo in
            let worktrees = try await git.listWorktrees(repoPath: repo)
            // Fresh repo has just the main worktree
            #expect(worktrees.count == 1)
            #expect(worktrees[0].isBare == false)
        }
    }

    @Test func listWorktreesMultiple() async throws {
        try await withTempRepo { repo in
            let wt1 = repo + "-wt-multi1"
            let wt2 = repo + "-wt-multi2"
            defer { try? fm.removeItem(atPath: wt1); try? fm.removeItem(atPath: wt2) }

            try await git.createWorktree(repoPath: repo, worktreePath: wt1, branch: "feat/a", createBranch: true)
            try await git.createWorktree(repoPath: repo, worktreePath: wt2, branch: "feat/b", createBranch: true)

            let worktrees = try await git.listWorktrees(repoPath: repo)
            #expect(worktrees.count == 3) // main + 2 worktrees
            #expect(worktrees.contains { $0.branch == "feat/a" })
            #expect(worktrees.contains { $0.branch == "feat/b" })
        }
    }

    // MARK: - Branch Edge Cases

    @Test func listBranchesMultiple() async throws {
        try await withTempRepo { repo in
            try shell("git branch develop && git branch staging", in: repo)
            let branches = try await git.listBranches(repoPath: repo)
            #expect(branches.count >= 3)
            #expect(branches.contains { $0.name == "develop" })
            #expect(branches.contains { $0.name == "staging" })
            // Current branch should be first
            #expect(branches[0].isCurrent)
        }
    }

    @Test func repoRootFromSubdirectory() async throws {
        try await withTempRepo { repo in
            let subdir = "\(repo)/sub/deep"
            try fm.createDirectory(atPath: subdir, withIntermediateDirectories: true)
            let root = try await git.repoRoot(path: subdir)
            let expected = (repo as NSString).resolvingSymlinksInPath
            let actual = (root as NSString).resolvingSymlinksInPath
            #expect(actual == expected)
        }
    }

    // MARK: - File Operations Edge Cases

    @Test func copyFilesEmptyList() throws {
        let src = NSTemporaryDirectory() + "tempo-empty-src-\(UUID().uuidString)"
        let dst = NSTemporaryDirectory() + "tempo-empty-dst-\(UUID().uuidString)"
        try fm.createDirectory(atPath: src, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: src); try? fm.removeItem(atPath: dst) }

        // Should not throw for empty file list
        try GitService.copyFiles(from: src, to: dst, paths: [])
    }

    @Test func symlinkReplacesExistingFile() throws {
        let src = NSTemporaryDirectory() + "tempo-sym-replace-src-\(UUID().uuidString)"
        let dst = NSTemporaryDirectory() + "tempo-sym-replace-dst-\(UUID().uuidString)"
        try fm.createDirectory(atPath: "\(src)/dir", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: "\(dst)/dir", withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: src); try? fm.removeItem(atPath: dst) }

        try "original".write(toFile: "\(src)/dir/file.txt", atomically: true, encoding: .utf8)
        try "existing".write(toFile: "\(dst)/dir/file.txt", atomically: true, encoding: .utf8)

        // Symlink should replace the existing directory
        try GitService.createSymlinks(from: src, to: dst, paths: ["dir"])

        let resolved = try fm.destinationOfSymbolicLink(atPath: "\(dst)/dir")
        #expect(resolved == "\(src)/dir")
    }

    @Test func setupCommandHasAccessToPath() async throws {
        let dir = NSTemporaryDirectory() + "tempo-path-\(UUID().uuidString)"
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: dir) }

        // Login shell should have PATH set up
        try await GitService.runSetupCommand("which git > output.txt", in: dir)
        let content = try String(contentsOfFile: "\(dir)/output.txt", encoding: .utf8)
        #expect(content.contains("git"))
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
            throw NSError(domain: "test", code: Int(process.terminationStatus))
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
