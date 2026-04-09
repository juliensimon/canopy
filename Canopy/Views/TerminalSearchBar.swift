import SwiftUI
import SwiftTerm

struct TerminalSearchBar: View {
    let terminalSession: TerminalSession
    @Binding var isVisible: Bool
    var initialQuery: String = ""

    @State private var query = ""
    @State private var matches: [Match] = []
    @State private var currentIndex = 0
    @FocusState private var isSearchFocused: Bool

    struct Match {
        let snippet: String   // ~60 chars around the hit
        let lineIndex: Int    // line number in getFullText() output
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                TextField("Search terminal...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isSearchFocused)
                    .foregroundColor(matches.isEmpty && !query.isEmpty ? .red : nil)
                    .onSubmit { navigate(by: 1) }

                if !matches.isEmpty {
                    Text("\(currentIndex + 1)/\(matches.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button(action: { navigate(by: -1) }) {
                        Image(systemName: "chevron.up").font(.system(size: 10, weight: .bold))
                    }.buttonStyle(.plain)
                    Button(action: { navigate(by: 1) }) {
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    }.buttonStyle(.plain)
                }

                Button(action: { isVisible = false }) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))

            if !matches.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(matches.enumerated()), id: \.offset) { index, match in
                                Text(match.snippet)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(index == currentIndex ? Color.accentColor.opacity(0.15) : Color.clear)
                                    .contentShape(Rectangle())
                                    .id(index)
                                    .onTapGesture { jumpTo(index: index) }
                            }
                        }
                    }
                    .background(Color(nsColor: .windowBackgroundColor))
                    .frame(maxHeight: 150)
                    .onChange(of: currentIndex) { _, i in proxy.scrollTo(i, anchor: .center) }
                }
            }
        }
        .onAppear {
            if !initialQuery.isEmpty { query = initialQuery }
            isSearchFocused = true
        }
        .onChange(of: query) { _, _ in search() }
        .onChange(of: isVisible) { _, visible in
            if !visible {
                terminalSession.terminalView?.clearSearch()
                query = ""
                matches = []
            }
        }
        .onKeyPress(.upArrow)   { navigate(by: -1); return .handled }
        .onKeyPress(.downArrow) { navigate(by:  1); return .handled }
        .onKeyPress(.escape)    { isVisible = false; return .handled }
    }

    // MARK: - Search

    private func search() {
        guard !query.isEmpty else {
            matches = []
            terminalSession.terminalView?.clearSearch()
            return
        }
        let q = query.lowercased()
        let lines = terminalSession.getFullText().components(separatedBy: "\n")
        matches = lines.enumerated().compactMap { lineIndex, line in
            guard let range = line.lowercased().range(of: q) else { return nil }
            let snippet = makeSnippet(line: line, range: range, query: query)
            return Match(snippet: snippet, lineIndex: lineIndex)
        }
        currentIndex = 0
        if let first = matches.first { scrollToLine(first.lineIndex, totalLines: lines.count) }
    }

    private func navigate(by delta: Int) {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex + delta + matches.count) % matches.count
        let lines = terminalSession.getFullText().components(separatedBy: "\n")
        scrollToLine(matches[currentIndex].lineIndex, totalLines: lines.count)
    }

    private func jumpTo(index: Int) {
        currentIndex = index
        let lines = terminalSession.getFullText().components(separatedBy: "\n")
        scrollToLine(matches[index].lineIndex, totalLines: lines.count)
    }

    // MARK: - Scroll

    private func scrollToLine(_ lineIndex: Int, totalLines: Int) {
        guard let tv = terminalSession.terminalView, totalLines > 0 else { return }
        // Try SwiftTerm's native search first (highlights text, works for plain output)
        let found = tv.findNext(query)
        if found { return }
        // Fallback: estimate scroll position from relative line index and jump there
        let position = Double(lineIndex) / Double(totalLines)
        tv.scroll(toPosition: position)
    }

    // MARK: - Snippet

    private func makeSnippet(line: String, range: Range<String.Index>, query: String) -> String {
        let window = 30
        let start = line.index(range.lowerBound, offsetBy: -min(window, line.distance(from: line.startIndex, to: range.lowerBound)))
        let end   = line.index(range.upperBound,  offsetBy:  min(window, line.distance(from: range.upperBound, to: line.endIndex)))
        var snippet = String(line[start..<end])
        if start > line.startIndex { snippet = "…" + snippet }
        if end < line.endIndex     { snippet = snippet + "…" }
        return snippet
    }
}
