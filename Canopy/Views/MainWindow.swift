import SwiftUI

/// The primary window layout: sidebar + tab bar + terminal content.
struct MainWindow: View {
    @EnvironmentObject var appState: AppState

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

/// Shown when no session is active.
struct WelcomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var showHelp = false

    var body: some View {
        VStack(spacing: 16) {
            Text("\u{1F333}")
                .font(.system(size: 56))

            Text("Canopy")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Parallel Claude Code sessions with git worktrees")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                Button(action: { appState.showAddProjectSheet = true }) {
                    HStack(spacing: 6) {
                        Text("Add Project")
                        keycap("\u{2318}\u{21E7}P")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: { appState.createSessionWithPicker() }) {
                    HStack(spacing: 6) {
                        Text("New Session")
                        keycap("\u{2318}T")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button("Getting Started \u{2318}?") {
                    showHelp = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .sheet(isPresented: $showHelp) {
            HelpView()
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
}
