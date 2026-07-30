import SwiftUI

/// Renders a single review comment plus any agent replies, with Reply/Apply actions.
struct CommentThreadView: View {
    let model: DiffReviewModel
    let comment: ReviewComment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "bubble.left.fill")
                    .foregroundStyle(DiffReviewTheme.commentAccent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(comment.body)
                        .font(.callout)
                    ForEach(comment.replies) { reply in
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
                Spacer()
            }

            HStack {
                Spacer()
                Button("Reply") { model.send(commentID: comment.id, mode: .reply) }
                    .disabled(isBusy)
                Button("Apply") { model.send(commentID: comment.id, mode: .apply) }
                    .disabled(isBusy)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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
