import SwiftUI

/// Shared color tokens for `DiffReviewKit`'s built-in views. Public so host apps that want a
/// different palette can reference/override these constants from their own theming layer.
public enum DiffReviewTheme {
    public static let additionBackground = Color.green.opacity(0.12)
    public static let additionForeground = Color.green
    public static let deletionBackground = Color.red.opacity(0.12)
    public static let deletionForeground = Color.red

    /// Stronger tint for the specific span that changed within a modified line — the rest of that
    /// line is left unhighlighted (see `SideBySideDiffView`'s intraline diff).
    public static let additionEmphasisBackground = Color.green.opacity(0.4)
    public static let deletionEmphasisBackground = Color.red.opacity(0.4)
    public static let contextForeground = Color.primary.opacity(0.85)
    public static let lineNumberForeground = Color.secondary.opacity(0.6)
    public static let commentAccent = Color.accentColor

    /// Tint for lines currently selected via shift-click, before a range comment is submitted.
    public static let selectionBackground = Color.accentColor.opacity(0.18)
    /// Subtler tint marking the full range an existing multi-line comment is anchored to.
    public static let commentRangeBackground = Color.accentColor.opacity(0.07)

    // MARK: - Syntax highlighting

    public static let syntaxKeyword = Color(red: 0.72, green: 0.32, blue: 0.62)
    public static let syntaxString = Color(red: 0.77, green: 0.24, blue: 0.17)
    public static let syntaxComment = Color(red: 0.45, green: 0.5, blue: 0.45)
    public static let syntaxNumber = Color(red: 0.22, green: 0.44, blue: 0.75)
    public static let syntaxProperty = Color(red: 0.32, green: 0.52, blue: 0.72)
    public static let syntaxVariable = Color(red: 0.32, green: 0.52, blue: 0.72)
}
