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

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(appState)
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
            }

            CommandGroup(after: .appSettings) {
                Button("Settings...") {
                    appState.showSettings = true
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}
