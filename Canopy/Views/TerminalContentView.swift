import SwiftUI
import SwiftTerm

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

            // If the terminal view is already first responder, let it handle normally
            if window.firstResponder === tv {
                return event
            }

            // If focus is on something intentional (e.g. a text field in a sheet),
            // don't steal events.
            let responder = window.firstResponder
            if responder is NSTextView || responder is NSTextField {
                return event
            }

            // Let Cmd+key shortcuts (copy, paste, quit, etc.) flow through
            // the normal menu/responder chain instead of forwarding as raw keys.
            if event.type == .keyDown && event.modifierFlags.contains(.command) {
                window.makeFirstResponder(tv)
                return event
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
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
    }

    deinit {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
