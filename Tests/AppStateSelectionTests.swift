import Testing
import Foundation
@testable import Canopy

/// Tests for AppState selection logic, project deduplication,
/// terminal session caching, and session naming edge cases.
@Suite("AppState Selection & Caching")
struct AppStateSelectionTests {

    // MARK: - Mutual Exclusion: selectSession / selectProject

    @Test @MainActor func selectSessionClearsProject() {
        let tmpDir = NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }
        let state = AppState(configDir: tmpDir)
        let project = Project(name: "p", repositoryPath: "/tmp/p")
        state.addProject(project)
        state.selectProject(project.id)
        #expect(state.selectedProjectId == project.id)
        #expect(state.activeSessionId == nil)

        state.createSession(name: "S", directory: "/tmp")
        let sessionId = state.sessions[0].id
        state.selectSession(sessionId)

        #expect(state.activeSessionId == sessionId)
        #expect(state.selectedProjectId == nil)
    }

    @Test @MainActor func selectProjectClearsSession() {
        let tmpDir = NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }
        let state = AppState(configDir: tmpDir)
        state.createSession(name: "S", directory: "/tmp")
        let sessionId = state.sessions[0].id
        #expect(state.activeSessionId == sessionId)

        let project = Project(name: "p", repositoryPath: "/tmp/p")
        state.addProject(project)
        state.selectProject(project.id)

        #expect(state.selectedProjectId == project.id)
        #expect(state.activeSessionId == nil)
    }

    @Test @MainActor func selectedProjectReturnsCorrectProject() {
        let tmpDir = NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }
        let state = AppState(configDir: tmpDir)
        let p1 = Project(name: "alpha", repositoryPath: "/a")
        let p2 = Project(name: "beta", repositoryPath: "/b")
        state.addProject(p1)
        state.addProject(p2)

        state.selectProject(p2.id)
        #expect(state.selectedProject?.name == "beta")
    }

    @Test @MainActor func selectedProjectNilWhenNoneSelected() {
        let state = AppState()
        #expect(state.selectedProject == nil)
    }

    // MARK: - Project Deduplication

    @Test @MainActor func addProjectPreventsDuplicateRepoPath() {
        let tmpDir = NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }
        let state = AppState(configDir: tmpDir)
        state.addProject(Project(name: "first", repositoryPath: "/same/path"))
        state.addProject(Project(name: "second", repositoryPath: "/same/path"))
        #expect(state.projects.count == 1)
        #expect(state.projects[0].name == "first")
    }

    @Test @MainActor func addProjectAllowsDifferentPaths() {
        let tmpDir = NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }
        let state = AppState(configDir: tmpDir)
        state.addProject(Project(name: "a", repositoryPath: "/path/a"))
        state.addProject(Project(name: "b", repositoryPath: "/path/b"))
        #expect(state.projects.count == 2)
    }

    // MARK: - Terminal Session Caching

    @Test @MainActor func terminalSessionReturnsSameInstance() {
        let state = AppState()
        state.createSession(name: "Test", directory: "/tmp")
        let sessionInfo = state.sessions[0]

        let ts1 = state.terminalSession(for: sessionInfo)
        let ts2 = state.terminalSession(for: sessionInfo)

        #expect(ts1 === ts2) // Same object reference
    }

    @Test @MainActor func terminalSessionCreatesNew() {
        let state = AppState()
        state.createSession(name: "A", directory: "/tmp")
        state.createSession(name: "B", directory: "/tmp")

        let tsA = state.terminalSession(for: state.sessions[0])
        let tsB = state.terminalSession(for: state.sessions[1])

        #expect(tsA !== tsB)
        #expect(tsA.id == state.sessions[0].id)
        #expect(tsB.id == state.sessions[1].id)
    }

    @Test @MainActor func closeSessionRemovesTerminalSession() {
        let state = AppState()
        state.settings.confirmBeforeClosing = false
        state.createSession(name: "Test", directory: "/tmp")
        let info = state.sessions[0]
        _ = state.terminalSession(for: info)
        #expect(state.terminalSessions[info.id] != nil)

        state.closeSession(id: info.id)
        #expect(state.terminalSessions[info.id] == nil)
    }

    // MARK: - Session Naming

    @Test @MainActor func createSessionUsesDirectoryName() {
        let state = AppState()
        state.createSession(directory: "/Users/dev/my-project")
        #expect(state.sessions[0].name == "my-project")
    }

    @Test @MainActor func createSessionFallsBackToSessionNumber() {
        let state = AppState()
        // Home directory → "Session N"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        state.createSession(directory: home)
        #expect(state.sessions[0].name == "Session 1")
    }

    @Test @MainActor func createSessionExplicitNameOverridesDirectory() {
        let state = AppState()
        state.createSession(name: "Custom", directory: "/Users/dev/my-project")
        #expect(state.sessions[0].name == "Custom")
    }

    // MARK: - SessionInfo

    @Test func sessionInfoWithClaudeSessionId() {
        let session = SessionInfo(
            name: "resume",
            workingDirectory: "/tmp",
            claudeSessionId: "abc-123"
        )
        #expect(session.claudeSessionId == "abc-123")
        #expect(!session.isWorktreeSession)
    }

    @Test func sessionInfoCreatedAtIsRecent() {
        let before = Date()
        let session = SessionInfo(name: "Test", workingDirectory: "/tmp")
        let after = Date()
        #expect(session.createdAt >= before)
        #expect(session.createdAt <= after)
    }
}
