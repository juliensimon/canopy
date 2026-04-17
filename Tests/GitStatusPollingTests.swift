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

        let state = AppState()
        state.createSession(name: "test", directory: repo)

        await state.refreshGitStatus()

        #expect(state.activeGitStatus != nil)
        #expect(state.activeGitStatus?.diffStat != nil)
        #expect(state.activeGitStatus?.diffStat?.isClean == true)
    }

    @Test @MainActor func refreshGitStatusWithDirtyRepo() async throws {
        let repo = try makeTempRepo()
        defer { try? fm.removeItem(atPath: repo) }

        let state = AppState()
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

        let state = AppState()
        state.createSession(name: "test", directory: tempDir)

        await state.refreshGitStatus()

        #expect(state.activeGitStatus == nil)
    }

    @Test @MainActor func refreshGitStatusNilWhenNoActiveSession() async {
        let state = AppState()

        await state.refreshGitStatus()

        #expect(state.activeGitStatus == nil)
    }

    @Test @MainActor func refreshGitStatusClearsOnSessionSwitch() async throws {
        let repo = try makeTempRepo()
        defer { try? fm.removeItem(atPath: repo) }

        let tempDir = NSTemporaryDirectory() + "canopy-pollswitch-\(UUID().uuidString)"
        try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let state = AppState()

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

    /// Regression: `refreshGitStatus` must not overwrite `activeGitStatus`
    /// with data from a session that was active when the refresh started but
    /// was switched away from before the git operations completed. Without
    /// the stale-session guard, the 10s poller racing with a tab switch
    /// writes the *previous* session's git state onto the new selection.
    @Test @MainActor func refreshGitStatusDoesNotOverwriteAfterSessionSwitch() async throws {
        let repo = try makeTempRepo()
        defer { try? fm.removeItem(atPath: repo) }
        let tempDir = NSTemporaryDirectory() + "canopy-pollrace-\(UUID().uuidString)"
        try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let state = AppState()
        state.createSession(name: "git-session", directory: repo)
        state.createSession(name: "plain-session", directory: tempDir)

        // Activate the git session and kick off a refresh. The async git
        // operations suspend; before they resume, we switch to the non-git
        // session. The guard must prevent the in-flight refresh from
        // writing the git-session's status onto the plain-session.
        state.activeSessionId = state.sessions[0].id
        let refresh = Task { @MainActor in await state.refreshGitStatus() }
        // Yield so the refresh task actually starts and captures the git
        // session before we swap the selection. Without this, the task
        // begins after the swap and reads the already-updated selection,
        // which wouldn't exercise the stale-write race at all.
        await Task.yield()
        state.activeSessionId = state.sessions[1].id
        await refresh.value

        #expect(state.activeGitStatus == nil,
                "Stale git status wrote over fresh non-git selection")
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

        let state = AppState()
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

        let state = AppState()
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

    @Test @MainActor func refreshAllSessionDiffStatsSkipsNonGit() async {
        let tempDir = NSTemporaryDirectory() + "canopy-nongitall-\(UUID().uuidString)"
        try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let state = AppState()
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
