import SwiftUI

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
                    Text(session.workingDirectory)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .foregroundStyle(.tertiary)
            }

            Spacer()

            // Activity summary with mini dots
            activitySummary
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(.bar)
    }

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
}
