import Foundation

/// How much of a collapsed gap the reviewer has revealed, counted from each end: `revealedFromTop`
/// lines just below the previous hunk, and `revealedFromBottom` lines just above the next one.
public struct GapExpansion: Hashable, Sendable {
    public enum Direction: Sendable, Hashable {
        /// Reveal the next lines just below the previous hunk.
        case down
        /// Reveal the next lines just above the next hunk.
        case up  // swiftlint:disable:this identifier_name
        /// Reveal the whole gap at once.
        case all
    }

    /// Lines per step, matching GitHub's expander.
    public static let defaultStep = 20

    public var revealedFromTop: Int
    public var revealedFromBottom: Int

    public init(revealedFromTop: Int = 0, revealedFromBottom: Int = 0) {
        self.revealedFromTop = revealedFromTop
        self.revealedFromBottom = revealedFromBottom
    }

    /// Lines still hidden, or `nil` while the gap's length is unknown.
    public func remaining(lineCount: Int?) -> Int? {
        guard let lineCount else { return nil }
        return max(0, lineCount - revealedFromTop - revealedFromBottom)
    }

    /// `false` while the length is unknown: an unfetched bottom gap can't be shown to be complete.
    public func isFullyExpanded(lineCount: Int?) -> Bool {
        remaining(lineCount: lineCount) == 0
    }

    /// Reveals up to `step` more lines in `direction`, never past the end of the gap, so the two
    /// revealed counts together never exceed `lineCount`. Returns `self` unchanged while the length
    /// is unknown, since nothing can be revealed before the file has been read.
    public func expanding(
        _ direction: Direction,
        step: Int = GapExpansion.defaultStep,
        lineCount: Int?
    ) -> GapExpansion {
        guard let hidden = remaining(lineCount: lineCount) else { return self }
        var result = self
        switch direction {
        case .down:
            result.revealedFromTop += min(max(step, 0), hidden)

        case .up:
            result.revealedFromBottom += min(max(step, 0), hidden)

        case .all:
            result.revealedFromTop += hidden
        }
        return result
    }
}
