import Testing
import Foundation
@testable import Canopy

@Suite("Project Model")
struct ProjectTests {

    // MARK: - Initialization

    @Test func defaultInit() {
        let project = Project(name: "myapp", repositoryPath: "/Users/dev/myapp")
        #expect(project.name == "myapp")
        #expect(project.repositoryPath == "/Users/dev/myapp")
        #expect(project.filesToCopy == [".env", ".env.local"])
        #expect(project.symlinkPaths.isEmpty)
        #expect(project.setupCommands.isEmpty)
        #expect(project.worktreeBaseDir == nil)
    }

    @Test func customInit() {
        let project = Project(
            name: "webapp",
            repositoryPath: "/Users/dev/webapp",
            filesToCopy: [".env", ".env.test"],
            symlinkPaths: ["node_modules"],
            setupCommands: ["npm install"]
        )
        #expect(project.filesToCopy == [".env", ".env.test"])
        #expect(project.symlinkPaths == ["node_modules"])
        #expect(project.setupCommands == ["npm install"])
    }

    @Test func uniqueIds() {
        let a = Project(name: "a", repositoryPath: "/a")
        let b = Project(name: "a", repositoryPath: "/a")
        #expect(a.id != b.id)
    }

    // MARK: - Worktree Base Directory

    @Test func resolvedWorktreeBaseDirDefault() {
        let project = Project(name: "myapp", repositoryPath: "/Users/dev/myapp")
        #expect(project.resolvedWorktreeBaseDir == "/Users/dev/canopy-worktrees/myapp")
    }

    @Test func resolvedWorktreeBaseDirCustom() {
        var project = Project(name: "myapp", repositoryPath: "/Users/dev/myapp")
        project.worktreeBaseDir = "/tmp/custom-worktrees"
        #expect(project.resolvedWorktreeBaseDir == "/tmp/custom-worktrees")
    }

    @Test func resolvedWorktreeBaseDirIgnoresEmpty() {
        var project = Project(name: "myapp", repositoryPath: "/Users/dev/myapp")
        project.worktreeBaseDir = ""
        #expect(project.resolvedWorktreeBaseDir == "/Users/dev/canopy-worktrees/myapp")
    }

    // MARK: - Codable

    @Test func codableRoundTrip() throws {
        let original = Project(
            name: "test-project",
            repositoryPath: "/path/to/repo",
            filesToCopy: [".env", ".env.local"],
            symlinkPaths: ["node_modules", ".venv"],
            setupCommands: ["npm install"]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Project.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.repositoryPath == original.repositoryPath)
        #expect(decoded.filesToCopy == original.filesToCopy)
        #expect(decoded.symlinkPaths == original.symlinkPaths)
        #expect(decoded.setupCommands == original.setupCommands)
    }

    @Test func codableArrayRoundTrip() throws {
        let projects = [
            Project(name: "a", repositoryPath: "/a"),
            Project(name: "b", repositoryPath: "/b", filesToCopy: [".env"]),
        ]

        let data = try JSONEncoder().encode(projects)
        let decoded = try JSONDecoder().decode([Project].self, from: data)

        #expect(decoded.count == 2)
        #expect(decoded[0].name == "a")
        #expect(decoded[1].filesToCopy == [".env"])
    }
}
