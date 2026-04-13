import SwiftUI
import AppKit

/// Outcome shown in the update-check sheet. Mirrors `UpdateCheckResult` but
/// the `.hidden` case is the default state (sheet not presented).
enum UpdateSheetState: Equatable {
    case checking
    case upToDate
    case available(version: String, url: URL)
    case failed(message: String)
}

/// Sheet shown by the "Check for Updates…" menu item. Auto-launch startup
/// checks only present this sheet when the result is `.available` — silent
/// no-ops and transient network errors don't nag the user.
struct UpdateCheckSheet: View {
    let state: UpdateSheetState
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            icon
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                if case .available(_, let url) = state {
                    Button("Download") {
                        NSWorkspace.shared.open(url)
                        onDismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Later", action: onDismiss)
                } else {
                    Button("OK", action: onDismiss)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private var icon: some View {
        Group {
            switch state {
            case .checking:
                ProgressView().controlSize(.large)
            case .upToDate:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.green)
            case .available:
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.blue)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var title: String {
        switch state {
        case .checking: "Checking for updates…"
        case .upToDate: "You're up to date"
        case .available(let version, _): "Canopy \(version) is available"
        case .failed: "Update check failed"
        }
    }

    private var subtitle: String? {
        switch state {
        case .checking: nil
        case .upToDate: "Canopy \(BuildInfo.version) is the latest version."
        case .available: "You're running \(BuildInfo.version). Download the new DMG from GitHub."
        case .failed(let message): message
        }
    }
}
