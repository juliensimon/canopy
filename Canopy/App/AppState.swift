import SwiftUI
import AppKit

/// Controls how tabs are ordered in the tab bar and sidebar.
enum TabSortMode: String, CaseIterable {
    case manual = "Manual"
    case name = "Name"
    case project = "Project"
    case creationDate = "Creation Date"
    case workingDirectory = "Directory"
}

/// Global application state shared across views.
///
/// Owns sessions, projects, and the active selection.
/// Views observe this via @EnvironmentObject.
@MainActor
final class AppState: ObservableObject {
    @Published var sessions: [SessionInfo] = []
    @Published var activeSessionId: UUID?
    @Published var selectedProjectId: UUID?
    @Published var projects: [Project] = []
    @Published var tabSortMode: TabSortMode = .manual

    /// Terminal sessions keyed by session ID. Kept alive across tab switches.
    var terminalSessions: [UUID: TerminalSession] = [:]

    /// Split terminal sessions keyed by session ID. Ephemeral — not persisted.
    var splitTerminalSessions: [UUID: TerminalSession] = [:]

    /// Tracks which sessions currently have an open split terminal.
    @Published var splitSessionIds: Set<UUID> = []

    /// App settings (auto-start claude, flags, etc.)
    @Published var settings = CanopySettings.load()

    /// UI triggers for sheets
    @Published var showNewWorktreeSheet = false
    /// When set, the worktree sheet preselects this project
    @Published var worktreeSheetProjectId: UUID?
    @Published var showAddProjectSheet = false
    @Published var showSettings = false
    @Published var showCommandPalette = false
    /// Whether the Activity dashboard is currently shown.
    @Published var showActivity = false
    @Published var showTerminalSearch = false
    @Published var showCloseConfirmation = false
    @Published var pendingCloseSessionId: UUID?

    /// Tracks which project sections are expanded in the sidebar
    @Published var expandedProjects: Set<UUID> = []

    /// Tracks worktree setup progress for UI feedback
    @Published var worktreeSetupInProgress = false
    @Published var worktreeSetupStatus: String?

    /// Pre-loaded activity data, populated at startup so the dashboard opens instantly.
    @Published var cachedActivityBuckets: [String: DailyBucket]?
    @Published var cachedActivitySummary: ActivitySummary?
    @Published var activityIndexing = false

    /// When true, session mutations skip saving (app is terminating).
    var isTerminating = false

    private let git = GitService()

    /// Injected config directory for persistence. Defaults to ~/.config/canopy.
    private let configDir: String

    init(configDir: String? = nil) {
        self.configDir = configDir ?? (NSHomeDirectory() as NSString).appendingPathComponent(".config/canopy")
    }

    var activeSession: SessionInfo? {
        sessions.first { $0.id == activeSessionId }
    }

