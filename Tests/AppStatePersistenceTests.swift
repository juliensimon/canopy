import Testing
import Foundation
@testable import Canopy

/// Tests for AppState persistence, worktree session creation, and expanded state.
@Suite("AppState Persistence & Worktree")
struct AppStatePersistenceTests {

    // MARK: - Project Expanded Binding

    @Test @MainActor func projectExpandedBindingDefaultFalse() {
        let state = AppState()
        let projectId = UUID()
        let binding = state.projectExpandedBinding(for: projectId)
        #expect(binding.wrappedValue == false)
    }

    @Test @MainActor func projectExpandedBindingSetTrue() {
        let state = AppState()
        let projectId = UUID()
        let binding = state.projectExpandedBinding(for: projectId)

        binding.wrappedValue = true
        #expect(state.expandedProjects.contains(projectId))
    }

    @Test @MainActor func projectExpandedBindingSetFalse() {
        let state = AppState()
        let projectId = UUID()
        state.expandedProjects.insert(projectId)

        let binding = state.projectExpandedBinding(for: projectId)
        binding.wrappedValue = false
        #expect(!state.expandedProjects.contains(projectId))
    }

    @Test @MainActor func addProjectAutoExpands() {
        let state = AppState()
        let project = Project(name: "test", repositoryPath: "/tmp/test")
        state.addProject(project)
        #expect(state.expandedProjects.contains(project.id))
    }

    // MARK: - Persistence Round-Trip

    @Test @MainActor func saveAndLoadProjects() {
        // Use a unique config dir to avoid interfering with real config
        let state1 = AppState()
        let project = Project(
            name: "persist-test",
            repositoryPath: "/tmp/persist-test",
            filesToCopy: [".env"],
            symlinkPaths: ["node_modules"],
            setupCommands: ["npm install"]
        )
        state1.addProject(project)

        // Load in a new AppState instance
        let state2 = AppState()
        state2.loadProjects()

        // Should find our project (if no other tests interfere)
        let found = state2.projects.first { $0.name == "persist-test" }
        #expect(found != nil)
        #expect(found?.filesToCopy == [".env"])
        #expect(found?.symlinkPaths == ["node_modules"])
        #expect(found?.setupCommands == ["npm install"])

        // Cleanup
        state2.removeProject(id: project.id)
    }

    @Test @MainActor func loadProjectsWithMissingFile() {
        // Should not crash when config file doesn't exist
        let state = AppState()
        state.projects = [] // Clear
        state.loadProjects() // Should silently succeed
        // May have projects from other tests, but shouldn't crash
    }

    @Test @MainActor func loadProjectsAutoExpandsAll() {
        let state1 = AppState()
        let p1 = Project(name: "expand-test-1", repositoryPath: "/tmp/e1")
        let p2 = Project(name: "expand-test-2", repositoryPath: "/tmp/e2")
        state1.addProject(p1)
        state1.addProject(p2)

        let state2 = AppState()
        state2.loadProjects()
        #expect(state2.expandedProjects.contains(p1.id))
        #expect(state2.expandedProjects.contains(p2.id))

        // Cleanup
        state2.removeProject(id: p1.id)
        state2.removeProject(id: p2.id)
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

        let state = AppState()
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
        let state = AppState()

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
        let state = AppState()

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
