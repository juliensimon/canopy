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
        let tmpDir = NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }
        let state = AppState(configDir: tmpDir)
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
        let tmpDir = NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }
        let state = AppState(configDir: tmpDir)
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

    @Test @MainActor func moveSession() {
        let state = AppState()
        state.createSession(name: "A", directory: "/tmp/a")
        state.createSession(name: "B", directory: "/tmp/b")
        state.createSession(name: "C", directory: "/tmp/c")

        state.moveSession(from: IndexSet(integer: 2), to: 0)

        #expect(state.sessions.map(\.name) == ["C", "A", "B"])
    }

    @Test @MainActor func moveSessionRevertsSortMode() {
        let state = AppState()
        state.createSession(name: "A", directory: "/tmp/a")
        state.createSession(name: "B", directory: "/tmp/b")
        state.tabSortMode = .name

        state.moveSession(from: IndexSet(integer: 1), to: 0)

        #expect(state.tabSortMode == .manual)
    }

    @Test @MainActor func swapSessions() {
        let state = AppState()
        state.createSession(name: "A", directory: "/tmp/a")
        state.createSession(name: "B", directory: "/tmp/b")
        state.createSession(name: "C", directory: "/tmp/c")
        let idA = state.sessions[0].id
        let idC = state.sessions[2].id

        state.swapSessions(idA, idC)

        #expect(state.sessions.map(\.name) == ["C", "B", "A"])
    }

    @Test @MainActor func swapSessionsRevertsSortMode() {
        let state = AppState()
        state.createSession(name: "A", directory: "/tmp/a")
        state.createSession(name: "B", directory: "/tmp/b")
        state.tabSortMode = .name
        let idA = state.sessions[0].id
        let idB = state.sessions[1].id

        state.swapSessions(idA, idB)

        #expect(state.tabSortMode == .manual)
    }

    // MARK: - Project Management

    @Test @MainActor func addProject() {
        let tmpDir = NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }
        let state = AppState(configDir: tmpDir)
        state.addProject(Project(name: "test", repositoryPath: "/tmp/test"))
        #expect(state.projects.count == 1)
        #expect(state.projects[0].name == "test")
    }

    @Test @MainActor func removeProject() {
        let tmpDir = NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }
        let state = AppState(configDir: tmpDir)
        let project = Project(name: "test", repositoryPath: "/tmp/test")
        state.addProject(project)
        state.removeProject(id: project.id)
        #expect(state.projects.isEmpty)
    }

    @Test @MainActor func updateProject() {
        let tmpDir = NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }
        let state = AppState(configDir: tmpDir)
        var project = Project(name: "old", repositoryPath: "/tmp")
        state.addProject(project)

        project.name = "new"
        state.updateProject(project)
        #expect(state.projects[0].name == "new")
    }

    @Test @MainActor func updateNonexistentDoesNothing() {
        let tmpDir = NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }
        let state = AppState(configDir: tmpDir)
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

    // MARK: - Sorted Insertion

    @Test @MainActor func newSessionInsertedInSortedPosition() {
        let state = AppState()
        state.createSession(name: "Apple", directory: "/tmp/a")
        state.createSession(name: "Cherry", directory: "/tmp/c")
        state.tabSortMode = .name

        state.createSession(name: "Banana", directory: "/tmp/b")

        // In name sort mode, the underlying array has Banana in sorted position
        #expect(state.sessions.map(\.name) == ["Apple", "Banana", "Cherry"])
    }

    @Test @MainActor func newSessionAppendsInManualMode() {
        let state = AppState()
        state.createSession(name: "Apple", directory: "/tmp/a")
        state.createSession(name: "Cherry", directory: "/tmp/c")
        state.tabSortMode = .manual

        state.createSession(name: "Banana", directory: "/tmp/b")

        #expect(state.sessions.map(\.name) == ["Apple", "Cherry", "Banana"])
    }

    // MARK: - Tab Sorting

    @Test @MainActor func defaultSortModeIsManual() {
        let state = AppState()
        #expect(state.tabSortMode == .manual)
    }

    @Test @MainActor func orderedSessionsManualReturnsInsertionOrder() {
        let state = AppState()
        state.createSession(name: "Zebra", directory: "/tmp/z")
        state.createSession(name: "Apple", directory: "/tmp/a")
        state.createSession(name: "Mango", directory: "/tmp/m")

        #expect(state.orderedSessions.map(\.name) == ["Zebra", "Apple", "Mango"])
    }

    @Test @MainActor func orderedSessionsSortedByName() {
        let state = AppState()
        state.createSession(name: "Zebra", directory: "/tmp/z")
        state.createSession(name: "Apple", directory: "/tmp/a")
        state.createSession(name: "Mango", directory: "/tmp/m")
        state.tabSortMode = .name

        #expect(state.orderedSessions.map(\.name) == ["Apple", "Mango", "Zebra"])
    }

    @Test @MainActor func orderedSessionsSortedByCreationDate() {
        let state = AppState()
        state.createSession(name: "First", directory: "/tmp/1")
        state.createSession(name: "Second", directory: "/tmp/2")
        state.createSession(name: "Third", directory: "/tmp/3")
        state.tabSortMode = .creationDate

        #expect(state.orderedSessions.map(\.name) == ["First", "Second", "Third"])
    }

    @Test @MainActor func orderedSessionsSortedByDirectory() {
        let state = AppState()
        state.createSession(name: "C", directory: "/tmp/zebra")
        state.createSession(name: "A", directory: "/tmp/apple")
        state.createSession(name: "B", directory: "/tmp/mango")
        state.tabSortMode = .workingDirectory

        #expect(state.orderedSessions.map(\.name) == ["A", "B", "C"])
    }

    @Test @MainActor func orderedSessionsSortedByProject() {
        let tmpDir = NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }
        let state = AppState(configDir: tmpDir)
        let projectA = Project(name: "Alpha", repositoryPath: "/tmp/alpha")
        let projectB = Project(name: "Beta", repositoryPath: "/tmp/beta")
        state.addProject(projectA)
        state.addProject(projectB)

        let s1 = SessionInfo(name: "B-session", workingDirectory: "/tmp/b", projectId: projectB.id)
        let s2 = SessionInfo(name: "A-session", workingDirectory: "/tmp/a", projectId: projectA.id)
        let s3 = SessionInfo(name: "Plain", workingDirectory: "/tmp/p")
        state.sessions = [s1, s2, s3]

        state.tabSortMode = .project

        let names = state.orderedSessions.map(\.name)
        #expect(names == ["A-session", "B-session", "Plain"])
    }

    @Test @MainActor func dragRevertsThenNewSessionAppends() {
        let state = AppState()
        state.createSession(name: "Banana", directory: "/tmp/b")
        state.createSession(name: "Apple", directory: "/tmp/a")
        state.tabSortMode = .name

        // orderedSessions is sorted
        #expect(state.orderedSessions.map(\.name) == ["Apple", "Banana"])

        // Swap reverts to manual
        let idA = state.sessions[0].id
        let idB = state.sessions[1].id
        state.swapSessions(idA, idB)
        #expect(state.tabSortMode == .manual)

        // New session appends (manual mode)
        state.createSession(name: "Cherry", directory: "/tmp/c")
        #expect(state.sessions.last?.name == "Cherry")
    }

    @Test @MainActor func cycleSortModes() {
        let state = AppState()
        let allModes = TabSortMode.allCases
        #expect(allModes.count == 5)
        #expect(allModes[0] == .manual)
        #expect(allModes[1] == .name)
        #expect(allModes[2] == .project)
        #expect(allModes[3] == .creationDate)
        #expect(allModes[4] == .workingDirectory)
    }

    // MARK: - Split Terminal

    @Test @MainActor func toggleSplitTerminalOpensAndCloses() {
        let state = AppState()
        state.createSession(name: "Test", directory: "/tmp")
        let sessionId = state.sessions[0].id

        #expect(!state.isSplitOpen(for: sessionId))

        state.toggleSplitTerminal(for: sessionId)
        #expect(state.isSplitOpen(for: sessionId))
        #expect(state.splitTerminalSessions[sessionId] != nil)

        state.toggleSplitTerminal(for: sessionId)
        #expect(!state.isSplitOpen(for: sessionId))
        #expect(state.splitTerminalSessions[sessionId] == nil)
    }

    @Test @MainActor func closingSessionClosesSplitTerminal() {
        let state = AppState()
        state.createSession(name: "Test", directory: "/tmp")
        let sessionId = state.sessions[0].id

        state.toggleSplitTerminal(for: sessionId)
        #expect(state.isSplitOpen(for: sessionId))

        state.performCloseSession(id: sessionId)
        #expect(!state.isSplitOpen(for: sessionId))
        #expect(state.splitTerminalSessions[sessionId] == nil)
    }

    @Test @MainActor func splitTerminalUsesSessionWorkingDirectory() {
        let state = AppState()
        state.createSession(name: "Test", directory: "/tmp/my-project")
        let sessionId = state.sessions[0].id

        state.toggleSplitTerminal(for: sessionId)
        #expect(state.splitTerminalSessions[sessionId]?.workingDirectory == "/tmp/my-project")
    }
}
