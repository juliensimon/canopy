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

/// Guards the SwiftTerm behaviour that lets Canopy ship NO hover workaround.
///
/// SwiftTerm ≤ 1.13 encoded buttonless SGR hover motion as a button RELEASE
/// (`CSI<32;…m`) instead of motion (`CSI<35;…M`). With any-event tracking
/// (DECSET 1003) active — which Claude Code enables in fullscreen mode —
/// every pointer move read to the app as a completed click, so the /model
/// picker and permission menus closed as the mouse crossed them (#42).
/// Canopy carried a local `mouseMoved` monitor that swallowed hover motion
/// to compensate; upstream fixed the encoding in #520 (shipped in 1.14.0)
/// and the workaround was removed in #48.
///
/// If this test FAILS after a SwiftTerm bump, upstream regressed the SGR
/// branch of `Terminal.sendEvent`: hover will start dismissing Claude Code's
/// fullscreen menus again and the workaround must come back. Do not "fix"
/// the expectation to match.
@Suite("SwiftTerm mouse encoding")
struct SwiftTermMouseEncodingTests {

    @Test func encodesButtonlessHoverAsMotionNotRelease() {
        let delegate = CapturingDelegate()
        let terminal = Terminal(delegate: delegate)
        // The application side enables any-event tracking + SGR encoding.
        terminal.feed(text: "\u{1b}[?1003h\u{1b}[?1006h")
        // What MacTerminalView.mouseMoved sends for a buttonless hover:
        // encodeButton(release: true) == 3, sendMotion adds the motion bit.
        terminal.sendMotion(buttonFlags: 3, x: 4, y: 2, pixelX: 0, pixelY: 0)
        let sent = String(decoding: delegate.sent, as: UTF8.self)
        // 35 = 3 (no button) + 32 (motion bit); 'M' = press/motion, not 'm'.
        #expect(sent == "\u{1b}[<35;5;3M")
    }
}
