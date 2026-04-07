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

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(appState)
                .task {
                    appState.loadProjects()
                    appState.loadSessions()
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
                    if let url = URL(string: "https://github.com/juliensimon/canopy/blob/main/docs/guide.md") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Button("Report an Issue...") {
                    if let url = URL(string: "https://github.com/juliensimon/canopy/issues") {
                        NSWorkspace.shared.open(url)
                    }
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

                Divider()

                Button("Find in Terminal") {
                    appState.showTerminalSearch.toggle()
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
            }

            CommandMenu("Tabs") {
                Picker("Sort By", selection: $appState.tabSortMode) {
                    ForEach(TabSortMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.inline)

                Divider()

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
}
