import AppKit
import SwiftUI

/// Right-hand sidebar listing the commits in the current `baseRef..headRef` range, newest first,
/// with a synthetic "Uncommitted changes" row pinned above them (index `-1`). All real commits
/// are selected by default (uncommitted changes are excluded); clicking a row narrows the
/// selection to just that row, and shift-clicking extends it to a contiguous run — both narrow
/// the file tree + diff via `model.effectiveBase`/`effectiveHead`/`includesUncommitted`.
struct CommitListView: View {
    @Bindable var model: DiffReviewModel

    /// Anchor index for shift-click range extension; reset whenever a plain click starts a new
    /// single-row selection. `-1` is the "Uncommitted changes" row.
    @State private var anchorIndex: Int?

    private var fullRange: ClosedRange<Int>? {
        model.commits.isEmpty ? nil : 0...(model.commits.count - 1)
    }

    private var selectedRange: ClosedRange<Int>? {
        model.selectedCommitRange ?? fullRange
    }

    var body: some View {
        VStack(spacing: 0) {
            RevisionPickerView(model: model)
            Divider()
            header
            Divider()
            List {
                UncommittedRow(isSelected: selectedRange?.contains(-1) ?? false)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        select(index: -1, extend: NSEvent.modifierFlags.contains(.shift))
                    }
                ForEach(Array(model.commits.enumerated()), id: \.element.id) { index, commit in
                    CommitRow(commit: commit, isSelected: selectedRange?.contains(index) ?? false)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            select(index: index, extend: NSEvent.modifierFlags.contains(.shift))
                        }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var header: some View {
        HStack {
            Text(rangeSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if model.selectedCommitRange != nil {
                Button("Select all") {
                    model.selectedCommitRange = nil
                    anchorIndex = nil
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var rangeSummary: String {
        guard let range = selectedRange else { return "0 commits" }
        guard range.lowerBound == -1 else {
            let count = range.upperBound - range.lowerBound + 1
            return count == model.commits.count
                ? "\(count) commit\(count == 1 ? "" : "s")"
                : "\(count) of \(model.commits.count) selected"
        }
        let commitCount = range.upperBound + 1
        return commitCount == 0
            ? "Uncommitted changes"
            : "Uncommitted + \(commitCount) commit\(commitCount == 1 ? "" : "s")"
    }

    private func select(index: Int, extend: Bool) {
        if extend, let anchor = anchorIndex {
            model.selectedCommitRange = min(anchor, index)...max(anchor, index)
        } else {
            anchorIndex = index
            model.selectedCommitRange = index...index
        }
        Task { await model.refreshDiff() }
    }
}

private struct UncommittedRow: View {
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil.circle")
                .foregroundStyle(DiffReviewTheme.commentAccent)
            Text("Uncommitted changes")
                .font(.callout.italic())
        }
        .padding(.vertical, 2)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
    }
}

private struct CommitRow: View {
    let commit: Commit
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(commit.shortHash)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.subject)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(commit.author) · \(commit.relativeDate)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
    }
}
