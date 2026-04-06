import SwiftUI

/// The left sidebar showing projects and their sessions.
///
/// Features:
/// - Close (X) button on each session row
/// - Right-click context menus on sessions and projects
/// - Inline rename via context menu
/// - Collapsible project sections
/// - Project CRUD (add, edit, delete)
struct Sidebar: View {
    @EnvironmentObject var appState: AppState
    @State private var editingProject: Project?
    @State private var renamingSessionId: UUID?
    @State private var renameText = ""
    @State private var infoSession: SessionInfo?

    private var plainSessions: [SessionInfo] {
        appState.sessions.filter { $0.projectId == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.sessions.isEmpty && appState.projects.isEmpty {
                emptyState
            } else {
                List(selection: $appState.activeSessionId) {
                    // Plain sessions
                    if !plainSessions.isEmpty {
                        Section("Sessions") {
                            ForEach(plainSessions) { session in
                                sessionRow(session)
                            }
                        }
                    }

                    // Projects
                    ForEach(appState.projects) { project in
                        projectSection(project)
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: appState.activeSessionId) { _, newValue in
                    if newValue != nil {
                        appState.selectedProjectId = nil
                    }
                }
            }

        }
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
        .sheet(isPresented: $appState.showAddProjectSheet) {
            AddProjectSheet()
        }
        .sheet(isPresented: $appState.showNewWorktreeSheet) {
            WorktreeSheet()
        }
        .sheet(item: $editingProject) { project in
            EditProjectSheet(project: project)
        }
        .sheet(item: $infoSession) { session in
            SessionInfoSheet(session: session)
                .environmentObject(appState)
        }
    }

    // MARK: - Session Row

    @ViewBuilder
    private func sessionRow(_ session: SessionInfo) -> some View {
        HStack(spacing: 6) {
            // Inline rename or display
            if renamingSessionId == session.id {
                RenameField(text: $renameText, onCommit: {
                    appState.renameSession(id: session.id, to: renameText)
                    renamingSessionId = nil
                }, onCancel: {
                    renamingSessionId = nil
                })
            } else {
                SidebarSessionRow(session: session)
            }

            Spacer()

            // Close button
            Button(action: { appState.closeSession(id: session.id) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help("Close session")
        }
        .tag(session.id)
        .contextMenu { sessionContextMenu(session) }
    }

    @ViewBuilder
    private func sessionContextMenu(_ session: SessionInfo) -> some View {
        Button("Rename...") {
            renameText = session.name
            renamingSessionId = session.id
        }

        Button("Copy Working Directory") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(session.workingDirectory, forType: .string)
        }

        if let branch = session.branchName {
            Button("Copy Branch Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(branch, forType: .string)
            }
        }

        Divider()

        Button("Open in IDE") {
            NSWorkspace.shared.open(
                [URL(fileURLWithPath: session.workingDirectory)],
                withApplicationAt: URL(fileURLWithPath: appState.settings.idePath),
                configuration: NSWorkspace.OpenConfiguration()
            )
        }

        Button("Open in Finder") {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.workingDirectory)
        }

        Button("Session Info") {
            infoSession = session
        }

        Divider()

        Button("Close", role: .destructive) {
            appState.closeSession(id: session.id)
        }
    }

    // MARK: - Project Section

    @ViewBuilder
    private func projectSection(_ project: Project) -> some View {
        let sessions = appState.sessions.filter { $0.projectId == project.id }

        Section(isExpanded: appState.projectExpandedBinding(for: project.id)) {
            if sessions.isEmpty {
                Text("No sessions")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 2)
            } else {
                ForEach(sessions) { session in
                    sessionRow(session)
                }
            }
        } header: {
            HStack(spacing: 5) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Text(project.name)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                appState.activeSessionId = nil
                appState.selectedProjectId = project.id
            }
            .contextMenu { projectContextMenu(project) }
        }
    }

    @ViewBuilder
    private func projectContextMenu(_ project: Project) -> some View {
        Button("New Worktree Session...") {
            appState.showNewWorktreeSheet = true
        }

        Divider()

        Button("Edit Project...") {
            editingProject = project
        }

        Button("Copy Repository Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(project.repositoryPath, forType: .string)
        }

        Divider()

        Button("Delete Project", role: .destructive) {
            appState.removeProject(id: project.id)
        }
    }

    // MARK: - Helpers

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No sessions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Press ⌘T to start")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Session Row (reusable)

struct SidebarSessionRow: View {
    let session: SessionInfo

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: session.isWorktreeSession ? "arrow.triangle.branch" : "terminal")
                .font(.system(size: 12))
                .foregroundStyle(session.isWorktreeSession ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(session.isWorktreeSession ? .blue.opacity(0.7) : .gray)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        if let branch = session.branchName {
            return branch
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var path = session.workingDirectory
        if path.hasPrefix(home) {
            path = "~" + path.dropFirst(home.count)
        }
        return path
    }
}

/// A text field that auto-focuses when it appears, commits on Enter, cancels on Escape.
struct RenameField: NSViewRepresentable {
    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.stringValue = text
        field.font = .systemFont(ofSize: 12)
        field.delegate = context.coordinator
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        // Auto-focus and select all text
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.selectText(nil)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: RenameField

        init(_ parent: RenameField) {
            self.parent = parent
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            // Check if ended via Enter (return) or something else
            let movementCode = obj.userInfo?["NSTextMovement"] as? Int
            if movementCode == NSReturnTextMovement {
                parent.text = field.stringValue
                parent.onCommit()
            } else {
                parent.onCancel()
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}
