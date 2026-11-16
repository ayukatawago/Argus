import SwiftUI

/// Renders one flat row item of a file's layout. Each case is a small view, so a row only re-renders
/// when the state it reads changes.
struct DiffRowView: View {
    let item: DiffRowItem
    let file: DiffFile
    let layout: DiffFileLayout
    let model: DiffReviewModel
    @Bindable var interaction: DiffInteractionState

    var body: some View {
        switch item {
        case .hunkHeader(_, let text):
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(DiffReviewTheme.hunkForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(DiffReviewTheme.hunkBackground)
                .id(item.id)

        case .expander(let expander):
            DiffExpanderRowView(expander: expander, gap: layout.gapsByExpanderID[expander.id], file: file, model: model)
                .id(item.id)

        case .line(let row):
            DiffLineRowView(row: row, file: file, layout: layout, model: model, interaction: interaction)
                .id(item.id)
        }
    }
}
