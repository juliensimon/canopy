import SwiftUI

/// Scrollable view of a session's transcript.
///
/// When the session has an associated Claude Code session id, we render the
/// structured JSONL transcript (clean user/assistant turns, tool calls
/// summarized, assistant markdown rendered). Otherwise we fall back to the
/// raw captured terminal output. The structured path exists because
/// `CLAUDE_CODE_NO_FLICKER=1` puts Claude Code into the alternate screen
/// buffer (DECSET 1049) — which has no scrollback by terminal protocol — so
/// the live viewport cannot scroll back through the conversation. See #16.
struct TranscriptSheet: View {
    @ObservedObject var session: TerminalSession
    let sessionInfo: SessionInfo

    @Environment(\.dismiss) private var dismiss
    @State private var messages: [TranscriptMessage] = []
    @State private var jsonlPath: String?
    @State private var lastModifiedTime: Date?
    @State private var pollTask: Task<Void, Never>?
    @State private var loadError: String?
    /// When on, the view auto-scrolls to the latest message as new content
    /// streams in. Turn off to read older content without being yanked down.
    @State private var autoTail = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 760, height: 580)
        .onAppear { startPolling() }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Transcript")
                    .font(.headline)
                Text(subtitleText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("Auto-tail", isOn: $autoTail)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Keep view pinned to the latest content as it streams in. Turn off to read older history without being yanked down.")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var subtitleText: String {
        if jsonlPath != nil {
            return sessionInfo.name + " · Claude Code session"
        }
        return sessionInfo.name + " · raw terminal output"
    }

    // MARK: - Content

    private static let bottomAnchorID = "transcript-bottom"

    @ViewBuilder
    private var content: some View {
        if let loadError {
            errorState(loadError)
        } else if !messages.isEmpty {
            messageList
        } else if jsonlPath == nil {
            rawFallback
        } else {
            emptyState
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(messages) { message in
                        TranscriptMessageView(message: message)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomAnchorID)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onAppear {
                if autoTail { scrollToBottom(proxy) }
            }
            .onChange(of: messages.count) { _, _ in
                guard autoTail else { return }
                scrollToBottom(proxy)
            }
            .onChange(of: autoTail) { _, isOn in
                if isOn { scrollToBottom(proxy) }
            }
        }
    }

    /// Defer the scroll one runloop tick so the LazyVStack has finished
    /// laying out the new row before we ask the proxy to scroll to the
    /// bottom anchor. Without this, scrollTo runs against the previous
    /// layout and the view appears not to auto-tail.
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        }
    }

    private var rawFallback: some View {
        let text = session.getFullText()
        let tail = text.count
        return ScrollViewReader { proxy in
            ScrollView {
                Text(text.isEmpty ? "No output captured yet." : text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(text.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                Color.clear.frame(height: 1).id(Self.bottomAnchorID)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onAppear {
                if autoTail { scrollToBottom(proxy) }
            }
            .onChange(of: tail) { _, _ in
                guard autoTail else { return }
                scrollToBottom(proxy)
            }
            .onChange(of: autoTail) { _, isOn in
                if isOn { scrollToBottom(proxy) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No transcript yet")
                .font(.headline)
            Text("Claude Code writes its conversation to disk as you go. Send a message and it will appear here.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(.orange)
            Text("Could not read transcript")
                .font(.headline)
            Text(message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(statusLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Copy") { copyOutput() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(copyDisabled)
                .help(copyHelp)
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var copyDisabled: Bool {
        messages.isEmpty && session.getFullText().isEmpty
    }

    private var copyHelp: String {
        messages.isEmpty
            ? "Copy raw terminal output to the clipboard"
            : "Copy formatted transcript (markdown) to the clipboard"
    }

    private func copyOutput() {
        let text = messages.isEmpty
            ? session.getFullText()
            : ClaudeTranscriptLoader.plainText(messages: messages)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var statusLabel: String {
        if jsonlPath != nil {
            return "\(messages.count) messages"
        }
        return "\(session.getFullText().count.formatted()) chars"
    }

    // MARK: - Polling

    /// While the sheet is visible, re-read the JSONL when its mtime changes.
    /// 500 ms is the gap Claude Code typically writes at, so we follow new
    /// turns within one tick without burning CPU between them.
    private func startPolling() {
        resolveAndReload()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                resolveAndReload()
            }
        }
    }

    private func resolveAndReload() {
        // Path can change mid-sheet only if claudeSessionId is set after open;
        // recompute each tick is cheap.
        let path = jsonlPath ?? currentJSONLPath()
        if jsonlPath == nil, path != nil { jsonlPath = path }
        guard let path else {
            // Plain (non-Claude) session — nothing to poll; fallback view drives off
            // TerminalSession's @Published activity, which already triggers re-renders.
            return
        }
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date
        else {
            // File doesn't exist yet — session may not have produced any output.
            if !messages.isEmpty { messages = [] }
            return
        }
        if lastModifiedTime == mtime { return }
        lastModifiedTime = mtime
        do {
            messages = try ClaudeTranscriptLoader.load(path: path)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func currentJSONLPath() -> String? {
        let sessionId = sessionInfo.claudeSessionId
            ?? ClaudeSessionFinder.findLatestSessionId(for: sessionInfo.workingDirectory)
        guard let sessionId else { return nil }
        let path = ClaudeTranscriptLoader.sessionFilePath(
            workingDirectory: sessionInfo.workingDirectory,
            sessionId: sessionId
        )
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }
}

// MARK: - Message rendering

/// Renders one TranscriptMessage with a role header and one row per block.
/// Text blocks use `AttributedString(markdown:)` so assistant responses pick
/// up inline bold/italic/code/links. Tool use/result rows are compact so
/// they don't drown the conversation.
struct TranscriptMessageView: View {
    let message: TranscriptMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: message.role == .user ? "person.circle.fill" : "sparkle")
                    .font(.system(size: 11))
                    .foregroundStyle(message.role == .user ? Color.accentColor : Color.purple)
                Text(message.role == .user ? "You" : "Claude")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(message.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: TranscriptMessage.Block) -> some View {
        switch block {
        case .text(let s):
            Text(attributedMarkdown(s))
                .font(.system(size: 13))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .toolUse(let name, let hint):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("🔧")
                Text(name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                if !hint.isEmpty {
                    Text(hint)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.leading, 8)
            .textSelection(.enabled)
        case .toolResult(let s):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("↳")
                    .foregroundStyle(.tertiary)
                Text(s)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.tail)
            }
            .padding(.leading, 8)
            .textSelection(.enabled)
        }
    }

    /// Renders the text as inline markdown when possible (bold/italic/code
    /// spans/links). Falls back to the plain string when parsing fails (very
    /// large blocks with exotic markdown can trip AttributedString).
    private func attributedMarkdown(_ s: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attr = try? AttributedString(markdown: s, options: options) {
            return attr
        }
        return AttributedString(s)
    }
}
