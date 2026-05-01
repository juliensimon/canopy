import AppKit
import Darwin
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
    var onSessionFinished: ((UUID, String) -> Void)?
    private var idleTimer: Task<Void, Never>?
    private var justFinishedTimer: Task<Void, Never>?

    /// When this terminal session was opened in Canopy (for token counting).
    let openedAt = Date()

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

        // Let Option generate characters (e.g. brackets on non-US keyboards)
        // instead of acting as Meta/ESC prefix.
        view.optionAsMetaKey = false

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
        guard let view = terminalView else { return }
        let fd = view.process.childfd
        guard fd >= 0 else { return }
        let bytes = Array(command.utf8)
        guard !bytes.isEmpty else { return }
        // Write text first, then Enter after a delay so Claude Code's event loop
        // reads them as two separate read() batches. If they arrive together the
        // \r is treated as a soft newline (Shift+Enter) rather than submit.
        writeAll(fd: fd, bytes: bytes)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            // Re-check the view is still alive and on the same fd before writing Enter.
            guard terminalView?.process.childfd == fd else { return }
            writeAll(fd: fd, bytes: [0x0D])
        }
    }

    private func writeAll(fd: Int32, bytes: [UInt8]) {
        var slice = bytes[...]
        while !slice.isEmpty {
            let n = slice.withUnsafeBytes { ptr in
                Darwin.write(fd, ptr.baseAddress!, ptr.count)
            }
            if n > 0 {
                slice = slice.dropFirst(n)
            } else if n == -1 && (Darwin.errno == EINTR || Darwin.errno == EAGAIN) {
                continue
            } else {
                break
            }
        }
    }

    /// Returns the full session output as plain text with ANSI escape codes stripped.
    func getFullText() -> String {
        guard let text = String(data: rawOutput, encoding: .utf8) else { return "" }
        return Self.stripAnsiEscapes(text)
    }

    /// Strips ANSI escape sequences, OSC sequences, and control characters from terminal output.
    nonisolated static func stripAnsiEscapes(_ text: String) -> String {
        let esc = "\u{1b}"
        let bel = "\u{07}"
        var result = text
        // OSC sequences: ESC ] ... (ST | BEL)
        result = result.replacingOccurrences(
            of: "\(esc)\\][^\(bel)\(esc)]*(?:\(bel)|\(esc)\\\\)",
            with: "",
            options: .regularExpression
        )
        // CSI sequences: ESC [ ... (letter or @)
        result = result.replacingOccurrences(
            of: "\(esc)\\[[0-9;?]*[A-Za-z@]",
            with: "",
            options: .regularExpression
        )
        // Other ESC sequences: ESC ( ) > =
        result = result.replacingOccurrences(
            of: "\(esc)[()=>][^\(esc)]*",
            with: "",
            options: .regularExpression
        )
        // Remaining bare ESC + single char
        result = result.replacingOccurrences(
            of: "\(esc).",
            with: "",
            options: .regularExpression
        )
        // Carriage returns (terminal overwrites)
        result = result.replacingOccurrences(of: "\r", with: "")
        return result
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

    func handleOutputData(_ data: Data) {
        rawOutput.append(data)
        if rawOutput.count > maxRawOutputSize {
            rawOutput.removeFirst(rawOutput.count - maxRawOutputSize)
        }

        guard Self.containsVisibleContent(data) else { return }
        activity = .working
        restartIdleTimer()
    }

    /// Returns true if data contains printable characters beyond terminal control sequences.
    nonisolated static func containsVisibleContent(_ data: Data) -> Bool {
        var i = data.startIndex
        while i < data.endIndex {
            let byte = data[i]
            // Skip ESC sequences
            if byte == 0x1B {
                i = data.index(after: i)
                guard i < data.endIndex else { return false }
                let next = data[i]
                if next == UInt8(ascii: "[") || next == UInt8(ascii: "]") || next == UInt8(ascii: ">") {
                    // CSI/OSC/DEC: skip until terminator
                    i = data.index(after: i)
                    while i < data.endIndex {
                        let c = data[i]
                        if next == UInt8(ascii: "]") {
                            // OSC terminates with BEL (0x07) or ST (ESC \)
                            if c == 0x07 { i = data.index(after: i); break }
                        } else if c >= 0x40 && c <= 0x7E {
                            // CSI terminates with a letter
                            i = data.index(after: i); break
                        }
                        i = data.index(after: i)
                    }
                } else {
                    // Two-char escape (e.g. ESC = or ESC >)
                    i = data.index(after: i)
                }
                continue
            }
            // Skip CR, LF, space, and common control chars
            if byte == 0x0D || byte == 0x0A || byte == 0x08 { i = data.index(after: i); continue }
            // Any printable ASCII or UTF-8 start byte → visible content
            if byte >= 0x21 && byte != 0x7F { return true }
            i = data.index(after: i)
        }
        return false
    }

    private func restartIdleTimer() {
        idleTimer?.cancel()
        idleTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            if self.activity == .working {
                self.activity = .justFinished
                self.onSessionFinished?(self.id, self.title)
                self.startJustFinishedTimer()
            }
        }
    }

    private func startJustFinishedTimer() {
        justFinishedTimer?.cancel()
        justFinishedTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            if self.activity == .justFinished {
                self.activity = .idle
            }
        }
    }

    func buildEnvironment() -> [String] {
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
    case justFinished

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        case .justFinished: return "Just Finished"
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
