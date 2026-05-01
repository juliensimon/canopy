import Testing
import Foundation
@testable import Canopy

@Suite("PromptLibrary")
struct PromptLibraryTests {

    @Test func savedPromptHasExpectedDefaults() {
        let p = SavedPrompt(title: "T", body: "B")
        #expect(p.isStarred == false)
        #expect(p.sortOrder == 0)
    }

    @Test func savedPromptCodableRoundTrip() throws {
        let id = UUID()
        let p = SavedPrompt(id: id, title: "My Prompt", body: "Do {{branch}}", isStarred: true, sortOrder: 3)
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(SavedPrompt.self, from: data)
        #expect(decoded.id == id)
        #expect(decoded.title == "My Prompt")
        #expect(decoded.body == "Do {{branch}}")
        #expect(decoded.isStarred == true)
        #expect(decoded.sortOrder == 3)
    }

    @Test func savedPromptArrayCodableRoundTrip() throws {
        let prompts = [
            SavedPrompt(title: "A", body: "Body A"),
            SavedPrompt(title: "B", body: "Body B", isStarred: true, sortOrder: 1)
        ]
        let data = try JSONEncoder().encode(prompts)
        let decoded = try JSONDecoder().decode([SavedPrompt].self, from: data)
        #expect(decoded.count == 2)
        #expect(decoded[0].title == "A")
        #expect(decoded[1].isStarred == true)
    }
}
