/// One rendered row of the side-by-side view: a line from the old file, the new file, or both
/// (for unchanged context lines).
struct SideBySideRow: Identifiable {
    let id: String
    let left: DiffLine?
    let right: DiffLine?
}

/// Pairs a hunk's flat sequence of context/deletion/addition lines into side-by-side rows, the way
/// GitHub's split diff view does: consecutive deletions are paired index-wise with the consecutive
/// additions that follow them, and unmatched lines get an empty cell on the other side.
enum SideBySideBuilder {
    static func rows(for hunk: DiffHunk) -> [SideBySideRow] {
        rows(for: hunk.lines)
    }

    /// Also used to pair up a flat run of context lines revealed from an expanded gap.
    static func rows(for lines: [DiffLine]) -> [SideBySideRow] {
        var rows: [SideBySideRow] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            switch line.kind {
            case .context:
                rows.append(SideBySideRow(id: line.id.uuidString, left: line, right: line))
                index += 1

            case .deletion, .addition:
                var deletions: [DiffLine] = []
                while index < lines.count, lines[index].kind == .deletion {
                    deletions.append(lines[index])
                    index += 1
                }
                var additions: [DiffLine] = []
                while index < lines.count, lines[index].kind == .addition {
                    additions.append(lines[index])
                    index += 1
                }
                let pairCount = max(deletions.count, additions.count)
                for pairIndex in 0..<pairCount {
                    let left = deletions[safe: pairIndex]
                    let right = additions[safe: pairIndex]
                    rows.append(
                        SideBySideRow(
                            id: "\(left?.id.uuidString ?? "-")|\(right?.id.uuidString ?? "-")",
                            left: left,
                            right: right
                        )
                    )
                }
            }
        }

        return rows
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
