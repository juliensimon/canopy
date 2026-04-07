import SwiftUI

/// Sheet showing detailed info about a session.
struct SessionInfoSheet: View {
    let session: SessionInfo
    let openedAt: Date?
    @Environment(\.dismiss) var dismiss
    @State private var usage: TokenUsage?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Session Info")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 10) {
                infoRow("Name", session.name)
                copiableRow("Working Directory", session.workingDirectory)
                infoRow("Created", session.createdAt.formatted(date: .abbreviated, time: .shortened))
                infoRow("Type", session.isWorktreeSession ? "Worktree" : "Plain")

                if let branch = session.branchName {
                    copiableRow("Branch", branch)
                }
                if let wtPath = session.worktreePath {
                    copiableRow("Worktree Path", wtPath)
                }
                if let claudeId = session.claudeSessionId {
                    copiableRow("Claude Session", claudeId)
                }
                if let usage {
                    Divider()
                    infoRow("Tokens (this session)", "In: \(usage.formattedInput)  Out: \(usage.formattedOutput)")
                    if !usage.models.isEmpty {
                        infoRow("Model\(usage.models.count > 1 ? "s" : "")", usage.models.sorted().joined(separator: ", "))
                    }
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500)
        .frame(minHeight: 260)
        .textSelection(.enabled)
        .task {
            usage = await Task.detached {
                SessionCostService.loadUsage(for: session.workingDirectory, sessionId: session.claudeSessionId, since: openedAt)
            }.value
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func copiableRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 12, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }
        }
    }
}
