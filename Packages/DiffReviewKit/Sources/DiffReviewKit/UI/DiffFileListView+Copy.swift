import SwiftUI

extension DiffFileListView {
    /// ⌘C: the drag-made text selection if there is one, otherwise the line-number range selection.
    func copySelection() {
        if let selection = interaction.textSelection {
            let texts = layout(forPath: selection.filePath)?.lineTexts[selection.side] ?? [:]
            DiffSelectionCopy.copyToPasteboard(DiffSelectionCopy.text(for: selection, texts: texts))
        } else if let selection = interaction.pendingSelection {
            let texts = layout(forPath: selection.filePath)?.lineTexts[selection.side] ?? [:]
            DiffSelectionCopy.copyToPasteboard(DiffSelectionCopy.text(lines: selection.range, texts: texts))
        }
    }
}
