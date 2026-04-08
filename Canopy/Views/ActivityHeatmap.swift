import SwiftUI

/// GitHub-style contribution heatmap — 12 weeks × 24 hours per day.
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

    private struct GridData {
        var columns: [[Int]]       // [dayIndex][hour] = tokens
        var cellLabels: [[String]] // hover tooltips
        var monthSpans: [(name: String, columns: Int)] // merged month headers
    }

    var body: some View {
        let grid = buildGrid()
        let maxValue = grid.columns.flatMap { $0 }.max() ?? 0

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Last 12 Weeks")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                legend
            }
            .padding(.bottom, 6)

            // Month labels — merged cells spanning the correct day columns
            monthLabelsView(grid.monthSpans)
                .padding(.leading, 24)
                .padding(.bottom, 2)

            HStack(alignment: .top, spacing: 0) {
                hourLabelsView()
                    .frame(width: 20)
                gridContentView(grid, maxValue: maxValue)
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

    private func buildGrid() -> GridData {
        let calendar = Calendar.current
        let today = Date()

        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        comps.weekday = 2
        let thisMonday = calendar.date(from: comps) ?? today
        let startDate = calendar.date(byAdding: .weekOfYear, value: -11, to: thisMonday) ?? thisMonday

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.timeZone = .current
        let displayFmt = DateFormatter()
        displayFmt.dateFormat = "MMM d"

        let totalDays = 12 * 7
        var columns: [[Int]] = []
        var cellLabels: [[String]] = []

        // Track month spans for merged headers
        var monthSpans: [(name: String, columns: Int)] = []
        let monthNameFmt = DateFormatter()
        monthNameFmt.dateFormat = "MMMM"
        var currentMonth = -1

        for dayOffset in 0..<totalDays {
            let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) ?? startDate
            let dateStr = displayFmt.string(from: date)
            let dayKey = dateFmt.string(from: date)
            let month = calendar.component(.month, from: date)

            // Track month transitions
            if month != currentMonth {
                monthSpans.append((name: monthNameFmt.string(from: date), columns: 1))
                currentMonth = month
            } else {
                monthSpans[monthSpans.count - 1].columns += 1
            }

            var col: [Int] = []
            var colLabels: [String] = []
            for hour in 0..<24 {
                let hourKey = "\(dayKey)-\(String(format: "%02d", hour))"
                let tokens = hourlyBuckets[hourKey]?.totalTokens ?? 0
                col.append(tokens)
                colLabels.append("\(dateStr), \(hour):00\n\(abbreviatedTokenCount(tokens)) tokens")
            }
            columns.append(col)
            cellLabels.append(colLabels)
        }

        return GridData(columns: columns, cellLabels: cellLabels, monthSpans: monthSpans)
    }

    // MARK: - Color

    private func colorForValue(_ value: Int, maxValue: Int) -> Color {
        guard value > 0, maxValue > 0 else { return Self.colors[0] }
        let level = min(Int(Double(value) / Double(maxValue) * 6) + 1, 6)
        return Self.colors[level]
    }

    // MARK: - Sub-views

    private func monthLabelsView(_ spans: [(name: String, columns: Int)]) -> some View {
        HStack(spacing: 1) {
            ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                Text(span.name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Weight proportional to number of day columns
                    .layoutPriority(Double(span.columns))
            }
        }
    }

    private func hourLabelsView() -> some View {
        VStack(spacing: 1) {
            ForEach(0..<24, id: \.self) { hour in
                Text(hour % 3 == 0 ? "\(hour)" : "")
                    .font(.system(size: 7))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
        }
    }

    private func gridContentView(_ grid: GridData, maxValue: Int) -> some View {
        HStack(spacing: 1) {
            ForEach(Array(grid.columns.enumerated()), id: \.offset) { colIdx, col in
                VStack(spacing: 1) {
                    ForEach(Array(col.enumerated()), id: \.offset) { rowIdx, value in
                        let tooltip = colIdx < grid.cellLabels.count && rowIdx < grid.cellLabels[colIdx].count
                            ? grid.cellLabels[colIdx][rowIdx] : ""
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
