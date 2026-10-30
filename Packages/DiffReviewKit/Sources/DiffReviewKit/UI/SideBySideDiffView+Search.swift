import SwiftUI

extension SideBySideDiffView {
    var trimmedQuery: String { searchQuery.trimmingCharacters(in: .whitespaces) }

    /// IDs of rows (in display order) where either side's text contains the query, case-insensitively.
    var matchingRowIDs: [String] {
        let query = trimmedQuery
        guard isSearching, !query.isEmpty else { return [] }
        return DiffBlockBuilder.blocks(for: file).flatMap { block -> [String] in
            guard case .hunk(let hunk) = block else { return [] }
            return SideBySideBuilder.rows(for: hunk).filter { row in
                [row.left, row.right].contains { $0?.text.localizedCaseInsensitiveContains(query) == true }
            }.map(\.id)
        }
    }

    func searchBar(proxy: ScrollViewProxy) -> some View {
        let matches = matchingRowIDs
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in diff", text: $searchQuery)
                .textFieldStyle(.plain)
                .focused($searchFieldFocused)
                .onSubmit { step(1, matches: matches, proxy: proxy) }
                .onChange(of: searchQuery) {
                    currentMatch = 0
                    if let first = matchingRowIDs.first { proxy.scrollTo(first, anchor: .center) }
                }
                .onExitCommand { closeSearch() }
            if !trimmedQuery.isEmpty {
                Text(matches.isEmpty ? "No matches" : "\(currentMatch + 1) of \(matches.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                step(-1, matches: matches, proxy: proxy)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(matches.isEmpty)
            Button {
                step(1, matches: matches, proxy: proxy)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(matches.isEmpty)
            Button {
                closeSearch()
            } label: {
                Image(systemName: "xmark")
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .onAppear { searchFieldFocused = true }
    }

    func step(_ delta: Int, matches: [String], proxy: ScrollViewProxy) {
        guard !matches.isEmpty else { return }
        currentMatch = (currentMatch + delta + matches.count) % matches.count
        proxy.scrollTo(matches[currentMatch], anchor: .center)
    }

    func closeSearch() {
        isSearching = false
        searchQuery = ""
        currentMatch = 0
    }

    func isCurrentMatch(_ row: SideBySideRow) -> Bool {
        let matches = matchingRowIDs
        return currentMatch < matches.count && matches[currentMatch] == row.id
    }

    func highlightSearchMatches(in attributed: inout AttributedString) {
        let query = trimmedQuery
        guard isSearching, !query.isEmpty else { return }
        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex,
            let found = attributed[searchStart...].range(of: query, options: .caseInsensitive)
        {
            attributed[found].backgroundColor = Color.yellow.opacity(0.55)
            searchStart = found.upperBound
        }
    }
}
