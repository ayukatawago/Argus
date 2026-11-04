import SwiftUI

extension SideBySideDiffView {
    func background(for kind: DiffLine.Kind?) -> Color {
        switch kind {
        case .addition: DiffReviewTheme.additionBackground
        case .deletion: DiffReviewTheme.deletionBackground
        default: .clear
        }
    }

    func emphasisBackground(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .addition: DiffReviewTheme.additionEmphasisBackground
        case .deletion: DiffReviewTheme.deletionEmphasisBackground
        case .context: .clear
        }
    }

    func commentButtonTitle(for range: ClosedRange<Int>) -> String {
        range.lowerBound == range.upperBound
            ? "Comment on line \(range.lowerBound)"
            : "Comment on lines \(range.lowerBound)\u{2013}\(range.upperBound)"
    }

    func isWithinExistingCommentRange(line number: Int, side: ReviewComment.Side) -> Bool {
        model.comments(for: file.path).contains { comment in
            guard comment.side == side else { return false }
            let range = (comment.startLineNumber ?? comment.lineNumber)...comment.lineNumber
            return range.contains(number)
        }
    }
}
