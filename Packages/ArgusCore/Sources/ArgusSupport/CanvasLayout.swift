import CoreGraphics
import Foundation

/// Grid layout math for the worktree "canvas" overview (every open worktree tiled into one
/// window). Moved out of App/Views/CanvasView.swift as-is so it can be tested without SwiftUI.
public struct CanvasLayout: Sendable {
    public let columns: Int
    public let cardWidth: CGFloat
    public let terminalHeight: CGFloat

    /// `padding`/`spacing`/`titleBarHeight` default to CanvasView.swift's own layout constants —
    /// keep the two in sync if either changes.
    public init(
        count: Int,
        available: CGSize,
        padding: CGFloat = 12,
        spacing: CGFloat = 8,
        titleBarHeight: CGFloat = 26
    ) {
        let cols = max(1, Int(ceil(sqrt(Double(max(1, count))))))
        columns = cols

        let totalHPad = padding * 2 + spacing * CGFloat(cols - 1)
        cardWidth = max(100, (available.width - totalHPad) / CGFloat(cols))

        let rows = max(1, Int(ceil(Double(count) / Double(cols))))
        let totalVPad = padding * 2 + spacing * CGFloat(rows - 1)
        let cardHeight = max(60, (available.height - totalVPad) / CGFloat(rows))
        terminalHeight = max(40, cardHeight - titleBarHeight)
    }

    /// Font size (pt) scaled so roughly 20 lines fit in the terminal area.
    public var fontSize: Int { max(7, min(13, Int(terminalHeight / 25.0))) }
}
