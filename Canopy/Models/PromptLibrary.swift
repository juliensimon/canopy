import Foundation

struct SavedPrompt: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var body: String
    var isStarred: Bool = false
    var sortOrder: Int = 0
}
