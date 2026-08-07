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

    /// Saved prompts for the prompt library.
    @Published var prompts: [SavedPrompt] = []

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
    @Published var terminalSearchQuery: String = ""
    @Published var showCloseConfirmation = false
    @Published var pendingCloseSessionId: UUID?

    /// Tracks which project sections are expanded in the sidebar
    @Published var expandedProjects: Set<UUID> = []

    /// Tracks worktree setup progress for UI feedback
    @Published var worktreeSetupInProgress = false
    @Published var worktreeSetupStatus: String?

    /// Pre-loaded activity data, populated at startup so the dashboard opens instantly.
    @Published var cachedActivityResult: ActivityDataService.ActivityResult?
    @Published var activityIndexing = false

    /// Result of the most recent update check.
    @Published var updateStatus: UpdateStatus = .unknown

    /// Git status for the currently active session.
    @Published var activeGitStatus: GitStatusInfo?

    /// Git diff stats per session, keyed by session ID. Used by sidebar rows.
    @Published var sessionDiffStats: [UUID: GitDiffStat] = [:]

    /// Commits ahead of upstream per session, keyed by session ID.
    @Published var sessionCommitsAhead: [UUID: Int] = [:]

    /// Open PR count per session, keyed by session ID. Used by sidebar rows.
    @Published var sessionPRCount: [UUID: Int] = [:]

    /// Cached PR data per repo path, to avoid hitting gh CLI every poll cycle.
    private var cachedPRsByRepo: [String: [GitPRInfo]] = [:]
    private var lastPRRefreshByRepo: [String: Date] = [:]
    private var gitPollTask: Task<Void, Never>?
    private var agentsPollTask: Task<Void, Never>?

    private let lastUpdateCheckKey = "canopy.lastUpdateCheck"
    private let updateCheckInterval: TimeInterval = 24 * 60 * 60

    /// When true, session mutations skip saving (app is terminating).
    var isTerminating = false

    private let git = GitService()

    /// Injected config directory for persistence. Defaults to ~/.config/canopy.
    private let configDir: String

    init(configDir: String? = nil) {
        self.configDir = configDir ?? (NSHomeDirectory() as NSString).appendingPathComponent(".config/canopy")
        installKeyboardShortcutObservers()
    }

    private func installKeyboardShortcutObservers() {
        // queue: .main guarantees the closure runs on the main thread, but
        // Swift 6 sees it as @Sendable and won't let it touch @MainActor state
        // without a runtime witness. MainActor.assumeIsolated provides exactly
        // that — a safe assertion that we're already on the main actor.
        NotificationCenter.default.addObserver(forName: .canopyShowCommandPalette, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showCommandPalette = true }
        }
        NotificationCenter.default.addObserver(forName: .canopyShowTerminalSearch, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showTerminalSearch = true }
        }
        NotificationCenter.default.addObserver(forName: .canopyShowActivity, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.selectActivity() }
        }
        NotificationCenter.default.addObserver(forName: .canopyToggleSplitTerminal, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let id = self.activeSessionId else { return }
                self.toggleSplitTerminal(for: id)
            }
        }
        NotificationCenter.default.addObserver(forName: .canopySelectTab, object: nil, queue: .main) { [weak self] note in
            // Extract the Sendable Int out of the non-Sendable Notification
            // before crossing into the main-actor isolation domain.
            guard let index = note.object as? Int else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                let sessions = self.orderedSessions
                if index <= sessions.count {
                    self.selectSession(sessions[index - 1].id)
                }
            }
        }
        NotificationCenter.default.addObserver(forName: .canopySelectSession, object: nil, queue: .main) { [weak self] note in
            guard let id = note.userInfo?["sessionId"] as? UUID else { return }
            MainActor.assumeIsolated {
                self?.selectSession(id)
                if let app = NSApp {
                    app.activate(ignoringOtherApps: true)
                }
            }
        }
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
    /// No-op when `id` does not match a live session (stale notification
    /// for a closed session, or observer on a different AppState instance).
    func selectSession(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
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
        let ts = TerminalSession(id: sessionInfo.id, workingDirectory: sessionInfo.workingDirectory, disableAltScreen: settings.disableAltScreen)
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
        NotificationService.shared.postSessionFinished(
            title: projectName ?? "Canopy",
            subtitle: session.name,
            sessionId: sessionId
        )
    }

    /// Unlike the finish notification, this fires even when Canopy is the
    /// active app -- you are usually looking at a DIFFERENT tab while another
    /// one blocks, and a blocked session stays blocked forever until answered.
    private func postNeedsInputNotification(for sessionId: UUID) {
        guard settings.notifyOnNeedsInput else { return }
        guard !NSApp.isActive || sessionId != activeSessionId else { return }
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }

        let projectName = projects.first(where: { $0.id == session.projectId })?.name
        NotificationService.shared.postSessionNeedsInput(
            title: projectName ?? "Canopy",
            subtitle: session.name,
            sessionId: sessionId
        )
    }

    // MARK: - Live Agent Reconciliation

    /// Consecutive idle observations required before a turn counts as
    /// finished. Status flaps to idle between tool calls inside a single
    /// turn, so one observation is not a turn boundary.
    static let confirmedIdlePolls = 2

    /// Whether a busy → idle transition is confirmed rather than a flap.
    static func confirmsFinish(wasWorking: Bool, consecutiveIdleObservations: Int) -> Bool {
        wasWorking && consecutiveIdleObservations >= confirmedIdlePolls
    }

    /// Consecutive idle observations per session, for the flap guard above.
    private var agentIdleObservations: [UUID: Int] = [:]

    /// Applies a poll of `claude agents --json` to the live sessions.
    ///
    /// Claude Code reports what it is actually doing, which the PTY cannot:
    /// a permission prompt emits no bytes, so the 5-second silence heuristic
    /// declared such sessions finished mid-turn and then decayed them to a
    /// grey dot indistinguishable from an empty prompt.
    ///
    /// Gated on the `.off` backend. Container sessions write their registry
    /// entry into the bind-mounted host ~/.claude, but `pid` is a guest
    /// namespace pid and the peer socket is unreachable from the host, so
    /// their status cannot be trusted. `.dockerSbx` shares nothing at all.
    func applyAgents(_ agents: [ClaudeAgent]) {
        for session in sessions {
            guard sandboxBackend(for: session) == .off,
                  let terminal = terminalSessions[session.id] else { continue }

            // Ambiguous means two claudes under one directory (a split
            // terminal, or one the user started by hand). Canopy cannot know
            // which is this tab's, and guessing binds it to the wrong
            // transcript -- so keep the existing behaviour.
            guard case .one(let agent) = ClaudeAgentsService.agent(
                forWorktree: session.workingDirectory, in: agents
            ) else {
                agentIdleObservations[session.id] = 0
                continue
            }

            // Adopt an id only from a conversation that started after this tab
            // opened. Without this, a claude the user has had running in that
            // worktree since yesterday would be adopted on the first poll.
            if let startedAt = agent.startedAt,
               Date(timeIntervalSince1970: startedAt / 1000) >= terminal.openedAt {
                assignClaudeSessionId(agent.sessionId, to: session.id)
            }

            // No opinion -> leave the PTY heuristic in charge. Reset the
            // counter too: "two consecutive idle polls" must mean consecutive.
            // Keeping a stale count across an opinion-less poll lets an idle
            // from before the gap pair with one after it and confirm a finish
            // that never happened.
            guard let reported = ClaudeAgentsService.activity(for: agent.status) else {
                agentIdleObservations[session.id] = 0
                continue
            }

            let previous = terminal.activity
            guard reported == .idle else {
                agentIdleObservations[session.id] = 0
                terminal.setAuthoritativeActivity(reported)
                // Only on the transition: a session sits in `waiting` for as
                // long as the prompt is open, and re-notifying every poll
                // would be a 2-second alarm clock.
                if reported == .needsInput, previous != .needsInput {
                    postNeedsInputNotification(for: session.id)
                }
                continue
            }

            let idleCount = (agentIdleObservations[session.id] ?? 0) + 1
            agentIdleObservations[session.id] = idleCount
            let wasWorking = previous == .working || previous == .needsInput
            guard Self.confirmsFinish(wasWorking: wasWorking, consecutiveIdleObservations: idleCount)
                    || !wasWorking else { continue }

            if wasWorking {
                terminal.setAuthoritativeActivity(.justFinished)
                postFinishNotification(for: session.id)
            } else if previous != .idle {
                // Decays the checkmark on the following poll.
                terminal.setAuthoritativeActivity(.idle)
            }
        }
    }

    /// Polls Claude Code for live session state. Separate from the 10 s git
    /// poll because this drives the activity dots and wants to be responsive.
    ///
    /// One `claude agents --json` invocation per cycle covers every session.
    func startAgentPolling() {
        agentsPollTask?.cancel()
        agentsPollTask = Task { @MainActor [weak self] in
            var consecutiveFailures = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { break }
                // Nothing to reconcile if every session is sandboxed: the
                // subprocess would be pure waste on a 2-second loop.
                guard self.sessions.contains(where: { self.sandboxBackend(for: $0) == .off })
                else { continue }

                guard let agents = await ClaudeAgentsService.fetch() else {
                    consecutiveFailures += 1
                    if consecutiveFailures >= 3 {
                        // Not an error state: the fallback is the behaviour
                        // Canopy shipped with. Say so once and stop trying.
                        NSLog("Canopy: `claude agents --json` unavailable; using the PTY heuristic")
                        return
                    }
                    continue
                }
                consecutiveFailures = 0
                self.applyAgents(agents)
            }
        }
    }

    func stopAgentPolling() {
        agentsPollTask?.cancel()
        agentsPollTask = nil
    }

    // MARK: - Git Status Polling

    /// Fetches git status for the active session and updates `activeGitStatus`.
    func refreshGitStatus() async {
        guard let session = activeSession else {
            activeGitStatus = nil
            return
        }
        let sessionId = session.id
        let path = session.workingDirectory
        guard await git.isGitRepo(path: path) else {
            guard activeSessionId == sessionId else { return }
            activeGitStatus = nil
            return
        }

        let diff = await git.diffStat(repoPath: path)
        let ahead = await git.commitsAhead(repoPath: path)

        // Cache PRs per repo path (60s TTL)
        let prs: [GitPRInfo]
        let lastRefresh = lastPRRefreshByRepo[path] ?? .distantPast
        if Date().timeIntervalSince(lastRefresh) > 60 {
            prs = await git.openPRs(repoPath: path)
            cachedPRsByRepo[path] = prs
            lastPRRefreshByRepo[path] = Date()
        } else {
            prs = cachedPRsByRepo[path] ?? []
        }

        // Guard against stale results if the session changed during async work.
        guard activeSessionId == sessionId else { return }

        activeGitStatus = GitStatusInfo(
            diffStat: diff, commitsAhead: ahead,
            openPRs: prs, changedFiles: diff?.changedFiles ?? []
        )
    }

    /// Refreshes diff stats and commits-ahead for all sessions (sidebar indicators).
    func refreshAllSessionDiffStats() async {
        for session in sessions {
            let path = session.workingDirectory
            guard await git.isGitRepo(path: path) else {
                sessionDiffStats.removeValue(forKey: session.id)
                sessionCommitsAhead.removeValue(forKey: session.id)
                continue
            }
            let diff = await git.diffStat(repoPath: path)
            let ahead = await git.commitsAhead(repoPath: path)
            // The session may have been closed during the awaits above --
            // writing then would resurrect its entries permanently.
            guard sessions.contains(where: { $0.id == session.id }) else { continue }
            if let diff {
                sessionDiffStats[session.id] = diff
            } else {
                sessionDiffStats.removeValue(forKey: session.id)
            }
            if let ahead, ahead > 0 {
                sessionCommitsAhead[session.id] = ahead
            } else {
                sessionCommitsAhead.removeValue(forKey: session.id)
            }
        }
    }

    /// Refreshes PR counts for all sessions by fetching once per unique repo.
    /// Uses git-common-dir to dedupe worktrees sharing the same underlying repo.
    private var lastSessionPRRefresh: Date = .distantPast

    func refreshAllSessionPRCounts(force: Bool = false) async {
        guard force || Date().timeIntervalSince(lastSessionPRRefresh) > 60 else { return }
        lastSessionPRRefresh = Date()

        // Group sessions by common git dir (dedupes worktrees from same repo)
        var repoSessions: [String: [(UUID, String?)]] = [:]
        for session in sessions {
            let path = session.workingDirectory
            guard await git.isGitRepo(path: path) else { continue }
            let commonDir = (try? await git.gitCommonDir(path: path)) ?? path
            var branch = session.branchName
            if branch == nil {
                branch = try? await git.currentBranch(repoPath: path)
            }
            repoSessions[commonDir, default: []].append((session.id, branch))
        }

        // Rebuild from scratch to clear stale entries
        var updatedPRCount: [UUID: Int] = [:]
        for (_, sessionsInRepo) in repoSessions {
            // Use the first session's path to run gh (any worktree will do)
            guard let firstSessionId = sessionsInRepo.first?.0,
                  let firstSession = sessions.first(where: { $0.id == firstSessionId }) else { continue }
            let allPRs = await git.openPRs(repoPath: firstSession.workingDirectory, branch: nil)
            for (sessionId, branch) in sessionsInRepo {
                guard let branch = branch else { continue }
                let count = allPRs.filter { $0.headBranch == branch }.count
                if count > 0 {
                    updatedPRCount[sessionId] = count
                }
            }
        }
        sessionPRCount = updatedPRCount
    }

    /// Starts periodic git status polling for all sessions.
    func startGitStatusPolling() {
        gitPollTask?.cancel()
        gitPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshGitStatus()
                await self.refreshAllSessionDiffStats()
                await self.refreshAllSessionPRCounts()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    /// Stops git status polling.
    func stopGitStatusPolling() {
        gitPollTask?.cancel()
        gitPollTask = nil
    }

    /// Terminates every live terminal session's shell + claude child. Called on
    /// app quit so spawned processes (and any running, paid Claude agent) do not
    /// outlive the app, relying solely on the kernel's SIGHUP to reap them.
    func stopAllSessions() {
        for session in terminalSessions.values { session.stop() }
        for session in splitTerminalSessions.values { session.stop() }
    }

    // MARK: - Update Checking

    /// Called at launch — only fetches if the user has the setting enabled
    /// and we haven't checked in the last 24 hours.
    func checkForUpdatesIfNeeded() async {
        guard settings.checkForUpdatesOnLaunch else { return }
        if let last = UserDefaults.standard.object(forKey: lastUpdateCheckKey) as? Date,
           Date().timeIntervalSince(last) < updateCheckInterval {
            return
        }
        await checkForUpdatesNow()
    }

    /// Manually-triggered or rate-limit-bypassing update check.
    func checkForUpdatesNow() async {
        updateStatus = .checking
        do {
            let release = try await UpdateChecker.fetchLatest()
            UserDefaults.standard.set(Date(), forKey: lastUpdateCheckKey)
            switch UpdateChecker.compareSemver(BuildInfo.version, release.tagName) {
            case .orderedAscending:
                let displayVersion = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
                updateStatus = .available(version: displayVersion, url: release.htmlUrl)
                if !NSApp.isActive {
                    NotificationService.shared.postUpdateAvailable(version: displayVersion)
                }
            case .orderedSame, .orderedDescending:
                updateStatus = .upToDate
            }
        } catch {
            updateStatus = .failed(error.localizedDescription)
        }
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
            let ts = TerminalSession(id: session.id, workingDirectory: session.workingDirectory, disableAltScreen: settings.disableAltScreen)
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
    /// Creates a session in an existing worktree directory (no git worktree
    /// add), resuming the most recent Claude session found for it.
    /// `sandboxBackend` and `claudeFlags` both nil = inherit project/global,
    /// like everywhere else. For flags, nil ("inherit") and "" ("no flags")
    /// are deliberately different values.
    func openWorktreeSession(project: Project, worktreePath: String, branch: String?, claudeFlags: String? = nil, sandboxBackend: SandboxBackend? = nil) {
        let sessionId = ClaudeSessionFinder.findLatestSessionId(for: worktreePath)
        let session = SessionInfo(
            name: branch ?? "session",
            workingDirectory: worktreePath,
            projectId: project.id,
            branchName: branch,
            worktreePath: worktreePath,
            claudeSessionId: sessionId,
            claudeFlags: claudeFlags,
            sandboxBackend: sandboxBackend
        )
        sessions.append(session)
        saveSessions()
    }

    /// Resolves the sandbox backend for a session:
    /// session override → project override → global setting.
    func sandboxBackend(for session: SessionInfo) -> SandboxBackend {
        if let override = session.sandboxBackend {
            return override
        }
        if let project = projects.first(where: { $0.id == session.projectId }) {
            return project.resolvedSandboxBackend(globalSettings: settings)
        }
        return settings.sandboxBackend
    }

    /// Builds the claude command for a session. The backend comes from the
    /// per-session resolution above; flags and image resolve through the
    /// normal project → global chain.
    ///
    /// Worktree sessions additionally mount the project's main repository:
    /// the worktree's `.git` file points there, so git inside the container
    /// is broken without it. Only for real worktrees -- a worktree is never
    /// inside the repo, so the mounts can't overlap (overlapping virtiofs
    /// mounts are silently dropped or hang the VM).
    func claudeCommand(for session: SessionInfo) -> String {
        let project = projects.first { $0.id == session.projectId }
        var extraMounts: [String] = []
        if session.worktreePath != nil,
           let repoPath = project?.repositoryPath,
           // Compare resolved paths: /tmp vs /private/tmp spellings of the
           // same directory must not produce a duplicate (overlapping) mount.
           SandboxBackend.realResolvedPath(repoPath)
               != SandboxBackend.realResolvedPath(session.workingDirectory) {
            extraMounts.append(repoPath)
        }
        // Mounting the main repo fixes the filesystem, but Claude Code's own
        // tool boundary is cwd-scoped independently of what is mounted:
        // verified on CLI 2.1.224, reading a main-repo file from a worktree
        // session under `--permission-mode manual` is refused outright.
        // --add-dir grants it, using the path we already resolved above.
        // session → project → global, mirroring sandboxBackend(for:) above.
        // `??` and not a blank check: a session that explicitly sets "" means
        // "no flags", which is different from inheriting.
        var resolvedFlags = session.claudeFlags ?? project?.claudeFlags ?? settings.claudeFlags
        for path in extraMounts {
            let resolved = SandboxBackend.realResolvedPath(path)
            if !resolved.isEmpty {
                resolvedFlags += " --add-dir \(SandboxBackend.shellSingleQuoted(resolved))"
            }
        }
        return sandboxBackend(for: session).claudeCommand(
            claudeFlags: resolvedFlags,
            sbxFlags: project?.sbxFlags ?? settings.sbxFlags,
            containerImage: project?.containerImage ?? settings.containerImage,
            containerFlags: project?.containerFlags ?? settings.containerFlags,
            extraMountPaths: extraMounts,
            disableAltScreen: settings.disableAltScreen
        )
    }

    /// The full command used to launch `claude` for a session, plus the
    /// Claude session ID this call newly assigned (nil when none was).
    ///
    /// This lived inside a SwiftUI `.onAppear`, where it could not be tested.
    /// It also carries three rules that are easy to get wrong:
    ///
    /// 1. `--session-id` and `--resume` are mutually exclusive absent
    ///    `--fork-session`, so exactly one is emitted.
    /// 2. Reusing a session ID in the same project directory aborts the CLI
    ///    ("Session ID <id> is already in use"). An app restart re-runs this
    ///    path with the same persisted `SessionInfo.id`, so once an id is
    ///    known the flags must swap to `--resume`.
    /// 3. `claudeSessionId` is decoded straight from sessions.json and gets
    ///    interpolated into a shell command. The discovery path validates it
    ///    as a UUID; this one must too, or a junk value reaches the shell.
    ///
    /// The id is seeded from `SessionInfo.id` -- already a stable persisted
    /// per-tab UUID -- so there is no new Codable field and no migration.
    /// Uniqueness is scoped per project directory, so reuse across worktrees
    /// is a non-issue.
    func claudeLaunchCommand(for session: SessionInfo) -> (command: String, assignedId: String?) {
        var command = claudeCommand(for: session)
        let backend = sandboxBackend(for: session)
        var assignedId: String?

        // Skipped for sbx -- its session files live inside the ephemeral
        // microVM, so neither resuming nor assigning means anything there.
        // The Apple container backend mounts ~/.claude from the host.
        if backend.supportsResume {
            if let existing = session.claudeSessionId, UUID(uuidString: existing) != nil {
                command += " --resume \(existing)"
            } else {
                if let junk = session.claudeSessionId {
                    NSLog("Canopy: discarding non-UUID claudeSessionId %@ for session %@",
                          junk, session.id.uuidString)
                }
                let fresh = session.id.uuidString
                command += " --session-id \(fresh)"
                assignedId = fresh
            }
        }

        if let nameFlag = session.claudeNameFlag {
            command += " \(nameFlag)"
        }
        return (command, assignedId)
    }

    /// Records an assigned Claude session ID. Must be called before the
    /// command is actually sent: a crash in between would otherwise leave a
    /// session file on disk that the next launch collides with.
    func assignClaudeSessionId(_ claudeSessionId: String, to sessionId: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }),
              sessions[index].claudeSessionId != claudeSessionId else { return }
        sessions[index].claudeSessionId = claudeSessionId
        saveSessions()
    }

    func createWorktreeSession(
        project: Project,
        branchName: String,
        baseBranch: String,
        claudeFlags: String? = nil,
        sandboxBackend: SandboxBackend? = nil
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
                worktreePath: worktreePath,
                claudeFlags: claudeFlags,
                sandboxBackend: sandboxBackend
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
        sessionDiffStats.removeValue(forKey: id)
        sessionCommitsAhead.removeValue(forKey: id)
        sessionPRCount.removeValue(forKey: id)
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

    /// Reorders plain (non-project) sessions (sidebar .onMove).
    /// `source`/`destination` are indices into the FILTERED plain-session
    /// list -- applying them to the full array moved arbitrary other
    /// sessions when project sessions interleave.
    func movePlainSessions(from source: IndexSet, to destination: Int) {
        var plain = sessions.filter { $0.projectId == nil }
        plain.move(fromOffsets: source, toOffset: destination)

        var result: [SessionInfo] = []
        var plainIndex = 0
        for session in sessions {
            if session.projectId == nil {
                result.append(plain[plainIndex])
                plainIndex += 1
            } else {
                result.append(session)
            }
        }
        sessions = result
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

    private var promptsFilePath: String {
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        return (configDir as NSString).appendingPathComponent("prompts.json")
    }

    func loadPrompts() {
        let path = promptsFilePath
        guard let data = FileManager.default.contents(atPath: path) else { return }
        // Back up before decoding so a corrupt prompt library is preserved
        // rather than silently dropped and overwritten with [] on the next save.
        let backupPath = (path as NSString).deletingPathExtension + ".backup.json"
        try? FileManager.default.removeItem(atPath: backupPath)
        try? FileManager.default.copyItem(atPath: path, toPath: backupPath)
        guard let decoded = try? JSONDecoder().decode([SavedPrompt].self, from: data) else {
            NSLog("Canopy: prompts.json failed to decode; previous content kept at %@", backupPath)
            return
        }
        prompts = decoded
    }

    func savePrompts() {
        guard let data = try? JSONEncoder().encode(prompts) else { return }
        // Atomic write so a crash mid-write can't corrupt the file (which would
        // then decode to nothing and be lost on the next save).
        do {
            try data.write(to: URL(fileURLWithPath: promptsFilePath), options: .atomic)
        } catch {
            NSLog("Canopy: failed to write %@ (%@)", promptsFilePath, "\(error)")
        }
    }

    func sendPrompt(_ prompt: SavedPrompt, to session: SessionInfo) {
        let project = projects.first(where: { $0.id == session.projectId })
        let dir = (session.workingDirectory as NSString).lastPathComponent
        let resolved = resolvePrompt(
            prompt.body,
            branchName: session.branchName,
            projectName: project?.name,
            dir: dir
        )
        terminalSessions[session.id]?.sendCommand(resolved)
    }

    /// Finds a live session whose worktree is the same on-disk location as
    /// `worktreePath`, comparing with symlink-resolving `GitService.samePath`.
    /// git reports the resolved `/private/...` form while a stored worktree path
    /// may keep the raw spelling (`/tmp`), so a raw `==` would miss it and leak
    /// the session — a tab left running over a deleted worktree (the same path
    /// divergence PR #32 fixed for `isMainWorktree`).
    func session(forWorktreePath worktreePath: String) -> SessionInfo? {
        sessions.first { $0.worktreePath.map { GitService.samePath($0, worktreePath) } ?? false }
    }

    func saveSessions() {
        guard !isTerminating else { return }
        guard let data = try? JSONEncoder().encode(sessions) else {
            NSLog("Canopy: failed to encode sessions for persistence")
            return
        }
        // Atomic: a crash mid-write must not corrupt the file (a corrupt
        // file decodes as no sessions, and the next save makes that final).
        do {
            try data.write(to: URL(fileURLWithPath: sessionsFilePath), options: .atomic)
        } catch {
            NSLog("Canopy: failed to write %@ (%@)", sessionsFilePath, "\(error)")
        }
    }

    /// Save sessions and mark as terminating so cleanup doesn't overwrite the file.
    func saveSessionsBeforeTermination() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: URL(fileURLWithPath: sessionsFilePath), options: .atomic)
        isTerminating = true
    }

    func loadSessions() {
        let path = sessionsFilePath
        guard let data = FileManager.default.contents(atPath: path) else { return }
        // Backup before decoding, like projects.json -- if this file is
        // corrupt, the next save would otherwise overwrite it with [].
        let backupPath = (path as NSString).deletingPathExtension + ".backup.json"
        try? FileManager.default.removeItem(atPath: backupPath)
        try? FileManager.default.copyItem(atPath: path, toPath: backupPath)
        guard var decoded = try? JSONDecoder().decode([SessionInfo].self, from: data) else {
            NSLog("Canopy: sessions.json failed to decode; previous content kept at %@", backupPath)
            return
        }
        // Fill in missing Claude session IDs from disk -- never overwrite one
        // we already have. An established id is user data: the newest-mtime
        // heuristic cannot tell which conversation belongs to which tab, so an
        // unrelated `claude` run in the same directory would otherwise hijack
        // the tab and get `--resume`d into on the next launch.
        for i in decoded.indices where decoded[i].claudeSessionId == nil {
            decoded[i].claudeSessionId = ClaudeSessionFinder.findLatestSessionId(
                for: decoded[i].workingDirectory
            )
        }
        sessions = decoded
        activeSessionId = sessions.first?.id
    }

    func loadProjects() {
        let path = projectsFilePath
        guard let data = FileManager.default.contents(atPath: path) else { return }
        // Back up BEFORE decoding so a corrupt file is preserved: a failed
        // decode followed by the next save would otherwise overwrite it with [],
        // permanently losing every project's repo path and worktree config.
        let backupPath = (configDir as NSString).appendingPathComponent("projects.backup.json")
        try? FileManager.default.removeItem(atPath: backupPath)
        try? FileManager.default.copyItem(atPath: path, toPath: backupPath)
        guard let decoded = try? JSONDecoder().decode([Project].self, from: data) else {
            NSLog("Canopy: projects.json failed to decode; previous content kept at %@", backupPath)
            return
        }

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
        // Atomic write so a crash mid-write can't corrupt the file (which would
        // then decode to nothing and be lost on the next save).
        do {
            try data.write(to: URL(fileURLWithPath: projectsFilePath), options: .atomic)
        } catch {
            NSLog("Canopy: failed to write %@ (%@)", projectsFilePath, "\(error)")
        }
    }

    // MARK: - Activity Data Pre-loading

    /// Indexes all Claude Code JSONL files in the background at startup.
    func preloadActivityData() {
        activityIndexing = true
        Task.detached(priority: .utility) {
            let result = ActivityDataService.loadData()
            await MainActor.run {
                self.cachedActivityResult = result
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

    /// A shell-safe Claude Code display-name flag for worktree sessions.
    /// Plain sessions start with generic names that may be renamed
    /// asynchronously, so passing those names would race the rename.
    /// A branch is required too: `openWorktreeSession` names detached-HEAD
    /// worktrees the literal "session", and labelling every one of them
    /// identically in the /resume picker is worse than letting Claude
    /// generate its own name.
    var claudeNameFlag: String? {
        guard isWorktreeSession, branchName != nil,
              let sanitized = Self.sanitizedClaudeName(name) else { return nil }
        return "--name \(SandboxBackend.shellSingleQuoted(sanitized))"
    }

    /// Removes terminal control characters, normalizes whitespace, and keeps
    /// Claude's display name compact. Shell quoting happens only after this
    /// validation step.
    static func sanitizedClaudeName(_ name: String) -> String? {
        // Whitespace controls (\n, \t, \r) are separators: map them to a space
        // so the collapse below keeps word boundaries. Dropping them outright
        // welds words together ("line\nbreak" -> "linebreak"). Other controls
        // carry no width and are removed.
        let scalars = name.unicodeScalars.compactMap { scalar -> Unicode.Scalar? in
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { return " " }
            if CharacterSet.controlCharacters.contains(scalar) { return nil }
            return scalar
        }
        let collapsed = String(String.UnicodeScalarView(scalars))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let sanitized = String(collapsed.prefix(64))
        return sanitized.isEmpty ? nil : sanitized
    }

    /// Claude Code session ID to resume (UUID from ~/.claude/projects/).
    /// When set, Claude is started with `--resume <id>`.
    var claudeSessionId: String?

    /// Per-session sandbox override chosen at creation time.
    /// nil = inherit the project/global setting.
    var sandboxBackend: SandboxBackend?

    /// Per-session `claude` flags chosen at creation time, mirroring the
    /// sandbox override's session → project → global chain.
    ///
    /// nil (inherit) and "" (explicitly no flags) are DIFFERENT: collapsing
    /// them with `?? ""` reintroduces the bug ClaudeOverrideDefaults exists to
    /// prevent, where a seeded value silently becomes an override.
    var claudeFlags: String?

    init(
        id: UUID = UUID(),
        name: String,
        workingDirectory: String,
        projectId: UUID? = nil,
        branchName: String? = nil,
        worktreePath: String? = nil,
        claudeSessionId: String? = nil,
        claudeFlags: String? = nil,
        sandboxBackend: SandboxBackend? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.workingDirectory = workingDirectory
        self.projectId = projectId
        self.branchName = branchName
        self.worktreePath = worktreePath
        self.claudeSessionId = claudeSessionId
        self.claudeFlags = claudeFlags
        self.sandboxBackend = sandboxBackend
        self.createdAt = createdAt
    }
}
