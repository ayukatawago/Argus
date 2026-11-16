import AppKit

/// Turns a selection into the text that ⌘C and the Copy button put on the pasteboard. The text work is
/// pure so it can be tested; only `copyToPasteboard` touches AppKit.
enum DiffSelectionCopy {
    /// The lines in `range` that exist on one side, one per line, in file order. `nil` if none do.
    static func text(lines range: ClosedRange<Int>, texts: [Int: String]) -> String? {
        let pieces = range.compactMap { texts[$0] }
        return pieces.isEmpty ? nil : pieces.joined(separator: "\n")
    }

    /// The characters a drag-made text selection covers, line by line. `nil` if it covers none.
    static func text(for selection: TextSelectionRange, texts: [Int: String]) -> String? {
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
        return pieces.isEmpty ? nil : pieces.joined(separator: "\n")
    }

    static func copyToPasteboard(_ text: String?) {
        guard let text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
