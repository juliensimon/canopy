import AppKit
import SwiftTerm

/// Manages one terminal session: a pseudo-terminal connected to a shell process.
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
    @Published var activity: SessionActivity = .idle

    /// Raw output capture for clipboard copy.
    private var rawOutput = Data()
    private let maxRawOutputSize = 500_000

    var hasCompletedSetup = false
    var onProcessExit: ((UUID) -> Void)?
    private var idleTimer: Task<Void, Never>?

    init(id: UUID, workingDirectory: String) {
        self.id = id
        self.workingDirectory = workingDirectory
    }

    func start(frame: CGRect) -> LocalProcessTerminalView {
        if let existing = terminalView {
            return existing
        }

        let view = WatchableTerminalView(frame: frame) { [weak self] data in
            self?.handleOutputData(data)
        }

        view.nativeBackgroundColor = .black
        view.nativeForegroundColor = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
        view.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // Disable mouse reporting so text selection works normally.
        // Claude Code uses keyboard navigation, not mouse clicks, so this is safe.
        view.allowMouseReporting = false

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

    /// Returns the full session output as plain text.
    func getFullText() -> String {
        guard let text = String(data: rawOutput, encoding: .utf8) else { return "" }
        return text
    }

    /// Copies the full session output to the clipboard.
    func copyFullSessionToClipboard() {
        let text = getFullText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func stop() {
        terminalView = nil
        isRunning = false
    }

    // MARK: - Private

    private func handleOutputData(_ data: Data) {
        rawOutput.append(data)
        if rawOutput.count > maxRawOutputSize {
            rawOutput.removeFirst(rawOutput.count - maxRawOutputSize)
        }

        activity = .working
        restartIdleTimer()
    }

    private func restartIdleTimer() {
        idleTimer?.cancel()
        idleTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            if self.activity == .working {
                self.activity = .idle
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

// MARK: - Session Activity

enum SessionActivity: String {
    case idle
    case working

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        }
    }
}

// MARK: - WatchableTerminalView

class WatchableTerminalView: LocalProcessTerminalView {
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
        let data = Data(slice)
        Task { @MainActor [onDataReceived] in
            onDataReceived?(data)
        }
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
