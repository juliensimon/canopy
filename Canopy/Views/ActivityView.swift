import SwiftUI

/// Main activity dashboard: stats cards + heatmap.
struct ActivityView: View {
    @EnvironmentObject var appState: AppState
    @State private var isLoading = false
    @State private var summary = ActivitySummary()
    @State private var hourlyBuckets: [String: HourlyBucket] = [:]

    private let cardBackground = Color(red: 0.102, green: 0.090, blue: 0.188)
    private let cardBorder    = Color(red: 0.165, green: 0.145, blue: 0.271)
    private let accentPurple  = Color(red: 0.486, green: 0.227, blue: 0.929)

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Activity")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }

            HStack(spacing: 8) {
                allTimeCard
                periodCard
                sessionsCard
                busiestDayCard
                modelsCard
            }
            .frame(height: 90)

            ActivityHeatmap(hourlyBuckets: hourlyBuckets)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if isLoading || appState.activityIndexing {
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                    if appState.activityIndexing {
                        Text("Indexing sessions...")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear { loadData() }
    }

    // MARK: - Stat Cards

    private var allTimeCard: some View {
        StatCard(title: "ALL-TIME TOKENS", cardBackground: cardBackground, cardBorder: cardBorder) {
            Text(abbreviatedTokenCount(summary.allTimeTotal))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(accentPurple)
            Text("In: \(abbreviatedTokenCount(summary.allTimeInput))  Out: \(abbreviatedTokenCount(summary.allTimeOutput))")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private var periodCard: some View {
        StatCard(title: "LAST 12 WEEKS", cardBackground: cardBackground, cardBorder: cardBorder) {
            Text(abbreviatedTokenCount(summary.periodTotal))
                .font(.system(size: 18, weight: .bold))
            Text("In: \(abbreviatedTokenCount(summary.periodInput))  Out: \(abbreviatedTokenCount(summary.periodOutput))")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private var sessionsCard: some View {
        StatCard(title: "SESSIONS", cardBackground: cardBackground, cardBorder: cardBorder) {
            Text("\(summary.periodSessionCount)")
                .font(.system(size: 18, weight: .bold))
            Text("Last 12 Weeks")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private var busiestDayCard: some View {
        StatCard(title: "BUSIEST DAY", cardBackground: cardBackground, cardBorder: cardBorder) {
            Text(abbreviatedTokenCount(summary.busiestDayTokens))
                .font(.system(size: 18, weight: .bold))
            Text(formattedBusiestDate(summary.busiestDayDate))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private var modelsCard: some View {
        StatCard(title: "MODELS", cardBackground: cardBackground, cardBorder: cardBorder) {
            if let top = summary.modelBreakdown.first {
                Text("\(shortModelName(top.name)) \(top.percentage)%")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accentPurple)
                ForEach(summary.modelBreakdown.dropFirst().prefix(2), id: \.name) { entry in
                    Text("\(shortModelName(entry.name)) \(entry.percentage)%")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("—")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        if let cached = appState.cachedActivityResult {
            summary = cached.summary
            hourlyBuckets = cached.hourlyBuckets
            return
        }

        isLoading = true
        Task.detached(priority: .userInitiated) {
            let result = ActivityDataService.loadData()
            await MainActor.run {
                self.summary = result.summary
                self.hourlyBuckets = result.hourlyBuckets
                self.isLoading = false
                self.appState.cachedActivityResult = result
            }
        }
    }

    // MARK: - Helpers

    private func shortModelName(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("opus") { return "Opus" }
        if lower.contains("sonnet") { return "Sonnet" }
        if lower.contains("haiku") { return "Haiku" }
        if lower.contains("claude") { return "Claude" }
        return name
    }

    private func formattedBusiestDate(_ dateStr: String) -> String {
        guard !dateStr.isEmpty else { return "—" }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = .current
        guard let date = parser.date(from: dateStr) else { return dateStr }
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .none
        return display.string(from: date)
    }
}

private struct StatCard<Content: View>: View {
    let title: String
    let cardBackground: Color
    let cardBorder: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9))
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            content
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(cardBorder, lineWidth: 1)
                )
        )
    }
}

#Preview {
    ActivityView()
        .frame(width: 900, height: 500)
        .background(Color(red: 0.08, green: 0.07, blue: 0.15))
}
