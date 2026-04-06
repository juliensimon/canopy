import SwiftUI
import AppKit

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

    /// Terminal sessions keyed by session ID. Kept alive across tab switches.
    var terminalSessions: [UUID: TerminalSession] = [:]

    /// App settings (auto-start claude, flags, etc.)
    @Published var settings = TempoSettings.load()

    /// UI triggers for sheets
    @Published var showNewWorktreeSheet = false
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

    /// Creates a plain session in the given directory, or shows a picker if no directory is provided.
    func createSession(name: String? = nil, directory: String? = nil) {
        let workDir: String
        if let dir = directory {
            workDir = dir
        } else {
            // Show directory picker
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.message = "Choose working directory for the new session"
            panel.prompt = "Open"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            workDir = url.path
        }

        let index = sessions.count + 1
        let dirName = (workDir as NSString).lastPathComponent
        let sessionName = name ?? dirName

        let session = SessionInfo(name: sessionName, workingDirectory: workDir)
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

    /// Projects are saved to ~/.config/tempo/projects.json
    private var projectsFilePath: String {
        let configDir = (NSHomeDirectory() as NSString).appendingPathComponent(".config/tempo")
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

    init(
        name: String,
        workingDirectory: String,
        projectId: UUID? = nil,
        branchName: String? = nil,
        worktreePath: String? = nil
    ) {
        self.name = name
        self.workingDirectory = workingDirectory
        self.projectId = projectId
        self.branchName = branchName
        self.worktreePath = worktreePath
    }
}
