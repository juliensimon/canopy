import AppKit
import SwiftTerm

/// Manages one terminal session: a pseudo-terminal connected to a shell process.
///
/// Each TerminalSession:
/// 1. Creates a SwiftTerm LocalProcessTerminalView (which handles PTY internally)
/// 2. Starts a shell process (zsh/bash) in the specified working directory
/// 3. Detects when the process exits via LocalProcessTerminalViewDelegate
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

    /// Whether the initial setup (process exit handler, auto-start) has run.
    /// Tracked here (not in the view) because the view gets recreated on tab switch.
    var hasCompletedSetup = false

    /// Called when the shell process terminates.
    var onProcessExit: ((UUID) -> Void)?

    init(id: UUID, workingDirectory: String) {
        self.id = id
        self.workingDirectory = workingDirectory
    }

    func start(frame: CGRect) -> LocalProcessTerminalView {
        if let existing = terminalView {
            return existing
        }

        let view = LocalProcessTerminalView(frame: frame)

        view.nativeBackgroundColor = .black
        view.nativeForegroundColor = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
        view.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // Set up delegate to detect process exit and title changes
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

    // MARK: - Private

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

/// Delegate handler that bridges SwiftTerm's process events back to TerminalSession.
/// Separate class because LocalProcessTerminalViewDelegate requires a class type
/// and we don't want TerminalSession to inherit from NSObject.
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
