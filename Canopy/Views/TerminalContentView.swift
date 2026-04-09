import SwiftUI
import SwiftTerm

extension Notification.Name {
    static let canopyShowCommandPalette = Notification.Name("canopyShowCommandPalette")
    static let canopyShowTerminalSearch  = Notification.Name("canopyShowTerminalSearch")
    static let canopyShowActivity        = Notification.Name("canopyShowActivity")
    static let canopyToggleSplitTerminal = Notification.Name("canopyToggleSplitTerminal")
    static let canopySelectTab           = Notification.Name("canopySelectTab")
}

/// Bridges SwiftTerm's LocalProcessTerminalView into SwiftUI.
///
/// SwiftUI aggressively intercepts keyboard events for its own navigation,
/// preventing AppKit views from receiving keystrokes. We solve this with
/// NSViewControllerRepresentable (better responder chain integration than
/// NSViewRepresentable) plus an explicit local event monitor as fallback.
struct TerminalContentView: NSViewControllerRepresentable {
    @ObservedObject var session: TerminalSession

    func makeNSViewController(context: Context) -> TerminalViewController {
        TerminalViewController(session: session)
    }

    func updateNSViewController(_ vc: TerminalViewController, context: Context) {
        // Nothing to update
    }
}

/// An NSViewController that hosts the terminal view.
/// Using a view controller gives us proper integration with AppKit's
/// responder chain, which NSViewRepresentable alone doesn't provide.
final class TerminalViewController: NSViewController {
    private let session: TerminalSession
    private var terminalView: LocalProcessTerminalView?
    private var hasStartedProcess = false
    private var keyEventMonitor: Any?

    init(session: TerminalSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func loadView() {
        // Create a plain container view
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        self.view = container
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        if !hasStartedProcess && view.bounds.width > 50 && view.bounds.height > 50 {
            hasStartedProcess = true
            setupTerminal()
        }
    }

    private func setupTerminal() {
        let tv = session.start(frame: view.bounds)
        self.terminalView = tv

        view.addSubview(tv)
        tv.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tv.topAnchor.constraint(equalTo: view.topAnchor),
            tv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        grabFocus()
        installKeyEventMonitor()
    }

    private func grabFocus() {
        guard let tv = terminalView else { return }
        DispatchQueue.main.async {
            self.view.window?.makeFirstResponder(tv)
        }
    }

    /// Install a local event monitor that intercepts key events when SwiftUI
    /// steals focus from the terminal. If the terminal is visible and the
    /// window is key, we force key events to the terminal view.
    private func installKeyEventMonitor() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self,
                  let tv = self.terminalView,
                  let window = self.view.window,
                  window.isKeyWindow else {
                return event
            }

            // Intercept Shift+Return and send CSI u encoding so Claude Code
            // can distinguish it from plain Enter (for multi-line input).
            // SwiftTerm's doCommand(by: insertNewline) loses the Shift modifier.
            if event.type == .keyDown,
               event.keyCode == 0x24,  // kVK_Return
               event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift) {
                window.makeFirstResponder(tv)
                // CSI u: ESC [ 1 3 ; 2 u  (13 = CR codepoint, 2 = 1+shift)
                tv.send([0x1b, 0x5b, 0x31, 0x33, 0x3b, 0x32, 0x75])
                return nil
            }

            // If the terminal view is already first responder, let it handle normally.
            if window.firstResponder === tv {
                return event
            }

            // If ANY other terminal view has focus, leave it alone.
            // Without this check, multiple TerminalContentView instances each install
            // a monitor and steal focus from each other (e.g. split terminal pane).
            if window.firstResponder is LocalProcessTerminalView {
                return event
            }

            // If focus is on something intentional (e.g. a text field in a sheet),
            // don't steal events.
            let responder = window.firstResponder
            if responder is NSTextView || responder is NSTextField {
                return event
            }

            // Intercept app-level Cmd shortcuts that SwiftTerm would otherwise
            // consume (e.g. ⌘K = clear screen in terminal, ⌘F = terminal search).
            if event.type == .keyDown && event.modifierFlags.contains(.command) {
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let cmdOnly = mods == .command
                let cmdShift = mods == [.command, .shift]
                let key = event.charactersIgnoringModifiers ?? ""

                if cmdOnly && key == "f" {
                    NotificationCenter.default.post(name: .canopyShowCommandPalette, object: nil)
                    return nil
                }
                if cmdShift && key == "a" {
                    NotificationCenter.default.post(name: .canopyShowActivity, object: nil)
                    return nil
                }
                if cmdShift && key == "d" {
                    NotificationCenter.default.post(name: .canopyToggleSplitTerminal, object: nil)
                    return nil
                }
                if cmdOnly, let digit = key.first?.wholeNumberValue, (1...9).contains(digit) {
                    NotificationCenter.default.post(name: .canopySelectTab, object: digit)
                    return nil
                }

                // All other Cmd shortcuts: let AppKit menu system handle them.
                window.makeFirstResponder(tv)
                return event
            }

            // Option+key on non-US keyboards (e.g. French AZERTY) produces characters
            // like ~, @, #, € that require the Option modifier. SwiftTerm's default
            // optionAsMetaKey=true would intercept these and send ESC+key instead.
            // Detect this case: Option is held, the resulting character differs from
            // the base character, and it's printable — send it directly.
            if event.type == .keyDown,
               event.modifierFlags.contains(.option),
               !event.modifierFlags.contains(.command),
               let chars = event.characters,
               let base = event.charactersIgnoringModifiers,
               !chars.isEmpty,
               chars != base,
               let scalar = chars.unicodeScalars.first,
               scalar.value >= 32 && scalar.value != 127 {
                window.makeFirstResponder(tv)
                tv.send(txt: chars)
                return nil
            }

            // Force focus back to the terminal and forward this event
            window.makeFirstResponder(tv)
            if event.type == .keyDown {
                tv.keyDown(with: event)
            } else if event.type == .keyUp {
                tv.keyUp(with: event)
            } else if event.type == .flagsChanged {
                tv.flagsChanged(with: event)
            }

            // Return nil to consume the event (we already forwarded it)
            return nil
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        grabFocus()
        if keyEventMonitor == nil {
            installKeyEventMonitor()
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
    }

    // Monitor cleanup is handled in viewWillDisappear
}
