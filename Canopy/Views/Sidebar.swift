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
    @State private var projectToClose: Project?
    @State private var mergeSession: SessionInfo?
    @State private var promptPickerSession: SessionInfo?

    private var plainSessions: [SessionInfo] {
        appState.orderedSessions.filter { $0.projectId == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.sessions.isEmpty && appState.projects.isEmpty {
                emptyState
            } else {
                List(selection: $appState.activeSessionId) {
                    // Activity dashboard
                    Button(action: { appState.selectActivity() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(red: 0.30, green: 0.75, blue: 0.32))
                            Text("Activity")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(appState.showActivity ? Color(red: 0.30, green: 0.75, blue: 0.32).opacity(0.15) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)

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
                        appState.showActivity = false
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
            SessionInfoSheet(
                session: session,
                openedAt: appState.terminalSessions[session.id]?.openedAt
            )
            .environmentObject(appState)
        }
        .alert("Close Project?", isPresented: Binding(
            get: { projectToClose != nil },
            set: { if !$0 { projectToClose = nil } }
        )) {
            Button("Close", role: .destructive) {
                if let project = projectToClose {
                    appState.removeProject(id: project.id)
                    projectToClose = nil
                }
            }
            Button("Cancel", role: .cancel) { projectToClose = nil }
        } message: {
            Text("Remove \"\(projectToClose?.name ?? "")\" from the sidebar? The repository and its worktrees on disk are not affected.")
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
        .sheet(item: $promptPickerSession) { session in
            PromptPickerSheet(session: session)
                .environmentObject(appState)
        }
    }

    // MARK: - Session Row

    @ViewBuilder
    private func sessionRow(_ session: SessionInfo) -> some View {
        let color = projectColorFor(session)

        HStack(spacing: 6) {
            let diff = appState.sessionDiffStats[session.id]
            let ahead = appState.sessionCommitsAhead[session.id]
            let prs = appState.sessionPRCount[session.id]
            let sandboxed = isSandboxed(session)
            if let ts = appState.terminalSessions[session.id] {
                LiveSessionRow(session: session, terminalSession: ts, projectColor: color, diffStat: diff, commitsAhead: ahead, prCount: prs, isSandboxed: sandboxed)
            } else {
                SidebarSessionRow(session: session, projectColor: color, diffStat: diff, commitsAhead: ahead, prCount: prs, isSandboxed: sandboxed)
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

        Menu("Send Prompt") {
            let starred = appState.prompts.filter(\.isStarred)
            if appState.prompts.isEmpty {
                Button("No prompts yet — add in Settings") { }
                    .disabled(true)
            } else if starred.isEmpty {
                Button("No starred prompts") { }
                    .disabled(true)
                Divider()
            } else {
                ForEach(starred) { prompt in
                    Button(prompt.title) { sendPrompt(prompt, to: session) }
                }
                Divider()
            }
            Button("Browse All…") { promptPickerSession = session }
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

        Button("Close Project", role: .destructive) {
            projectToClose = project
        }
    }

    // MARK: - Helpers

    private func isSandboxed(_ session: SessionInfo) -> Bool {
        if let projectId = session.projectId,
           let project = appState.projects.first(where: { $0.id == projectId }) {
            return project.useSandbox ?? appState.settings.useSandbox
        }
        return appState.settings.useSandbox
    }

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

    private func sendPrompt(_ prompt: SavedPrompt, to session: SessionInfo) {
        let project = appState.projects.first(where: { $0.id == session.projectId })
        let dir = (session.workingDirectory as NSString).lastPathComponent
        let resolved = resolvePrompt(
            prompt.body,
            branchName: session.branchName,
            projectName: project?.name,
            dir: dir
        )
        appState.terminalSessions[session.id]?.sendCommand(resolved)
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
    var diffStat: GitDiffStat?
    var commitsAhead: Int?
    var prCount: Int?
    var isSandboxed: Bool = false

    var body: some View {
        SidebarSessionRow(
            session: session,
            activity: terminalSession.activity,
            projectColor: projectColor,
            diffStat: diffStat,
            commitsAhead: commitsAhead,
            prCount: prCount,
            isSandboxed: isSandboxed
        )
    }
}

// MARK: - Session Row (reusable)

struct SidebarSessionRow: View {
    let session: SessionInfo
    var activity: SessionActivity = .idle
    var projectColor: Color = .gray
    var diffStat: GitDiffStat?
    var commitsAhead: Int?
    var prCount: Int?
    var isSandboxed: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            ActivityDot(activity: activity, projectColor: projectColor)
                .frame(width: 10)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(session.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    if isSandboxed {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .tooltip("Running in Docker Sandbox")
                    }
                }

                // Subtitle: branch (if different from name) + git indicators
                if branchSubtitle != nil || hasGitInfo {
                    HStack(spacing: 4) {
                        if let branch = branchSubtitle {
                            Text(branch)
                                .font(.system(size: 10))
                                .foregroundColor(session.isWorktreeSession ? projectColor.opacity(0.7) : .gray)
                                .lineLimit(1)
                        }

                        if hasGitInfo {
                            if branchSubtitle != nil { Spacer(minLength: 2) }

                            if let count = prCount, count > 0 {
                                HStack(spacing: 1) {
                                    Image(systemName: "arrow.triangle.pull")
                                        .font(.system(size: 7))
                                    Text("\(count)")
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                }
                                .foregroundStyle(.secondary)
                                .tooltip("\(count) open PR\(count == 1 ? "" : "s")")
                            }

                            if let ahead = commitsAhead, ahead > 0 {
                                HStack(spacing: 1) {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 7, weight: .bold))
                                    Text("\(ahead)")
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                }
                                .foregroundStyle(.secondary)
                                .tooltip("\(ahead) commit\(ahead == 1 ? "" : "s") ahead of base branch")
                            }

                            if let diff = diffStat, !diff.isClean {
                                HStack(spacing: 2) {
                                    if diff.insertions > 0 {
                                        Text("+\(diff.insertions)")
                                            .foregroundStyle(.green)
                                    }
                                    if diff.deletions > 0 {
                                        Text("−\(diff.deletions)")
                                            .foregroundStyle(.red)
                                    }
                                }
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .tooltip("\(diff.filesChanged) file\(diff.filesChanged == 1 ? "" : "s") changed\(diff.changedFiles.isEmpty ? "" : ":\n" + diff.changedFiles.joined(separator: "\n"))")
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var hasGitInfo: Bool {
        (commitsAhead ?? 0) > 0 || !(diffStat?.isClean ?? true) || (prCount ?? 0) > 0
    }

    /// Branch name only when it differs from session name. No path — it's redundant.
    private var branchSubtitle: String? {
        guard let branch = session.branchName, branch != session.name else { return nil }
        return branch
    }
}

