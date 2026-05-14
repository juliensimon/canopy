import Testing
import Foundation
import AppKit
@testable import Canopy

/// Covers the output-parsing and buffering logic that `start(frame:)` normally
/// exercises at runtime: visible-content detection, raw-output accumulation,
/// the ring-buffer trim, and activity transitions driven by incoming data.
@Suite("TerminalSession Output Handling")
struct TerminalSessionOutputTests {

    // MARK: - containsVisibleContent

    @Test func visibleContentDetectsPlainAscii() {
        #expect(TerminalSession.containsVisibleContent(Data("hello".utf8)))
    }

    @Test func visibleContentIgnoresPureCSISequence() {
        // Color reset only — no printable payload.
        #expect(!TerminalSession.containsVisibleContent(Data([0x1B, 0x5B, 0x30, 0x6D])))
    }

    @Test func visibleContentIgnoresOSCTitleWithBEL() {
        // ESC ] 0 ; title BEL — window-title update, no visible chars.
        var bytes: [UInt8] = [0x1B, 0x5D, 0x30, 0x3B]
        bytes.append(contentsOf: Array("Window".utf8))
        bytes.append(0x07)
        #expect(!TerminalSession.containsVisibleContent(Data(bytes)))
    }

    @Test func visibleContentIgnoresWhitespaceAndNewlines() {
        #expect(!TerminalSession.containsVisibleContent(Data([0x20, 0x0A, 0x0D, 0x08])))
    }

    @Test func visibleContentDetectsPayloadAfterCSI() {
        // ESC [ 1 m 'X' — bold sequence followed by a printable character.
        #expect(TerminalSession.containsVisibleContent(Data([0x1B, 0x5B, 0x31, 0x6D, 0x58])))
    }

    @Test func visibleContentEmptyDataIsNotVisible() {
        #expect(!TerminalSession.containsVisibleContent(Data()))
    }

    // MARK: - handleOutputData / getFullText

    @Test @MainActor func handleOutputAppendsToRawBuffer() {
        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        session.handleOutputData(Data("first line\n".utf8))
        session.handleOutputData(Data("second line\n".utf8))
        #expect(session.getFullText() == "first line\nsecond line\n")
    }

    @Test @MainActor func handleOutputStripsAnsiOnRead() {
        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        session.handleOutputData(Data("\u{1b}[31mred\u{1b}[0m".utf8))
        #expect(session.getFullText() == "red")
    }

    /// Regression guard for the Transcript sheet (issue #16): when Claude Code
    /// runs with `CLAUDE_CODE_NO_FLICKER=1` it enters the alternate screen
    /// buffer and emits a salvo of CSI private-mode toggles around its rendered
    /// frames. The Transcript view relies on `getFullText()` returning only the
    /// printable payload so users can read their conversation even though the
    /// live terminal viewport cannot scroll in alt-screen mode.
    @Test @MainActor func getFullTextStripsNoFlickerToggleSequences() {
        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        let raw =
            "\u{1b}[?1049h" +                                  // alt-screen on
            "\u{1b}[?2026h" +                                  // begin sync update
            "\u{1b}[?1000h\u{1b}[?1002h\u{1b}[?1006h" +        // mouse reporting
            "hello from claude\n" +
            "\u{1b}[?2026l" +                                  // end sync update
            "\u{1b}[?1049l"                                    // alt-screen off
        session.handleOutputData(Data(raw.utf8))
        #expect(session.getFullText() == "hello from claude\n")
    }

    @Test @MainActor func handleOutputRingBufferTrimsOldest() {
        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        // Push well past the 500k cap with a distinctive head and tail.
        session.handleOutputData(Data(repeating: UInt8(ascii: "A"), count: 10))
        session.handleOutputData(Data(repeating: UInt8(ascii: "B"), count: 600_000))
        let text = session.getFullText()
        // Head "AAA…" must have been dropped; only Bs remain, capped at 500k.
        #expect(text.count == 500_000)
        #expect(!text.contains("A"))
    }

    @Test @MainActor func handleOutputVisibleDataFlipsActivityToWorking() {
        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        #expect(session.activity == .idle)
        session.handleOutputData(Data("hello".utf8))
        #expect(session.activity == .working)
    }

    @Test @MainActor func handleOutputInvisibleDataLeavesActivityIdle() {
        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        // Pure CSI color reset — should not count as activity.
        session.handleOutputData(Data([0x1B, 0x5B, 0x30, 0x6D]))
        #expect(session.activity == .idle)
    }

    // MARK: - Environment

    @Test @MainActor func buildEnvironmentIncludesTermVariable() {
        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        let env = session.buildEnvironment()
        #expect(env.contains { $0.hasPrefix("TERM=") })
    }

    @Test @MainActor func buildEnvironmentForwardsSSHAuthSockWhenPresent() {
        let key = "SSH_AUTH_SOCK"
        let expected = "/tmp/canopy-test-\(UUID().uuidString).sock"
        setenv(key, expected, 1)
        defer { unsetenv(key) }

        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        let env = session.buildEnvironment()
        #expect(env.contains("\(key)=\(expected)"))
    }

    // MARK: - Clipboard

    @Test @MainActor func copyFullSessionToClipboardWritesStrippedText() {
        let session = TerminalSession(id: UUID(), workingDirectory: "/tmp")
        session.handleOutputData(Data("\u{1b}[32mgreen\u{1b}[0m output".utf8))
        session.copyFullSessionToClipboard()
        #expect(NSPasteboard.general.string(forType: .string) == "green output")
    }

    // MARK: - SessionActivity

    @Test func justFinishedLabel() {
        #expect(SessionActivity.justFinished.label == "Just Finished")
        #expect(SessionActivity.justFinished.rawValue == "justFinished")
    }
}
