import SwiftUI

/// GitHub-style contribution heatmap showing the last 12 weeks.
struct ActivityHeatmap: View {
    let buckets: [String: DailyBucket]

    private static let colors: [Color] = [
        Color(red: 0.118, green: 0.118, blue: 0.227),  // empty
        Color(red: 0.145, green: 0.110, blue: 0.310),  // level 1
        Color(red: 0.176, green: 0.106, blue: 0.412),  // level 2
        Color(red: 0.240, green: 0.110, blue: 0.540),  // level 3
        Color(red: 0.310, green: 0.120, blue: 0.650),  // level 4
        Color(red: 0.400, green: 0.160, blue: 0.780),  // level 5
        Color(red: 0.486, green: 0.227, blue: 0.929),  // level 6 — max
    ]

    private struct GridLayout {
        var columns: [[Int]]
        var cellLabels: [[String]]
        var columnLabels: [String]
        var rowLabels: [String]
    }

    var body: some View {
        let layout = buildWeekGrid()
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
            .padding(.bottom, 8)

            columnLabelsView(layout)
                .padding(.leading, 30)
                .padding(.bottom, 4)

            HStack(alignment: .top, spacing: 0) {
                rowLabelsView(layout)
                    .frame(width: 26)
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
        HStack(spacing: 4) {
            Text("Less")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            ForEach(0..<7, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Self.colors[level])
                    .frame(width: 10, height: 10)
            }
            Text("More")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Grid building

    private func buildWeekGrid() -> GridLayout {
        let calendar = Calendar.current
        let today = Date()

        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        comps.weekday = 2 // Monday
        let thisMonday = calendar.date(from: comps) ?? today
        let startMonday = calendar.date(byAdding: .weekOfYear, value: -11, to: thisMonday) ?? thisMonday

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "MMM d, yyyy"

        var columns: [[Int]] = []
        var labels: [[String]] = []
        var colLabels: [String] = []
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"

        for week in 0..<12 {
            let weekStart = calendar.date(byAdding: .weekOfYear, value: week, to: startMonday) ?? startMonday
            var col: [Int] = []
            var colCellLabels: [String] = []
            var labelForWeek = ""

            for day in 0..<7 {
                let date = calendar.date(byAdding: .day, value: day, to: weekStart) ?? weekStart
                let key = dateFormatter.string(from: date)
                let tokens = buckets[key]?.totalTokens ?? 0
                col.append(tokens)
                colCellLabels.append("\(displayFormatter.string(from: date))\n\(abbreviatedTokenCount(tokens)) tokens")

                if calendar.component(.day, from: date) == 1 {
                    labelForWeek = monthFormatter.string(from: date)
                }
            }
            columns.append(col)
            labels.append(colCellLabels)
            colLabels.append(labelForWeek)
        }

        return GridLayout(
            columns: columns,
            cellLabels: labels,
            columnLabels: colLabels,
            rowLabels: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        )
    }

    // MARK: - Color mapping

    private func colorForValue(_ value: Int, maxValue: Int) -> Color {
        guard value > 0, maxValue > 0 else { return Self.colors[0] }
        let ratio = Double(value) / Double(maxValue)
        let level = min(Int(ratio * 6) + 1, 6)
        return Self.colors[level]
    }

    // MARK: - Sub-views

    private func columnLabelsView(_ layout: GridLayout) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(layout.columnLabels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func rowLabelsView(_ layout: GridLayout) -> some View {
        VStack(spacing: 4) {
            ForEach(Array(layout.rowLabels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
        }
    }

    private func gridContentView(_ layout: GridLayout, maxValue: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(layout.columns.enumerated()), id: \.offset) { colIdx, col in
                VStack(spacing: 4) {
                    ForEach(Array(col.enumerated()), id: \.offset) { rowIdx, value in
                        let tooltip = colIdx < layout.cellLabels.count && rowIdx < layout.cellLabels[colIdx].count
                            ? layout.cellLabels[colIdx][rowIdx] : ""
                        RoundedRectangle(cornerRadius: 3)
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

    ActivityHeatmap(buckets: sampleBuckets)
        .padding()
        .frame(height: 300)
        .background(Color(red: 0.08, green: 0.07, blue: 0.15))
}
