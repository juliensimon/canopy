import SwiftUI

struct PromptLibrarySettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var selectedId: UUID?
    @State private var editTitle = ""
    @State private var editBody = ""

    var body: some View {
        VStack(spacing: 0) {
            if appState.prompts.isEmpty {
                emptyState
            } else {
                promptList
            }

            if selectedId != nil {
                editPanel
            }

            Divider()

            HStack {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: addPrompt) {
                    Image(systemName: "plus")
                }
                .help("Add prompt")
            }
            .padding(8)
        }
        .onChange(of: selectedId) { _, newId in
            guard let id = newId,
                  let p = appState.prompts.first(where: { $0.id == id }) else { return }
            editTitle = p.title
            editBody = p.body
        }
        .onChange(of: editTitle) { _, newValue in updateSelected { $0.title = newValue } }
        .onChange(of: editBody)  { _, newValue in updateSelected { $0.body  = newValue } }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "text.book.closed")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No prompts yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Click + to create your first reusable prompt.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var promptList: some View {
        List(selection: $selectedId) {
            ForEach(appState.prompts) { prompt in
                promptRow(prompt).tag(prompt.id)
            }
            .onMove { from, to in
                appState.prompts.move(fromOffsets: from, toOffset: to)
                appState.savePrompts()
            }
            .onDelete { indices in
                if let id = selectedId,
                   indices.contains(where: { appState.prompts[$0].id == id }) {
                    selectedId = nil
                }
                appState.prompts.remove(atOffsets: indices)
                appState.savePrompts()
            }
        }
        .listStyle(.bordered)
        .frame(minHeight: 120)
    }

    @ViewBuilder
    private func promptRow(_ prompt: SavedPrompt) -> some View {
        HStack(spacing: 8) {
            Button(action: { toggleStar(prompt) }) {
                Image(systemName: prompt.isStarred ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundStyle(prompt.isStarred ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(prompt.isStarred ? "Remove from starred" : "Star for quick access in context menus")

            VStack(alignment: .leading, spacing: 2) {
                Text(prompt.title.isEmpty ? "Untitled" : prompt.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(prompt.body)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: { deletePrompt(prompt) }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete prompt")
        }
        .padding(.vertical, 2)
    }

    private var editPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                TextField("Title", text: $editTitle)
                    .textFieldStyle(.roundedBorder)

                TextEditor(text: $editBody)
                    .font(.system(size: 12))
                    .frame(minHeight: 80, maxHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                Text("Available variables: {{branch}}  {{project}}  {{dir}}")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Mutations

    private func addPrompt() {
        let prompt = SavedPrompt(title: "New Prompt", body: "")
        appState.prompts.append(prompt)
        appState.savePrompts()
        selectedId = prompt.id
    }

    private func deletePrompt(_ prompt: SavedPrompt) {
        if selectedId == prompt.id { selectedId = nil }
        appState.prompts.removeAll { $0.id == prompt.id }
        appState.savePrompts()
    }

    private func toggleStar(_ prompt: SavedPrompt) {
        guard let i = appState.prompts.firstIndex(where: { $0.id == prompt.id }) else { return }
        appState.prompts[i].isStarred.toggle()
        appState.savePrompts()
    }

    private func updateSelected(_ update: (inout SavedPrompt) -> Void) {
        guard let id = selectedId,
              let i = appState.prompts.firstIndex(where: { $0.id == id }) else { return }
        update(&appState.prompts[i])
        appState.savePrompts()
    }
}
