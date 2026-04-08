import SwiftUI

/// The primary window layout: sidebar + tab bar + terminal content.
struct MainWindow: View {
    @EnvironmentObject var appState: AppState
    @State private var showSplash = true
    @State private var splashOpacity: Double = 0
    @State private var textOpacity: Double = 0

    var body: some View {
        ZStack {
            NavigationSplitView {
                Sidebar()
            } detail: {
                VStack(spacing: 0) {
                    if !appState.sessions.isEmpty {
                        SessionTabBar()
                        Divider()
                    }

                    // Content with crossfade
                    ZStack {
                        if let activeSession = appState.activeSession {
                            TerminalInsetView(session: activeSession, appState: appState)
                                .id(activeSession.id)
                                .transition(.opacity)
                        } else if appState.showActivity {
                            ActivityView()
                        } else if let projectId = appState.selectedProjectId,
                                  let project = appState.projects.first(where: { $0.id == projectId }) {
                            ProjectDetailView(project: project)
                                .id(project.id)
                        } else {
                            WelcomeView()
                        }
                    }
                    .animation(.easeInOut(duration: 0.15), value: appState.activeSessionId)


                }
            }
            .navigationSplitViewStyle(.balanced)

            // Command palette overlay
            if appState.showCommandPalette {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture { appState.showCommandPalette = false }

                VStack {
                    CommandPaletteView()
                        .padding(.top, 80)
                    Spacer()
                }
            }

            // Splash screen — sessions load underneath
            if showSplash {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
                    .overlay {
                        ZStack {
                            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 768, height: 768)
                                .mask(
                                    RadialGradient(
                                        gradient: Gradient(stops: [
                                            .init(color: .white, location: 0),
                                            .init(color: .white, location: 0.55),
                                            .init(color: .clear, location: 0.85)
                                        ]),
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 384
                                    )
                                )

                            if let logoImage = Self.loadLogo() {
                                Image(nsImage: logoImage)
                                    .resizable()
                                    .interpolation(.high)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: 300)
                                    .opacity(textOpacity)
                                    .offset(y: -192)
                            }
                        }
                        .opacity(splashOpacity)
                    }
                    .onAppear {
                        Task { @MainActor in
                            withAnimation(.easeIn(duration: 1.0)) {
                                splashOpacity = 1
                            }
                            try? await Task.sleep(for: .seconds(0.8))
                            withAnimation(.easeIn(duration: 1.0)) {
                                textOpacity = 1
                            }
                            try? await Task.sleep(for: .seconds(3.0))
                            withAnimation(.easeOut(duration: 1.0)) {
                                splashOpacity = 0
                            }
                            try? await Task.sleep(for: .seconds(1.0))
                            showSplash = false
                        }
                    }
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .alert("Close Session?", isPresented: $appState.showCloseConfirmation) {
            Button("Close", role: .destructive) {
                if let id = appState.pendingCloseSessionId {
                    appState.performCloseSession(id: id)
                }
            }
            Button("Cancel", role: .cancel) {
                appState.pendingCloseSessionId = nil
            }
        } message: {
            Text("The session is still running. Are you sure you want to close it?")
        }
        .onAppear {
            appState.loadProjects()
        }
    }

    /// Load the logo PNG from the app bundle or Resources directory.
    private static func loadLogo() -> NSImage? {
        // Xcode build: bundle resource
        if let path = Bundle.main.path(forResource: "CanopyLogo", ofType: "png") {
            return NSImage(contentsOfFile: path)
        }
        // SPM/bundle.sh: relative to executable
        if let exec = Bundle.main.executablePath {
            let resourcesDir = ((exec as NSString).deletingLastPathComponent as NSString).appendingPathComponent("../Resources/CanopyLogo.png")
            return NSImage(contentsOfFile: resourcesDir)
        }
        return nil
    }
}

/// The view for a single active session — wraps the terminal.
/// The TerminalSession is owned by AppState so it persists across tab switches.
struct SessionView: View {
    let session: SessionInfo
    @EnvironmentObject var appState: AppState
    @ObservedObject var terminalSession: TerminalSession

    var body: some View {
        TerminalContentView(session: terminalSession)
            .onAppear {
                guard !terminalSession.hasCompletedSetup else { return }
                terminalSession.hasCompletedSetup = true

                terminalSession.onProcessExit = { sessionId in
                    appState.closeSession(id: sessionId, force: true)
                }

                // Auto-start Claude Code if enabled.
                let project = appState.projects.first { $0.id == session.projectId }
                let shouldStart = project?.shouldAutoStartClaude(globalSettings: appState.settings)
                    ?? appState.settings.autoStartClaude
                if shouldStart {
                    var command = project?.resolvedClaudeCommand(globalSettings: appState.settings)
                        ?? appState.settings.claudeCommand
                    // Resume a specific Claude session if we have its ID
                    if let sessionId = session.claudeSessionId {
                        command += " --resume \(sessionId)"
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        terminalSession.sendCommand(command)
                    }
                }
            }
    }
}

