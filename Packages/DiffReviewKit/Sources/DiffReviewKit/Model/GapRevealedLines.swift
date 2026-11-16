import Foundation

/// The context lines a gap reveals, built from the file's source content. Pure so the id scheme and
/// the top/bottom split can be tested without running git.
enum GapRevealedLines {
    /// Index into the source lines where `gap` begins (0-based): the old side for a deleted file,
    /// since only the base revision still has it, and the new side otherwise.
    static func sourceStart(of gap: DiffGap, in file: DiffFile) -> Int {
        (file.kind == .deleted ? gap.oldStart : gap.newStart) - 1
    }

    /// Deterministic id `<path>|ctx|<old>|<new>`, with `-` standing in for a side that has no line
    /// number. Fresh UUIDs on every render would churn row identity and drop anchored comments.
    static func lineID(path: String, oldLineNumber: Int?, newLineNumber: Int?) -> String {
        "\(path)|ctx|\(oldLineNumber.map(String.init) ?? "-")|\(newLineNumber.map(String.init) ?? "-")"
    }

    /// The first `revealedFromTop` lines of the gap, and the last `revealedFromBottom` lines, never
    /// overlapping and never past the end of `sourceLines`. Empty while `lineCount` is unknown.
    static func make(
        gap: DiffGap,
        file: DiffFile,
        expansion: GapExpansion,
        lineCount: Int?,
        sourceLines: [String]
    ) -> (top: [DiffLine], bottom: [DiffLine]) {
        let start = sourceStart(of: gap, in: file)
        guard let lineCount, start >= 0 else { return ([], []) }
        let length = min(lineCount, sourceLines.count - start)
        guard length > 0 else { return ([], []) }

        let topEnd = min(expansion.revealedFromTop, length)
        let bottomStart = max(length - expansion.revealedFromBottom, topEnd)
        let top = (0..<topEnd).map { line(offset: $0, gap: gap, file: file, text: sourceLines[start + $0]) }
        let bottom = (bottomStart..<length).map {
            line(offset: $0, gap: gap, file: file, text: sourceLines[start + $0])
        }
        return (top, bottom)
    }

    private static func line(offset: Int, gap: DiffGap, file: DiffFile, text: String) -> DiffLine {
        let oldLineNumber = file.kind == .added ? nil : gap.oldStart + offset
        let newLineNumber = file.kind == .deleted ? nil : gap.newStart + offset
        return DiffLine(
            kind: .context,
            text: text,
            oldLineNumber: oldLineNumber,
            newLineNumber: newLineNumber,
            id: lineID(path: file.path, oldLineNumber: oldLineNumber, newLineNumber: newLineNumber)
        )
    }

    /// Splits file text into lines, keeping interior empty lines and dropping the one a trailing newline adds.
    static func splitLines(_ text: String) -> [String] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if text.hasSuffix("\n") { lines.removeLast() }
        return lines
    }
}
