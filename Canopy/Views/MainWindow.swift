import SwiftUI

/// The primary window layout: sidebar + tab bar + terminal content.
struct MainWindow: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            Sidebar()
        } detail: {
            VStack(spacing: 0) {
                if !appState.sessions.isEmpty {
                    SessionTabBar()
                    Divider()
                }

                // Content: active session, project detail, or welcome
                if let activeSession = appState.activeSession {
                    SessionView(
                        session: activeSession,
                        terminalSession: appState.terminalSession(for: activeSession)
                    )
                    // Use .id to ensure SwiftUI binds the correct terminal view,
                    // but the TerminalSession itself persists in AppState
                    .id(activeSession.id)
                } else if let projectId = appState.selectedProjectId,
                          let project = appState.projects.first(where: { $0.id == projectId }) {
                    ProjectDetailView(project: project)
                        .id(project.id)
                } else {
                    WelcomeView()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
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

/// Shown when no session is active.
struct WelcomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var showHelp = false

    var body: some View {
        VStack(spacing: 16) {
            Text("🌳")
                .font(.system(size: 56))

            Text("Canopy")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Parallel Claude Code sessions with git worktrees")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                Button("Add Project ⌘⇧P") {
                    appState.showAddProjectSheet = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("New Session ⌘T") {
                    appState.createSessionWithPicker()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button("Getting Started ⌘?") {
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
}
