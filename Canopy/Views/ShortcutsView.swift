import SwiftUI

/// Dedicated keyboard shortcuts reference sheet.
struct ShortcutsView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Keyboard Shortcuts")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.bottom, 20)

            ScrollView {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 16) {
                shortcutSection("Sessions") {
                    shortcutRow("New Session", "T")
                    shortcutRow("New Worktree Session", "\u{21E7}T")
                    shortcutRow("Add Project", "\u{21E7}P")
                    shortcutRow("Toggle Split Terminal", "\u{21E7}D")
                }

                Divider()
                    .gridCellColumns(2)

                shortcutSection("Tabs") {
                    shortcutRow("Switch to Tab 1\u{2013}9", "1\u{2013}9")
                    shortcutRow("Cycle Sort Mode", "\u{21E7}S")
                }

                Divider()
                    .gridCellColumns(2)

                shortcutSection("App") {
                    shortcutRow("Settings", ",")
                    shortcutRow("Help", "?")
                }
            }
            }

            Spacer(minLength: 12)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    @ViewBuilder
    private func shortcutSection(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        GridRow {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .gridCellColumns(2)
        }
        rows()
    }

    private func shortcutRow(_ label: String, _ key: String) -> some View {
        GridRow {
            Text(label)
                .font(.system(size: 13))
            HStack(spacing: 2) {
                keycap("\u{2318}")
                keycap(key)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func keycap(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 11))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1))
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
            )
    }
}
