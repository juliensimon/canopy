import SwiftUI

enum CommandPaletteItemKind {
    case session
    case project
    case action
}

struct CommandPaletteItem: Identifiable {
    let id = UUID()
    let kind: CommandPaletteItemKind
    let title: String
    let subtitle: String
    let keywords: String  // extra searchable text, not displayed
    let icon: String
    let action: () -> Void

    init(kind: CommandPaletteItemKind, title: String, subtitle: String,
         keywords: String = "", icon: String, action: @escaping () -> Void) {
        self.kind = kind; self.title = title; self.subtitle = subtitle
        self.keywords = keywords; self.icon = icon; self.action = action
    }

    @MainActor
    static func generate(from state: AppState) -> [CommandPaletteItem] {
        var items: [CommandPaletteItem] = []

        for session in state.orderedSessions {
            let projectName = state.projects.first { $0.id == session.projectId }?.name ?? ""
            let branch = session.branchName ?? ""
            let subtitle = branch.isEmpty ? session.workingDirectory : "\(branch) — \(session.workingDirectory)"
            let bufferText = state.terminalSessions[session.id]?.getFullText() ?? ""
            items.append(CommandPaletteItem(
                kind: .session, title: session.name, subtitle: subtitle,
                keywords: "\(projectName) \(branch) \(bufferText)",
                icon: "terminal", action: { state.selectSession(session.id) }
            ))
        }

        for project in state.projects {
            items.append(CommandPaletteItem(
                kind: .project, title: project.name, subtitle: project.repositoryPath,
                icon: "folder.fill", action: { state.selectProject(project.id) }
            ))
        }

        items.append(CommandPaletteItem(
            kind: .action, title: "New Session", subtitle: "Open directory picker",
            icon: "plus", action: { state.createSessionWithPicker() }
        ))
        items.append(CommandPaletteItem(
            kind: .action, title: "New Worktree Session", subtitle: "Create worktree",
            icon: "arrow.triangle.branch", action: { state.showNewWorktreeSheet = true }
        ))
        items.append(CommandPaletteItem(
            kind: .action, title: "Settings", subtitle: "App preferences",
            icon: "gear", action: { state.showSettings = true }
        ))

        return items
    }

    static func filter(_ items: [CommandPaletteItem], query: String) -> [CommandPaletteItem] {
        guard !query.isEmpty else { return items }
        let q = query.lowercased()
        return items.filter {
            $0.title.lowercased().contains(q)
            || $0.subtitle.lowercased().contains(q)
            || $0.keywords.lowercased().contains(q)
        }
    }
}

struct CommandPaletteView: View {
    @EnvironmentObject var appState: AppState
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var items: [CommandPaletteItem] {
        CommandPaletteItem.filter(
            CommandPaletteItem.generate(from: appState),
            query: query
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Find sessions, projects, actions...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($isSearchFocused)
                    .onSubmit { executeSelected() }
            }
            .padding(12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            paletteRow(item, isSelected: index == selectedIndex)
                                .id(index)
                                .onTapGesture { execute(item) }
                        }
                    }
                }
                .frame(maxHeight: 300)
                .onChange(of: selectedIndex) { _, newValue in
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        .frame(width: 500)
        .onAppear {
            query = ""
            selectedIndex = 0
            isSearchFocused = true
        }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
        .onKeyPress(.escape) { appState.showCommandPalette = false; return .handled }
    }

    private func paletteRow(_ item: CommandPaletteItem, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                Text(item.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Text(kindLabel(item.kind))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }

    private func kindLabel(_ kind: CommandPaletteItemKind) -> String {
        switch kind {
        case .session: return "Session"
        case .project: return "Project"
        case .action: return "Action"
        }
    }

    private func moveSelection(_ delta: Int) {
        let count = items.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func executeSelected() {
        guard !items.isEmpty, selectedIndex < items.count else { return }
        execute(items[selectedIndex])
    }

    private func execute(_ item: CommandPaletteItem) {
        appState.showCommandPalette = false
        // If this was a session match and the query doesn't match name/subtitle
        // (i.e. it matched buffer content), open terminal search pre-populated.
        if item.kind == .session && !query.isEmpty {
            let q = query.lowercased()
            let matchedMeta = item.title.lowercased().contains(q) || item.subtitle.lowercased().contains(q)
            if !matchedMeta {
                appState.terminalSearchQuery = query
                appState.showTerminalSearch = true
            } else {
                appState.terminalSearchQuery = ""
            }
        }
        item.action()
    }
}
