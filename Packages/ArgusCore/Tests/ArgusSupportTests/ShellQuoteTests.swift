import Foundation
import Testing

@testable import ArgusSupport

@Suite("ShellQuote")
struct ShellQuoteTests {
    @Test(
        "safe words are left bare",
        arguments: ["tmux", "/opt/homebrew/bin/tmux", "-l", "a_b-c.d:e,f=g@h+i%j", "argus-c-1a2b"])
    func safeWordsUnquoted(_ word: String) {
        #expect(ShellQuote.quote(word) == word)
    }

    @Test("an empty string becomes an empty quoted word")
    func empty() {
        #expect(ShellQuote.quote("") == "''")
    }

    @Test("words with spaces or metacharacters are single-quoted")
    func quoted() {
        #expect(ShellQuote.quote("a b") == "'a b'")
        #expect(ShellQuote.quote("$HOME;rm -rf ~") == "'$HOME;rm -rf ~'")
        #expect(ShellQuote.quote(#"say "hi""#) == #"'say "hi"'"#)
    }

    @Test("an embedded single quote is closed, escaped and reopened")
    func embeddedSingleQuote() {
        #expect(ShellQuote.quote("it's") == #"'it'\''s'"#)
    }

    @Test(
        "a real /bin/sh round-trips every awkward value back to the exact original",
        arguments: [
            "plain", "with space", "it's", "a'b'c", "$HOME `date` $(id)", "semi;colon && pipe | x", "tab\there",
            "new\nline", "back\\slash", "*glob?", "日本語 'quoted'", "''",
        ])
    func shellRoundTrip(_ value: String) async {
        let result = await ProcessRunner.run("/bin/sh", ["-c", "printf %s \(ShellQuote.quote(value))"])
        #expect(result.succeeded)
        #expect(result.standardOutput == value)
    }

    @Test("join quotes each word and separates with single spaces")
    func join() {
        #expect(ShellQuote.join(["sh", "-c", "echo 'x y'"]) == #"sh -c 'echo '\''x y'\'''"#)
    }
}
