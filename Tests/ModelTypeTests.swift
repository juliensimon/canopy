import Testing
import Foundation
@testable import Canopy

/// Tests for supporting model types: WorktreeInfo, BranchInfo, GitError.
@Suite("Model Types")
struct ModelTypeTests {

    // MARK: - WorktreeInfo

    @Test func worktreeInfoId() {
        let wt = WorktreeInfo(path: "/my/path", branch: "main", isBare: false)
        #expect(wt.id == "/my/path")
    }

    @Test func worktreeInfoNilBranch() {
        let wt = WorktreeInfo(path: "/detached", branch: nil, isBare: false)
        #expect(wt.branch == nil)
        #expect(wt.isBare == false)
    }

    @Test func worktreeInfoBare() {
        let wt = WorktreeInfo(path: "/bare", branch: nil, isBare: true)
        #expect(wt.isBare == true)
    }

    @Test func worktreeInfoBaseBranch() {
        var wt = WorktreeInfo(path: "/p", branch: "feat", isBare: false)
        #expect(wt.baseBranch == nil)
        wt.baseBranch = "main"
        #expect(wt.baseBranch == "main")
    }

    // MARK: - BranchInfo

    @Test func branchInfoId() {
        let b = BranchInfo(name: "main", isCurrent: true, upstream: "origin/main")
        #expect(b.id == "main")
    }

    @Test func branchInfoNoUpstream() {
        let b = BranchInfo(name: "local-only", isCurrent: false, upstream: nil)
        #expect(b.upstream == nil)
        #expect(b.isCurrent == false)
    }

    // MARK: - GitError

    @Test func gitErrorDescription() {
        let error = GitError.commandFailed("git push: rejected")
        #expect(error.errorDescription == "git push: rejected")
        #expect(error.localizedDescription == "git push: rejected")
    }
}
