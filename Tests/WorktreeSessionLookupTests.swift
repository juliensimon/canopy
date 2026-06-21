import Testing
import Foundation
@testable import Canopy

/// Closing the session after Merge & Finish must locate it by *resolved* path.
///
/// `git worktree list` reports a worktree as `/private/tmp/...` while the stored
/// `SessionInfo.worktreePath` may keep the raw `/tmp` spelling. A raw `==`
/// lookup misses that match and leaves a tab pointing at a now-deleted worktree
/// (its shell + claude keep running in a vanished cwd). The lookup must use
/// symlink-resolving comparison — the same correctness PR #32 shipped for
/// `isMainWorktree`, applied to the session-close fallback in MergeWorktreeSheet.
@Suite("Worktree Session Lookup")
@MainActor
struct WorktreeSessionLookupTests {
    private let fm = FileManager.default

    @Test func findsSessionAcrossSymlinkResolvedPathSpelling() throws {
        // A real directory under /tmp, which resolves to /private/tmp on macOS.
        let name = "canopy-p3-\(UUID().uuidString)"
        let rawPath = "/tmp/\(name)"
        try fm.createDirectory(atPath: rawPath, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: rawPath) }

        let state = AppState(configDir: NSTemporaryDirectory() + "cfg-\(UUID().uuidString)")
        let session = SessionInfo(name: name, workingDirectory: rawPath, worktreePath: rawPath)
        state.sessions = [session]

        // git reports the resolved spelling; the lookup must still find it.
        let resolved = "/private/tmp/\(name)"
        #expect(state.session(forWorktreePath: resolved)?.id == session.id)
    }

    @Test func doesNotMatchGenuinelyDifferentWorktree() throws {
        let name = "canopy-p3-\(UUID().uuidString)"
        let rawPath = "/tmp/\(name)"
        try fm.createDirectory(atPath: rawPath, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: rawPath) }

        let state = AppState(configDir: NSTemporaryDirectory() + "cfg-\(UUID().uuidString)")
        state.sessions = [SessionInfo(name: name, workingDirectory: rawPath, worktreePath: rawPath)]

        #expect(state.session(forWorktreePath: "/tmp/canopy-p3-totally-different") == nil)
    }
}
