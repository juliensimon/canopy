import Testing
import Foundation
@testable import Tempo

/// Tests for TerminalSession — environment building, process exit, callbacks.
/// We can't test actual PTY/terminal rendering without a window, but we can
/// test the logic around environment construction and state management.
@Suite("TerminalSession")
struct TerminalSessionTests {

    @Test @MainActor func initialState() {
        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        #expect(session.isRunning == false)
        #expect(session.processExited == false)
        #expect(session.exitCode == nil)
        #expect(session.title == "")
    }

    @Test @MainActor func stopClearsState() {
        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        session.stop()
        #expect(session.isRunning == false)
    }

    @Test @MainActor func handleProcessExitSetsState() {
        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        session.handleProcessExit(exitCode: 0)

        #expect(session.isRunning == false)
        #expect(session.processExited == true)
        #expect(session.exitCode == 0)
    }

    @Test @MainActor func handleProcessExitWithNonZeroCode() {
        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        session.handleProcessExit(exitCode: 127)
        #expect(session.exitCode == 127)
    }

    @Test @MainActor func handleProcessExitWithNilCode() {
        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        session.handleProcessExit(exitCode: nil)
        #expect(session.exitCode == nil)
        #expect(session.processExited == true)
    }

    @Test @MainActor func handleProcessExitCallsCallback() async {
        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        var callbackId: UUID?
        session.onProcessExit = { id in callbackId = id }

        session.handleProcessExit(exitCode: 0)
        #expect(callbackId == session.id)
    }

    @Test @MainActor func handleTitleChange() {
        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        session.handleTitleChange(title: "zsh - ~/projects")
        #expect(session.title == "zsh - ~/projects")
    }

    @Test @MainActor func sendWithoutStartDoesNotCrash() {
        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        // Should silently no-op, not crash
        session.send(text: "hello")
        session.sendCommand("ls")
    }
}
