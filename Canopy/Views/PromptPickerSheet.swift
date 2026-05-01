import SwiftUI

struct PromptPickerSheet: View {
    let session: SessionInfo
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""

    private var filtered: [SavedPrompt] {
        guard !searchText.isEmpty else { return appState.prompts }
        let q = searchText.lowercased()
        return appState.prompts.filter {
            $0.title.lowercased().contains(q) || $0.body.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search prompts…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(12)

            Divider()

            if filtered.isEmpty {
                emptyState
            } else {
                List(filtered) { prompt in
                    Button(action: { send(prompt) }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prompt.title.isEmpty ? "Untitled" : prompt.title)
                                .font(.system(size: 13, weight: .medium))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(prompt.body)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 400, height: 320)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            if appState.prompts.isEmpty {
                Text("No prompts yet.")
                    .foregroundStyle(.secondary)
                Text("Add prompts in Settings → Prompt Library.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("No results for \"\(searchText)\".")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func send(_ prompt: SavedPrompt) {
        let project = appState.projects.first(where: { $0.id == session.projectId })
        let dir = (session.workingDirectory as NSString).lastPathComponent
        let resolved = resolvePrompt(
            prompt.body,
            branchName: session.branchName,
            projectName: project?.name,
            dir: dir
        )
        appState.terminalSessions[session.id]?.sendCommand(resolved)
        dismiss()
    }
}
