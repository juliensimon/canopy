import Testing
import Foundation
@testable import Tempo

/// Tests for GitService — worktree CRUD, branch listing, file operations.
/// Each test creates a temporary git repo, runs the test, and cleans up.
@Suite("GitService")
struct GitServiceTests {
    private let git = GitService()
    private let fm = FileManager.default

    /// Creates a temporary git repo with an initial commit, runs the body, cleans up.
    private func withTempRepo(_ body: (String) async throws -> Void) async throws {
        let repoPath = NSTemporaryDirectory() + "tempo-test-\(UUID().uuidString)"
        try fm.createDirectory(atPath: repoPath, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: repoPath) }

        try shell("git init && git config user.email 'test@test.com' && git config user.name 'Test'", in: repoPath)
        try "hello".write(toFile: "\(repoPath)/file.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'initial'", in: repoPath)

        try await body(repoPath)
    }

    // MARK: - Repository Detection

    @Test func isGitRepo() async throws {
        try await withTempRepo { repo in
            let result = await git.isGitRepo(path: repo)
            #expect(result == true)
        }
    }

    @Test func isGitRepoFalseForNonRepo() async {
        let result = await git.isGitRepo(path: NSTemporaryDirectory())
        #expect(result == false)
    }

    @Test func repoRoot() async throws {
        try await withTempRepo { repo in
            let root = try await git.repoRoot(path: repo)
            let expected = (repo as NSString).resolvingSymlinksInPath
            let actual = (root as NSString).resolvingSymlinksInPath
            #expect(actual == expected)
        }
    }

    // MARK: - Branch Operations

    @Test func listBranches() async throws {
        try await withTempRepo { repo in
            let branches = try await git.listBranches(repoPath: repo)
            #expect(!branches.isEmpty)
            #expect(branches.contains { $0.isCurrent })
        }
    }

    @Test func currentBranch() async throws {
        try await withTempRepo { repo in
            let branch = try await git.currentBranch(repoPath: repo)
            #expect(!branch.isEmpty)
            #expect(branch == "main" || branch == "master")
        }
    }

    // MARK: - Worktree Operations

    @Test func createWorktree() async throws {
        try await withTempRepo { repo in
            let wtPath = repo + "-wt-create"
            defer { try? fm.removeItem(atPath: wtPath) }

            try await git.createWorktree(
                repoPath: repo, worktreePath: wtPath,
                branch: "feat/test", createBranch: true
            )

            #expect(fm.fileExists(atPath: wtPath))
            #expect(fm.fileExists(atPath: "\(wtPath)/file.txt"))
        }
    }

    @Test func listWorktrees() async throws {
        try await withTempRepo { repo in
            let wtPath = repo + "-wt-list"
            defer { try? fm.removeItem(atPath: wtPath) }

            try await git.createWorktree(
                repoPath: repo, worktreePath: wtPath,
                branch: "feat/list", createBranch: true
            )

            let worktrees = try await git.listWorktrees(repoPath: repo)
            #expect(worktrees.count >= 2)
            #expect(worktrees.contains { $0.branch == "feat/list" })
        }
    }

    @Test func removeWorktree() async throws {
        try await withTempRepo { repo in
            let wtPath = repo + "-wt-remove"

            try await git.createWorktree(
                repoPath: repo, worktreePath: wtPath,
                branch: "feat/remove", createBranch: true
            )
            #expect(fm.fileExists(atPath: wtPath))

            try await git.removeWorktree(repoPath: repo, worktreePath: wtPath)
            #expect(!fm.fileExists(atPath: wtPath))
        }
    }

    @Test func createWorktreeFromSpecificBranch() async throws {
        try await withTempRepo { repo in
            // Create develop branch with extra file
            try shell("git checkout -b develop", in: repo)
            try "dev-content".write(toFile: "\(repo)/develop.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'develop'", in: repo)
            try shell("git checkout main 2>/dev/null || git checkout master", in: repo)

            let wtPath = repo + "-wt-from-dev"
            defer { try? fm.removeItem(atPath: wtPath) }

            try await git.createWorktree(
                repoPath: repo, worktreePath: wtPath,
                branch: "feat/from-dev", baseBranch: "develop", createBranch: true
            )

            #expect(fm.fileExists(atPath: "\(wtPath)/develop.txt"))
        }
    }

    // MARK: - File Copy

    @Test func copyFiles() throws {
        let src = NSTemporaryDirectory() + "tempo-copy-src-\(UUID().uuidString)"
        let dst = NSTemporaryDirectory() + "tempo-copy-dst-\(UUID().uuidString)"
        try fm.createDirectory(atPath: src, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: src); try? fm.removeItem(atPath: dst) }

        try ".env content".write(toFile: "\(src)/.env", atomically: true, encoding: .utf8)

        try GitService.copyFiles(from: src, to: dst, paths: [".env", ".env.missing"])

        let content = try String(contentsOfFile: "\(dst)/.env", encoding: .utf8)
        #expect(content == ".env content")
        #expect(!fm.fileExists(atPath: "\(dst)/.env.missing"))
    }

    @Test func copyFilesCreatesParentDirs() throws {
        let src = NSTemporaryDirectory() + "tempo-nested-src-\(UUID().uuidString)"
        let dst = NSTemporaryDirectory() + "tempo-nested-dst-\(UUID().uuidString)"
        try fm.createDirectory(atPath: "\(src)/config/deep", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: src); try? fm.removeItem(atPath: dst) }

        try "nested".write(toFile: "\(src)/config/deep/s.json", atomically: true, encoding: .utf8)

        try GitService.copyFiles(from: src, to: dst, paths: ["config/deep/s.json"])

        let content = try String(contentsOfFile: "\(dst)/config/deep/s.json", encoding: .utf8)
        #expect(content == "nested")
    }

    @Test func copyFilesOverwrites() throws {
        let src = NSTemporaryDirectory() + "tempo-ow-src-\(UUID().uuidString)"
        let dst = NSTemporaryDirectory() + "tempo-ow-dst-\(UUID().uuidString)"
        try fm.createDirectory(atPath: src, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: src); try? fm.removeItem(atPath: dst) }

        try "new".write(toFile: "\(src)/.env", atomically: true, encoding: .utf8)
        try "old".write(toFile: "\(dst)/.env", atomically: true, encoding: .utf8)

        try GitService.copyFiles(from: src, to: dst, paths: [".env"])

        #expect(try String(contentsOfFile: "\(dst)/.env", encoding: .utf8) == "new")
    }

    // MARK: - Symlinks

    @Test func createSymlinks() throws {
        let src = NSTemporaryDirectory() + "tempo-sym-src-\(UUID().uuidString)"
        let dst = NSTemporaryDirectory() + "tempo-sym-dst-\(UUID().uuidString)"
        try fm.createDirectory(atPath: "\(src)/node_modules", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: src); try? fm.removeItem(atPath: dst) }

        try "pkg".write(toFile: "\(src)/node_modules/test.js", atomically: true, encoding: .utf8)

        try GitService.createSymlinks(from: src, to: dst, paths: ["node_modules"])

        let resolved = try fm.destinationOfSymbolicLink(atPath: "\(dst)/node_modules")
        #expect(resolved == "\(src)/node_modules")

        let content = try String(contentsOfFile: "\(dst)/node_modules/test.js", encoding: .utf8)
        #expect(content == "pkg")
    }

    @Test func createSymlinksSkipsMissing() throws {
        let dst = NSTemporaryDirectory() + "tempo-sym-skip-\(UUID().uuidString)"
        try fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: dst) }

        try GitService.createSymlinks(from: "/nonexistent", to: dst, paths: ["nope"])
        #expect(!fm.fileExists(atPath: "\(dst)/nope"))
    }

    // MARK: - Setup Commands

    @Test func runSetupCommand() async throws {
        let dir = NSTemporaryDirectory() + "tempo-setup-\(UUID().uuidString)"
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: dir) }

        try await GitService.runSetupCommand("echo 'hello' > output.txt", in: dir)

        let content = try String(contentsOfFile: "\(dir)/output.txt", encoding: .utf8)
        #expect(content.contains("hello"))
    }

    @Test func runSetupCommandFailsOnError() async {
        let dir = NSTemporaryDirectory() + "tempo-setup-fail-\(UUID().uuidString)"
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: dir) }

        await #expect(throws: GitError.self) {
            try await GitService.runSetupCommand("exit 1", in: dir)
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
