import Testing
import Foundation
@testable import Canopy

/// Tests for AppState persistence, worktree session creation, and expanded state.
@Suite("AppState Persistence & Worktree")
struct AppStatePersistenceTests {

    /// An AppState whose persistence is confined to a throwaway directory.
    /// A default-constructed AppState writes to the developer's real
    /// ~/.config/canopy -- see ConfigIsolationGuardTests.
    ///
    /// ponytail: the directories are left in place under one parent rather
    /// than cleaned per test; NSTemporaryDirectory is periodically cleared,
    /// and threading a defer through every call site here buys tidiness at
    /// the cost of restructuring tests that are not otherwise changing.
    @MainActor
    private func isolatedAppState() -> AppState {
        AppState(configDir: NSTemporaryDirectory()
            + "canopy-isolated-tests/\(UUID().uuidString)")
    }


    // MARK: - Project Expanded Binding

    @Test @MainActor func projectExpandedBindingDefaultFalse() {
        let state = isolatedAppState()
        let projectId = UUID()
        let binding = state.projectExpandedBinding(for: projectId)
        #expect(binding.wrappedValue == false)
    }

    @Test @MainActor func projectExpandedBindingSetTrue() {
        let state = isolatedAppState()
        let projectId = UUID()
        let binding = state.projectExpandedBinding(for: projectId)

        binding.wrappedValue = true
        #expect(state.expandedProjects.contains(projectId))
    }

    @Test @MainActor func projectExpandedBindingSetFalse() {
        let state = isolatedAppState()
        let projectId = UUID()
        state.expandedProjects.insert(projectId)

        let binding = state.projectExpandedBinding(for: projectId)
        binding.wrappedValue = false
        #expect(!state.expandedProjects.contains(projectId))
    }

