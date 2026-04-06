import Testing
import Foundation
@testable import Canopy

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

    // MARK: - ANSI Escape Stripping

    @Test func stripPlainText() {
        let input = "Hello, world!"
        #expect(TerminalSession.stripAnsiEscapes(input) == "Hello, world!")
    }

    @Test func stripCSIColorCodes() {
        let input = "\u{1b}[38;2;215;119;87mHello\u{1b}[0m world"
        #expect(TerminalSession.stripAnsiEscapes(input) == "Hello world")
    }

    @Test func stripCSICursorMovement() {
        let input = "\u{1b}[2AUp two\u{1b}[3BDown three"
        #expect(TerminalSession.stripAnsiEscapes(input) == "Up twoDown three")
    }

    @Test func stripCSIEraseSequences() {
        let input = "\u{1b}[2JCleared\u{1b}[K"
        #expect(TerminalSession.stripAnsiEscapes(input) == "Cleared")
    }

    @Test func stripOSCTitleSequence() {
        let input = "\u{1b}]2;Window Title\u{07}Visible text"
        #expect(TerminalSession.stripAnsiEscapes(input) == "Visible text")
    }

    @Test func stripOSCWithSTTerminator() {
        let input = "\u{1b}]0;Title\u{1b}\\Content"
        #expect(TerminalSession.stripAnsiEscapes(input) == "Content")
    }

    @Test func stripMixedSequences() {
        let input = "\u{1b}[1m\u{1b}[32m➜\u{1b}[0m \u{1b}[36mproject\u{1b}[0m git:(\u{1b}[31mmaster\u{1b}[0m)"
        #expect(TerminalSession.stripAnsiEscapes(input) == "➜ project git:(master)")
    }

    @Test func stripCarriageReturns() {
        let input = "line1\r\nline2\r\n"
        #expect(TerminalSession.stripAnsiEscapes(input) == "line1\nline2\n")
    }

    @Test func stripDECPrivateMode() {
        let input = "\u{1b}[?2004hText\u{1b}[?2004l"
        #expect(TerminalSession.stripAnsiEscapes(input) == "Text")
    }

    @Test func stripEmptyString() {
        #expect(TerminalSession.stripAnsiEscapes("") == "")
    }

    @Test func stripOnlyEscapeCodes() {
        let input = "\u{1b}[0m\u{1b}[1m\u{1b}[39m"
        #expect(TerminalSession.stripAnsiEscapes(input) == "")
    }
}
