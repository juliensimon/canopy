import Foundation

struct SavedPrompt: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var body: String
    var isStarred: Bool = false
    var sortOrder: Int = 0
}

func resolvePrompt(_ body: String, branchName: String?, projectName: String?, dir: String) -> String {
    body
        .replacingOccurrences(of: "{{branch}}", with: branchName ?? "")
        .replacingOccurrences(of: "{{project}}", with: projectName ?? "")
        .replacingOccurrences(of: "{{dir}}", with: dir)
}
