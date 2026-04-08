import SwiftUI

/// GitHub-style contribution heatmap — 12 weeks × 24 hours per day.
/// Each column is one day, each row is one hour. Real hourly resolution.
struct ActivityHeatmap: View {
    let hourlyBuckets: [String: HourlyBucket]

    private static let colors: [Color] = [
        Color(red: 0.118, green: 0.118, blue: 0.227),  // empty
        Color(red: 0.145, green: 0.110, blue: 0.310),
        Color(red: 0.176, green: 0.106, blue: 0.412),
        Color(red: 0.240, green: 0.110, blue: 0.540),
        Color(red: 0.310, green: 0.120, blue: 0.650),
        Color(red: 0.400, green: 0.160, blue: 0.780),
        Color(red: 0.486, green: 0.227, blue: 0.929),  // max
    ]

    private struct GridLayout {
        var columns: [[Int]]       // columns[dayIndex][hour] = token count
        var cellLabels: [[String]] // hover tooltips
        var dayLabels: [String]    // one per column (shown sparsely)
        var hourLabels: [String]   // 24 rows
    }

    var body: some View {
        let layout = buildGrid()
        let allValues = layout.columns.flatMap { $0 }
        let maxValue = allValues.max() ?? 0

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Last 12 Weeks")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                legend
            }
            .padding(.bottom, 6)

            // Day labels along the top (show Monday dates sparsely)
            dayLabelsView(layout)
                .padding(.leading, 28)
                .padding(.bottom, 2)

            HStack(alignment: .top, spacing: 0) {
                hourLabelsView(layout)
                    .frame(width: 24)
                gridContentView(layout, maxValue: maxValue)
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
        HStack(spacing: 3) {
            Text("Less")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            ForEach(0..<7, id: \.self) { level in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Self.colors[level])
                    .frame(width: 8, height: 8)
            }
            Text("More")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Grid building

    private func buildGrid() -> GridLayout {
        let calendar = Calendar.current
        let today = Date()

        // Start from 12 weeks ago (Monday)
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        comps.weekday = 2
        let thisMonday = calendar.date(from: comps) ?? today
        let startDate = calendar.date(byAdding: .weekOfYear, value: -11, to: thisMonday) ?? thisMonday

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let displayFmt = DateFormatter()
        displayFmt.dateFormat = "MMM d"
        let hourKeyFmt = DateFormatter()
        hourKeyFmt.dateFormat = "yyyy-MM-dd-HH"
        hourKeyFmt.timeZone = .current
        dateFmt.timeZone = .current

        // 84 days × 24 hours
        let totalDays = 12 * 7
        var columns: [[Int]] = []
        var cellLabels: [[String]] = []
        var dayLabels: [String] = []

        for dayOffset in 0..<totalDays {
            let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) ?? startDate
            let dateStr = displayFmt.string(from: date)
            let dayKey = dateFmt.string(from: date)

            // Show label on Mondays
            let weekday = calendar.component(.weekday, from: date)
            dayLabels.append(weekday == 2 ? dateStr : "")

            var col: [Int] = []
            var colLabels: [String] = []
            for hour in 0..<24 {
                let hourKey = "\(dayKey)-\(String(format: "%02d", hour))"
                let tokens = hourlyBuckets[hourKey]?.totalTokens ?? 0
                col.append(tokens)

                let hourStr = hour == 0 ? "12a" : hour < 12 ? "\(hour)a" : hour == 12 ? "12p" : "\(hour-12)p"
                colLabels.append("\(dateStr), \(hourStr)\n\(abbreviatedTokenCount(tokens)) tokens")
            }
            columns.append(col)
            cellLabels.append(colLabels)
        }

        let hourLabels: [String] = (0..<24).map { hour in
            if hour == 0 { return "12a" }
            if hour < 12 { return "\(hour)a" }
            if hour == 12 { return "12p" }
            return "\(hour - 12)p"
        }

        return GridLayout(columns: columns, cellLabels: cellLabels, dayLabels: dayLabels, hourLabels: hourLabels)
    }

    // MARK: - Color mapping

    private func colorForValue(_ value: Int, maxValue: Int) -> Color {
        guard value > 0, maxValue > 0 else { return Self.colors[0] }
        let ratio = Double(value) / Double(maxValue)
        let level = min(Int(ratio * 6) + 1, 6)
        return Self.colors[level]
    }

    // MARK: - Sub-views

    private func dayLabelsView(_ layout: GridLayout) -> some View {
        HStack(spacing: 1) {
            ForEach(Array(layout.dayLabels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.system(size: 7))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
            }
        }
    }

    private func hourLabelsView(_ layout: GridLayout) -> some View {
        VStack(spacing: 1) {
            ForEach(Array(layout.hourLabels.enumerated()), id: \.offset) { idx, label in
                // Show every 3rd hour to keep it readable
                Text(idx % 3 == 0 ? label : "")
                    .font(.system(size: 7))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
        }
    }

    private func gridContentView(_ layout: GridLayout, maxValue: Int) -> some View {
        HStack(spacing: 1) {
            ForEach(Array(layout.columns.enumerated()), id: \.offset) { colIdx, col in
                VStack(spacing: 1) {
                    ForEach(Array(col.enumerated()), id: \.offset) { rowIdx, value in
                        let tooltip = colIdx < layout.cellLabels.count && rowIdx < layout.cellLabels[colIdx].count
                            ? layout.cellLabels[colIdx][rowIdx] : ""
                        RoundedRectangle(cornerRadius: 1)
                            .fill(colorForValue(value, maxValue: maxValue))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .help(tooltip)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

#Preview {
    ActivityHeatmap(hourlyBuckets: [:])
        .padding()
        .frame(width: 900, height: 400)
        .background(Color(red: 0.08, green: 0.07, blue: 0.15))
}
