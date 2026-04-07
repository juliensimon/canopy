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
    @State private var renameSession: SessionInfo?
    @State private var renameText = ""
    @State private var infoSession: SessionInfo?
    @State private var projectToDelete: Project?
    @State private var mergeSession: SessionInfo?

    private var plainSessions: [SessionInfo] {
        appState.orderedSessions.filter { $0.projectId == nil }
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
                            .onMove { source, destination in
                                appState.moveSession(from: source, to: destination)
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
        .sheet(isPresented: $appState.showNewWorktreeSheet, onDismiss: {
            appState.worktreeSheetProjectId = nil
        }) {
            WorktreeSheet(preselectedProjectId: appState.worktreeSheetProjectId)
        }
        .sheet(item: $editingProject) { project in
            EditProjectSheet(project: project)
        }
        .sheet(item: $infoSession) { session in
            SessionInfoSheet(session: session)
                .environmentObject(appState)
        }
        .alert("Delete Project?", isPresented: Binding(
            get: { projectToDelete != nil },
            set: { if !$0 { projectToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let project = projectToDelete {
                    appState.removeProject(id: project.id)
                    projectToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { projectToDelete = nil }
        } message: {
            Text("Remove \"\(projectToDelete?.name ?? "")\" from Canopy? This does not delete the repository or its worktrees from disk.")
        }
        .alert("Rename Session", isPresented: Binding(
            get: { renameSession != nil },
            set: { if !$0 { renameSession = nil } }
        )) {
            TextField("Session name", text: $renameText)
            Button("Rename") {
                if let session = renameSession {
                    appState.renameSession(id: session.id, to: renameText)
                    renameSession = nil
                }
            }
            Button("Cancel", role: .cancel) { renameSession = nil }
        }
        .sheet(item: $mergeSession) { session in
            if let project = appState.projects.first(where: { $0.id == session.projectId }),
               let branch = session.branchName,
               let wtPath = session.worktreePath {
                MergeWorktreeSheet(
                    project: project,
                    worktreePath: wtPath,
                    branchName: branch,
                    sessionId: session.id
                )
                .environmentObject(appState)
            }
        }
    }

    // MARK: - Session Row

    @ViewBuilder
    private func sessionRow(_ session: SessionInfo) -> some View {
        let color = projectColorFor(session)

        HStack(spacing: 6) {
            if let ts = appState.terminalSessions[session.id] {
                LiveSessionRow(session: session, terminalSession: ts, projectColor: color)
            } else {
                SidebarSessionRow(session: session, projectColor: color)
            }

            Spacer()

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
        if session.isWorktreeSession {
            Button("Merge & Finish...") {
                mergeSession = session
            }

            Divider()
        }

        Button("Rename...") {
            renameText = session.name
            renameSession = session
        }

        Button("Copy Session Output") {
            appState.terminalSessions[session.id]?.copyFullSessionToClipboard()
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

        Button(appState.isSplitOpen(for: session.id) ? "Close Split Terminal" : "Open Split Terminal") {
            appState.toggleSplitTerminal(for: session.id)
            if appState.activeSessionId != session.id {
                appState.selectSession(session.id)
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

        Button("Open in \(appState.settings.terminalName)") {
            openInTerminal(session.workingDirectory)
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
        let sessions = appState.orderedSessions.filter { $0.projectId == project.id }

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
                .onMove { source, destination in
                    appState.moveSessionsInProject(project.id, from: source, to: destination)
                }
            }
        } header: {
            projectHeaderView(project)
        }
    }

    @ViewBuilder
    private func projectHeaderView(_ project: Project) -> some View {
        let color = ProjectColor.color(for: project.colorIndex)
        let sessionCount = appState.orderedSessions.filter { $0.projectId == project.id }.count

        HStack(spacing: 5) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundStyle(color)
            Text(project.name)
                .font(.system(size: 12, weight: .medium))

            if sessionCount > 0 {
                Text("\(sessionCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(color.opacity(0.2))
                    )
                    .foregroundStyle(color)
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.05))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            appState.activeSessionId = nil
            appState.selectedProjectId = project.id
        }
        .contextMenu { projectContextMenu(project) }
    }

    @ViewBuilder
    private func projectContextMenu(_ project: Project) -> some View {
        Button("New Worktree Session...") {
            appState.worktreeSheetProjectId = project.id
            appState.showNewWorktreeSheet = true
        }

        Divider()

        Button("Edit Project...") {
            editingProject = project
        }

        Button("Open in \(appState.settings.terminalName)") {
            openInTerminal(project.repositoryPath)
        }

        Button("Open in Finder") {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.repositoryPath)
        }

        Button("Copy Repository Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(project.repositoryPath, forType: .string)
        }

        Divider()

        Button("Delete Project", role: .destructive) {
            projectToDelete = project
        }
    }

    // MARK: - Helpers

    private func projectColorFor(_ session: SessionInfo) -> Color {
        guard let projectId = session.projectId,
              let project = appState.projects.first(where: { $0.id == projectId }) else {
            return .gray
        }
        return ProjectColor.color(for: project.colorIndex)
    }

    private func openInTerminal(_ path: String) {
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: path)],
            withApplicationAt: URL(fileURLWithPath: appState.settings.terminalPath),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            // Layered card illustration
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(ProjectColor.allColors[0].opacity(0.1))
                    .stroke(ProjectColor.allColors[0].opacity(0.2), lineWidth: 1)
                    .frame(width: 48, height: 36)
                    .rotationEffect(.degrees(-8))

                RoundedRectangle(cornerRadius: 6)
                    .fill(ProjectColor.allColors[4].opacity(0.1))
                    .stroke(ProjectColor.allColors[4].opacity(0.2), lineWidth: 1)
                    .frame(width: 48, height: 36)
                    .rotationEffect(.degrees(4))
                    .offset(x: 8, y: -4)

                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(ProjectColor.allColors[7].opacity(0.15))
                        .stroke(ProjectColor.allColors[7].opacity(0.25), lineWidth: 1)
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(ProjectColor.allColors[7].opacity(0.6))
                }
                .frame(width: 48, height: 36)
                .offset(x: 16, y: -8)
            }
            .frame(width: 80, height: 60)

            Text("No sessions yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Start your first parallel Claude session")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            // Keycap badges
            HStack(spacing: 12) {
                keycapBadge(key: "\u{2318}T", label: "New Session")
                keycapBadge(key: "\u{2318}\u{21E7}P", label: "Add Project")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func keycapBadge(key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.08))
                        .stroke(Color.gray.opacity(0.12), lineWidth: 1)
                )
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Live Session Row (observes TerminalSession for activity updates)

/// Wrapper that uses @ObservedObject to react to activity changes.
struct LiveSessionRow: View {
    let session: SessionInfo
    @ObservedObject var terminalSession: TerminalSession
    var projectColor: Color = .gray

    var body: some View {
        SidebarSessionRow(
            session: session,
            activity: terminalSession.activity,
            projectColor: projectColor
        )
    }
}

// MARK: - Session Row (reusable)

struct SidebarSessionRow: View {
    let session: SessionInfo
    var activity: SessionActivity = .idle
    var projectColor: Color = .gray

    var body: some View {
        HStack(spacing: 8) {
            ActivityDot(activity: activity, projectColor: projectColor)
                .frame(width: 10)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(session.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(session.isWorktreeSession ? projectColor.opacity(0.7) : .gray)
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

