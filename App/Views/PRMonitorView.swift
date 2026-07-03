import AppKit
import SwiftUI

struct PRMonitorView: View {
    @ObservedObject var store: PRMonitorStore
    @State private var isDNMExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if store.isLoading && !store.hasAnyPRs {
                Text("Loading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            } else {
                prSection(title: "My Open PRs", prs: store.myOpenPRs, showAuthor: false)
                prSection(title: "My Drafts", prs: store.myDraftPRs, showAuthor: false)
                prSection(title: "Assigned", prs: store.reviewRequestedPRs, showAuthor: true)
                doNotMergeSection
                if !store.hasAnyPRs && store.lastError == nil {
                    Text("No open pull requests")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                }
                if let error = store.lastError {
                    Text("⚠ \(error)")
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.75))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private func prSection(title: String, prs: [GitHubPR], showAuthor: Bool) -> some View {
        if !prs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05))
                ForEach(prs) { pullRequest in
                    PRRow(
                        pr: pullRequest,
                        showAuthor: showAuthor,
                        isHighlighted: store.highlightedPRIDs.contains(pullRequest.id),
                        onOpen: { store.dismissHighlight(prID: pullRequest.id) }
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.03))
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 6)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var doNotMergeSection: some View {
        if !store.doNotMergePRs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    isDNMExpanded.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isDNMExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 10)
                        Text("Do Not Merge (\(store.doNotMergePRs.count))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05))
                }
                .buttonStyle(.plain)
                if isDNMExpanded {
                    ForEach(store.doNotMergePRs) { pullRequest in
                        PRRow(pr: pullRequest, showAuthor: false, isHighlighted: false, onOpen: {})
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.03))
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 6)
            .padding(.top, 4)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 4) {
            Text("Pull Requests")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
            Spacer()
            if store.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 14, height: 14)
            }
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Refresh pull requests")
            .padding(.trailing, 8)
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}

private struct PRRow: View {
    let pr: GitHubPR  // swiftlint:disable:this identifier_name
    let showAuthor: Bool
    let isHighlighted: Bool
    let onOpen: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            onOpen()
            NSWorkspace.shared.open(pr.htmlURL)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text(pr.title)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 4) {
                        Text(pr.repoName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("#\(pr.number)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let branch = pr.baseBranch {
                            Text("→ \(branch)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if showAuthor {
                        Text("by \(pr.authorLogin)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if pr.approvedBy.isEmpty {
                        Text("waiting for review")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("✓ \(pr.approvedBy.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(.green.opacity(0.75))
                    }
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isHighlighted ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1.5)
        )
        .opacity(pr.approvedByMe ? 0.45 : 1.0)
        .help("\(pr.title) — \(pr.repoName) #\(pr.number)")
    }
}