/// Wraps SessionView with a rounded inset container and branch name overlay.
/// Optionally shows a split terminal pane below the main terminal.
struct TerminalInsetView: View {
    let session: SessionInfo
    @ObservedObject var appState: AppState
    @State private var showBranchLabel = true

    private var isSplitOpen: Bool {
        appState.isSplitOpen(for: session.id)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if isSplitOpen {
                VSplitView {
                    mainTerminal
                    splitTerminal
                }
            } else {
                mainTerminal
            }

            // Branch name overlay
            if let branch = session.branchName, showBranchLabel {
                Text(branch)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            if appState.showTerminalSearch {
                VStack {
                    TerminalSearchBar(
                        terminalSession: appState.terminalSession(for: session),
                        isVisible: $appState.showTerminalSearch
                    )
                    Spacer()
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            showBranchLabel = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeOut(duration: 0.5)) {
                    showBranchLabel = false
                }
            }
        }
    }

    private var mainTerminal: some View {
        SessionView(
            session: session,
            terminalSession: appState.terminalSession(for: session)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
        .padding(4)
    }

    @ViewBuilder
    private var splitTerminal: some View {
        if let splitSession = appState.splitTerminalSessions[session.id] {
            SplitTerminalView(terminalSession: splitSession)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
                .padding(4)
                .frame(minHeight: 100)
        }
    }
}

/// A plain shell terminal for the split pane. No Claude auto-start, no process exit handling.
struct SplitTerminalView: View {
    @ObservedObject var terminalSession: TerminalSession

    var body: some View {
        TerminalContentView(session: terminalSession)
    }
}

/// Shown when no session is active. Branches on whether projects exist.
struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.projects.isEmpty {
                FirstLaunchView()
            } else {
                ProjectQuickLaunchView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

private func keycap(_ key: String) -> some View {
    Text(key)
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.1))
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
        )
}

/// Shown inside WelcomeView when no projects exist yet.
private struct FirstLaunchView: View {
    @EnvironmentObject var appState: AppState
    @State private var showHelp = false

    var body: some View {
        VStack(spacing: 16) {
            Text("🌳")
                .font(.system(size: 48))

            VStack(spacing: 6) {
                Text("Canopy")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Run multiple Claude Code sessions in parallel,\neach on its own git branch.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 6) {
                workflowStep(icon: "🗂", title: "Add a project", detail: "Point to any git repo", dimmed: false)
                workflowStep(icon: "🌿", title: "Create a worktree", detail: "Isolated branch, own directory", dimmed: true)
                workflowStep(icon: "⚡", title: "Claude starts automatically", detail: "Run parallel tasks without conflicts", dimmed: true)
            }
            .padding(.vertical, 4)

            Button(action: { appState.showAddProjectSheet = true }) {
                HStack(spacing: 6) {
                    Text("Add Project")
                    keycap("⌘⇧P")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button(action: { appState.createSessionWithPicker() }) {
                Text("or  New Session ⌘T  to open a plain terminal")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .font(.footnote)

            Button(action: { showHelp = true }) {
                HStack(spacing: 4) {
                    keycap("⌘?")
                    Text("help")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.quaternary)
            .font(.system(size: 10))
        }
        .frame(maxWidth: 300)
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
    }

    private func workflowStep(icon: String, title: String, detail: String, dimmed: Bool) -> some View {
        HStack(spacing: 10) {
            Text(icon)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .opacity(dimmed ? 0.4 : 1)
    }
}

/// One row in ProjectQuickLaunchView — shows a project with Session and Worktree actions.
private struct ProjectLaunchRow: View {
    let project: Project
    let onSession: () -> Void
    let onWorktree: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(ProjectColor.color(for: project.colorIndex))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 13, weight: .semibold))
                Text(shortenedPath(project.repositoryPath))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: onWorktree) {
                Text("Worktree")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(action: onSession) {
                Text("Session")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func shortenedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

/// Shown inside WelcomeView when at least one project exists.
private struct ProjectQuickLaunchView: View {
    @EnvironmentObject var appState: AppState
    @State private var showHelp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("START A SESSION")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(1)
                    .frame(maxWidth: .infinity, alignment: .center)

                ForEach(appState.projects) { project in
                    ProjectLaunchRow(
                        project: project,
                        onSession: {
                            appState.createSession(directory: project.repositoryPath)
                        },
                        onWorktree: {
                            appState.worktreeSheetProjectId = project.id
                            appState.showNewWorktreeSheet = true
                        }
                    )
                }

                Button(action: { appState.showAddProjectSheet = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 12))
                        HStack(spacing: 6) {
                            Text("Add another project")
                            keycap("⌘⇧P")
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4]))
                )

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        keycap("⌘K")
                        Text("command palette")
                    }
                    Text("·")
                    HStack(spacing: 4) {
                        keycap("⌘?")
                        Button("help") { showHelp = true }
                            .buttonStyle(.plain)
                            .foregroundStyle(.quaternary)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(20)
        }
        .frame(maxWidth: 480)
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
    }
}
