import AppKit
import SwiftUI

struct PRMonitorView: View {
    @ObservedObject var store: PRMonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if store.isLoading && !store.hasAnyPRs {
                Text("Loading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            } else if let error = store.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                    .lineLimit(3)
            } else {
                prSection(title: "My Open PRs", prs: store.myOpenPRs)
                prSection(title: "My Drafts", prs: store.myDraftPRs)
                prSection(title: "Review Requested", prs: store.reviewRequestedPRs)
                if !store.hasAnyPRs {
                    Text("No open pull requests")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func prSection(title: String, prs: [GitHubPR]) -> some View {
        if !prs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                ForEach(prs) { pullRequest in
                    PRRow(pr: pullRequest)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                }
            }
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
    @State private var isHovered = false

    var body: some View {
        Button {
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
        .help("\(pr.title) — \(pr.repoName) #\(pr.number)")
    }
}
