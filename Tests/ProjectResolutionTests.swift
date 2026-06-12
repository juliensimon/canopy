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
        settings.sandboxBackend = .dockerSbx

        #expect(project.resolvedClaudeCommand(globalSettings: settings) == "sbx run claude -- --permission-mode auto")
    }

    @Test func claudeCommandProjectOverridesSandbox() {
        let project = Project(
            name: "test", repositoryPath: "/tmp",
            sandboxBackend: .off
        )
        var settings = CanopySettings()
        settings.sandboxBackend = .dockerSbx

        #expect(project.resolvedClaudeCommand(globalSettings: settings) == "claude --permission-mode auto")
    }

    @Test func claudeCommandProjectEnablesSandbox() {
        let project = Project(
            name: "test", repositoryPath: "/tmp",
            sandboxBackend: .dockerSbx,
            sbxFlags: "--memory 16g"
        )
        let settings = CanopySettings()

        #expect(project.resolvedClaudeCommand(globalSettings: settings) == "sbx run --memory 16g claude -- --permission-mode auto")
    }

    @Test func claudeCommandProjectSelectsAppleContainer() {
        let project = Project(
            name: "test", repositoryPath: "/tmp",
            sandboxBackend: .appleContainer,
            containerImage: "project-image"
        )
        let settings = CanopySettings()

        let command = project.resolvedClaudeCommand(globalSettings: settings)
        #expect(command.contains("container run"))
        #expect(command.contains(#"--workdir "$PWD" project-image sh -c"#))
        #expect(command.contains(#"exec claude --permission-mode auto "$@""#))
    }

    @Test func appleContainerImageFallsBackToGlobal() {
        // Project opts into the container backend but inherits the global image.
        let project = Project(
            name: "test", repositoryPath: "/tmp",
            sandboxBackend: .appleContainer
        )
        var settings = CanopySettings()
        settings.containerImage = "global-image"
        settings.containerFlags = "--memory 8g"

        let command = project.resolvedClaudeCommand(globalSettings: settings)
        #expect(command.contains(" --memory 8g global-image sh -c"))
    }

    @Test func claudeCommandSandboxWithResume() {
        // When sandbox is on, --resume still lands after -- (passed to claude, not sbx)
        let project = Project(name: "test", repositoryPath: "/tmp", sandboxBackend: .dockerSbx)
        let settings = CanopySettings()

        var command = project.resolvedClaudeCommand(globalSettings: settings)
        command += " --resume abc-123"

        #expect(command == "sbx run claude -- --permission-mode auto --resume abc-123")
    }

    @Test func sandboxResumeSkippedWhenDockerSbx() {
        // Simulates MainWindow logic: --resume is not appended for the sbx
        // backend because session files are ephemeral inside its microVM.
        let project = Project(name: "test", repositoryPath: "/tmp", sandboxBackend: .dockerSbx)
        let settings = CanopySettings()

        let backend = project.resolvedSandboxBackend(globalSettings: settings)
        var command = project.resolvedClaudeCommand(globalSettings: settings)
        let sessionId = "277f18de-ba7a-440e-aaf4-66987b38f08d"
        if backend.supportsResume {
            command += " --resume \(sessionId)"
        }

        // Resume must NOT be appended
        #expect(!command.contains("--resume"))
        #expect(command == "sbx run claude -- --permission-mode auto")
    }

    @Test func sandboxResumeAppendedWhenAppleContainer() {
        // Apple container sessions ARE resumable: ~/.claude is bind-mounted
        // from the host, so session JSONLs persist across container runs.
        let project = Project(
            name: "test", repositoryPath: "/tmp",
            sandboxBackend: .appleContainer,
            containerImage: "canopy-claude"
        )
        let settings = CanopySettings()

        let backend = project.resolvedSandboxBackend(globalSettings: settings)
        var command = project.resolvedClaudeCommand(globalSettings: settings)
        let sessionId = "277f18de-ba7a-440e-aaf4-66987b38f08d"
        if backend.supportsResume {
            command += " --resume \(sessionId)"
        }

        // Appended args become "$@" positionals forwarded to claude.
        #expect(command.hasSuffix("' claude --resume \(sessionId)"))
    }

    @Test func sandboxResumeAppendedWhenNotSandboxed() {
        // Simulates MainWindow logic: --resume IS appended when not sandboxed
        let project = Project(name: "test", repositoryPath: "/tmp")
        let settings = CanopySettings()

        let backend = project.resolvedSandboxBackend(globalSettings: settings)
        var command = project.resolvedClaudeCommand(globalSettings: settings)
        let sessionId = "277f18de-ba7a-440e-aaf4-66987b38f08d"
        if backend.supportsResume {
            command += " --resume \(sessionId)"
        }

        #expect(command.contains("--resume"))
        #expect(command == "claude --permission-mode auto --resume \(sessionId)")
    }

    @Test func sandboxResolutionProjectNilFallsToGlobal() {
        // sandboxBackend == nil on project means use global setting
        let project = Project(name: "test", repositoryPath: "/tmp")
        var settings = CanopySettings()

        settings.sandboxBackend = .off
        #expect(project.resolvedSandboxBackend(globalSettings: settings) == .off)

        settings.sandboxBackend = .appleContainer
        #expect(project.resolvedSandboxBackend(globalSettings: settings) == .appleContainer)
    }

    @Test func sandboxResolutionProjectOverridesGlobal() {
        let projectOn = Project(name: "on", repositoryPath: "/tmp", sandboxBackend: .dockerSbx)
        let projectOff = Project(name: "off", repositoryPath: "/tmp", sandboxBackend: .off)
        var settings = CanopySettings()
        settings.sandboxBackend = .off

        #expect(projectOn.resolvedSandboxBackend(globalSettings: settings) == .dockerSbx)
        #expect(projectOff.resolvedSandboxBackend(globalSettings: settings) == .off)
    }

    @Test func sandboxEmptyClaudeFlagsStillHasSeparator() {
        // Even with no claude flags, -- must be present so appended flags
        // (like --resume from MainWindow) are passed to claude, not sbx.
        var settings = CanopySettings()
        settings.sandboxBackend = .dockerSbx
        settings.claudeFlags = ""

        #expect(settings.claudeCommand == "sbx run claude --")
    }

    // MARK: - Override Sheet Seeding

    @Test func overrideDefaultsSeedFromGlobalsWhenProjectHasNoOverrides() {
        // Enabling "Override global Claude settings" must start from the
        // EFFECTIVE values. Seeding autoStart=false / flags="" used to write
        // unintended overrides that silently disabled claude auto-start when
        // the user only wanted to change the sandbox backend.
        var settings = CanopySettings()
        settings.autoStartClaude = true
        settings.claudeFlags = "--permission-mode auto"
        settings.sandboxBackend = .dockerSbx
        settings.sbxFlags = "--memory 8g"
        let project = Project(name: "p", repositoryPath: "/tmp")

        let seeds = ClaudeOverrideDefaults(project: project, settings: settings)
        #expect(seeds.autoStartClaude == true)
        #expect(seeds.claudeFlags == "--permission-mode auto")
        #expect(seeds.sandboxBackend == .dockerSbx)
        #expect(seeds.sbxFlags == "--memory 8g")
    }

    @Test func overrideDefaultsKeepExistingProjectOverrides() {
        var settings = CanopySettings()
        settings.autoStartClaude = true
        let project = Project(
            name: "p", repositoryPath: "/tmp",
            autoStartClaude: false,
            claudeFlags: "--model haiku",
            sandboxBackend: .appleContainer
        )

        let seeds = ClaudeOverrideDefaults(project: project, settings: settings)
        #expect(seeds.autoStartClaude == false)
        #expect(seeds.claudeFlags == "--model haiku")
        #expect(seeds.sandboxBackend == .appleContainer)
    }

    @Test func overrideDefaultsForNewProjectUseGlobals() {
        var settings = CanopySettings()
        settings.autoStartClaude = false
        settings.claudeFlags = "--verbose"

        let seeds = ClaudeOverrideDefaults(project: nil, settings: settings)
        #expect(seeds.autoStartClaude == false)
        #expect(seeds.claudeFlags == "--verbose")
        #expect(seeds.sandboxBackend == .off)
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
        #expect(project.sandboxBackend == nil)
        #expect(project.sbxFlags == nil)
        #expect(project.containerImage == nil)
        #expect(project.containerFlags == nil)
    }

    @Test func legacyProjectUseSandboxMigratesToDockerSbx() throws {
        // Projects saved before the backend enum used a useSandbox boolean.
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "name": "legacy",
            "repositoryPath": "/repo",
            "useSandbox": true,
            "sbxFlags": "--memory 8g"
        }
        """
        let project = try JSONDecoder().decode(Project.self, from: json.data(using: .utf8)!)
        #expect(project.sandboxBackend == .dockerSbx)
        #expect(project.sbxFlags == "--memory 8g")
    }

    @Test func unknownBackendRawValueDecodesAsNilWithoutLosingProject() throws {
        // A projects.json written by a NEWER Canopy must not throw: the
        // loader's try? fallback would silently drop ALL projects.
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "name": "future",
            "repositoryPath": "/repo",
            "sandboxBackend": "futureBackend"
        }
        """
        let project = try JSONDecoder().decode(Project.self, from: json.data(using: .utf8)!)
        #expect(project.sandboxBackend == nil)
        #expect(project.name == "future")
    }

    @Test func legacyProjectUseSandboxFalseMigratesToExplicitOff() throws {
        // useSandbox: false was an explicit per-project override (not nil),
        // so it must stay an override after migration.
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "name": "legacy",
            "repositoryPath": "/repo",
            "useSandbox": false
        }
        """
        let project = try JSONDecoder().decode(Project.self, from: json.data(using: .utf8)!)
        #expect(project.sandboxBackend == .off)
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
            sandboxBackend: .dockerSbx,
            sbxFlags: "--memory 8g",
            containerImage: "img",
            containerFlags: "--cpus 4"
        )

        let data = try JSONEncoder().encode(project)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["autoStartClaude"] as? Bool == true)
        #expect(json["claudeFlags"] as? String == "--verbose")
        #expect(json["setupCommands"] as? [String] == ["npm i"])
        #expect(json["sandboxBackend"] as? String == "dockerSbx")
        #expect(json["sbxFlags"] as? String == "--memory 8g")
        #expect(json["containerImage"] as? String == "img")
        #expect(json["containerFlags"] as? String == "--cpus 4")
    }
}
