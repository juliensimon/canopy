import Testing
import Foundation
@testable import Canopy

/// Per-session sandbox override: session → project → global resolution.
@Suite("Per-Session Sandbox")
@MainActor
struct SessionSandboxTests {

    /// Temp config dir so no test can touch the real ~/.config/canopy.
    private func makeState() -> AppState {
        AppState(configDir: NSTemporaryDirectory() + "canopy-test-\(UUID().uuidString)")
    }

    @Test func sessionOverrideWinsOverProjectAndGlobal() {
        let state = makeState()
        state.settings.sandboxBackend = .off
        let project = Project(name: "p", repositoryPath: "/tmp", sandboxBackend: .off)
        state.projects = [project]
        let session = SessionInfo(
            name: "s", workingDirectory: "/tmp",
            projectId: project.id,
            sandboxBackend: .appleContainer
        )

        #expect(state.sandboxBackend(for: session) == .appleContainer)
    }

    @Test func sessionWithoutOverrideFallsBackToProject() {
        let state = makeState()
        state.settings.sandboxBackend = .off
        let project = Project(name: "p", repositoryPath: "/tmp", sandboxBackend: .dockerSbx)
        state.projects = [project]
        let session = SessionInfo(name: "s", workingDirectory: "/tmp", projectId: project.id)

        #expect(state.sandboxBackend(for: session) == .dockerSbx)
    }

    @Test func plainSessionFallsBackToGlobal() {
        let state = makeState()
        state.settings.sandboxBackend = .appleContainer
        let session = SessionInfo(name: "s", workingDirectory: "/tmp")

        #expect(state.sandboxBackend(for: session) == .appleContainer)
    }

    @Test func claudeCommandUsesSessionBackendWithProjectFlags() {
        // The override changes only the backend; flags and image still
        // resolve through the normal project → global chain.
        let state = makeState()
        state.settings.sandboxBackend = .off
        state.settings.containerImage = "global-image"
        let project = Project(name: "p", repositoryPath: "/tmp", claudeFlags: "--model haiku")
        state.projects = [project]
        let session = SessionInfo(
            name: "s", workingDirectory: "/tmp",
            projectId: project.id,
            sandboxBackend: .appleContainer
        )

        let command = state.claudeCommand(for: session)
        #expect(command.hasPrefix("container run"))
        #expect(command.hasSuffix("global-image claude --model haiku"))
    }

    @Test func claudeCommandWithoutOverrideMatchesProjectResolution() {
        let state = makeState()
        state.settings.sandboxBackend = .dockerSbx
        let project = Project(name: "p", repositoryPath: "/tmp")
        state.projects = [project]
        let session = SessionInfo(name: "s", workingDirectory: "/tmp", projectId: project.id)

        #expect(state.claudeCommand(for: session)
            == project.resolvedClaudeCommand(globalSettings: state.settings))
    }

    @Test func legacySessionDecodesWithNilBackend() throws {
        // sessions.json entries saved before the field existed.
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "name": "old",
            "workingDirectory": "/tmp",
            "createdAt": 0
        }
        """
        let session = try JSONDecoder().decode(SessionInfo.self, from: json.data(using: .utf8)!)
        #expect(session.sandboxBackend == nil)
    }
}
