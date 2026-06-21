import Testing
import Foundation
@testable import Canopy

/// Branch names from UI text fields can carry stray whitespace. git rejects a
/// refname with surrounding spaces, so `createWorktree` must trim before
/// `git worktree add -b` rather than fail (or create a malformed ref).
@Suite("Create Worktree Trim")
struct CreateWorktreeTrimTests {
    private let git = GitService()
    private let fm = FileManager.default

    @Test func trimsBranchNameBeforeCreatingWorktree() async throws {
        let repo = NSTemporaryDirectory() + "canopy-trim-\(UUID().uuidString)"
        try fm.createDirectory(atPath: repo, withIntermediateDirectories: true)
        let wt = repo + "-wt"
        defer { try? fm.removeItem(atPath: repo); try? fm.removeItem(atPath: wt) }

        try shell("git init -q -b main && git config user.email t@t.com && git config user.name T", in: repo)
        try "base\n".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -q -m initial", in: repo)

        try await git.createWorktree(
            repoPath: repo, worktreePath: wt, branch: "  feat/trim  ",
            baseBranch: "main", createBranch: true
        )

        let worktrees = try await git.listWorktrees(repoPath: repo)
        #expect(worktrees.contains { $0.branch == "feat/trim" })
    }

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
