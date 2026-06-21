import Testing
import Foundation
@testable import Canopy

/// Regression guard for the `run()` / `runGH()` / `runAllowingFailure()`
/// pipe-buffer deadlock.
///
/// Those helpers must drain stdout AND stderr *concurrently with* the child
/// process — never read a pipe only after `waitUntilExit()`. When a git
/// command's output exceeds the OS pipe buffer (~16–64KB on macOS), the old
/// "wait, then read" ordering deadlocked forever: the child blocks writing a
/// full pipe while the parent blocks in `waitUntilExit()`. That froze the
/// destructive Merge & Finish path (`git merge` summary) and the routine
/// per-worktree `diffStat` refresh (`git diff --name-only`) — exactly when a
/// monorepo has many changed files.
///
/// This test makes a worktree dirty enough to overflow the buffer and asserts
/// `diffStat` returns. It is timeout-guarded so the *buggy* code fails the test
/// rather than hanging the entire suite.
@Suite("GitService Pipe Deadlock")
struct GitServiceDeadlockTests {
    private let git = GitService()
    private let fm = FileManager.default

    @Test func diffStatDoesNotDeadlockOnLargeChangeOutput() async throws {
        let repo = NSTemporaryDirectory() + "canopy-deadlock-\(UUID().uuidString)"
        try fm.createDirectory(atPath: repo, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: repo) }

        try shell("git init -b main && git config user.email 't@t.com' && git config user.name 'T'", in: repo)

        // Enough tracked files with long paths that `git diff --name-only HEAD`
        // output decisively exceeds the pipe buffer once they are all modified:
        // ~1500 files * ~80-char paths ≈ 117KB of stdout.
        let dir = "\(repo)/src"
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let pad = String(repeating: "x", count: 60)
        let count = 1500
        for i in 0..<count {
            try "v1\n".write(toFile: "\(dir)/file_\(i)_\(pad).txt", atomically: true, encoding: .utf8)
        }
        // `-q`: a 1500-file commit otherwise prints a "create mode" line per
        // file (~90KB) and would deadlock this helper's own read-after-wait
        // pipe handling — the very bug under test, in the test's setup.
        try shell("git add -A && git commit -q -m initial", in: repo)
        // Modify every file so they all appear in `git diff --name-only HEAD`.
        for i in 0..<count {
            try "v2\n".write(toFile: "\(dir)/file_\(i)_\(pad).txt", atomically: true, encoding: .utf8)
        }

        let git = self.git
        let repoPath = repo
        let outcome = await withTimeout(seconds: 15) {
            await git.diffStat(repoPath: repoPath)
        }
        guard case .value(let stat) = outcome else {
            Issue.record("diffStat deadlocked on a large dirty worktree (>64KB of name-only output)")
            return
        }
        let unwrapped = try #require(stat, "diffStat returned nil on a large dirty worktree")
        #expect(unwrapped.changedFiles.count == count)
    }

    // MARK: - Helpers

    private enum TimedResult<T: Sendable>: Sendable { case value(T); case timedOut }

    /// Single-resume guard so the first of {operation, timeout} to finish wins.
    private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false
        private let cont: CheckedContinuation<T, Never>
        init(_ cont: CheckedContinuation<T, Never>) { self.cont = cont }
        func resume(_ value: T) {
            lock.lock(); defer { lock.unlock() }
            guard !resumed else { return }
            resumed = true
            cont.resume(returning: value)
        }
    }

    /// Runs `operation` on a DETACHED task that is never awaited, returning
    /// `.timedOut` if it does not finish within `seconds`. Because the operation
    /// is not awaited, one stuck in un-cancellable synchronous I/O (a pipe-buffer
    /// deadlock) fails this test via the timeout instead of wedging the whole
    /// suite (which `withThrowingTaskGroup` would, since it awaits its children).
    private func withTimeout<T: Sendable>(
        seconds: Double, _ operation: @escaping @Sendable () async -> T
    ) async -> TimedResult<T> {
        await withCheckedContinuation { (cont: CheckedContinuation<TimedResult<T>, Never>) in
            let once = ResumeOnce(cont)
            // Operation on a detached (cooperative-pool) task; timeout on a GCD
            // timer so it fires even if the operation blocks a cooperative-pool
            // thread in un-cancellable synchronous I/O — the deadlock we guard
            // against (a cooperative-pool timeout could be starved by it).
            Task.detached { once.resume(.value(await operation())) }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                once.resume(.timedOut)
            }
        }
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