    @Test @MainActor func addProjectAutoExpands() {
        let tmpDir = NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }
        let state = AppState(configDir: tmpDir)
        let project = Project(name: "test", repositoryPath: "/tmp/test")
        state.addProject(project)
        #expect(state.expandedProjects.contains(project.id))
    }

    // MARK: - Reopen Existing Worktree

    @Test @MainActor func openWorktreeSessionPersistsToDisk() {
        // Reopening a worktree from the project detail view must survive an
        // app restart -- this path used to append the session without saving.
        let tmpDir = NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let state1 = AppState(configDir: tmpDir)
        let project = Project(name: "test", repositoryPath: "/tmp/repo")
        state1.projects = [project]
        state1.openWorktreeSession(project: project, worktreePath: "/tmp/wt-x", branch: "feat/x")

        #expect(state1.sessions.count == 1)
        #expect(state1.sessions.first?.projectId == project.id)

        let state2 = AppState(configDir: tmpDir)
        state2.loadSessions()
        #expect(state2.sessions.first?.worktreePath == "/tmp/wt-x")
        #expect(state2.sessions.first?.branchName == "feat/x")
    }

    @Test @MainActor func openWorktreeSessionDefaultsNameWithoutBranch() {
        let tmpDir = NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let state = AppState(configDir: tmpDir)
        let project = Project(name: "test", repositoryPath: "/tmp/repo")
        state.openWorktreeSession(project: project, worktreePath: "/tmp/wt-y", branch: nil)

        #expect(state.sessions.first?.name == "session")
    }

    // MARK: - Persistence Round-Trip

    @Test @MainActor func saveAndLoadProjects() {
        let tmpDir = NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let state1 = AppState(configDir: tmpDir)
        let project = Project(
            name: "persist-test",
            repositoryPath: "/tmp/persist-test",
            filesToCopy: [".env"],
            symlinkPaths: ["node_modules"],
            setupCommands: ["npm install"]
        )
        state1.addProject(project)

        // Load in a new AppState instance sharing the same config dir
        let state2 = AppState(configDir: tmpDir)
        state2.loadProjects()

        let found = state2.projects.first { $0.name == "persist-test" }
        #expect(found != nil)
        #expect(found?.filesToCopy == [".env"])
        #expect(found?.symlinkPaths == ["node_modules"])
        #expect(found?.setupCommands == ["npm install"])
    }

    @Test @MainActor func loadProjectsWithMissingFile() {
        let tmpDir = NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)"
        // Don't create the dir — test that missing file doesn't crash
        let state = AppState(configDir: tmpDir)
        state.projects = []
        state.loadProjects()
    }

    @Test @MainActor func loadProjectsAutoExpandsAll() {
        let tmpDir = NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let state1 = AppState(configDir: tmpDir)
        let p1 = Project(name: "expand-test-1", repositoryPath: "/tmp/e1")
        let p2 = Project(name: "expand-test-2", repositoryPath: "/tmp/e2")
        state1.addProject(p1)
        state1.addProject(p2)

        let state2 = AppState(configDir: tmpDir)
        state2.loadProjects()
        #expect(state2.expandedProjects.contains(p1.id))
        #expect(state2.expandedProjects.contains(p2.id))
    }

    // MARK: - Worktree Session Creation

    @Test @MainActor func createWorktreeSessionEndToEnd() async throws {
        // Create a real temp git repo
        let repoPath = NSTemporaryDirectory() + "canopy-wt-e2e-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: repoPath, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: repoPath) }

        try shell("git init -b main && git config user.email 'test@test.com' && git config user.name 'Test'", in: repoPath)
        try "hello".write(toFile: "\(repoPath)/file.txt", atomically: true, encoding: .utf8)
        try ".env-content".write(toFile: "\(repoPath)/.env", atomically: true, encoding: .utf8)
        try shell("git add file.txt && git commit -m 'initial'", in: repoPath)

        let project = Project(
            name: "e2e-test",
            repositoryPath: repoPath,
            filesToCopy: [".env"]
        )

        let state = isolatedAppState()
        try await state.createWorktreeSession(
            project: project,
            branchName: "feat/e2e-test",
            baseBranch: "main"
        )

        // Session should be created
        #expect(state.sessions.count == 1)
        #expect(state.sessions[0].branchName == "feat/e2e-test")
        #expect(state.sessions[0].projectId == project.id)
        #expect(state.sessions[0].isWorktreeSession)
        #expect(state.activeSessionId == state.sessions[0].id)

        // .env should be copied
        let wtPath = state.sessions[0].worktreePath!
        let envContent = try String(contentsOfFile: "\(wtPath)/.env", encoding: .utf8)
        #expect(envContent == ".env-content")

        // Cleanup worktree
        try shell("git worktree remove --force '\(wtPath)'", in: repoPath)
    }

    @Test @MainActor func createWorktreeSessionSetsStatusMessages() async throws {
        let repoPath = NSTemporaryDirectory() + "canopy-wt-status-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: repoPath, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: repoPath) }

        try shell("git init -b main && git config user.email 'test@test.com' && git config user.name 'Test'", in: repoPath)
        try "x".write(toFile: "\(repoPath)/f.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'init'", in: repoPath)

        let project = Project(name: "status-test", repositoryPath: repoPath)
        let state = isolatedAppState()

        try await state.createWorktreeSession(
            project: project,
            branchName: "feat/status-test",
            baseBranch: "main"
        )

        // After completion, status should be cleared
        #expect(state.worktreeSetupInProgress == false)
        #expect(state.worktreeSetupStatus == nil)

        // Cleanup
        let wtPath = state.sessions[0].worktreePath!
        try shell("git worktree remove --force '\(wtPath)'", in: repoPath)
    }

    @Test @MainActor func createWorktreeSessionFailsGracefully() async {
        let project = Project(name: "fail-test", repositoryPath: "/nonexistent/path")
        let state = isolatedAppState()

        do {
            try await state.createWorktreeSession(
                project: project,
                branchName: "feat/fail",
                baseBranch: "main"
            )
            #expect(Bool(false), "Should have thrown")
        } catch {
            // Should clean up state on failure
            #expect(state.worktreeSetupInProgress == false)
            #expect(state.worktreeSetupStatus == nil)
            #expect(state.sessions.isEmpty)
        }
    }

    // MARK: - Claude Session ID Refresh

    @Test @MainActor func loadSessionsKeepsStoredClaudeSessionId() throws {
        // An established claudeSessionId is user data, not a cache. A newer
        // unrelated transcript in the same directory -- the user running
        // `claude` by hand from Terminal.app, or a second Canopy tab -- is not
        // evidence about which conversation this tab owns. Overwriting it made
        // the tab `--resume` a stranger's conversation on the next launch.
        let tmpDir = NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let workDir = "/tmp/canopy-keepid-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let ownedId = UUID().uuidString
        let strangerId = UUID().uuidString

        let state1 = AppState(configDir: tmpDir)
        state1.sessions = [SessionInfo(
            name: "s", workingDirectory: workDir, projectId: UUID(),
            claudeSessionId: ownedId
        )]
        state1.saveSessions()

        // The stranger's transcript is the newest file on disk.
        try withFakeClaudeDir(directory: workDir, files: [
            (name: "\(ownedId).jsonl", age: 3600),
            (name: "\(strangerId).jsonl", age: 0),
        ]) {
            let state2 = AppState(configDir: tmpDir)
            state2.loadSessions()
            #expect(state2.sessions.first?.claudeSessionId == ownedId)
        }
    }

    @Test @MainActor func loadSessionsFillsInMissingClaudeSessionId() throws {
        // The mtime heuristic's legitimate job: cold-starting a tab that has
        // no id yet. This path must not regress when the clobber is removed.
        let tmpDir = NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let workDir = "/tmp/canopy-fillid-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let discoverableId = UUID().uuidString

        let state1 = AppState(configDir: tmpDir)
        state1.sessions = [SessionInfo(
            name: "s", workingDirectory: workDir, projectId: UUID()
        )]
        state1.saveSessions()

        try withFakeClaudeDir(directory: workDir, files: [
            (name: "\(discoverableId).jsonl", age: 0),
        ]) {
            let state2 = AppState(configDir: tmpDir)
            state2.loadSessions()
            #expect(state2.sessions.first?.claudeSessionId == discoverableId)
        }
    }

    // MARK: - Helpers

    /// Creates a fake Claude projects directory for `directory`, runs `body`,
    /// then removes it. Mirrors the helper in ClaudeSessionFinderTests.
    private func withFakeClaudeDir(
        directory: String,
        files: [(name: String, age: TimeInterval)],
        body: () throws -> Void
    ) throws {
        let fm = FileManager.default
        let projectDir = ClaudeSessionFinder.projectDirectory(for: directory)
        try fm.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: projectDir) }

        let now = Date()
        for file in files {
            let path = (projectDir as NSString).appendingPathComponent(file.name)
            fm.createFile(atPath: path, contents: Data("test".utf8))
            try fm.setAttributes([.modificationDate: now.addingTimeInterval(-file.age)],
                                 ofItemAtPath: path)
        }
        try body()
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
            throw NSError(domain: "test", code: Int(process.terminationStatus))
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
