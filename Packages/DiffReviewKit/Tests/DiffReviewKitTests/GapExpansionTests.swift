import Testing

@testable import DiffReviewKit

@Suite("GapExpansion")
struct GapExpansionTests {
    @Test("stepping down reveals 20 lines from the top, then the rest")
    func stepDown() {
        var expansion = GapExpansion()
        expansion = expansion.expanding(.down, lineCount: 50)
        #expect(expansion.revealedFromTop == 20)
        #expect(expansion.remaining(lineCount: 50) == 30)
        expansion = expansion.expanding(.down, lineCount: 50)
        #expect(expansion.revealedFromTop == 40)
        #expect(expansion.remaining(lineCount: 50) == 10)
    }

    @Test("stepping up reveals 20 lines from the bottom, counted separately from the top")
    func stepUp() {
        let expansion = GapExpansion().expanding(.up, lineCount: 50)
        #expect(expansion.revealedFromBottom == 20)
        #expect(expansion.revealedFromTop == 0)
        #expect(expansion.remaining(lineCount: 50) == 30)
    }

    @Test("a step never reveals more than remains")
    func clampsToRemaining() {
        let expansion = GapExpansion().expanding(.down, lineCount: 7)
        #expect(expansion.revealedFromTop == 7)
        #expect(expansion.isFullyExpanded(lineCount: 7))
    }

    @Test("all reveals the whole gap in one go, from either end")
    func expandAll() {
        let fromNothing = GapExpansion().expanding(.all, lineCount: 45)
        #expect(fromNothing.isFullyExpanded(lineCount: 45))
        #expect(fromNothing.revealedFromBottom == 0)

        let partlyUp = GapExpansion(revealedFromTop: 0, revealedFromBottom: 20).expanding(.all, lineCount: 45)
        #expect(partlyUp.isFullyExpanded(lineCount: 45))
        #expect(partlyUp.revealedFromTop + partlyUp.revealedFromBottom == 45)
    }

    @Test("down and up meeting in the middle never overshoot the gap")
    func downAndUpMeet() {
        var expansion = GapExpansion()
        for _ in 0..<3 {
            expansion = expansion.expanding(.down, lineCount: 30)
            expansion = expansion.expanding(.up, lineCount: 30)
        }
        #expect(expansion.revealedFromTop + expansion.revealedFromBottom == 30)
        #expect(expansion.remaining(lineCount: 30) == 0)
        #expect(expansion.isFullyExpanded(lineCount: 30))
    }

    @Test("an expansion of an already full gap is a no-op")
    func fullGapIsStable() {
        let full = GapExpansion(revealedFromTop: 10, revealedFromBottom: 5)
        #expect(full.expanding(.down, lineCount: 15) == full)
        #expect(full.expanding(.up, lineCount: 15) == full)
        #expect(full.expanding(.all, lineCount: 15) == full)
    }

    @Test("an unknown length is never fully expanded, and nothing can be revealed yet")
    func unknownLength() {
        let expansion = GapExpansion()
        #expect(expansion.remaining(lineCount: nil) == nil)
        #expect(!expansion.isFullyExpanded(lineCount: nil))
        #expect(expansion.expanding(.down, lineCount: nil) == expansion)
        #expect(expansion.expanding(.all, lineCount: nil) == expansion)
    }

    @Test("a bottom gap whose length is resolved later becomes expandable and then complete")
    func bottomGapResolvedLater() {
        let unresolved = GapExpansion()
        #expect(!unresolved.isFullyExpanded(lineCount: nil))

        // The file turns out to have 12 lines past the last hunk: one step is enough.
        let resolved = unresolved.expanding(.down, lineCount: 12)
        #expect(resolved.revealedFromTop == 12)
        #expect(resolved.isFullyExpanded(lineCount: 12))
    }

    @Test("a gap with no lines left after its last hunk is complete immediately")
    func emptyGap() {
        #expect(GapExpansion().isFullyExpanded(lineCount: 0))
    }
}
