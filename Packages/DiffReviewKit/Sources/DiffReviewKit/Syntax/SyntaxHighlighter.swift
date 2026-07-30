import Foundation
import SwiftUI

/// Best-effort, per-line syntax highlighting for diff content. Each diff line is tokenized in
/// isolation (no cross-line state), so a multi-line `/* ... */` comment is only recognized on the
/// line(s) where it's fully self-contained — an accepted trade-off for keeping this simple and
/// dependency-free.
public enum SyntaxHighlighter {
    public static func highlight(_ text: String, language: SyntaxLanguage) -> AttributedString {
        guard !text.isEmpty, let regex = regex(for: language) else {
            return AttributedString(text)
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var result = AttributedString()
        var cursor = 0

        for match in regex.matches(in: text, range: fullRange) {
            guard let (range, color) = classify(match), range.location >= cursor else { continue }
            if range.location > cursor {
                result += AttributedString(
                    nsText.substring(with: NSRange(location: cursor, length: range.location - cursor)))
            }
            var styled = AttributedString(nsText.substring(with: range))
            styled.foregroundColor = color
            result += styled
            cursor = range.location + range.length
        }
        if cursor < nsText.length {
            result += AttributedString(
                nsText.substring(with: NSRange(location: cursor, length: nsText.length - cursor)))
        }
        return result
    }

    private static func classify(_ match: NSTextCheckingResult) -> (NSRange, Color)? {
        let groups: [(String, Color)] = [
            ("comment", DiffReviewTheme.syntaxComment),
            ("property", DiffReviewTheme.syntaxProperty),
            ("string", DiffReviewTheme.syntaxString),
            ("number", DiffReviewTheme.syntaxNumber),
            ("keyword", DiffReviewTheme.syntaxKeyword),
            ("variable", DiffReviewTheme.syntaxVariable),
        ]
        for (name, color) in groups {
            let range = match.range(withName: name)
            if range.location != NSNotFound {
                return (range, color)
            }
        }
        return nil
    }

    // MARK: - Compiled regex cache

    private static let cache = Cache()

    private static func regex(for language: SyntaxLanguage) -> NSRegularExpression? {
        cache.regex(for: language)
    }

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [SyntaxLanguage: NSRegularExpression?] = [:]

        func regex(for language: SyntaxLanguage) -> NSRegularExpression? {
            lock.lock()
            defer { lock.unlock() }
            if let cached = storage[language] {
                return cached
            }
            let compiled = SyntaxPatterns.compile(for: language)
            storage[language] = compiled
            return compiled
        }
    }
}

/// Per-language regex patterns, combined into one alternation with named capture groups so a
/// single left-to-right scan yields non-overlapping, priority-ordered matches.
private enum SyntaxPatterns {
    static func compile(for language: SyntaxLanguage) -> NSRegularExpression? {
        guard let pattern = pattern(for: language) else { return nil }
        return try? NSRegularExpression(pattern: pattern)
    }

    private static func pattern(for language: SyntaxLanguage) -> String? {
        switch language {
        case .swift: cLikePattern(keywords: swiftKeywords)
        case .kotlin: cLikePattern(keywords: kotlinKeywords)
        case .java: cLikePattern(keywords: javaKeywords)
        case .javascript: cLikePattern(keywords: javaScriptKeywords)
        case .typescript: cLikePattern(keywords: javaScriptKeywords + typeScriptKeywords)
        case .json: jsonPattern
        case .yaml: yamlPattern
        case .shell: shellPattern
        case .plainText: nil
        }
    }

    // MARK: - C-like languages (Swift, Kotlin, Java, JS, TS)

    private static func cLikePattern(keywords: [String]) -> String {
        let keywordAlternation = keywords.joined(separator: "|")
        return """
            (?<comment>//.*$|/\\*.*?\\*/)\
            |(?<string>"(?:[^"\\\\]|\\\\.)*"|'(?:[^'\\\\]|\\\\.)*')\
            |(?<number>\\b\\d+(?:\\.\\d+)?\\b)\
            |(?<keyword>\\b(?:\(keywordAlternation))\\b)
            """
    }

