import Testing
import Foundation
@testable import Canopy

/// Tests for git status polling infrastructure in AppState.
@Suite("Git Status Polling")
struct GitStatusPollingTests {


    private let fm = FileManager.default

    private func makeTempRepo() throws -> String {
        let repoPath = NSTemporaryDirectory() + "canopy-poll-\(UUID().uuidString)"
        try fm.createDirectory(atPath: repoPath, withIntermediateDirectories: true)
        try shell("git init -b main && git config user.email 'test@test.com' && git config user.name 'Test'", in: repoPath)
        try "hello".write(toFile: "\(repoPath)/file.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'initial'", in: repoPath)
        return repoPath
    }

    // MARK: - GitStatusInfo type

    @Test func gitStatusInfoInitialization() {
        let stat = GitDiffStat(filesChanged: 3, insertions: 45, deletions: 12, changedFiles: ["a.swift", "b.swift", "c.swift"])
        let info = GitStatusInfo(diffStat: stat, commitsAhead: 2, openPRs: [], changedFiles: ["a.swift", "b.swift", "c.swift"])

        #expect(info.diffStat?.filesChanged == 3)
        #expect(info.commitsAhead == 2)
        #expect(info.openPRs.isEmpty)
        #expect(info.changedFiles.count == 3)
    }

    @Test func gitStatusInfoNilsForNonGit() {
        let info = GitStatusInfo(diffStat: nil, commitsAhead: nil, openPRs: [], changedFiles: [])
        #expect(info.diffStat == nil)
        #expect(info.commitsAhead == nil)
    }

    // MARK: - refreshGitStatus in AppState

    @Test @MainActor func refreshGitStatusForGitRepo() async throws {
        let repo = try makeTempRepo()
        defer { try? fm.removeItem(atPath: repo) }

        let state = isolatedAppState()
        state.createSession(name: "test", directory: repo)

        await state.refreshGitStatus()

        #expect(state.activeGitStatus != nil)
        #expect(state.activeGitStatus?.diffStat != nil)
        #expect(state.activeGitStatus?.diffStat?.isClean == true)
    }

    @Test @MainActor func refreshGitStatusWithDirtyRepo() async throws {
        let repo = try makeTempRepo()
        defer { try? fm.removeItem(atPath: repo) }

        let state = isolatedAppState()
        state.createSession(name: "test", directory: repo)

        // Dirty the repo
        try "changed".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)

        await state.refreshGitStatus()

