import SwiftUI
import AppKit

// MARK: - Tooltip Modifier (reliable NSView-based tooltips for non-interactive views)

/// SwiftUI's `.help()` only works reliably on interactive views (buttons).
/// This modifier uses an `NSView` overlay with `toolTip` for guaranteed hover tooltips.
private struct TooltipModifier: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        content.overlay(TooltipOverlay(text: text))
    }
}

private struct TooltipOverlay: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.toolTip = text
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.toolTip = text
    }
}

extension View {
    func tooltip(_ text: String) -> some View {
        modifier(TooltipModifier(text: text))
    }
}

// MARK: - Status Bar

struct StatusBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            if let session = appState.activeSession {
                HStack(spacing: 4) {
                    Image(systemName: "terminal")
                        .font(.system(size: 10))
                    Text(session.name)
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)

                Divider()
                    .frame(height: 12)

                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                    Text(abbreviatedPath(session.workingDirectory))
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .foregroundStyle(.tertiary)

                // Git status indicators
                if let status = appState.activeGitStatus {
                    gitIndicators(status)
                }

                // Claude model / effort / live context size
                if let context = appState.activeSessionContext,
                   let label = Self.contextLabel(context) {
                    Divider()
                        .frame(height: 12)

                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 9))
                        Text(label)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                    .tooltip(Self.contextTooltip(context))
                }
            }

            Spacer()

            activitySummary
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(.bar)
    }

    // MARK: - Git Indicators

    @ViewBuilder
    private func gitIndicators(_ status: GitStatusInfo) -> some View {
        // Changes indicator
        if let diff = status.diffStat, !diff.isClean {
            Divider()
                .frame(height: 12)

            HStack(spacing: 4) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 9))
                Text("\(diff.filesChanged) file\(diff.filesChanged == 1 ? "" : "s")")
                    .font(.system(size: 11))
                if diff.insertions > 0 {
                    Text("+\(diff.insertions)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.green)
                }
                if diff.deletions > 0 {
                    Text("−\(diff.deletions)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.red)
                }
            }
            .foregroundStyle(.secondary)
            .tooltip(changesHelpText(status))
        }

        // Commits ahead indicator
        if let ahead = status.commitsAhead, ahead > 0 {
            Divider()
                .frame(height: 12)

            HStack(spacing: 3) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 9, weight: .medium))
                Text("\(ahead) ahead")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
            .tooltip("\(ahead) commit\(ahead == 1 ? "" : "s") not yet pushed")
        }

        // PR indicator
        if !status.openPRs.isEmpty {
            Divider()
                .frame(height: 12)

            let draftCount = status.openPRs.filter(\.isDraft).count

            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.pull")
                    .font(.system(size: 9))
                if draftCount > 0 && draftCount < status.openPRs.count {
                    Text("\(status.openPRs.count) open (\(draftCount) draft)")
                        .font(.system(size: 11))
                } else if draftCount == status.openPRs.count {
                    Text("\(status.openPRs.count) draft")
                        .font(.system(size: 11))
                } else {
                    Text("\(status.openPRs.count) open")
                        .font(.system(size: 11))
                }
            }
            .foregroundStyle(.secondary)
            .tooltip(prHelpText(status.openPRs))
        }
    }

    // MARK: - Hover Tooltips

    private func changesHelpText(_ status: GitStatusInfo) -> String {
        if status.changedFiles.isEmpty { return "Uncommitted changes" }
        let header = "Modified files:"
        let files = status.changedFiles.prefix(15).joined(separator: "\n")
        let suffix = status.changedFiles.count > 15
            ? "\n... and \(status.changedFiles.count - 15) more"
            : ""
        return "\(header)\n\(files)\(suffix)"
    }

    private func prHelpText(_ prs: [GitPRInfo]) -> String {
        prs.map { pr in
            let draft = pr.isDraft ? " (draft)" : ""
            return "#\(pr.number) \(pr.title)\(draft)"
        }.joined(separator: "\n")
    }

    // MARK: - Activity Summary

    @ViewBuilder
    private var activitySummary: some View {
        let sessions = appState.sessions
        let activities: [(UUID, SessionActivity)] = sessions.map { session in
            let activity = appState.terminalSessions[session.id]?.activity ?? .idle
            return (session.id, activity)
        }
        let workingCount = activities.filter { $0.1 == .working }.count
        let needsInputCount = activities.filter { $0.1 == .needsInput }.count
        let totalCount = sessions.count

        HStack(spacing: 4) {
            ForEach(activities, id: \.0) { _, activity in
                Circle()
                    .fill(Self.dotColor(for: activity))
                    .frame(width: 5, height: 5)
            }

            if totalCount > 0 {
                Text(Self.summaryText(working: workingCount, needsInput: needsInputCount, total: totalCount))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    static func dotColor(for activity: SessionActivity) -> Color {
        switch activity {
        case .working: return .green
        // A blocked session used to be counted and coloured as idle, which is
        // exactly backwards: it is the one that needs you.
        case .needsInput: return .orange
        case .idle, .justFinished: return .gray.opacity(0.4)
        }
    }

    /// "N need input" leads: with eight worktrees open, which one is blocked
    /// is the single most valuable thing the status bar can say.
    static func summaryText(working: Int, needsInput: Int, total: Int) -> String {
        var parts: [String] = []
        if needsInput > 0 { parts.append("\(needsInput) need\(needsInput == 1 ? "s" : "") input") }
        if working > 0 { parts.append("\(working) working") }

        let accounted = needsInput + working
        if parts.isEmpty {
            return "\(total) session\(total == 1 ? "" : "s")"
        }
        if accounted < total {
            parts.append("\(total - accounted) idle")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Claude Session Context

    /// `opus-5 · high · 71.3K` -- model, reasoning effort, and how much context
    /// the newest turn had to read.
    ///
    /// Nil when the turn says nothing worth a segment, so the bar drops it
    /// entirely rather than showing a zero -- the same `if`-wrapped treatment
    /// every git segment gets.
    ///
    /// Deliberately no percentage: `claude-opus-5` and `claude-opus-5[1m]` are
    /// indistinguishable in the transcript, so a share-of-window figure would
    /// be silently five times wrong for long-context sessions.
    nonisolated static func contextLabel(_ context: SessionContext) -> String? {
        var parts: [String] = []
        if let attribution = ClaudeTranscriptLoader.attributionLabel(
            model: context.model, effort: context.effort
        ) {
            parts.append(attribution)
        }
        if context.contextTokens > 0 {
            parts.append(abbreviatedTokenCount(context.contextTokens))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The segment is abbreviated to fit a 24pt bar, so the exact figure lives
    /// here -- otherwise the number could not be checked against the transcript.
    nonisolated static func contextTooltip(_ context: SessionContext) -> String {
        var lines: [String] = []
        if let model = context.model { lines.append(model) }
        if let effort = context.effort { lines.append("Reasoning effort: \(effort)") }
        if context.contextTokens > 0 {
            lines.append("\(context.contextTokens.formatted()) tokens of context as of the last turn")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }
}
