import Foundation
import Testing

@testable import ArgusSupport

@Suite("TerminalURLDetector")
struct TerminalURLDetectorTests {
    @Test("finds every URL with its row and display columns")
    func findsURLs() {
        let pane = "see https://a.example/x and\nhttp://b.example"
        let found = TerminalURLDetector.candidates(in: pane)
        #expect(found.map(\.url.absoluteString) == ["https://a.example/x", "http://b.example"])
        #expect(found[0].row == 0 && found[0].startColumn == 4 && found[0].endColumn == 23)
        #expect(found[1].row == 1 && found[1].startColumn == 0)
    }

    @Test(
        "trailing sentence punctuation is trimmed",
        arguments: [
            ("https://a.example/x.", "https://a.example/x"),
            ("https://a.example/x,", "https://a.example/x"),
            ("https://a.example/x)", "https://a.example/x"),
            ("https://a.example/x\".", "https://a.example/x"),
            ("https://a.example/?q=1!", "https://a.example/?q=1"),
        ])
    func trimsPunctuation(raw: String, expected: String) {
        #expect(TerminalURLDetector.trimmed(raw) == expected)
    }

    @Test("a closing parenthesis that balances one in the URL is kept")
    func keepsBalancedParen() {
        #expect(
            TerminalURLDetector.trimmed("https://en.wikipedia.org/wiki/Foo_(bar)")
                == "https://en.wikipedia.org/wiki/Foo_(bar)")
        let wrapped = TerminalURLDetector.candidates(in: "(see https://example.com/x)")
        #expect(wrapped.first?.url.absoluteString == "https://example.com/x")
    }

    @Test("wide characters before a URL shift its column by two cells each")
    func wideCharactersShiftColumns() {
        let found = TerminalURLDetector.candidates(in: "日本 https://a.example")
        #expect(found.first?.startColumn == 5)  // 2 + 2 + 1 space
    }

    @Test("display width: ASCII 1, CJK 2, combining mark 0")
    func widths() {
        #expect(TerminalURLDetector.displayWidth(of: "abc") == 3)
        #expect(TerminalURLDetector.displayWidth(of: "日本") == 4)
        #expect(TerminalURLDetector.displayWidth(of: "e\u{0301}") == 1)
    }

    @Test("a click inside a URL's own span wins over a nearer-start neighbour")
    func clickInsideSpanWins() {
        let found = TerminalURLDetector.candidates(in: "https://a.example/longer-path https://b.example")
        // Column 20 is inside the first URL (which spans 0..<29), even though b starts at 30.
        #expect(
            TerminalURLDetector.best(found, clickRow: 0, clickColumn: 20)?.absoluteString
                == "https://a.example/longer-path")
        #expect(TerminalURLDetector.best(found, clickRow: 0, clickColumn: 35)?.absoluteString == "https://b.example")
    }

    @Test("rows outweigh columns when the click is on no URL")
    func nearestRow() {
        let found = TerminalURLDetector.candidates(in: "https://top.example\n\n\nhttps://bottom.example")
        #expect(
            TerminalURLDetector.best(found, clickRow: 2, clickColumn: 0)?.absoluteString == "https://bottom.example")
        #expect(TerminalURLDetector.best(found, clickRow: 1, clickColumn: 0)?.absoluteString == "https://top.example")
    }

    @Test("no known click row falls back to the first URL; no URLs gives nil")
    func fallbacks() {
        let found = TerminalURLDetector.candidates(in: "https://one.example https://two.example")
        #expect(TerminalURLDetector.best(found, clickRow: nil, clickColumn: 0)?.absoluteString == "https://one.example")
        #expect(TerminalURLDetector.best([], clickRow: 0, clickColumn: 0) == nil)
    }
}
