import Testing
import Foundation
@testable import Canopy

@Suite("CommandPalette")
struct CommandPaletteTests {

    @Test @MainActor func generateItemsIncludesSessions() {
        let state = AppState()
        state.createSession(name: "my-feature", directory: "/tmp")
        let items = CommandPaletteItem.generate(from: state)
        let sessionItems = items.filter { $0.kind == .session }
        #expect(sessionItems.count == 1)
        #expect(sessionItems[0].title == "my-feature")
    }

    @Test @MainActor func generateItemsIncludesProjects() {
        let state = AppState()
        var project = Project(name: "MyApp", repositoryPath: "/tmp/myapp")
        project.colorIndex = 0
        state.projects.append(project)
        let items = CommandPaletteItem.generate(from: state)
        let projectItems = items.filter { $0.kind == .project }
        #expect(projectItems.count == 1)
        #expect(projectItems[0].title == "MyApp")
    }

    @Test @MainActor func generateItemsIncludesActions() {
        let state = AppState()
        let items = CommandPaletteItem.generate(from: state)
        let actionItems = items.filter { $0.kind == .action }
        #expect(actionItems.count >= 3)
    }

    @Test @MainActor func filterBySubstring() {
        let state = AppState()
        state.createSession(name: "auth-feature", directory: "/tmp")
        state.createSession(name: "billing-fix", directory: "/tmp")
        let items = CommandPaletteItem.generate(from: state)
        let filtered = CommandPaletteItem.filter(items, query: "auth")
        #expect(filtered.count >= 1)
        #expect(filtered.first?.title == "auth-feature")
    }

    @Test @MainActor func filterCaseInsensitive() {
        let state = AppState()
        state.createSession(name: "MyProject", directory: "/tmp")
        let items = CommandPaletteItem.generate(from: state)
        let filtered = CommandPaletteItem.filter(items, query: "myproject")
        #expect(filtered.contains { $0.title == "MyProject" })
    }

    @Test @MainActor func filterEmptyQueryReturnsAll() {
        let state = AppState()
        state.createSession(name: "test", directory: "/tmp")
        let items = CommandPaletteItem.generate(from: state)
        let filtered = CommandPaletteItem.filter(items, query: "")
        #expect(filtered.count == items.count)
    }
}
