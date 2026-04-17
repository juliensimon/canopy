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
        let totalCount = sessions.count

        HStack(spacing: 4) {
            ForEach(activities, id: \.0) { _, activity in
                Circle()
                    .fill(activity == .working ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 5, height: 5)
            }

            if totalCount > 0 {
                Text(summaryText(working: workingCount, total: totalCount))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func summaryText(working: Int, total: Int) -> String {
        if working == 0 {
            return "\(total) session\(total == 1 ? "" : "s")"
        } else if working == total {
            return "\(total) working"
        } else {
            return "\(working) working, \(total - working) idle"
        }
    }

    // MARK: - Helpers

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
