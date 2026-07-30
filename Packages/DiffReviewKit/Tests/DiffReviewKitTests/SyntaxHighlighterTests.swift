import Foundation
import SwiftUI
import Testing

@testable import DiffReviewKit

@Suite("SyntaxLanguage")
struct SyntaxLanguageTests {
    @Test(
        "detects language from common file extensions",
        arguments: [
            ("Foo.swift", SyntaxLanguage.swift),
            ("Foo.kt", .kotlin),
            ("Foo.kts", .kotlin),
            ("Foo.java", .java),
            ("data.json", .json),
            ("config.yaml", .yaml),
            ("config.yml", .yaml),
            ("app.js", .javascript),
            ("app.jsx", .javascript),
            ("app.ts", .typescript),
            ("app.tsx", .typescript),
            ("build.sh", .shell),
            ("build.bash", .shell),
            ("README.md", .plainText),
        ]
    )
    func detection(path: String, expected: SyntaxLanguage) {
        #expect(SyntaxLanguage.detect(fromPath: path) == expected)
    }
}

@Suite("SyntaxHighlighter")
struct SyntaxHighlighterTests {
    /// Extracts the plain-text runs of an AttributedString that carry a non-nil foregroundColor,
    /// as a set — enough to assert "this substring got highlighted" without depending on the
    /// specific Color values (which aren't Equatable in a way that's convenient to assert on).
    private func highlightedSubstrings(_ text: String, language: SyntaxLanguage) -> Set<String> {
        let attributed = SyntaxHighlighter.highlight(text, language: language)
        var result: Set<String> = []
        for run in attributed.runs where run.foregroundColor != nil {
            result.insert(String(attributed[run.range].characters))
        }
        return result
    }

    @Test("plain text is returned unstyled")
    func plainTextUnstyled() {
        let attributed = SyntaxHighlighter.highlight("just some text", language: .plainText)
        #expect(attributed.runs.allSatisfy { $0.foregroundColor == nil })
    }

    @Test("swift keyword and string are highlighted")
    func swiftKeywordAndString() {
        let highlighted = highlightedSubstrings(#"let name = "Argus""#, language: .swift)
        #expect(highlighted.contains("let"))
        #expect(highlighted.contains("\"Argus\""))
    }

    @Test("kotlin fun keyword is highlighted")
    func kotlinKeyword() {
        #expect(highlightedSubstrings("fun main() {}", language: .kotlin).contains("fun"))
    }

    @Test("java line comment is highlighted")
    func javaComment() {
        #expect(highlightedSubstrings("// a comment", language: .java).contains("// a comment"))
    }

    @Test("json object key is highlighted as a property, distinct from a plain string value")
    func jsonPropertyVsString() throws {
        let attributed = SyntaxHighlighter.highlight(#""name": "Argus""#, language: .json)
        var colors: [String: Color?] = [:]
        for run in attributed.runs {
            colors[String(attributed[run.range].characters)] = run.foregroundColor
        }
        let propertyColor = try #require(colors["\"name\""] ?? nil)
        let stringColor = try #require(colors["\"Argus\""] ?? nil)
        #expect(propertyColor != stringColor)
    }

    @Test("yaml comment is highlighted")
    func yamlComment() {
        #expect(highlightedSubstrings("key: value # trailing comment", language: .yaml).contains("# trailing comment"))
    }

    @Test("shell variable and keyword are highlighted")
    func shellVariableAndKeyword() {
        let highlighted = highlightedSubstrings("if [ -z $FOO ]; then exit 1; fi", language: .shell)
        #expect(highlighted.contains("if"))
        #expect(highlighted.contains("$FOO"))
        #expect(highlighted.contains("fi"))
    }

    @Test("a shell variable inside a double-quoted string is part of the string token")
    func shellVariableInsideString() {
        let highlighted = highlightedSubstrings("echo \"$FOO\"", language: .shell)
        #expect(highlighted.contains("\"$FOO\""))
    }
}