    private static let swiftKeywords = [
        "func", "let", "var", "if", "else", "guard", "return", "class", "struct", "enum",
        "protocol", "extension", "import", "private", "public", "internal", "fileprivate",
        "static", "final", "override", "init", "deinit", "self", "Self", "nil", "true", "false",
        "switch", "case", "default", "for", "while", "in", "do", "try", "catch", "throw", "throws",
        "rethrows", "async", "await", "where", "as", "is", "typealias", "associatedtype", "some",
        "any", "inout", "mutating", "lazy", "weak", "unowned", "defer", "break", "continue",
        "repeat", "subscript", "indirect", "convenience", "required", "open", "super",
    ]

    private static let kotlinKeywords = [
        "fun", "val", "var", "if", "else", "when", "is", "in", "as", "return", "class", "object",
        "interface", "package", "import", "private", "public", "internal", "protected",
        "override", "open", "final", "abstract", "companion", "init", "constructor", "this",
        "super", "null", "true", "false", "for", "while", "do", "try", "catch", "finally", "throw",
        "break", "continue", "sealed", "data", "enum", "annotation", "inline", "suspend",
        "lateinit", "by", "typealias", "vararg", "out", "reified", "crossinline", "noinline",
        "tailrec", "operator", "infix", "external", "actual", "expect", "const",
    ]

    private static let javaKeywords = [
        "public", "private", "protected", "class", "interface", "extends", "implements", "static",
        "final", "abstract", "void", "int", "long", "short", "byte", "char", "boolean", "float",
        "double", "new", "return", "if", "else", "switch", "case", "default", "for", "while", "do",
        "break", "continue", "try", "catch", "finally", "throw", "throws", "import", "package",
        "this", "super", "null", "true", "false", "instanceof", "synchronized", "volatile",
        "transient", "native", "strictfp", "enum", "assert", "record", "sealed", "permits",
        "yield",
    ]

    private static let javaScriptKeywords = [
        "function", "var", "let", "const", "if", "else", "for", "while", "do", "switch", "case",
        "default", "break", "continue", "return", "try", "catch", "finally", "throw", "new",
        "delete", "typeof", "instanceof", "in", "of", "this", "super", "class", "extends",
        "static", "get", "set", "import", "export", "from", "as", "async", "await", "yield",
        "null", "undefined", "true", "false", "void", "with", "debugger",
    ]

    private static let typeScriptKeywords = [
        "interface", "type", "enum", "implements", "private", "public", "protected", "readonly",
        "namespace", "declare", "abstract", "is", "keyof", "infer", "satisfies",
    ]

    // MARK: - JSON

    private static let jsonPattern = """
        (?<property>"(?:[^"\\\\]|\\\\.)*"(?=\\s*:))\
        |(?<string>"(?:[^"\\\\]|\\\\.)*")\
        |(?<number>-?\\b\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b)\
        |(?<keyword>\\b(?:true|false|null)\\b)
        """

    // MARK: - YAML

    private static let yamlPattern = """
        (?<comment>#.*$)\
        |(?<property>^\\s*[\\w.\\-]+(?=\\s*:))\
        |(?<string>"(?:[^"\\\\]|\\\\.)*"|'(?:[^'\\\\]|\\\\.)*')\
        |(?<number>\\b-?\\d+(?:\\.\\d+)?\\b)\
        |(?<keyword>\\b(?:true|false|null|yes|no|on|off)\\b)
        """

    // MARK: - Shell

    private static let shellPattern = """
        (?<comment>#.*$)\
        |(?<string>"(?:[^"\\\\]|\\\\.)*"|'(?:[^'\\\\]|\\\\.)*')\
        |(?<variable>\\$\\{?\\w+\\}?)\
        |(?<number>\\b\\d+(?:\\.\\d+)?\\b)\
        |(?<keyword>\\b(?:if|then|else|elif|fi|for|in|do|done|while|until|case|esac|function|\
        return|break|continue|local|export|readonly|shift|exit|trap|select)\\b)
        """
}
