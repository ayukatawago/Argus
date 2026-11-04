import AppKit

extension SideBySideDiffView {
    /// Puts the selected line range (one side only, in file order) on the pasteboard, one line per row.
    func copy(_ selection: LineSelection) {
        let lines = DiffBlockBuilder.blocks(for: file).flatMap { block -> [String] in
            guard case .hunk(let hunk) = block else { return [] }
            return SideBySideBuilder.rows(for: hunk).compactMap { row in
                let line = selection.side == .old ? row.left : row.right
                let number = selection.side == .old ? line?.oldLineNumber : line?.newLineNumber
                guard let line, let number, selection.range.contains(number) else { return nil }
                return line.text
            }
        }
        guard !lines.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    /// ⌘C: the drag-made text selection if there is one, otherwise the line-number range selection.
    func copySelection() {
        guard let selection = textSelection else {
            if let pendingSelection { copy(pendingSelection) }
            return
        }
        let texts = lineTexts(side: selection.side)
        let (start, end) = (selection.start, selection.end)
        let pieces = (start.line...end.line).compactMap { number -> String? in
            guard let text = texts[number] else { return nil }
            let from = number == start.line ? min(start.column, text.count) : 0
            let upTo = number == end.line ? min(end.column, text.count) : text.count
            guard from <= upTo else { return nil }
            let lower = text.index(text.startIndex, offsetBy: from)
            let upper = text.index(text.startIndex, offsetBy: upTo)
            return String(text[lower..<upper])
        }
        guard !pieces.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pieces.joined(separator: "\n"), forType: .string)
    }
}
