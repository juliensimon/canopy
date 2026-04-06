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

    /// App settings (auto-start claude, flags, etc.)
    @Published var settings = CanopySettings.load()

    /// UI triggers for sheets
    @Published var showNewWorktreeSheet = false
    /// When set, the worktree sheet preselects this project
    @Published var worktreeSheetProjectId: UUID?
    @Published var showAddProjectSheet = false
    @Published var showSettings = false
    @Published var showCloseConfirmation = false
    @Published var pendingCloseSessionId: UUID?

    /// Tracks which project sections are expanded in the sidebar
    @Published var expandedProjects: Set<UUID> = []

    /// Tracks worktree setup progress for UI feedback
    @Published var worktreeSetupInProgress = false
    @Published var worktreeSetupStatus: String?

    private let git = GitService()

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
    }

    func selectProject(_ id: UUID) {
        activeSessionId = nil
        selectedProjectId = id
    }

    // MARK: - Session Management

    /// Returns (or creates) the TerminalSession for a given session ID.
    func terminalSession(for sessionInfo: SessionInfo) -> TerminalSession {
        if let existing = terminalSessions[sessionInfo.id] {
            return existing
        }
        let ts = TerminalSession(id: sessionInfo.id, workingDirectory: sessionInfo.workingDirectory)
        terminalSessions[sessionInfo.id] = ts
        return ts
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
    func createSession(name: String? = nil, directory: String? = nil) {
        let workDir = directory ?? FileManager.default.homeDirectoryForCurrentUser.path
        let dirName = (workDir as NSString).lastPathComponent
        let sessionName = name ?? dirName
        let index = sessions.count + 1
        let finalName = sessionName == NSHomeDirectory().split(separator: "/").last.map(String.init) ? "Session \(index)" : sessionName

        let session = SessionInfo(name: finalName, workingDirectory: workDir)
        sessions.append(session)
        activeSessionId = session.id
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

            let session = SessionInfo(
                name: branchName,
                workingDirectory: worktreePath,
                projectId: project.id,
                branchName: branchName,
                worktreePath: worktreePath
            )
            sessions.append(session)
            activeSessionId = session.id

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
        sessions.removeAll { $0.id == id }
        if activeSessionId == id {
            activeSessionId = sessions.last?.id
        }
        pendingCloseSessionId = nil
    }

    func renameSession(id: UUID, to newName: String) {
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].name = newName
        }
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

    // MARK: - Project Management

    func addProject(_ project: Project) {
        // Prevent duplicates by repo path
        guard !projects.contains(where: { $0.repositoryPath == project.repositoryPath }) else { return }
        projects.append(project)
        expandedProjects.insert(project.id)
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

    /// Projects are saved to ~/.config/canopy/projects.json
    private var projectsFilePath: String {
        let configDir = (NSHomeDirectory() as NSString).appendingPathComponent(".config/canopy")
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        return (configDir as NSString).appendingPathComponent("projects.json")
    }

    func loadProjects() {
        guard let data = FileManager.default.contents(atPath: projectsFilePath),
              let decoded = try? JSONDecoder().decode([Project].self, from: data) else {
            return
        }
        projects = decoded
        // Auto-expand all projects on load
        expandedProjects = Set(decoded.map(\.id))
    }

    private func saveProjects() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        FileManager.default.createFile(atPath: projectsFilePath, contents: data)
    }
}

/// Info about a session. Optionally linked to a project and worktree.
struct SessionInfo: Identifiable {
    let id = UUID()
    var name: String
    let workingDirectory: String
    let createdAt = Date()

    // Phase 2: worktree-backed session info
    var projectId: UUID?
    var branchName: String?
    var worktreePath: String?

    var isWorktreeSession: Bool { worktreePath != nil }

    /// Claude Code session ID to resume (UUID from ~/.claude/projects/).
    /// When set, Claude is started with `--resume <id>`.
    var claudeSessionId: String?

    init(
        name: String,
        workingDirectory: String,
        projectId: UUID? = nil,
        branchName: String? = nil,
        worktreePath: String? = nil,
        claudeSessionId: String? = nil
    ) {
        self.name = name
        self.workingDirectory = workingDirectory
        self.projectId = projectId
        self.branchName = branchName
        self.worktreePath = worktreePath
        self.claudeSessionId = claudeSessionId
    }
}
