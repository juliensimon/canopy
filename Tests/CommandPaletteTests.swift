import Testing
import Foundation
@testable import Canopy

@Suite("CommandPalette")
struct CommandPaletteTests {

    /// An AppState whose persistence is confined to a throwaway directory.
    /// A default-constructed AppState writes to the developer's real
    /// ~/.config/canopy -- see ConfigIsolationGuardTests.
    ///
    /// ponytail: the directories are left in place under one parent rather
    /// than cleaned per test; NSTemporaryDirectory is periodically cleared,
    /// and threading a defer through every call site here buys tidiness at
    /// the cost of restructuring tests that are not otherwise changing.
    @MainActor
    private func isolatedAppState() -> AppState {
        AppState(configDir: NSTemporaryDirectory()
            + "canopy-isolated-tests/\(UUID().uuidString)")
    }


    @Test @MainActor func generateItemsIncludesSessions() {
        let state = isolatedAppState()
        state.createSession(name: "my-feature", directory: "/tmp")
        let items = CommandPaletteItem.generate(from: state)
        let sessionItems = items.filter { $0.kind == .session }
        #expect(sessionItems.count == 1)
        #expect(sessionItems[0].title == "my-feature")
    }

    @Test @MainActor func generateItemsIncludesProjects() {
        let state = isolatedAppState()
        var project = Project(name: "MyApp", repositoryPath: "/tmp/myapp")
        project.colorIndex = 0
        state.projects.append(project)
        let items = CommandPaletteItem.generate(from: state)
        let projectItems = items.filter { $0.kind == .project }
        #expect(projectItems.count == 1)
        #expect(projectItems[0].title == "MyApp")
    }

    @Test @MainActor func generateItemsIncludesActions() {
        let state = isolatedAppState()
        let items = CommandPaletteItem.generate(from: state)
        let actionItems = items.filter { $0.kind == .action }
        #expect(actionItems.count >= 3)
    }

    @Test @MainActor func filterBySubstring() {
        let state = isolatedAppState()
        state.createSession(name: "auth-feature", directory: "/tmp")
        state.createSession(name: "billing-fix", directory: "/tmp")
        let items = CommandPaletteItem.generate(from: state)
        let filtered = CommandPaletteItem.filter(items, query: "auth")
        #expect(filtered.count >= 1)
        #expect(filtered.first?.title == "auth-feature")
    }

    @Test @MainActor func filterCaseInsensitive() {
        let state = isolatedAppState()
        state.createSession(name: "MyProject", directory: "/tmp")
        let items = CommandPaletteItem.generate(from: state)
        let filtered = CommandPaletteItem.filter(items, query: "myproject")
        #expect(filtered.contains { $0.title == "MyProject" })
    }

    @Test @MainActor func filterEmptyQueryReturnsAll() {
        let state = isolatedAppState()
        state.createSession(name: "test", directory: "/tmp")
        let items = CommandPaletteItem.generate(from: state)
        let filtered = CommandPaletteItem.filter(items, query: "")
        #expect(filtered.count == items.count)
    }
}
