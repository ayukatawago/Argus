import CoreGraphics
import Testing

@testable import ArgusSupport

@Suite("CanvasLayout")
struct CanvasLayoutTests {
    @Test("1 card uses 1 column")
    func oneCardOneColumn() {
        let layout = CanvasLayout(count: 1, available: CGSize(width: 1_000, height: 1_000))
        #expect(layout.columns == 1)
    }

    @Test("4 cards use 2 columns")
    func fourCardsTwoColumns() {
        let layout = CanvasLayout(count: 4, available: CGSize(width: 1_000, height: 1_000))
        #expect(layout.columns == 2)
    }

    @Test("5 cards use 3 columns")
    func fiveCardsThreeColumns() {
        let layout = CanvasLayout(count: 5, available: CGSize(width: 1_000, height: 1_000))
        #expect(layout.columns == 3)
    }

    @Test("a count of zero is clamped to a single column, not division by zero")
    func zeroCountClampsToOneColumn() {
        let layout = CanvasLayout(count: 0, available: CGSize(width: 1_000, height: 1_000))
        #expect(layout.columns == 1)
    }

    @Test("card width and terminal height have a floor even in a tiny window")
    func floorsOnTinyWindow() {
        let layout = CanvasLayout(count: 9, available: CGSize(width: 10, height: 10))
        #expect(layout.cardWidth >= 100)
        #expect(layout.terminalHeight >= 40)
    }

    @Test("fontSize is clamped to 7...13")
    func fontSizeClamped() {
        let tiny = CanvasLayout(count: 9, available: CGSize(width: 10, height: 10))
        #expect(tiny.fontSize == 7)

        let huge = CanvasLayout(count: 1, available: CGSize(width: 4_000, height: 4_000))
        #expect(huge.fontSize == 13)
    }
}
