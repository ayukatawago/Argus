import SwiftUI

/// Header shown across the top of `DiffReviewView`, above both the file tree and the diff pane:
/// "files +X −Y" broken down into total/production/test categories.
struct DiffSummaryBar: View {
    let stats: [DiffSizeStat]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                if index > 0 {
                    Divider().frame(height: 16)
                }
                statView(stat)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func statView(_ stat: DiffSizeStat) -> some View {
        HStack(spacing: 6) {
            Text(stat.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(stat.fileCount == 1 ? "1 file" : "\(stat.fileCount) files")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("+\(stat.additions)")
                .foregroundStyle(DiffReviewTheme.additionForeground)
            Text("−\(stat.deletions)")
                .foregroundStyle(DiffReviewTheme.deletionForeground)
        }
        .font(.subheadline.monospacedDigit())
    }
}
