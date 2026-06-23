import SwiftUI
import AppKit

/// About window showing version, author, and build info.
struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState

    private let githubURL = "https://github.com/juliensimon/canopy"

    /// Headline privacy claim shown in the About window. Defensible as written:
    /// Canopy ships no analytics SDK and persists everything to local JSON.
    static let privacyHeadline = "Zero telemetry · Zero data collection"

    /// Detail line. MUST disclose the single outbound request (the optional,
    /// user-toggleable update check to GitHub) so the headline stays accurate
    /// even when someone runs a packet sniffer. See AboutViewTests.
    static let privacyDetail =
        "Everything stays on your Mac. The only network request is an "
        + "optional check to GitHub for new versions."

    var body: some View {
        VStack(spacing: 16) {
            if let splash = Self.loadResource(name: "Splash", ext: "jpg") {
                Image(nsImage: splash)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Canopy")
                    .font(.title)
                    .fontWeight(.bold)
            }

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

            updateStatusRow

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

            Divider()

            privacySection

            Spacer()

            Button("OK") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 540, height: 560)
    }

    private static func loadResource(name: String, ext: String) -> NSImage? {
        if let path = Bundle.main.path(forResource: name, ofType: ext) {
            return NSImage(contentsOfFile: path)
        }
        if let exec = Bundle.main.executablePath {
            let path = ((exec as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent("../Resources/\(name).\(ext)")
            return NSImage(contentsOfFile: path)
        }
        return nil
    }

    private var privacySection: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(Self.privacyHeadline)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
            Text(Self.privacyDetail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private var updateStatusRow: some View {
        HStack(spacing: 8) {
            switch appState.updateStatus {
            case .unknown:
                Text(" ").font(.caption)
            case .checking:
                ProgressView().controlSize(.small)
                Text("Checking for updates…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .upToDate:
                Text("✓ Up to date")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .available(let version, let url):
                Text("New version \(version) available")
                    .font(.caption)
                    .foregroundStyle(.primary)
                Button("Download") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.link)
                .font(.caption)
            case .failed:
                Text("Couldn't check for updates")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Check Now") {
                Task { await appState.checkForUpdatesNow() }
            }
            .buttonStyle(.link)
            .font(.caption)
            .disabled(appState.updateStatus == .checking)
        }
        .frame(maxWidth: .infinity)
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
