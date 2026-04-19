import Testing
@testable import Canopy

/// Tests for the Shift+Return dispatch policy inside TerminalViewController's
/// local key event monitor.
///
/// Each TerminalViewController installs its own NSEvent local monitor; when a
/// split terminal is open, two monitors fire for every keypress. The policy
/// decides whether *this* controller's monitor should handle Shift+Return
/// (send CSI u to its own terminal view) or defer to another monitor.
///
/// Regression context: Before the fix, the Shift+Return branch ran
/// unconditionally — so whichever monitor fired last stole focus and routed
/// CSI u to the wrong pane. See GitHub issue #13.
@Suite("TerminalViewController Shift+Return policy")
struct TerminalKeyPolicyTests {

    @Test func handlesWhenOwnTerminalIsFocused() {
        let decision = TerminalViewController.shouldHandleShiftReturn(
            isFirstResponderSelf: true,
            firstResponderIsOtherTerminal: false
        )
        #expect(decision == true)
    }

    @Test func defersWhenOtherTerminalIsFocused() {
        // Regression: this was 'true' before the fix, which caused the split
        // pane's monitor to steal focus and route Shift+Return to the wrong
        // terminal.
        let decision = TerminalViewController.shouldHandleShiftReturn(
            isFirstResponderSelf: false,
            firstResponderIsOtherTerminal: true
        )
        #expect(decision == false)
    }

    @Test func handlesWhenNoTerminalIsFocused() {
        // SwiftUI or a sheet may have grabbed focus; one monitor must still
        // handle Shift+Return to steal focus back, otherwise the keystroke is
        // lost entirely.
        let decision = TerminalViewController.shouldHandleShiftReturn(
            isFirstResponderSelf: false,
            firstResponderIsOtherTerminal: false
        )
        #expect(decision == true)
    }
}
