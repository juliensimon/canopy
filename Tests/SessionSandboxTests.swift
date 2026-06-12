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
        #expect(command.contains("container run"))
        #expect(command.contains(" global-image sh -c"))
        #expect(command.contains(#"exec claude --model haiku "$@""#))
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

    @Test func worktreeSessionMountsMainRepository() {
        // A worktree's .git file points at the main repo: without this
        // mount, every git command inside the container fails.
        let state = makeState()
        let project = Project(name: "p", repositoryPath: "/Users/x/dev/repo")
        state.projects = [project]
        let session = SessionInfo(
            name: "s", workingDirectory: "/Users/x/dev/canopy-worktrees/repo/feat",
            projectId: project.id,
            worktreePath: "/Users/x/dev/canopy-worktrees/repo/feat",
            sandboxBackend: .appleContainer
        )

        #expect(state.claudeCommand(for: session).contains(#"--volume "/Users/x/dev/repo":"/Users/x/dev/repo""#))
    }

    @Test func mainRepoSessionDoesNotDoubleMount() {
        // When the session runs IN the main repo, $PWD already mounts it;
        // a second identical mount risks the overlapping-mount failure.
        let state = makeState()
        let project = Project(name: "p", repositoryPath: "/Users/x/dev/repo")
        state.projects = [project]
        let session = SessionInfo(
            name: "s", workingDirectory: "/Users/x/dev/repo",
            projectId: project.id,
            sandboxBackend: .appleContainer
        )

        #expect(!state.claudeCommand(for: session).contains(#"--volume "/Users/x/dev/repo""#))
    }

    @Test func openWorktreeSessionStoresOverride() {
        // Reopening a worktree must be able to carry a sandbox override,
        // like createWorktreeSession -- otherwise the override is silently
        // dropped and claude runs with weaker isolation than chosen.
        let state = makeState()
        let project = Project(name: "p", repositoryPath: "/tmp")
        state.projects = [project]
        state.openWorktreeSession(project: project, worktreePath: "/tmp/wt", branch: "b", sandboxBackend: .appleContainer)

        #expect(state.sessions.first?.sandboxBackend == .appleContainer)
        #expect(state.sandboxBackend(for: state.sessions.first!) == .appleContainer)
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
