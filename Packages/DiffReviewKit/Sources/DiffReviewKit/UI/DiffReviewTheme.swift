import SwiftUI

/// Shared color tokens for `DiffReviewKit`'s built-in views. Public so host apps that want a
/// different palette can reference/override these constants from their own theming layer.
public enum DiffReviewTheme {
    public static let additionBackground = Color.green.opacity(0.12)
    public static let additionForeground = Color.green
    public static let deletionBackground = Color.red.opacity(0.12)
    public static let deletionForeground = Color.red
    public static let contextForeground = Color.primary.opacity(0.85)
    public static let lineNumberForeground = Color.secondary.opacity(0.6)
    public static let commentAccent = Color.accentColor
}
