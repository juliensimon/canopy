import Testing
import Foundation
@testable import Canopy

/// On app quit, every live terminal session — main AND split — must be stopped
/// so its shell + claude child (a running, paid agent) doesn't outlive the app,
/// relying solely on the kernel's SIGHUP to reap it. The `willTerminate` handler
/// calls `stopAllSessions()`; this pins that it stops sessions in BOTH the main
/// and split dictionaries (a fix that stopped only one would silently leak the
/// other).
@Suite("Stop All Sessions On Quit")
@MainActor
struct StopAllSessionsTests {
    @Test func stopsBothMainAndSplitSessions() {
        let state = AppState(configDir: NSTemporaryDirectory() + "cfg-\(UUID().uuidString)")
        let main = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        let split = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        main.isRunning = true
        split.isRunning = true
        state.terminalSessions[main.id] = main
        state.splitTerminalSessions[split.id] = split

        state.stopAllSessions()

        #expect(!main.isRunning, "main session was not stopped on quit")
        #expect(!split.isRunning, "split session was not stopped on quit")
    }
}