    var orderedSessions: [SessionInfo] {
        switch tabSortMode {
        case .manual:
            return sessions
        case .name:
            return sessions.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .creationDate:
            return sessions.sorted { $0.createdAt < $1.createdAt }
        case .workingDirectory:
            return sessions.sorted { $0.workingDirectory.localizedCaseInsensitiveCompare($1.workingDirectory) == .orderedAscending }
        case .project:
            return sessions.sorted { a, b in
                let aProject = projects.first { $0.id == a.projectId }
                let bProject = projects.first { $0.id == b.projectId }
                let aName = aProject?.name ?? "\u{FFFF}"
                let bName = bProject?.name ?? "\u{FFFF}"
                if aName != bName { return aName.localizedCaseInsensitiveCompare(bName) == .orderedAscending }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
    }

    var selectedProject: Project? {
        projects.first { $0.id == selectedProjectId }
    }

    /// When selecting a session, clear the project selection (and vice versa).
    func selectSession(_ id: UUID) {
        activeSessionId = id
        selectedProjectId = nil
        showActivity = false
    }

    func selectProject(_ id: UUID) {
        activeSessionId = nil
        selectedProjectId = id
        showActivity = false
    }

    func selectActivity() {
        activeSessionId = nil
        selectedProjectId = nil
        showActivity = true
    }

    // MARK: - Session Management

    /// Returns (or creates) the TerminalSession for a given session ID.
    func terminalSession(for sessionInfo: SessionInfo) -> TerminalSession {
        if let existing = terminalSessions[sessionInfo.id] {
            return existing
        }
        let ts = TerminalSession(id: sessionInfo.id, workingDirectory: sessionInfo.workingDirectory)
        ts.onSessionFinished = { [weak self] sessionId, _ in
            self?.postFinishNotification(for: sessionId)
        }
        terminalSessions[sessionInfo.id] = ts
        return ts
    }

    private func postFinishNotification(for sessionId: UUID) {
        guard settings.notifyOnFinish, !NSApp.isActive else { return }
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }

        let projectName = projects.first(where: { $0.id == session.projectId })?.name
        let title = (projectName ?? "Canopy").replacingOccurrences(of: "\"", with: "\\\"")
        let subtitle = session.name.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"Session finished\" with title \"\(title)\" subtitle \"\(subtitle)\" sound name \"Glass\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    // MARK: - Split Terminal

    func isSplitOpen(for sessionId: UUID) -> Bool {
        splitSessionIds.contains(sessionId)
    }

    func toggleSplitTerminal(for sessionId: UUID) {
        if splitSessionIds.contains(sessionId) {
            closeSplitTerminal(for: sessionId)
        } else {
            guard let session = sessions.first(where: { $0.id == sessionId }) else { return }
            let ts = TerminalSession(id: session.id, workingDirectory: session.workingDirectory)
            ts.onProcessExit = { [weak self] id in
                self?.closeSplitTerminal(for: id)
            }
            splitTerminalSessions[session.id] = ts
            splitSessionIds.insert(sessionId)
        }
    }

    private func closeSplitTerminal(for sessionId: UUID) {
        splitTerminalSessions[sessionId]?.stop()
        splitTerminalSessions.removeValue(forKey: sessionId)
        splitSessionIds.remove(sessionId)
    }

    /// Shows a directory picker then creates a session in the chosen directory.
    func createSessionWithPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose working directory for the new session"
        panel.prompt = "Open"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.createSession(directory: url.path)
            }
        }
    }

    /// Creates a plain session in the given directory.
    /// Auto-names tabs as "reponame-branchname" when inside a git repo.
    func createSession(name: String? = nil, directory: String? = nil) {
        let workDir = directory ?? FileManager.default.homeDirectoryForCurrentUser.path
        let index = sessions.count + 1

        let finalName: String
        if let name = name {
            finalName = name
        } else {
            finalName = "Session \(index)"
        }

        let session = SessionInfo(name: finalName, workingDirectory: workDir)
        withAnimation(.easeOut(duration: 0.25)) {
            if tabSortMode == .manual {
                sessions.append(session)
            } else {
                sessions.append(session)
                sessions = orderedSessions
            }
        }
        activeSessionId = session.id
        saveSessions()

        // Auto-detect git repo name and branch for the tab name
        if name == nil {
            Task {
                if let autoName = await Self.gitTabName(for: workDir, git: git) {
                    renameSession(id: session.id, to: autoName)
                }
            }
        }
    }

    /// Derives a "reponame-branchname" tab name from a directory, or nil if not a git repo.
    private static func gitTabName(for directory: String, git: GitService) async -> String? {
        guard await git.isGitRepo(path: directory) else { return nil }
        guard let root = try? await git.repoRoot(path: directory) else { return nil }
        guard let branch = try? await git.currentBranch(repoPath: directory) else { return nil }
        let repoName = (root as NSString).lastPathComponent
        return "\(repoName)-\(branch)"
    }

    /// Creates a session backed by a git worktree.
    /// This is the key Phase 2 feature:
    /// 1. Creates a worktree with a new branch
    /// 2. Copies .env and config files from the main repo
    /// 3. Creates symlinks for heavy directories
    /// 4. Runs setup commands
    /// 5. Launches a terminal session in the worktree
    func createWorktreeSession(
        project: Project,
        branchName: String,
        baseBranch: String
    ) async throws {
        worktreeSetupInProgress = true
        worktreeSetupStatus = "Creating worktree..."

        let baseDir = project.resolvedWorktreeBaseDir
        let worktreePath = (baseDir as NSString).appendingPathComponent(
            branchName.replacingOccurrences(of: "/", with: "-")
        )

        do {
            // Create parent directory if needed
            try FileManager.default.createDirectory(
                atPath: baseDir,
                withIntermediateDirectories: true
            )
            // 1. Create the git worktree
            try await git.createWorktree(
                repoPath: project.repositoryPath,
                worktreePath: worktreePath,
                branch: branchName,
                baseBranch: baseBranch,
                createBranch: true
            )

            // 2. Copy config files (.env, etc.)
            if !project.filesToCopy.isEmpty {
                worktreeSetupStatus = "Copying config files..."
                try GitService.copyFiles(
                    from: project.repositoryPath,
                    to: worktreePath,
                    paths: project.filesToCopy
                )
            }

            // 3. Create symlinks (node_modules, .venv, etc.)
            if !project.symlinkPaths.isEmpty {
                worktreeSetupStatus = "Creating symlinks..."
                try GitService.createSymlinks(
                    from: project.repositoryPath,
                    to: worktreePath,
                    paths: project.symlinkPaths
                )
            }

            // 4. Run setup commands
            for command in project.setupCommands {
                worktreeSetupStatus = "Running: \(command)..."
                try await GitService.runSetupCommand(command, in: worktreePath)
            }

            // 5. Create the session
            worktreeSetupStatus = nil
            worktreeSetupInProgress = false

            let repoName = (project.repositoryPath as NSString).lastPathComponent
            let session = SessionInfo(
                name: "\(repoName)-\(branchName)",
                workingDirectory: worktreePath,
                projectId: project.id,
                branchName: branchName,
                worktreePath: worktreePath
            )
            withAnimation(.easeOut(duration: 0.25)) {
                if tabSortMode == .manual {
                    sessions.append(session)
                } else {
                    sessions.append(session)
                    sessions = orderedSessions
                }
                activeSessionId = session.id
            }
            saveSessions()

        } catch {
            worktreeSetupInProgress = false
            worktreeSetupStatus = nil
            throw error
        }
    }

    func closeSession(id: UUID, force: Bool = false) {
        let session = sessions.first { $0.id == id }

        // If the session is running and confirmation is required, ask first
        if !force && settings.confirmBeforeClosing && session != nil {
            pendingCloseSessionId = id
            showCloseConfirmation = true
            return
        }

        performCloseSession(id: id)
    }

    func performCloseSession(id: UUID) {
        terminalSessions[id]?.stop()
        terminalSessions.removeValue(forKey: id)
        closeSplitTerminal(for: id)
        withAnimation(.easeOut(duration: 0.25)) {
            sessions.removeAll { $0.id == id }
            if activeSessionId == id {
                activeSessionId = sessions.last?.id
            }
        }
        pendingCloseSessionId = nil
        saveSessions()
    }

    func renameSession(id: UUID, to newName: String) {
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].name = newName
        }
        saveSessions()
    }

    /// Reorders sessions within a project by moving items at the given offsets to a new position.
    /// `source` and `destination` are indices relative to the project's filtered session list.
    func moveSessionsInProject(_ projectId: UUID, from source: IndexSet, to destination: Int) {
        var projectSessions = sessions.filter { $0.projectId == projectId }
        projectSessions.move(fromOffsets: source, toOffset: destination)

        var result: [SessionInfo] = []
        var projectIndex = 0
        for session in sessions {
            if session.projectId == projectId {
                result.append(projectSessions[projectIndex])
                projectIndex += 1
            } else {
                result.append(session)
            }
        }
        sessions = result
    }

    /// Moves sessions using IndexSet (for sidebar .onMove).
    func moveSession(from source: IndexSet, to destination: Int) {
        sessions.move(fromOffsets: source, toOffset: destination)
        tabSortMode = .manual
    }

    /// Swaps two sessions by ID (for tab bar drag-and-drop).
    func swapSessions(_ idA: UUID, _ idB: UUID) {
        guard let indexA = sessions.firstIndex(where: { $0.id == idA }),
              let indexB = sessions.firstIndex(where: { $0.id == idB }),
              indexA != indexB else { return }
        sessions.swapAt(indexA, indexB)
        tabSortMode = .manual
    }

    // MARK: - Project Management

    func addProject(_ project: Project) {
        // Prevent duplicates by repo path
        guard !projects.contains(where: { $0.repositoryPath == project.repositoryPath }) else { return }
        var newProject = project
        if newProject.colorIndex == nil {
            newProject.colorIndex = ProjectColor.nextIndex(
                existingIndices: projects.compactMap(\.colorIndex)
            )
        }
        projects.append(newProject)
        expandedProjects.insert(newProject.id)
        saveProjects()
    }

    /// Returns a Binding<Bool> for a project's expanded/collapsed state in the sidebar.
    func projectExpandedBinding(for projectId: UUID) -> Binding<Bool> {
        Binding(
            get: { self.expandedProjects.contains(projectId) },
            set: { isExpanded in
                if isExpanded {
                    self.expandedProjects.insert(projectId)
                } else {
                    self.expandedProjects.remove(projectId)
                }
            }
        )
    }

    func removeProject(id: UUID) {
        projects.removeAll { $0.id == id }
        saveProjects()
    }

    func updateProject(_ project: Project) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
            saveProjects()
        }
    }

    // MARK: - Persistence

    /// Projects are saved to <configDir>/projects.json
    private var projectsFilePath: String {
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        return (configDir as NSString).appendingPathComponent("projects.json")
    }

    private var sessionsFilePath: String {
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        return (configDir as NSString).appendingPathComponent("sessions.json")
    }

    func saveSessions() {
        guard !isTerminating else { return }
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        FileManager.default.createFile(atPath: sessionsFilePath, contents: data)
    }

    /// Save sessions and mark as terminating so cleanup doesn't overwrite the file.
    func saveSessionsBeforeTermination() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        FileManager.default.createFile(atPath: sessionsFilePath, contents: data)
        isTerminating = true
    }

    func loadSessions() {
        let path = sessionsFilePath
        guard let data = FileManager.default.contents(atPath: path),
              var decoded = try? JSONDecoder().decode([SessionInfo].self, from: data) else {
            return
        }
        // Refresh Claude session IDs from disk
        for i in decoded.indices {
            decoded[i].claudeSessionId = ClaudeSessionFinder.findLatestSessionId(
                for: decoded[i].workingDirectory
            )
        }
        sessions = decoded
        activeSessionId = sessions.first?.id
    }

    func loadProjects() {
        let path = projectsFilePath
        guard let data = FileManager.default.contents(atPath: path),
              let decoded = try? JSONDecoder().decode([Project].self, from: data) else {
            return
        }
        // Back up before loading so we can recover if something overwrites
        let backupPath = (configDir as NSString).appendingPathComponent("projects.backup.json")
        try? FileManager.default.removeItem(atPath: backupPath)
        try? FileManager.default.copyItem(atPath: path, toPath: backupPath)

        projects = decoded
        // Auto-assign colors to projects that predate the color system
        var needsSave = false
        for i in projects.indices where projects[i].colorIndex == nil {
            projects[i].colorIndex = ProjectColor.nextIndex(
                existingIndices: projects.compactMap(\.colorIndex)
            )
            needsSave = true
        }
        if needsSave { saveProjects() }
        // Auto-expand all projects on load
        expandedProjects = Set(decoded.map(\.id))
    }

    private func saveProjects() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        FileManager.default.createFile(atPath: projectsFilePath, contents: data)
    }

    // MARK: - Activity Data Pre-loading

    /// Indexes all Claude Code JSONL files in the background at startup.
    func preloadActivityData() {
        activityIndexing = true
        Task.detached(priority: .utility) {
            let result = ActivityDataService.loadData()
            await MainActor.run {
                self.cachedActivityBuckets = result.buckets
                self.cachedActivitySummary = result.summary
                self.activityIndexing = false
            }
        }
    }
}

/// Info about a session. Optionally linked to a project and worktree.
struct SessionInfo: Identifiable, Codable {
    let id: UUID
    var name: String
    let workingDirectory: String
    let createdAt: Date

    // Phase 2: worktree-backed session info
    var projectId: UUID?
    var branchName: String?
    var worktreePath: String?

    var isWorktreeSession: Bool { worktreePath != nil }

    /// Claude Code session ID to resume (UUID from ~/.claude/projects/).
    /// When set, Claude is started with `--resume <id>`.
    var claudeSessionId: String?

    init(
        id: UUID = UUID(),
        name: String,
        workingDirectory: String,
        projectId: UUID? = nil,
        branchName: String? = nil,
        worktreePath: String? = nil,
        claudeSessionId: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.workingDirectory = workingDirectory
        self.projectId = projectId
        self.branchName = branchName
        self.worktreePath = worktreePath
        self.claudeSessionId = claudeSessionId
        self.createdAt = createdAt
    }
}
