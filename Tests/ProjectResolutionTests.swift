import Testing
import Foundation
@testable import Canopy

/// Tests for Project methods that resolve settings with global fallback.
@Suite("Project Resolution")
struct ProjectResolutionTests {

    // MARK: - shouldAutoStartClaude

    @Test func autoStartFallsBackToGlobal() {
        let project = Project(name: "test", repositoryPath: "/tmp")
        var settings = CanopySettings()

        settings.autoStartClaude = true
        #expect(project.shouldAutoStartClaude(globalSettings: settings) == true)

        settings.autoStartClaude = false
        #expect(project.shouldAutoStartClaude(globalSettings: settings) == false)
    }

    @Test func autoStartProjectOverridesGlobal() {
        let projectOn = Project(
            name: "on", repositoryPath: "/tmp",
            autoStartClaude: true
        )
        let projectOff = Project(
            name: "off", repositoryPath: "/tmp",
            autoStartClaude: false
        )
        var settings = CanopySettings()
        settings.autoStartClaude = false

        #expect(projectOn.shouldAutoStartClaude(globalSettings: settings) == true)
        #expect(projectOff.shouldAutoStartClaude(globalSettings: settings) == false)
    }

    // MARK: - resolvedClaudeCommand

    @Test func claudeCommandFallsBackToGlobal() {
        let project = Project(name: "test", repositoryPath: "/tmp")
        var settings = CanopySettings()
        settings.claudeFlags = "--model opus"

        #expect(project.resolvedClaudeCommand(globalSettings: settings) == "claude --model opus")
    }

    @Test func claudeCommandProjectOverridesGlobal() {
        let project = Project(
            name: "test", repositoryPath: "/tmp",
            claudeFlags: "--model haiku"
        )
        var settings = CanopySettings()
        settings.claudeFlags = "--model opus"

        #expect(project.resolvedClaudeCommand(globalSettings: settings) == "claude --model haiku")
    }

    @Test func claudeCommandEmptyFlags() {
        let project = Project(
            name: "test", repositoryPath: "/tmp",
            claudeFlags: "   "
        )
        let settings = CanopySettings()

        #expect(project.resolvedClaudeCommand(globalSettings: settings) == "claude")
    }

    @Test func claudeCommandNoFlagsGlobally() {
        let project = Project(name: "test", repositoryPath: "/tmp")
        var settings = CanopySettings()
        settings.claudeFlags = ""

        #expect(project.resolvedClaudeCommand(globalSettings: settings) == "claude")
    }

    // MARK: - Forward-Compatible Decoding

    @Test func decodesWithMissingOptionalFields() throws {
        // Simulates loading a project saved by an older version
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "name": "legacy-project",
            "repositoryPath": "/old/repo"
        }
        """
        let data = json.data(using: .utf8)!
        let project = try JSONDecoder().decode(Project.self, from: data)

        #expect(project.name == "legacy-project")
        #expect(project.filesToCopy == [".env", ".env.local"])
        #expect(project.symlinkPaths == [])
        #expect(project.setupCommands == [])
        #expect(project.worktreeBaseDir == nil)
        #expect(project.autoStartClaude == nil)
        #expect(project.claudeFlags == nil)
    }

    @Test func decodesWithPartialFields() throws {
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "name": "partial",
            "repositoryPath": "/repo",
            "symlinkPaths": ["node_modules"],
            "autoStartClaude": false
        }
        """
        let data = json.data(using: .utf8)!
        let project = try JSONDecoder().decode(Project.self, from: data)

        #expect(project.symlinkPaths == ["node_modules"])
        #expect(project.autoStartClaude == false)
        #expect(project.filesToCopy == [".env", ".env.local"]) // default
        #expect(project.claudeFlags == nil) // absent
    }

    @Test func encodesAllFields() throws {
        let project = Project(
            name: "full",
            repositoryPath: "/repo",
            filesToCopy: [".env"],
            symlinkPaths: ["nm"],
            setupCommands: ["npm i"],
            autoStartClaude: true,
            claudeFlags: "--verbose"
        )

        let data = try JSONEncoder().encode(project)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["autoStartClaude"] as? Bool == true)
        #expect(json["claudeFlags"] as? String == "--verbose")
        #expect(json["setupCommands"] as? [String] == ["npm i"])
    }
}
