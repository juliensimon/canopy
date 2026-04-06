import AppKit
import SwiftTerm

/// Manages one terminal session: a pseudo-terminal connected to a shell process.
///
/// Each TerminalSession:
/// 1. Creates a WatchableTerminalView (subclass of LocalProcessTerminalView)
/// 2. Starts a shell process (zsh/bash) in the specified working directory
/// 3. Feeds output through TerminalOutputParser → WatchdogEngine for auto-responses
/// 4. Detects process exit via LocalProcessTerminalViewDelegate
@MainActor
final class TerminalSession: ObservableObject {
    let id: UUID
    let workingDirectory: String

    private(set) var terminalView: LocalProcessTerminalView?
    private var delegateHandler: TerminalDelegateHandler?

    @Published var isRunning = false
    @Published var title: String = ""
    @Published var processExited = false
    @Published var exitCode: Int32?

    /// Watchdog system: parser detects events, engine evaluates rules and responds.
    let outputParser = TerminalOutputParser()
    let watchdog = WatchdogEngine()

    /// Recent watchdog actions for display
    @Published var recentActions: [WatchdogAction] = []

    var hasCompletedSetup = false
    var onProcessExit: ((UUID) -> Void)?

    init(id: UUID, workingDirectory: String) {
        self.id = id
        self.workingDirectory = workingDirectory

        // Wire watchdog to send keystrokes to the terminal
        watchdog.sendToTerminal = { [weak self] text in
            self?.send(text: text)
        }
    }

    func start(frame: CGRect) -> LocalProcessTerminalView {
        if let existing = terminalView {
            return existing
        }

        // Use our subclass that intercepts output for the watchdog
        let view = WatchableTerminalView(frame: frame) { [weak self] data in
            self?.handleOutputData(data)
        }

        view.nativeBackgroundColor = .black
        view.nativeForegroundColor = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
        view.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        let handler = TerminalDelegateHandler(session: self)
        view.processDelegate = handler
        self.delegateHandler = handler

        self.terminalView = view
        self.isRunning = true

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        view.startProcess(
            executable: shell,
            args: ["-l"],
            environment: buildEnvironment(),
            execName: shell,
            currentDirectory: workingDirectory
        )

        return view
    }

    func send(text: String) {
        guard let view = terminalView else { return }
        view.send(Array(text.utf8))
    }

    func sendCommand(_ command: String) {
        send(text: command + "\n")
    }

    func stop() {
        terminalView = nil
        isRunning = false
    }

    /// Attach a watchdog configuration to this session.
    func setWatchdogConfig(_ config: WatchdogConfig?) {
        watchdog.config = config
        watchdog.isActive = config?.isEnabled ?? false
        watchdog.resetCounts()
    }

    // MARK: - Private

    /// Called by WatchableTerminalView when output data arrives.
    /// This runs on the main queue since the terminal view dispatches there.
    private func handleOutputData(_ data: Data) {
        let events = outputParser.feed(data)
        guard !events.isEmpty else { return }

        let actions = watchdog.evaluate(events: events)
        if !actions.isEmpty {
            recentActions.append(contentsOf: actions)
            // Keep only last 50 actions
            if recentActions.count > 50 {
                recentActions.removeFirst(recentActions.count - 50)
            }
        }
    }

    private func buildEnvironment() -> [String] {
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        let parentEnv = ProcessInfo.processInfo.environment
        for key in ["SSH_AUTH_SOCK", "SSH_AGENT_PID", "DISPLAY", "TMPDIR"] {
            if let value = parentEnv[key] {
                env.append("\(key)=\(value)")
            }
        }
        return env
    }

    func handleProcessExit(exitCode: Int32?) {
        self.isRunning = false
        self.processExited = true
        self.exitCode = exitCode
        self.onProcessExit?(id)
    }

    func handleTitleChange(title: String) {
        self.title = title
    }
}

// MARK: - WatchableTerminalView

/// Subclass of LocalProcessTerminalView that taps the data stream.
///
/// LocalProcessTerminalView.dataReceived is the method that receives all
/// output from the child process before feeding it to the terminal renderer.
/// By overriding it, we can observe the raw output and pass it to the
/// watchdog system without disrupting the terminal display.
class WatchableTerminalView: LocalProcessTerminalView {
    /// Called with raw output data before it's rendered.
    private var onDataReceived: ((Data) -> Void)?

    init(frame: CGRect, onDataReceived: @escaping (Data) -> Void) {
        self.onDataReceived = onDataReceived
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        // Tap the data for the watchdog
        let data = Data(slice)
        Task { @MainActor [onDataReceived] in
            onDataReceived?(data)
        }

        // Continue normal rendering
        super.dataReceived(slice: slice)
    }
}

// MARK: - Delegate Handler

private class TerminalDelegateHandler: NSObject, LocalProcessTerminalViewDelegate, @unchecked Sendable {
    weak var session: TerminalSession?

    init(session: TerminalSession) {
        self.session = session
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor in
            session?.handleTitleChange(title: title)
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            session?.handleProcessExit(exitCode: exitCode)
        }
    }
}
