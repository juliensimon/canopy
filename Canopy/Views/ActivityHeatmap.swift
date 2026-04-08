import SwiftUI

/// GitHub-style contribution heatmap that fills available space.
struct ActivityHeatmap: View {
    let buckets: [String: DailyBucket]
    let granularity: Granularity

    private static let colors: [Color] = [
        Color(red: 0.118, green: 0.118, blue: 0.227),  // #1e1e3a
        Color(red: 0.176, green: 0.106, blue: 0.412),  // #2d1b69
        Color(red: 0.357, green: 0.129, blue: 0.714),  // #5b21b6
        Color(red: 0.486, green: 0.227, blue: 0.929),  // #7c3aed
    ]

    private struct GridLayout {
        var columns: [[Int]]      // columns[col][row] = value
        var columnLabels: [String]
        var rowLabels: [String]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(granularity.periodLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                legend
            }
            .padding(.bottom, 8)

            columnLabels
                .padding(.leading, 30)
                .padding(.bottom, 4)

            HStack(alignment: .top, spacing: 0) {
                rowLabels
                    .frame(width: 26)
                gridContent
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.102, green: 0.090, blue: 0.188))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(red: 0.165, green: 0.145, blue: 0.271), lineWidth: 1)
                )
        )
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 4) {
            Text("Less")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            ForEach(0..<4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Self.colors[level])
                    .frame(width: 10, height: 10)
            }
            Text("More")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Grid data

    private var gridData: GridLayout {
        switch granularity {
        case .week:   return buildWeekGrid()
        case .day:    return buildDayGrid()
        case .month:  return buildMonthGrid()
        }
    }

    /// Week view: 12 columns (weeks), 7 rows (Mon–Sun).
    private func buildWeekGrid() -> GridLayout {
        let calendar = Calendar.current
        let today = Date()

        // Find the most recent Monday
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        comps.weekday = 2 // Monday
        let thisMonday = calendar.date(from: comps) ?? today

        // Start from Monday 11 weeks ago
        let startMonday = calendar.date(byAdding: .weekOfYear, value: -11, to: thisMonday) ?? thisMonday

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var columns: [[Int]] = []
        var colLabels: [String] = []
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"

        for week in 0..<12 {
            let weekStart = calendar.date(byAdding: .weekOfYear, value: week, to: startMonday) ?? startMonday
            var col: [Int] = []
            var labelForWeek = ""

            for day in 0..<7 {
                let date = calendar.date(byAdding: .day, value: day, to: weekStart) ?? weekStart
                let key = dateFormatter.string(from: date)
                let value = buckets[key]?.totalTokens ?? 0
                col.append(value)

                // Show month label when this day is the 1st of a month
                let dayOfMonth = calendar.component(.day, from: date)
                if dayOfMonth == 1 {
                    labelForWeek = monthFormatter.string(from: date)
                }
            }
            columns.append(col)
            colLabels.append(labelForWeek)
        }

        let rowLabels = ["Mon", "", "Wed", "", "Fri", "", "Sun"]
        return GridLayout(columns: columns, columnLabels: colLabels, rowLabels: rowLabels)
    }

    /// Day view: 7 columns (last 7 days), 24 rows (hours, approximated from daily).
    private func buildDayGrid() -> GridLayout {
        let calendar = Calendar.current
        let today = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dayOfWeekFormatter = DateFormatter()
        dayOfWeekFormatter.dateFormat = "EEE"

        var columns: [[Int]] = []
        var colLabels: [String] = []

        for dayOffset in stride(from: -6, through: 0, by: 1) {
            let date = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
            let key = dateFormatter.string(from: date)
            let dailyTotal = buckets[key]?.totalTokens ?? 0

            // Distribute evenly across 24 hours as approximation
            let hourly = dailyTotal / 24
            let remainder = dailyTotal % 24
            var col: [Int] = (0..<24).map { hour in
                hour < remainder ? hourly + 1 : hourly
            }
            // Bias activity toward waking hours (8–22) by zeroing out 0–7
            for hour in 0..<8 {
                col[hour] = 0
            }

            columns.append(col)
            colLabels.append(dayOfWeekFormatter.string(from: date))
        }

        let rowLabels: [String] = (0..<24).map { hour in
            switch hour {
            case 0:  return "12a"
            case 6:  return "6a"
            case 12: return "12p"
            case 18: return "6p"
            default: return ""
            }
        }

        return GridLayout(columns: columns, columnLabels: colLabels, rowLabels: rowLabels)
    }

    /// Month view: 12 columns (months), ~5 rows (weeks in month).
    private func buildMonthGrid() -> GridLayout {
        let calendar = Calendar.current
        let today = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"

        // Start from the beginning of the month 11 months ago
        var startComps = calendar.dateComponents([.year, .month], from: today)
        startComps.day = 1
        let thisMonthStart = calendar.date(from: startComps) ?? today
        let startMonth = calendar.date(byAdding: .month, value: -11, to: thisMonthStart) ?? thisMonthStart

        var columns: [[Int]] = []
        var colLabels: [String] = []

        for monthOffset in 0..<12 {
            let monthStart = calendar.date(byAdding: .month, value: monthOffset, to: startMonth) ?? startMonth
            colLabels.append(monthFormatter.string(from: monthStart))

            // Get all days in this month and sum by week-of-month (up to 5 weeks)
            var weekTotals = [Int](repeating: 0, count: 5)

            let range = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<32
            for dayOfMonth in range {
                var comps = calendar.dateComponents([.year, .month], from: monthStart)
                comps.day = dayOfMonth
                guard let date = calendar.date(from: comps) else { continue }

                let key = dateFormatter.string(from: date)
                let value = buckets[key]?.totalTokens ?? 0

                // Week index within month (0-based)
                let weekOfMonth = calendar.component(.weekOfMonth, from: date)
                let weekIndex = min(weekOfMonth - 1, 4)
                weekTotals[weekIndex] += value
            }

            columns.append(weekTotals)
        }

        let rowLabels = ["W1", "", "W3", "", "W5"]
        return GridLayout(columns: columns, columnLabels: colLabels, rowLabels: rowLabels)
    }

    // MARK: - Color mapping

    private func colorForValue(_ value: Int, maxValue: Int) -> Color {
        guard value > 0, maxValue > 0 else { return Self.colors[0] }
        let ratio = Double(value) / Double(maxValue)
        switch ratio {
        case ..<0.25: return Self.colors[1]
        case ..<0.50: return Self.colors[2]
        default:      return Self.colors[3]
        }
    }

    // MARK: - Sub-views

    private var columnLabels: some View {
        let layout = gridData
        return HStack(spacing: 4) {
            ForEach(Array(layout.columnLabels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var rowLabels: some View {
        let layout = gridData
        let rowCount = layout.columns.first?.count ?? 0
        return VStack(spacing: 4) {
            ForEach(0..<rowCount, id: \.self) { row in
                let label = row < layout.rowLabels.count ? layout.rowLabels[row] : ""
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var gridContent: some View {
        let layout = gridData
        let allValues = layout.columns.flatMap { $0 }
        let maxValue = allValues.max() ?? 0

        return HStack(spacing: 4) {
            ForEach(Array(layout.columns.enumerated()), id: \.offset) { _, col in
                VStack(spacing: 4) {
                    ForEach(Array(col.enumerated()), id: \.offset) { _, value in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(colorForValue(value, maxValue: maxValue))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleBuckets: [String: DailyBucket] = {
        var result: [String: DailyBucket] = [:]
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        for i in 0..<84 {
            if let date = calendar.date(byAdding: .day, value: -i, to: Date()) {
                let key = formatter.string(from: date)
                var bucket = DailyBucket()
                bucket.inputTokens = Int.random(in: 0...50000)
                bucket.outputTokens = Int.random(in: 0...15000)
                result[key] = bucket
            }
        }
        return result
    }()

    VStack(spacing: 16) {
        ActivityHeatmap(buckets: sampleBuckets, granularity: .week)
        ActivityHeatmap(buckets: sampleBuckets, granularity: .day)
        ActivityHeatmap(buckets: sampleBuckets, granularity: .month)
    }
    .padding()
    .background(Color(red: 0.08, green: 0.07, blue: 0.15))
}
