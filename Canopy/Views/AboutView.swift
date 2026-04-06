import SwiftUI

/// About window showing version and build info.
struct AboutView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Canopy")
                .font(.title)
                .fontWeight(.bold)

            Text("Native Claude Code session manager")
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

            Spacer()

            Button("OK") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 380, height: 320)
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
