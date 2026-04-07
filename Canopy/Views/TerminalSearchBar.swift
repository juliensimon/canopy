import SwiftUI

struct TerminalSearchBar: View {
    let terminalSession: TerminalSession
    @Binding var isVisible: Bool
    @State private var query = ""
    @State private var matches: [SearchMatch] = []
    @State private var currentMatchIndex = 0
    @FocusState private var isSearchFocused: Bool

    struct SearchMatch: Identifiable {
        let id = UUID()
        let lineNumber: Int
        let line: String
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                TextField("Search terminal output...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isSearchFocused)
                    .onSubmit { nextMatch() }

                if !matches.isEmpty {
                    Text("\(currentMatchIndex + 1)/\(matches.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Button(action: { previousMatch() }) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)

                    Button(action: { nextMatch() }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: { isVisible = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)

            if !matches.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                                HStack(spacing: 8) {
                                    Text("\(match.lineNumber)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 35, alignment: .trailing)
                                    Text(match.line)
                                        .font(.system(size: 11, design: .monospaced))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(index == currentMatchIndex ? Color.accentColor.opacity(0.1) : Color.clear)
                                .contentShape(Rectangle())
                                .id(index)
                                .onTapGesture {
                                    currentMatchIndex = index
                                    copyMatch(match)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                    .onChange(of: currentMatchIndex) { _, newValue in
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
        .onAppear { isSearchFocused = true }
        .onChange(of: query) { _, _ in search() }
        .onKeyPress(.escape) { isVisible = false; return .handled }
    }

    private func search() {
        guard !query.isEmpty else {
            matches = []
            currentMatchIndex = 0
            return
        }
        let text = terminalSession.getFullText()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let q = query.lowercased()
        matches = lines.enumerated().compactMap { index, line in
            let str = String(line)
            guard str.lowercased().contains(q) else { return nil }
            return SearchMatch(lineNumber: index + 1, line: str)
        }
        currentMatchIndex = 0
    }

    private func nextMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matches.count
    }

    private func previousMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matches.count) % matches.count
    }

    private func copyMatch(_ match: SearchMatch) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(match.line, forType: .string)
    }
}
