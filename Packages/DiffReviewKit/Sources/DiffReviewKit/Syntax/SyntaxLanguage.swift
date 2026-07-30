import Foundation

/// Languages `SyntaxHighlighter` knows how to tokenize. `.plainText` disables highlighting.
public enum SyntaxLanguage: Sendable, Hashable {
    case swift
    case kotlin
    case java
    case json
    case yaml
    case javascript
    case typescript
    case shell
    case plainText

    /// Detects a language from a file path's extension.
    public static func detect(fromPath path: String) -> SyntaxLanguage {
        switch (path as NSString).pathExtension.lowercased() {
        case "swift": .swift
        case "kt", "kts": .kotlin
        case "java": .java
        case "json": .json
        case "yaml", "yml": .yaml
        case "js", "jsx", "mjs", "cjs": .javascript
        case "ts", "tsx": .typescript
        case "sh", "bash", "zsh": .shell
        default: .plainText
        }
    }
}
