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

    // MARK: - Sandbox Resolution

    @Test func claudeCommandSandboxFallsBackToGlobal() {
        let project = Project(name: "test", repositoryPath: "/tmp")
        var settings = CanopySettings()
        settings.useSandbox = true

        #expect(project.resolvedClaudeCommand(globalSettings: settings) == "sbx run claude -- --permission-mode auto")
    }

    @Test func claudeCommandProjectOverridesSandbox() {
        let project = Project(
            name: "test", repositoryPath: "/tmp",
            useSandbox: false
        )
        var settings = CanopySettings()
        settings.useSandbox = true

        #expect(project.resolvedClaudeCommand(globalSettings: settings) == "claude --permission-mode auto")
    }

    @Test func claudeCommandProjectEnablesSandbox() {
        let project = Project(
            name: "test", repositoryPath: "/tmp",
            useSandbox: true,
            sbxFlags: "--memory 16g"
        )
        let settings = CanopySettings()

        #expect(project.resolvedClaudeCommand(globalSettings: settings) == "sbx run --memory 16g claude -- --permission-mode auto")
    }

    @Test func claudeCommandSandboxWithResume() {
        // When sandbox is on, --resume still lands after -- (passed to claude, not sbx)
        let project = Project(name: "test", repositoryPath: "/tmp", useSandbox: true)
        let settings = CanopySettings()

        var command = project.resolvedClaudeCommand(globalSettings: settings)
        command += " --resume abc-123"

        #expect(command == "sbx run claude -- --permission-mode auto --resume abc-123")
    }

    @Test func sandboxResumeSkippedWhenSandboxed() {
        // Simulates MainWindow logic: --resume is not appended in sandbox mode
        // because session files are ephemeral inside the microVM.
        let project = Project(name: "test", repositoryPath: "/tmp", useSandbox: true)
        let settings = CanopySettings()

        let isSandboxed = project.useSandbox ?? settings.useSandbox
        var command = project.resolvedClaudeCommand(globalSettings: settings)
        let sessionId = "277f18de-ba7a-440e-aaf4-66987b38f08d"
        if !isSandboxed {
            command += " --resume \(sessionId)"
        }

        // Resume must NOT be appended
        #expect(!command.contains("--resume"))
        #expect(command == "sbx run claude -- --permission-mode auto")
    }

    @Test func sandboxResumeAppendedWhenNotSandboxed() {
        // Simulates MainWindow logic: --resume IS appended when not sandboxed
        let project = Project(name: "test", repositoryPath: "/tmp")
        let settings = CanopySettings()

        let isSandboxed = project.useSandbox ?? settings.useSandbox
        var command = project.resolvedClaudeCommand(globalSettings: settings)
        let sessionId = "277f18de-ba7a-440e-aaf4-66987b38f08d"
        if !isSandboxed {
            command += " --resume \(sessionId)"
        }

        #expect(command.contains("--resume"))
        #expect(command == "claude --permission-mode auto --resume \(sessionId)")
    }

    @Test func sandboxResolutionProjectNilFallsToGlobal() {
        // useSandbox == nil on project means use global setting
        let project = Project(name: "test", repositoryPath: "/tmp")
        var settings = CanopySettings()

        settings.useSandbox = false
        #expect((project.useSandbox ?? settings.useSandbox) == false)

        settings.useSandbox = true
        #expect((project.useSandbox ?? settings.useSandbox) == true)
    }

    @Test func sandboxResolutionProjectOverridesGlobal() {
        let projectOn = Project(name: "on", repositoryPath: "/tmp", useSandbox: true)
        let projectOff = Project(name: "off", repositoryPath: "/tmp", useSandbox: false)
        var settings = CanopySettings()
        settings.useSandbox = false

        #expect((projectOn.useSandbox ?? settings.useSandbox) == true)
        #expect((projectOff.useSandbox ?? settings.useSandbox) == false)
    }

    @Test func sandboxEmptyClaudeFlagsStillHasSeparator() {
        // Even with no claude flags, -- must be present so appended flags
        // (like --resume from MainWindow) are passed to claude, not sbx.
        var settings = CanopySettings()
        settings.useSandbox = true
        settings.claudeFlags = ""

        #expect(settings.claudeCommand == "sbx run claude --")
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
        #expect(project.useSandbox == nil)
        #expect(project.sbxFlags == nil)
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
            claudeFlags: "--verbose",
            useSandbox: true,
            sbxFlags: "--memory 8g"
        )

        let data = try JSONEncoder().encode(project)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["autoStartClaude"] as? Bool == true)
        #expect(json["claudeFlags"] as? String == "--verbose")
        #expect(json["setupCommands"] as? [String] == ["npm i"])
        #expect(json["useSandbox"] as? Bool == true)
        #expect(json["sbxFlags"] as? String == "--memory 8g")
    }
}
