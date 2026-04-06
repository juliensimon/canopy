import Testing
import Foundation
@testable import Canopy

/// Additional tests for TerminalSession state management and SessionActivity.
@Suite("TerminalSession Edge Cases")
struct TerminalSessionEdgeCaseTests {

    // MARK: - getFullText

    @Test @MainActor func getFullTextEmptyByDefault() {
        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        #expect(session.getFullText() == "")
    }

    // MARK: - Activity State

    @Test @MainActor func initialActivityIsIdle() {
        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        #expect(session.activity == .idle)
    }

    // MARK: - SessionActivity Enum

    @Test func activityRawValues() {
        #expect(SessionActivity.idle.rawValue == "idle")
        #expect(SessionActivity.working.rawValue == "working")
    }

    @Test func activityLabels() {
        #expect(SessionActivity.idle.label == "Idle")
        #expect(SessionActivity.working.label == "Working")
    }

    // MARK: - Multiple State Transitions

    @Test @MainActor func processExitAfterStop() {
        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        session.stop()
        session.handleProcessExit(exitCode: 1)

        // Both should be reflected
        #expect(session.isRunning == false)
        #expect(session.processExited == true)
        #expect(session.exitCode == 1)
    }

    @Test @MainActor func titleChangeMultipleTimes() {
        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        session.handleTitleChange(title: "first")
        session.handleTitleChange(title: "second")
        session.handleTitleChange(title: "third")
        #expect(session.title == "third")
    }

    @Test @MainActor func emptyTitleChange() {
        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        session.handleTitleChange(title: "something")
        session.handleTitleChange(title: "")
        #expect(session.title == "")
    }

    @Test @MainActor func workingDirectoryPreserved() {
        let session = TerminalSession(id: UUID(), workingDirectory: "/custom/path")
        #expect(session.workingDirectory == "/custom/path")
    }

    @Test @MainActor func hasCompletedSetupDefaultFalse() {
        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        #expect(session.hasCompletedSetup == false)
    }

    @Test @MainActor func hasCompletedSetupCanBeSet() {
        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        session.hasCompletedSetup = true
        #expect(session.hasCompletedSetup == true)
    }
}
