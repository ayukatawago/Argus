import AppKit
import SwiftUI

/// Shared color tokens for `DiffReviewKit`'s built-in views, modeled on GitHub's diff palette. Each
/// token resolves per appearance (light or dark). Public so host apps that want a different palette can
/// reference or override these constants from their own theming layer.
public enum DiffReviewTheme {
    // MARK: - Diff lines

    /// Whole-line tint of an added or removed line. A modified line keeps it, with the darker
    /// `…EmphasisBackground` layered over only the changed spans.
    public static let additionBackground = dynamic(light: hex(0xe6ffec), dark: rgba(46, 160, 67, 0.15))
    public static let deletionBackground = dynamic(light: hex(0xffebe9), dark: rgba(248, 81, 73, 0.10))

    /// Opaque gutter tint of an added or removed line. Dark variants are composited onto the dark canvas,
    /// so a gutter never lets scrolled content show through.
    public static let additionGutterBackground = dynamic(
        light: hex(0xccffd8), dark: opaque(rgba(46, 160, 67, 0.30), over: darkCanvas))
    public static let deletionGutterBackground = dynamic(
        light: hex(0xffd7d5), dark: opaque(rgba(248, 81, 73, 0.30), over: darkCanvas))
    /// Opaque gutter of a context line, and of the empty side of an added or removed line.
    public static let contextGutterBackground = dynamic(light: hex(0xf6f8fa), dark: darkCanvas)

    /// Stronger tint for the specific span that changed within a modified line. The rest of that line
    /// keeps only its whole-line tint (see `DiffLineRowView`'s intraline diff).
    public static let additionEmphasisBackground = dynamic(light: hex(0xabf2bc), dark: rgba(46, 160, 67, 0.40))
    public static let deletionEmphasisBackground = dynamic(
        light: rgba(255, 129, 130, 0.40), dark: rgba(248, 81, 73, 0.40))

    public static let additionForeground = dynamic(light: hex(0x1a7f37), dark: hex(0x3fb950))
    public static let deletionForeground = dynamic(light: hex(0xd1242f), dark: hex(0xf85149))
    public static let contextForeground = dynamic(light: hex(0x1f2328), dark: hex(0xe6edf3))
    public static let lineNumberForeground = dynamic(light: hex(0x59636e), dark: hex(0x9198a1))
    public static let commentAccent = dynamic(light: hex(0x0969da), dark: hex(0x4493f5))

    /// The blue "+" square shown on hover to start a comment on a line.
    public static let addCommentBackground = dynamic(light: hex(0x0969da), dark: hex(0x1f6feb))
    public static let addCommentForeground = Color.white

    /// Tint for lines currently selected via shift-click, before a range comment is submitted.
    public static let selectionBackground = Color.accentColor.opacity(0.18)
    /// Subtler tint marking the full range an existing multi-line comment is anchored to.
    public static let commentRangeBackground = Color.accentColor.opacity(0.07)
    /// Selected row in a sidebar list (file tree, commit list).
    public static let listSelectionBackground = Color.accentColor.opacity(0.18)
    /// Background of text the user selected by dragging across code.
    public static let textSelectionBackground = Color(nsColor: .selectedTextBackgroundColor)

    /// ⌘F matches: every match, and the current one, which gets a border.
    public static let searchMatchBackground = dynamic(
        light: rgba(255, 212, 0, 0.55), dark: rgba(187, 128, 9, 0.45))
    public static let searchCurrentMatchBorder = dynamic(light: hex(0xd4a72c), dark: hex(0xbb8009))

    // MARK: - Hunk and expander rows

    /// Background of a hunk's `@@` row and of a collapsed gap's expander row.
    public static let hunkBackground = dynamic(light: hex(0xddf4ff), dark: rgba(56, 139, 253, 0.10))
    public static let hunkForeground = dynamic(light: hex(0x59636e), dark: hex(0x9198a1))
    /// Opaque gutter of an expander row, where its ↑ ↓ ↕ buttons sit.
    public static let expanderGutterBackground = dynamic(
        light: hex(0xb6e3ff), dark: opaque(rgba(56, 139, 253, 0.25), over: darkCanvas))

    /// Kept for existing callers; the expander row now uses `hunkBackground`.
    public static let gapBackground = hunkBackground

    // MARK: - Borders and file headers

    public static let border = dynamic(light: hex(0xd1d9e0), dark: hex(0x3d444d))

    /// Background and bottom border of a file's header. The background is opaque, so a pinned header
    /// never lets scrolled rows show through.
    public static let fileHeaderBackground = dynamic(light: hex(0xf6f8fa), dark: hex(0x151b23))
    public static let fileHeaderBorder = border

    // MARK: - Comment cards

    /// The card body and composer background. Opaque, as above.
    public static let cardBackground = dynamic(light: hex(0xffffff), dark: darkCanvas)
    /// The card's header bar.
    public static let cardHeaderBackground = dynamic(light: hex(0xf6f8fa), dark: hex(0x151b23))
    public static let cardBorder = border

    public static let statusOpen = dynamic(light: hex(0x1a7f37), dark: hex(0x3fb950))
    public static let statusInProgress = dynamic(light: hex(0x9a6700), dark: hex(0xd29922))
    public static let statusResolved = dynamic(light: hex(0x8250df), dark: hex(0xa371f7))

    // MARK: - Syntax highlighting

    public static let syntaxKeyword = dynamic(light: hex(0xcf222e), dark: hex(0xff7b72))
    public static let syntaxString = dynamic(light: hex(0x0a3069), dark: hex(0xa5d6ff))
    public static let syntaxComment = dynamic(light: hex(0x59636e), dark: hex(0x9198a1))
    public static let syntaxNumber = dynamic(light: hex(0x0550ae), dark: hex(0x79c0ff))
    public static let syntaxProperty = dynamic(light: hex(0x0550ae), dark: hex(0x79c0ff))
    public static let syntaxVariable = dynamic(light: hex(0x953800), dark: hex(0xffa657))

    // MARK: - Helpers

    private static let darkCanvas = hex(0x0d1117)

    /// A color that resolves to `light` or `dark` according to the appearance it is drawn in.
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            })
    }

    private static func hex(_ value: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }

    private static func rgba(_ red: Int, _ green: Int, _ blue: Int, _ alpha: CGFloat) -> NSColor {
        NSColor(
            srgbRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: alpha
        )
    }

    /// `top` blended over `base`, as an opaque color.
    private static func opaque(_ top: NSColor, over base: NSColor) -> NSColor {
        let alpha = top.alphaComponent
        func mix(_ foreground: CGFloat, _ background: CGFloat) -> CGFloat {
            foreground * alpha + background * (1 - alpha)
        }
        return NSColor(
            srgbRed: mix(top.redComponent, base.redComponent),
            green: mix(top.greenComponent, base.greenComponent),
            blue: mix(top.blueComponent, base.blueComponent),
            alpha: 1
        )
    }
}
