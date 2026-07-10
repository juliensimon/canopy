import Testing
import Foundation
import SwiftTerm
@testable import Canopy

/// Captures bytes the terminal engine sends toward the application (pty).
private final class CapturingDelegate: TerminalDelegate {
    var sent = Data()
    func send(source: Terminal, data: ArraySlice<UInt8>) {
        sent.append(contentsOf: data)
    }
}

/// Pins the upstream SwiftTerm 1.13 bug behind WatchableTerminalView's
/// hover-motion workaround (#42): SGR motion-without-button (flags 3 + the
/// motion bit) is encoded as a button RELEASE (`CSI<32;…m`) instead of
/// motion (`CSI<35;…M`). With any-event tracking (DECSET 1003) active,
/// every pointer move therefore reads to a TUI app as a completed click —
/// Claude Code's /model picker closes as the mouse hovers it.
///
/// When this test FAILS after a SwiftTerm bump, upstream fixed the SGR
/// encoding: delete WatchableTerminalView.mouseMoved and this test.
@Suite("SwiftTerm mouse encoding")
struct SwiftTermMouseEncodingTests {

    @Test func upstreamEncodesHoverMotionAsRelease() {
        let delegate = CapturingDelegate()
        let terminal = Terminal(delegate: delegate)
        // The application side enables any-event tracking + SGR encoding.
        terminal.feed(text: "\u{1b}[?1003h\u{1b}[?1006h")
        // What MacTerminalView.mouseMoved sends for a buttonless hover:
        // encodeButton(release: true) == 3, sendMotion adds the motion bit.
        terminal.sendMotion(buttonFlags: 3, x: 4, y: 2, pixelX: 0, pixelY: 0)
        let sent = String(decoding: delegate.sent, as: UTF8.self)
        // Buggy: release final byte 'm' and stripped button bits.
        // Correct would be "\u{1b}[<35;5;3M".
        #expect(sent == "\u{1b}[<32;5;3m")
    }
}
