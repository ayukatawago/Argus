import Foundation

/// Identifies one row of a file's diff across the whole list: the file path plus the row id.
struct RowRef: Hashable, Sendable {
    let filePath: String
    let rowID: String
}

/// Cross-file search over the diff's hunk lines.
enum DiffSearch {
    /// Every line row, across all files and in display order, where either side's text contains
    /// `query` case-insensitively. Hidden gap context is not in the diff, so it isn't searched.
    /// An empty (or all-whitespace) query matches nothing.
    static func matches(in files: [DiffFile], query: String) -> [RowRef] {
        let sections = files.map { file in
            DiffRowSection(filePath: file.path, items: DiffRowItemBuilder.items(for: file, gaps: [:]))
        }
        return matches(query: query, sections: sections)
    }

    /// The same search over already-built rows, so the list can reuse each file's memoized layout
    /// (including revealed gap context) instead of rebuilding it.
    static func matches(query: String, sections: [DiffRowSection]) -> [RowRef] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        return sections.flatMap { section -> [RowRef] in
            section.items.compactMap { item -> RowRef? in
                guard case .line(let row) = item else { return nil }
                let hit = [row.left, row.right].contains { $0?.text.localizedCaseInsensitiveContains(needle) == true }
                return hit ? RowRef(filePath: section.filePath, rowID: row.id) : nil
            }
        }
    }
}
