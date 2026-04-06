import Testing
import Foundation
@testable import Canopy

@Suite("AppState")
struct AppStateTests {

    // MARK: - Session Management

    @Test @MainActor func createSession() {
        let state = AppState()
        state.createSession(name: "Test", directory: "/tmp")

        #expect(state.sessions.count == 1)
        #expect(state.sessions[0].name == "Test")
        #expect(state.sessions[0].workingDirectory == "/tmp")
        #expect(state.activeSessionId == state.sessions[0].id)
    }

    @Test @MainActor func createSessionDefaultName() {
        let state = AppState()
        state.createSession()
        #expect(state.sessions[0].name == "Session 1")

        state.createSession()
        #expect(state.sessions[1].name == "Session 2")
    }

    @Test @MainActor func createSessionDefaultDirectory() {
        let state = AppState()
        state.createSession()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(state.sessions[0].workingDirectory == home)
    }

    @Test @MainActor func newSessionBecomesActive() {
        let state = AppState()
        state.createSession(name: "First")
        let firstId = state.activeSessionId

        state.createSession(name: "Second")
        #expect(state.activeSessionId != firstId)
        #expect(state.sessions.count == 2)
    }

    @Test @MainActor func activeSession() {
        let state = AppState()
        state.createSession(name: "Test")
        #expect(state.activeSession?.name == "Test")
    }

    @Test @MainActor func activeSessionNilWhenEmpty() {
        let state = AppState()
        #expect(state.activeSession == nil)
    }

    @Test @MainActor func closeSession() {
        let state = AppState()
        state.settings.confirmBeforeClosing = false
        state.createSession(name: "A")
        state.createSession(name: "B")
        let idA = state.sessions[0].id

        state.closeSession(id: idA)

        #expect(state.sessions.count == 1)
        #expect(state.sessions[0].name == "B")
    }

    @Test @MainActor func closeSessionWithForce() {
        let state = AppState()
        state.createSession(name: "A")
        state.createSession(name: "B")
        let idA = state.sessions[0].id

        state.closeSession(id: idA, force: true)

        #expect(state.sessions.count == 1)
        #expect(state.sessions[0].name == "B")
    }

    @Test @MainActor func closeSessionShowsConfirmation() {
        let state = AppState()
        state.settings.confirmBeforeClosing = true
        state.createSession(name: "A")
        let idA = state.sessions[0].id

        state.closeSession(id: idA)

        // Should not actually close — should show confirmation
        #expect(state.sessions.count == 1)
        #expect(state.showCloseConfirmation == true)
        #expect(state.pendingCloseSessionId == idA)

        // Now confirm
        state.performCloseSession(id: idA)
        #expect(state.sessions.isEmpty)
    }

    @Test @MainActor func closeActiveSessionSwitchesToLast() {
        let state = AppState()
        state.settings.confirmBeforeClosing = false
        state.createSession(name: "A")
        state.createSession(name: "B")
        state.createSession(name: "C")
        let idC = state.sessions[2].id
        let idB = state.sessions[1].id

        state.closeSession(id: idC)
        #expect(state.activeSessionId == idB)
    }

    @Test @MainActor func closeLastSessionClearsActive() {
        let state = AppState()
        state.settings.confirmBeforeClosing = false
        state.createSession(name: "Only")
        let id = state.sessions[0].id

        state.closeSession(id: id)
        #expect(state.sessions.isEmpty)
        #expect(state.activeSessionId == nil)
    }

    @Test @MainActor func closeNonActiveKeepsActive() {
        let state = AppState()
        state.settings.confirmBeforeClosing = false
        state.createSession(name: "A")
        state.createSession(name: "B")
        let idA = state.sessions[0].id
        let idB = state.sessions[1].id

        state.closeSession(id: idA)
        #expect(state.activeSessionId == idB)
    }

    @Test @MainActor func renameSession() {
        let state = AppState()
        state.createSession(name: "Old")
        let id = state.sessions[0].id

        state.renameSession(id: id, to: "New")
        #expect(state.sessions[0].name == "New")
    }

    @Test @MainActor func renameNonexistentDoesNothing() {
        let state = AppState()
        state.createSession(name: "Original")
        state.renameSession(id: UUID(), to: "Nope")
        #expect(state.sessions[0].name == "Original")
    }

    // MARK: - Session Reordering

    @Test @MainActor func moveSessionsInProject() {
        let state = AppState()
        let project = Project(name: "proj", repositoryPath: "/tmp/proj")
        state.addProject(project)

        let s1 = SessionInfo(name: "A", workingDirectory: "/a", projectId: project.id)
        let s2 = SessionInfo(name: "B", workingDirectory: "/b", projectId: project.id)
        let s3 = SessionInfo(name: "C", workingDirectory: "/c", projectId: project.id)
        state.sessions = [s1, s2, s3]

        state.moveSessionsInProject(project.id, from: IndexSet(integer: 0), to: 3)

        let names = state.sessions.map(\.name)
        #expect(names == ["B", "C", "A"])
    }

    @Test @MainActor func moveSessionsPreservesOtherSessions() {
        let state = AppState()
        let project = Project(name: "proj", repositoryPath: "/tmp/proj")
        state.addProject(project)

        let plain = SessionInfo(name: "Plain", workingDirectory: "/plain")
        let s1 = SessionInfo(name: "A", workingDirectory: "/a", projectId: project.id)
        let s2 = SessionInfo(name: "B", workingDirectory: "/b", projectId: project.id)
        state.sessions = [plain, s1, s2]

        state.moveSessionsInProject(project.id, from: IndexSet(integer: 0), to: 2)

        #expect(state.sessions[0].name == "Plain")
        #expect(state.sessions[1].name == "B")
        #expect(state.sessions[2].name == "A")
    }

    // MARK: - Project Management

    @Test @MainActor func addProject() {
        let state = AppState()
        state.addProject(Project(name: "test", repositoryPath: "/tmp/test"))
        #expect(state.projects.count == 1)
        #expect(state.projects[0].name == "test")
    }

    @Test @MainActor func removeProject() {
        let state = AppState()
        let project = Project(name: "test", repositoryPath: "/tmp/test")
        state.addProject(project)
        state.removeProject(id: project.id)
        #expect(state.projects.isEmpty)
    }

    @Test @MainActor func updateProject() {
        let state = AppState()
        var project = Project(name: "old", repositoryPath: "/tmp")
        state.addProject(project)

        project.name = "new"
        state.updateProject(project)
        #expect(state.projects[0].name == "new")
    }

    @Test @MainActor func updateNonexistentDoesNothing() {
        let state = AppState()
        let project = Project(name: "ghost", repositoryPath: "/tmp")
        state.updateProject(project)
        #expect(state.projects.isEmpty)
    }

    // MARK: - SessionInfo

    @Test func sessionInfoPlain() {
        let session = SessionInfo(name: "Test", workingDirectory: "/tmp")
        #expect(session.projectId == nil)
        #expect(session.branchName == nil)
        #expect(!session.isWorktreeSession)
    }

    @Test func sessionInfoWorktree() {
        let session = SessionInfo(
            name: "feat/auth",
            workingDirectory: "/tmp/wt",
            projectId: UUID(),
            branchName: "feat/auth",
            worktreePath: "/tmp/wt"
        )
        #expect(session.projectId != nil)
        #expect(session.isWorktreeSession)
        #expect(session.branchName == "feat/auth")
    }

    @Test func sessionInfoUniqueIds() {
        let a = SessionInfo(name: "A", workingDirectory: "/a")
        let b = SessionInfo(name: "A", workingDirectory: "/a")
        #expect(a.id != b.id)
    }
}
