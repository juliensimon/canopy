import SwiftUI

/// Forest canopy-themed contribution heatmap — 12 weeks × 24 hours per day.
/// Active cells gently sway in opacity like light filtering through leaves.
struct ActivityHeatmap: View {
    let hourlyBuckets: [String: HourlyBucket]

    // Forest green palette: dark moss → emerald → bright canopy
    private static let colors: [Color] = [
        Color(red: 0.08, green: 0.10, blue: 0.08),   // empty — dark forest floor
        Color(red: 0.08, green: 0.16, blue: 0.08),   // level 1 — deep moss
        Color(red: 0.10, green: 0.24, blue: 0.10),   // level 2 — dark fern
        Color(red: 0.12, green: 0.34, blue: 0.14),   // level 3 — forest shade
        Color(red: 0.16, green: 0.46, blue: 0.18),   // level 4 — mid canopy
        Color(red: 0.22, green: 0.60, blue: 0.24),   // level 5 — bright leaf
        Color(red: 0.30, green: 0.75, blue: 0.32),   // level 6 — sunlit canopy
    ]

    private struct GridData {
        var columns: [[Int]]
        var cellLabels: [[String]]
        var monthSpans: [(name: String, columns: Int)]
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
                .fill(Color(red: 0.06, green: 0.08, blue: 0.06))
                .stroke(Color(red: 0.12, green: 0.18, blue: 0.12), lineWidth: 1)
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
        var monthSpans: [(name: String, columns: Int)] = []
        let monthNameFmt = DateFormatter()
        monthNameFmt.dateFormat = "MMMM"
        var currentMonth = -1

        for dayOffset in 0..<totalDays {
            let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) ?? startDate
            let dateStr = displayFmt.string(from: date)
            let dayKey = dateFmt.string(from: date)
            let month = calendar.component(.month, from: date)

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
        GeometryReader { geo in
            let totalCols = spans.reduce(0) { $0 + $1.columns }
            let totalSpacing = CGFloat(totalCols - 1)
            let availableWidth = geo.size.width - totalSpacing
            let colWidth = totalCols > 0 ? availableWidth / CGFloat(totalCols) : 0

            HStack(spacing: 0) {
                ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                    let spanWidth = colWidth * CGFloat(span.columns) + CGFloat(span.columns - 1)
                    Text(span.name)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: spanWidth, alignment: .leading)
                        .clipped()
                }
            }
        }
        .frame(height: 14)
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
                        LeafCell(
                            color: colorForValue(value, maxValue: maxValue),
                            isActive: value > 0,
                            seed: colIdx * 24 + rowIdx
                        )
                        .contentShape(Rectangle())
                        .help(tooltip)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Animated leaf cell

/// A single heatmap cell that gently sways in opacity when active,
/// like light filtering through a canopy.
private struct LeafCell: View {
    let color: Color
    let isActive: Bool
    let seed: Int

    @State private var swaying = false

    // Each cell gets a unique duration and delay based on its seed,
    // so the sway looks organic, not synchronized.
    private var duration: Double {
        3.5 + Double(seed % 7) * 0.5 // 3.5–7.0 seconds
    }

    private var delay: Double {
        Double(seed % 13) * 0.3 // 0–3.9 second offset
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(swaying && isActive ? 0.75 : 1.0)
            .onAppear {
                guard isActive else { return }
                withAnimation(
                    .easeInOut(duration: duration)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    swaying = true
                }
            }
    }
}

// MARK: - Preview

#Preview {
    ActivityHeatmap(hourlyBuckets: [:])
        .padding()
        .frame(width: 900, height: 400)
        .background(Color(red: 0.05, green: 0.06, blue: 0.05))
}
