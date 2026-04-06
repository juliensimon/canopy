import SwiftUI

/// Bottom status bar showing current session info.
/// Phase 1: just the working directory.
/// Phase 3+: branch name, watchdog status, resource usage.
struct StatusBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            if let session = appState.activeSession {
                // Session indicator
                HStack(spacing: 4) {
                    Image(systemName: "terminal")
                        .font(.system(size: 10))
                    Text(session.name)
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)

                Divider()
                    .frame(height: 12)

                // Working directory
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                    Text(session.workingDirectory)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .foregroundStyle(.tertiary)
            }

            Spacer()

            // Session count
            Text("\(appState.sessions.count) session\(appState.sessions.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(.bar)
    }
}
