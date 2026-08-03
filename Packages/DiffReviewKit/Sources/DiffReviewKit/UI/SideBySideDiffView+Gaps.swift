import SwiftUI

/// Rendering for collapsed "hidden lines" gaps between/around hunks — split out from
/// `SideBySideDiffView` to keep that type's body under the lint length limit.
extension SideBySideDiffView {
    @ViewBuilder
    func gapView(_ gap: DiffGap) -> some View {
        if let lines = model.expandedLines(forGapID: gap.id) {
            if !lines.isEmpty {
                ForEach(SideBySideBuilder.rows(for: lines)) { row in
                    rowView(row)
                }
            }
        } else {
            Button {
                Task { await model.expandGap(gap, in: file) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.and.down.text.horizontal")
                    Text(gapLabel(gap))
                    Spacer()
                    if model.isLoadingGap(gap.id) {
                        ProgressView().controlSize(.small)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isLoadingGap(gap.id))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(DiffReviewTheme.gapBackground)
        }
    }

    private func gapLabel(_ gap: DiffGap) -> String {
        switch gap.position {
        case .top: gap.lineCount.map { "Expand \($0) lines above" } ?? "Expand lines above"
        case .bottom: gap.lineCount.map { "Expand \($0) lines below" } ?? "Expand lines below"
        case .middle: gap.lineCount.map { "Expand \($0) hidden lines" } ?? "Expand hidden lines"
        }
    }
}
