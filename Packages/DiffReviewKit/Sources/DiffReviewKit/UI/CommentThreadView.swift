import SwiftUI

/// Renders a single review comment plus any agent replies, with Reply/Apply actions. Each reply sits in
/// its own section below a divider.
struct CommentThreadView: View {
    let model: DiffReviewModel
    let comment: ReviewComment

    var body: some View {
        CommentCard(
            lineRange: comment.startLineNumber.map { "Lines \($0)\u{2013}\(comment.lineNumber)" },
            status: comment.status
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(comment.body)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(comment.replies) { reply in
                    Divider()
                    replyView(reply)
                }
                if isBusy {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text(comment.status == .applying ? "Applying…" : "Replying…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } footer: {
            HStack {
                Spacer()
                Button("Reply") { model.send(commentID: comment.id, mode: .reply) }
                    .disabled(isBusy)
                Button("Apply") { model.send(commentID: comment.id, mode: .apply) }
                    .disabled(isBusy)
            }
        }
    }

    private var isBusy: Bool {
        comment.status == .replying || comment.status == .applying
    }

    @ViewBuilder
    private func replyView(_ reply: ReviewReply) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon(for: reply.kind))
                .foregroundStyle(color(for: reply.kind))
            Text(reply.text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func icon(for kind: ReviewReply.Kind) -> String {
        switch kind {
        case .reply: "text.bubble"
        case .apply: "wand.and.stars"
        case .error: "exclamationmark.triangle"
        }
    }

    private func color(for kind: ReviewReply.Kind) -> Color {
        switch kind {
        case .reply: .secondary
        case .apply: DiffReviewTheme.additionForeground
        case .error: DiffReviewTheme.deletionForeground
        }
    }
}

/// The bordered, rounded card shared by a review thread and the composer: a header bar ("You", the line
/// range, and an optional status badge), a body, and a footer for actions.
struct CommentCard<Content: View, Footer: View>: View {
    let lineRange: String?
    let status: ReviewComment.Status?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("You")
                    .font(.caption.weight(.semibold))
                if let lineRange {
                    Text(lineRange)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let status {
                    CommentStatusBadge(status: status)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DiffReviewTheme.cardHeaderBackground)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DiffReviewTheme.cardBorder).frame(height: 1)
            }

            content()
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(DiffReviewTheme.cardBorder).frame(height: 1)
            footer()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .background(DiffReviewTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(DiffReviewTheme.cardBorder))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

/// The Open / Replying / Applying / Resolved pill in a comment card's header.
private struct CommentStatusBadge: View {
    let status: ReviewComment.Status

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var label: String {
        switch status {
        case .open: "Open"
        case .replying: "Replying"
        case .applying: "Applying"
        case .resolved: "Resolved"
        }
    }

    private var color: Color {
        switch status {
        case .open: DiffReviewTheme.statusOpen
        case .replying, .applying: DiffReviewTheme.statusInProgress
        case .resolved: DiffReviewTheme.statusResolved
        }
    }
}
