import Testing
@testable import Canopy

/// Tests for the Shift+Return dispatch policy inside TerminalViewController's
/// local key event monitor.
///
/// Each TerminalViewController installs its own NSEvent local monitor; when a
/// split terminal is open, two monitors fire for every keypress. The policy
/// decides whether *this* controller's monitor should handle Shift+Return
/// (send CSI u to its own terminal view) or defer to another monitor / let
/// the event reach a focused text field.
///
/// Regression context: Before the fix, the Shift+Return branch ran
/// unconditionally — so whichever monitor fired last stole focus and routed
/// CSI u to the wrong pane, and typing Shift+Enter inside a sheet's text
/// field would also hijack focus to the terminal. See GitHub issue #13.
@Suite("TerminalViewController Shift+Return policy")
struct TerminalKeyPolicyTests {

    @Test func handlesWhenOwnTerminalIsFocused() {
        let decision = TerminalViewController.shouldHandleShiftReturn(
            isFirstResponderSelf: true,
            firstResponderIsOtherTerminal: false,
            firstResponderIsTextInput: false
        )
        #expect(decision == true)
    }

    @Test func defersWhenOtherTerminalIsFocused() {
        // Regression: this was 'true' before the fix, which caused the split
        // pane's monitor to steal focus and route Shift+Return to the wrong
        // terminal.
        let decision = TerminalViewController.shouldHandleShiftReturn(
            isFirstResponderSelf: false,
            firstResponderIsOtherTerminal: true,
            firstResponderIsTextInput: false
        )
        #expect(decision == false)
    }

    @Test func defersWhenTextFieldOrSheetIsFocused() {
        // Shift+Return inside an NSTextField/NSTextView (e.g. Add Project
        // sheet, Settings) must reach that control, not hijack focus to a
        // hidden terminal.
        let decision = TerminalViewController.shouldHandleShiftReturn(
            isFirstResponderSelf: false,
            firstResponderIsOtherTerminal: false,
            firstResponderIsTextInput: true
        )
        #expect(decision == false)
    }

    @Test func handlesWhenNoRelevantResponder() {
        // SwiftUI or a plain container may have grabbed focus; one monitor
        // must still handle Shift+Return to steal focus back, otherwise the
        // keystroke is lost entirely.
        let decision = TerminalViewController.shouldHandleShiftReturn(
            isFirstResponderSelf: false,
            firstResponderIsOtherTerminal: false,
            firstResponderIsTextInput: false
        )
        #expect(decision == true)
    }
}
