import Testing
import Foundation
@testable import Canopy

/// Claude Code creates git worktrees by itself now -- `claude -w/--worktree`,
/// `/fork`, and subagents with `isolation: worktree`. They land in
/// `.claude/worktrees/<name>` on branch `worktree-<name>`, **inside** the
/// repository, unlike Canopy's sibling layout
/// (`<parent>/canopy-worktrees/<project>/<branch>`).
///
/// Upstream's management story is a sweep that skips anything with work in it
/// and never removes `--worktree` worktrees, so these accumulate with real
/// commits and nothing watching them. That makes Canopy's cross-worktree
/// collision pre-flight *more* valuable, not less -- and it would be
/// unfortunate if the worktrees most likely to surprise you were the ones
/// Canopy filtered out.
///
/// `parseWorktreeList` handles `git worktree list --porcelain` generically, so
/// all of this *should* already work. These tests exist to prove it, and to
/// fail loudly if a future change starts assuming worktrees live outside the
/// repo. All shell out to real `git`.
@Suite("Claude-created nested worktrees")
struct NestedWorktreeTests {
    private let git = GitService()
    private let fm = FileManager.default

    /// A nested path must not be filtered out of the worktree list, and must
    /// not be mistaken for the main checkout by the `samePath` comparison that
    /// `isMainWorktree` and session lookup both use.
    @Test func listsWorktreesNestedInsideRepository() async throws {
        try await withRepo { repo in
            try shell("git worktree add .claude/worktrees/foo -b worktree-foo", in: repo)

            let worktrees = try await git.listWorktrees(repoPath: repo)
            let nested = try #require(worktrees.first { $0.branch == "worktree-foo" })

            #expect(nested.path.hasSuffix(".claude/worktrees/foo"))
            #expect(!nested.isBare)
            // Must not collapse onto the main checkout.
            #expect(!GitService.samePath(nested.path, repo))
            #expect(worktrees.contains { GitService.samePath($0.path, repo) })
        }
    }

    /// The collision pre-flight is Canopy's differentiator precisely because
    /// Claude creates worktrees nobody is watching. A Claude-style nested
    /// worktree and a Canopy-style sibling one touching the same shared
    /// surface must be reported.
    @Test func nestedWorktreeParticipatesInCollisionReports() async throws {
        try await withRepo { repo in
            let sibling = "\(repo)-wt-canopy-style"
            defer { try? fm.removeItem(atPath: sibling) }

            try shell("git worktree add .claude/worktrees/foo -b worktree-foo", in: repo)
            try await git.createWorktree(
                repoPath: repo, worktreePath: sibling, branch: "feat/canopy",
                baseBranch: "main", createBranch: true
            )

            // Different files on the SAME surface: merge-tree sees nothing.
            try commit("{\"a\":1}\n", to: "apps/web/package.json",
                       in: "\(repo)/.claude/worktrees/foo")
            try commit("{\"b\":2}\n", to: "services/api/package.json", in: sibling)

            let report = await git.collisionReport(
                for: "worktree-foo", against: ["feat/canopy"], base: "main", repoPath: repo
            )
            let collision = try #require(report.collisions.first { $0.branch == "feat/canopy" })
            #expect(collision.sharedSurfaceFiles.contains("apps/web/package.json"))
        }
    }

    /// `worktree-<name>` branches are cut from `origin/HEAD`, so deleting one
    /// must hit the base-branch *detection* path rather than a hardcoded
    /// branch name -- otherwise Canopy would delete a Claude worktree that
    /// still has unmerged commits in it without warning.
    @Test func nestedWorktreeUnmergedCommitsWarnBeforeDelete() async throws {
        try await withRepo { repo in
            try shell("git worktree add .claude/worktrees/foo -b worktree-foo", in: repo)
            try commit("work in progress\n", to: "feature.txt",
                       in: "\(repo)/.claude/worktrees/foo")

            let hasUnmerged = await git.branchHasUnmergedCommits(
                repoPath: repo, branch: "worktree-foo", baseBranch: nil
            )
            #expect(hasUnmerged)
        }
    }

    /// The inverse, so the test above can't pass by the warn-side default that
    /// `branchHasUnmergedCommits` falls back to when the base can't be resolved.
    @Test func nestedWorktreeWithNoCommitsDoesNotWarn() async throws {
        try await withRepo { repo in
            try shell("git worktree add .claude/worktrees/foo -b worktree-foo", in: repo)

            let hasUnmerged = await git.branchHasUnmergedCommits(
                repoPath: repo, branch: "worktree-foo", baseBranch: nil
            )
            #expect(!hasUnmerged)
        }
    }

    // MARK: - Fixture

    /// A repo on `main` with one commit. Nested worktrees live inside it, so
    /// removing the repo removes them too.
    private func withRepo(_ body: (_ repo: String) async throws -> Void) async throws {
        let repo = NSTemporaryDirectory() + "canopy-nested-\(UUID().uuidString)"
        try fm.createDirectory(atPath: repo, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: repo) }

        try shell("git init -b main && git config user.email 'test@test.com' && git config user.name 'Test'", in: repo)
        try "base\n".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'initial'", in: repo)

        try await body(repo)
    }

    private func commit(_ contents: String, to file: String, in dir: String) throws {
        let full = (dir as NSString).appendingPathComponent(file)
        try fm.createDirectory(
            atPath: (full as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try contents.write(toFile: full, atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'edit'", in: dir)
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
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(domain: "test", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? ""])
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
