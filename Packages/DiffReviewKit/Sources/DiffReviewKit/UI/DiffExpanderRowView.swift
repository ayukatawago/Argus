import AppKit
import SwiftUI

/// The expander row of a gap: ↑ / ↓ / ↕ buttons in the gutter, and the following hunk's `@@` header.
/// ⌥-click on any button reveals the whole gap.
struct DiffExpanderRowView: View {
    let expander: DiffRowItem.Expander
    let gap: DiffGap?
    let file: DiffFile
    let model: DiffReviewModel

    private var isLoading: Bool {
        gap.map { model.isLoadingGap($0.id, filePath: file.path) } ?? false
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                if expander.offersUp { expandButton(.up, systemImage: "arrow.up", help: "Show more above") }
                if expander.offersDown { expandButton(.down, systemImage: "arrow.down", help: "Show more below") }
                if expander.offersAll { expandButton(.all, systemImage: "arrow.up.and.down", help: "Show all") }
                if isLoading { ProgressView().controlSize(.small) }
            }
            .frame(width: 96)
            .frame(maxHeight: .infinity)
            .background(DiffReviewTheme.expanderGutterBackground)

            if let header = expander.hunkHeader {
                Text(header)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(DiffReviewTheme.hunkForeground)
                    .lineLimit(1)
                    .padding(.leading, 8)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
        .background(DiffReviewTheme.hunkBackground)
    }

    private func expandButton(_ direction: GapExpansion.Direction, systemImage: String, help: String) -> some View {
        Button {
            expand(direction)
        } label: {
            Image(systemName: systemImage)
                .frame(width: 18, height: 16)
        }
        .buttonStyle(.borderless)
        .disabled(isLoading || gap == nil)
        .help(help)
    }

    private func expand(_ direction: GapExpansion.Direction) {
        guard let gap else { return }
        let effective: GapExpansion.Direction = NSEvent.modifierFlags.contains(.option) ? .all : direction
        Task { await model.expandGap(gap, in: file, direction: effective) }
    }
}
