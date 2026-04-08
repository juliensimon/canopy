import SwiftUI

/// Main activity dashboard: stats cards + heatmap.
struct ActivityView: View {
    @State private var granularity: Granularity = .week
    @State private var isLoading = false
    @State private var summary = ActivitySummary()
    @State private var buckets: [String: DailyBucket] = [:]
    @State private var loadTask: Task<Void, Never>?

    private let cardBackground = Color(red: 0.102, green: 0.090, blue: 0.188)
    private let cardBorder    = Color(red: 0.165, green: 0.145, blue: 0.271)
    private let accentPurple  = Color(red: 0.486, green: 0.227, blue: 0.929)

    var body: some View {
        VStack(spacing: 12) {
            // Header row
            HStack {
                Text("Activity")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                granularityPicker
            }

            // Stats cards row
            HStack(spacing: 8) {
                allTimeCard
                periodCard
                sessionsCard
                busiestDayCard
                modelsCard
            }
            .frame(height: 90)

            // Heatmap fills remaining space
            ActivityHeatmap(buckets: buckets, granularity: granularity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
            }
        }
        .onAppear { loadData() }
        .onChange(of: granularity) { loadData() }
    }

    // MARK: - Granularity Picker

    private var granularityPicker: some View {
        HStack(spacing: 0) {
            ForEach(Granularity.allCases, id: \.self) { g in
                Button(action: { granularity = g }) {
                    Text(g.label)
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(granularity == g ? accentPurple : Color.clear)
                        .foregroundStyle(granularity == g ? .white : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Stat Cards

    private var allTimeCard: some View {
        StatCard(
            title: "ALL-TIME TOKENS",
            cardBackground: cardBackground,
            cardBorder: cardBorder
        ) {
            Text(abbreviatedTokenCount(summary.allTimeTotal))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(accentPurple)
            Text("In: \(abbreviatedTokenCount(summary.allTimeInput))  Out: \(abbreviatedTokenCount(summary.allTimeOutput))")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private var periodCard: some View {
        StatCard(
            title: granularity.periodLabel.uppercased(),
            cardBackground: cardBackground,
            cardBorder: cardBorder
        ) {
            Text(abbreviatedTokenCount(summary.periodTotal))
                .font(.system(size: 18, weight: .bold))
            Text("In: \(abbreviatedTokenCount(summary.periodInput))  Out: \(abbreviatedTokenCount(summary.periodOutput))")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private var sessionsCard: some View {
        StatCard(
            title: "SESSIONS",
            cardBackground: cardBackground,
            cardBorder: cardBorder
        ) {
            Text("\(summary.periodSessionCount)")
                .font(.system(size: 18, weight: .bold))
            Text(granularity.periodLabel)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private var busiestDayCard: some View {
        StatCard(
            title: "BUSIEST DAY",
            cardBackground: cardBackground,
            cardBorder: cardBorder
        ) {
            Text(abbreviatedTokenCount(summary.busiestDayTokens))
                .font(.system(size: 18, weight: .bold))
            Text(formattedBusiestDate(summary.busiestDayDate))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private var modelsCard: some View {
        StatCard(
            title: "MODELS",
            cardBackground: cardBackground,
            cardBorder: cardBorder
        ) {
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
        loadTask?.cancel()
        isLoading = true
        let g = granularity
        loadTask = Task.detached(priority: .userInitiated) {
            let result = ActivityDataService.loadData(granularity: g)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.granularity == g else { return } // stale result
                self.summary = result.summary
                self.buckets = result.buckets
                self.isLoading = false
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

// MARK: - StatCard helper

/// Generic stat card with a title and free-form content.
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

// MARK: - Preview

#Preview {
    ActivityView()
        .frame(width: 900, height: 500)
        .background(Color(red: 0.08, green: 0.07, blue: 0.15))
}
