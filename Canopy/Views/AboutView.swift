import SwiftUI

/// About window showing version, author, and build info.
struct AboutView: View {
    @Environment(\.dismiss) var dismiss

    private let githubURL = "https://github.com/juliensimon/canopy"

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            Text("Canopy")
                .font(.title)
                .fontWeight(.bold)

            Text("Parallel Claude Code sessions with git worktrees")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                infoRow("Version", BuildInfo.version)
                infoRow("Commit", BuildInfo.gitHash)
                infoRow("Commit date", BuildInfo.gitDate)
                infoRow("Built", BuildInfo.buildDate)
            }
            .textSelection(.enabled)

            Divider()

            VStack(spacing: 4) {
                Text("Julien Simon")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("julien@julien.org")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: {
                    if let url = URL(string: githubURL) {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 10))
                        Text("GitHub")
                            .font(.caption)
                    }
                }
                .buttonStyle(.link)
            }

            Spacer()

            Button("OK") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 380, height: 400)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
