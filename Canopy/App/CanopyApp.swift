import SwiftUI
import AppKit
/// Custom NSApplicationDelegate that ensures the app is properly activated
/// as a foreground application. Without this, SPM-built executables appear
/// as background processes — windows show up but don't receive keyboard events.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Suppress SwiftTerm's "Unhandled DEC Private Mode" log noise
        freopen("/dev/null", "w", stderr)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct CanopyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @State private var showAbout = false
    @State private var showHelp = false
    @State private var showShortcuts = false
    @State private var updateSheetState: UpdateSheetState?

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(appState)
                .task {
                    appState.loadProjects()
                    appState.loadSessions()
                    appState.preloadActivityData()
                    await runStartupUpdateCheck()
                }
                .sheet(isPresented: $appState.showSettings) {
                    SettingsView(settings: appState.settings)
                        .environmentObject(appState)
                }
                .sheet(isPresented: $showAbout) {
                    AboutView()
                }
                .sheet(isPresented: $showHelp) {
                    HelpView()
                }
                .sheet(isPresented: $showShortcuts) {
                    ShortcutsView()
                }
                .sheet(item: Binding(
                    get: { updateSheetState.map(IdentifiedUpdateState.init) },
                    set: { updateSheetState = $0?.state }
                )) { identified in
                    UpdateCheckSheet(state: identified.state) {
                        updateSheetState = nil
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    appState.saveSessionsBeforeTermination()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            // File menu
            CommandGroup(after: .newItem) {
                Button("New Session") {
                    appState.createSessionWithPicker()
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button("New Worktree Session...") {
                    appState.worktreeSheetProjectId = nil
                    appState.showNewWorktreeSheet = true
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()

                Button("Add Project...") {
                    appState.showAddProjectSheet = true
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }

            // App menu
            CommandGroup(replacing: .appInfo) {
                Button("About Canopy") {
                    showAbout = true
                }
            }

            // Help menu
            CommandGroup(replacing: .help) {
                Button("Canopy Help") {
                    showHelp = true
                }
                .keyboardShortcut("?", modifiers: [.command])

                Button("Keyboard Shortcuts") {
                    showShortcuts = true
                }

                Divider()

                Button("User Guide") {
                    if let url = URL(string: "https://github.com/juliensimon/canopy/blob/master/docs/guide.md") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Button("Report an Issue...") {
                    if let url = URL(string: "https://github.com/juliensimon/canopy/issues") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Divider()

                Button("Check for Updates...") {
                    Task { await runManualUpdateCheck() }
                }
            }

            CommandGroup(after: .appSettings) {
                Button("Settings...") {
                    appState.showSettings = true
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandMenu("Session") {
                Button("Command Palette") {
                    appState.showCommandPalette.toggle()
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Find in Terminal") {
                    appState.showTerminalSearch = true
                }
                .keyboardShortcut("f", modifiers: .command)

                Divider()

                Button("Toggle Split Terminal") {
                    if let id = appState.activeSessionId {
                        appState.toggleSplitTerminal(for: id)
                    }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Divider()

                Button("Activity Dashboard") {
                    appState.selectActivity()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Divider()

                Picker("Sort Tabs By", selection: $appState.tabSortMode) {
                    ForEach(TabSortMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.inline)

                Button("Cycle Sort Mode") {
                    let allCases = TabSortMode.allCases
                    let currentIndex = allCases.firstIndex(of: appState.tabSortMode) ?? 0
                    let nextIndex = (currentIndex + 1) % allCases.count
                    appState.tabSortMode = allCases[nextIndex]
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                ForEach(1...9, id: \.self) { index in
                    Button("Tab \(index)") {
                        let sessions = appState.orderedSessions
                        if index <= sessions.count {
                            appState.selectSession(sessions[index - 1].id)
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
                }
            }
        }
    }

    // MARK: - Update check

    /// Manual "Check for Updates…" from the Help menu. Always shows the sheet,
    /// including on `.upToDate` and `.failed` — user asked, so give feedback.
    @MainActor
    private func runManualUpdateCheck() async {
        updateSheetState = .checking
        let checker = UpdateChecker()
        let result = await checker.checkForUpdates()
        updateSheetState = Self.sheetState(for: result)
        recordCheckTimestamp(result: result)
    }

    /// Startup auto-check. Silent unless an update is available — never
    /// presents `.upToDate` or `.failed`. Throttled to once per day via
    /// `CanopySettings.lastUpdateCheck`.
    @MainActor
    private func runStartupUpdateCheck() async {
        guard appState.settings.autoCheckForUpdates else { return }
        guard UpdateChecker.shouldAutoCheck(lastCheck: appState.settings.lastUpdateCheck) else { return }
        let checker = UpdateChecker()
        let result = await checker.checkForUpdates()
        recordCheckTimestamp(result: result)
        if case .available = result {
            updateSheetState = Self.sheetState(for: result)
        }
    }

    @MainActor
    private func recordCheckTimestamp(result: UpdateCheckResult) {
        // Only record successful checks — don't let a transient network error
        // block the next day's retry.
        if case .failed = result { return }
        appState.settings.lastUpdateCheck = Date()
        appState.settings.save()
    }

    private static func sheetState(for result: UpdateCheckResult) -> UpdateSheetState {
        switch result {
        case .upToDate: .upToDate
        case .available(let version, let url): .available(version: version, url: url)
        case .failed(let message): .failed(message: message)
        }
    }
}

/// Wraps `UpdateSheetState` with a stable identity so SwiftUI's
/// `.sheet(item:)` can observe it. A fresh identity per state transition is
/// fine — the sheet only exists while non-nil.
private struct IdentifiedUpdateState: Identifiable {
    let id = UUID()
    let state: UpdateSheetState
}