        #expect(state.activeGitStatus != nil)
        #expect(state.activeGitStatus?.diffStat?.isClean == false)
        #expect(state.activeGitStatus?.diffStat?.filesChanged == 1)
        #expect(state.activeGitStatus?.changedFiles.contains("file.txt") == true)
    }

    @Test @MainActor func refreshGitStatusForNonGitDir() async {
        let tempDir = NSTemporaryDirectory() + "canopy-pollnogit-\(UUID().uuidString)"
        try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let state = isolatedAppState()
        state.createSession(name: "test", directory: tempDir)

        await state.refreshGitStatus()

        #expect(state.activeGitStatus == nil)
    }

    @Test @MainActor func refreshGitStatusNilWhenNoActiveSession() async {
        let state = isolatedAppState()

        await state.refreshGitStatus()

        #expect(state.activeGitStatus == nil)
    }

    @Test @MainActor func refreshGitStatusClearsOnSessionSwitch() async throws {
        let repo = try makeTempRepo()
        defer { try? fm.removeItem(atPath: repo) }

        let tempDir = NSTemporaryDirectory() + "canopy-pollswitch-\(UUID().uuidString)"
        try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let state = isolatedAppState()

        // Session 1: git repo with changes
        state.createSession(name: "git-session", directory: repo)
        try "changed".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
        await state.refreshGitStatus()
        #expect(state.activeGitStatus != nil)
        #expect(state.activeGitStatus?.diffStat?.isClean == false)

        // Session 2: non-git dir
        state.createSession(name: "plain-session", directory: tempDir)
        await state.refreshGitStatus()
        #expect(state.activeGitStatus == nil)

        // Switch back to session 1
        state.activeSessionId = state.sessions[0].id
        await state.refreshGitStatus()
        #expect(state.activeGitStatus != nil)
        #expect(state.activeGitStatus?.diffStat?.isClean == false)
    }

    /// Issue #81. A refresh that completes for one session after the user has
    /// switched to another must not publish its result.
    ///
    /// Driven through `applyGitStatus` rather than by racing
    /// `refreshGitStatus`. The version this replaces started the refresh, did
    /// `await Task.yield()`, and flipped `activeSessionId` hoping to land
    /// inside the suspension. That only worked because the awaited work is
    /// subprocesses and therefore slow -- a margin, not a guarantee. The same
    /// pattern written for the session-context guard passed in isolation,
    /// failed under full-suite load, and was finally broken outright when an
    /// optimisation made the awaited work four times faster. A test that has
    /// to lose a scheduling race gets more fragile every time the code it
    /// covers gets quicker.
    @Test @MainActor func aGitStatusReadForAnotherSessionIsNotPublished() {
        let state = isolatedAppState()
        state.createSession(name: "first", directory: "/tmp/first")
        state.createSession(name: "second", directory: "/tmp/second")
        let first = state.sessions[0].id
        let second = state.sessions[1].id
        let status = GitStatusInfo(
            diffStat: GitDiffStat(filesChanged: 2, insertions: 9, deletions: 1, changedFiles: ["a.swift"]),
            commitsAhead: 3, openPRs: [], changedFiles: ["a.swift"]
        )

        state.activeSessionId = first
        state.applyGitStatus(status, readFor: first)
        #expect(state.activeGitStatus?.commitsAhead == 3)

        state.activeSessionId = second
        state.activeGitStatus = nil
        state.applyGitStatus(status, readFor: first)

        #expect(state.activeGitStatus == nil,
                "git status read for another session was published over the active one")
    }

    /// The *other* guard. `refreshGitStatus` returns early when the path is
    /// not a git repo, and clears `activeGitStatus` on the way out -- behind
    /// its own copy of the same check. The race-based test could never reach
    /// it: its active session was always a real repo, so that branch had no
    /// coverage at all. A stale clear is as wrong as a stale write; it blanks
    /// the git segments of a session that does have them.
    @Test @MainActor func aStaleClearDoesNotBlankTheActiveSession() {
        let state = isolatedAppState()
        state.createSession(name: "repo", directory: "/tmp/repo")
        state.createSession(name: "plain", directory: "/tmp/plain")
        let repo = state.sessions[0].id
        let plain = state.sessions[1].id
        let status = GitStatusInfo(diffStat: nil, commitsAhead: 1, openPRs: [], changedFiles: [])

        // The repo session is active and showing git state.
        state.activeSessionId = repo
        state.applyGitStatus(status, readFor: repo)

        // A refresh that started for the *plain* session finishes late and
        // wants to clear. It is no longer active, so it must not.
        state.applyGitStatus(GitStatusInfo?.none, readFor: plain)

        #expect(state.activeGitStatus?.commitsAhead == 1,
                "a stale clear blanked the active session's git status")
    }

    @Test @MainActor func refreshGitStatusInWorktree() async throws {
        let repo = try makeTempRepo()
        defer { try? fm.removeItem(atPath: repo) }

        let git = GitService()
        let wtPath = repo + "-wt-poll"
        defer { try? fm.removeItem(atPath: wtPath) }

        try await git.createWorktree(
            repoPath: repo, worktreePath: wtPath,
            branch: "feat/poll-test", createBranch: true
        )

        let state = isolatedAppState()
        state.createSession(name: "wt-session", directory: wtPath)

        // Dirty the worktree
        try "wt-change".write(toFile: "\(wtPath)/file.txt", atomically: true, encoding: .utf8)

        await state.refreshGitStatus()

        #expect(state.activeGitStatus != nil)
        #expect(state.activeGitStatus?.diffStat?.isClean == false)
    }

    // MARK: - All-session diff stats

    @Test @MainActor func refreshAllSessionDiffStats() async throws {
        let repo1 = try makeTempRepo()
        let repo2 = try makeTempRepo()
        defer { try? fm.removeItem(atPath: repo1); try? fm.removeItem(atPath: repo2) }

        let state = isolatedAppState()
        state.createSession(name: "clean", directory: repo1)
        state.createSession(name: "dirty", directory: repo2)

        try "changed".write(toFile: "\(repo2)/file.txt", atomically: true, encoding: .utf8)

        await state.refreshAllSessionDiffStats()

        let cleanId = state.sessions[0].id
        let dirtyId = state.sessions[1].id

        #expect(state.sessionDiffStats[cleanId] != nil)
        #expect(state.sessionDiffStats[cleanId]?.isClean == true)
        #expect(state.sessionDiffStats[dirtyId] != nil)
        #expect(state.sessionDiffStats[dirtyId]?.isClean == false)
    }

    @Test @MainActor func refreshAllSessionDiffStatsTracksCommitsAhead() async throws {
        let repo = try makeTempRepo()
        defer { try? fm.removeItem(atPath: repo) }

        let git = GitService()
        let wt = repo + "-ahead-wt"
        defer { try? fm.removeItem(atPath: wt) }
        try await git.createWorktree(
            repoPath: repo, worktreePath: wt,
            branch: "feat/ahead", createBranch: true
        )
        // Add a commit on the feature branch so it's ahead of main.
        try "new".write(toFile: "\(wt)/new.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'ahead'", in: wt)

        let state = isolatedAppState()
        state.createSession(name: "feat", directory: wt)

        await state.refreshAllSessionDiffStats()

        let id = state.sessions[0].id
        #expect(state.sessionCommitsAhead[id] == 1)
    }

    // MARK: - refreshAllSessionPRCounts throttling

    @Test @MainActor func refreshAllSessionPRCountsReturnsEmptyForNoSessions() async {
        let state = isolatedAppState()
        await state.refreshAllSessionPRCounts(force: true)
        #expect(state.sessionPRCount.isEmpty)
    }

    @Test @MainActor func refreshAllSessionPRCountsThrottlesRapidCalls() async throws {
        // With `force: false` and a fresh AppState, the first call passes the
        // throttle (lastSessionPRRefresh starts at distantPast). A second
        // immediate call must bail early without touching the state.
        // We seed a fake entry and verify the second call doesn't clear it,
        // which would happen if it re-ran the "rebuild from scratch" block.
        let repo = try makeTempRepo()
        defer { try? fm.removeItem(atPath: repo) }

        let state = isolatedAppState()
        state.createSession(name: "s", directory: repo)
        let id = state.sessions[0].id

        // First call updates lastSessionPRRefresh. Since there's no `gh` PR
        // matching the branch, sessionPRCount is set to [:].
        await state.refreshAllSessionPRCounts(force: false)

        // Seed a value a non-forced second call would clobber if it ran.
        state.sessionPRCount[id] = 42

        await state.refreshAllSessionPRCounts(force: false)

        #expect(state.sessionPRCount[id] == 42,
                "Throttle should have prevented the rebuild")
    }

    @Test @MainActor func refreshAllSessionPRCountsForceOverridesThrottle() async throws {
        let repo = try makeTempRepo()
        defer { try? fm.removeItem(atPath: repo) }

        let state = isolatedAppState()
        state.createSession(name: "s", directory: repo)
        let id = state.sessions[0].id

        await state.refreshAllSessionPRCounts(force: false)
        state.sessionPRCount[id] = 42

        // force: true must bypass the throttle and rebuild, clearing the
        // stale seed since no gh match exists in tests.
        await state.refreshAllSessionPRCounts(force: true)

        #expect(state.sessionPRCount[id] == nil,
                "Force must bypass throttle and rebuild session PR counts")
    }

    @Test @MainActor func refreshAllSessionDiffStatsSkipsNonGit() async {
        let tempDir = NSTemporaryDirectory() + "canopy-nongitall-\(UUID().uuidString)"
        try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let state = isolatedAppState()
        state.createSession(name: "nongit", directory: tempDir)

        await state.refreshAllSessionDiffStats()

        #expect(state.sessionDiffStats[state.sessions[0].id] == nil)
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
