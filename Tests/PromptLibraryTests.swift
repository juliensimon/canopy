import Testing
import Foundation
@testable import Canopy

@Suite("PromptLibrary")
struct PromptLibraryTests {

    @Test func savedPromptHasExpectedDefaults() {
        let p = SavedPrompt(title: "T", body: "B")
        #expect(p.isStarred == false)
    }

    @Test func savedPromptCodableRoundTrip() throws {
        let id = UUID()
        let p = SavedPrompt(id: id, title: "My Prompt", body: "Do {{branch}}", isStarred: true)
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(SavedPrompt.self, from: data)
        #expect(decoded.id == id)
        #expect(decoded.title == "My Prompt")
        #expect(decoded.body == "Do {{branch}}")
        #expect(decoded.isStarred == true)
    }

    @Test func savedPromptArrayCodableRoundTrip() throws {
        let prompts = [
            SavedPrompt(title: "A", body: "Body A"),
            SavedPrompt(title: "B", body: "Body B", isStarred: true)
        ]
        let data = try JSONEncoder().encode(prompts)
        let decoded = try JSONDecoder().decode([SavedPrompt].self, from: data)
        #expect(decoded.count == 2)
        #expect(decoded[0].title == "A")
        #expect(decoded[1].isStarred == true)
    }

    // MARK: - resolvePrompt

    @Test func resolveBranch() {
        #expect(resolvePrompt("Fix {{branch}}", branchName: "main", projectName: nil, dir: "") == "Fix main")
    }

    @Test func resolveProject() {
        #expect(resolvePrompt("In {{project}}", branchName: nil, projectName: "MyApp", dir: "") == "In MyApp")
    }

    @Test func resolveDir() {
        #expect(resolvePrompt("At {{dir}}", branchName: nil, projectName: nil, dir: "canopy") == "At canopy")
    }

    @Test func resolveAllThree() {
        let result = resolvePrompt("{{branch}} in {{project}} at {{dir}}", branchName: "feat/x", projectName: "App", dir: "src")
        #expect(result == "feat/x in App at src")
    }

    @Test func resolveNilBranchBecomesEmpty() {
        #expect(resolvePrompt("{{branch}}", branchName: nil, projectName: nil, dir: "") == "")
    }

    @Test func resolveNilProjectBecomesEmpty() {
        #expect(resolvePrompt("{{project}}", branchName: nil, projectName: nil, dir: "") == "")
    }

    @Test func unknownTokenLeftAlone() {
        #expect(resolvePrompt("{{unknown}}", branchName: nil, projectName: nil, dir: "") == "{{unknown}}")
    }

    @Test func plainTextUnchanged() {
        #expect(resolvePrompt("Just text", branchName: "main", projectName: "App", dir: "src") == "Just text")
    }

    // MARK: - AppState persistence

    @Test @MainActor func loadPromptsReturnsEmptyWhenFileAbsent() {
        let tmpDir = NSTemporaryDirectory() + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }
        let state = AppState(configDir: tmpDir)
        state.loadPrompts()
        #expect(state.prompts.isEmpty)
    }

    @Test @MainActor func saveAndLoadPromptsRoundTrip() {
        let tmpDir = NSTemporaryDirectory() + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }
        let state = AppState(configDir: tmpDir)
        state.prompts = [SavedPrompt(title: "Hello", body: "{{branch}}", isStarred: true)]
        state.savePrompts()

        let state2 = AppState(configDir: tmpDir)
        state2.loadPrompts()
        #expect(state2.prompts.count == 1)
        #expect(state2.prompts[0].title == "Hello")
        #expect(state2.prompts[0].body == "{{branch}}")
        #expect(state2.prompts[0].isStarred == true)
    }
}
