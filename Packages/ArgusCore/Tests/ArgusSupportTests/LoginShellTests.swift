import Foundation
import Testing

@testable import ArgusSupport

@Suite("LoginShell")
struct LoginShellTests {
    @Test("parses a normal dscl UserShell line")
    func parsesNormalOutput() {
        let shell = LoginShell.parse(dsclOutput: "UserShell: /bin/zsh\n", fallback: "/bin/bash")
        #expect(shell == "/bin/zsh")
    }

    @Test("parses a fish path")
    func parsesFishPath() {
        let shell = LoginShell.parse(dsclOutput: "UserShell: /opt/homebrew/bin/fish\n", fallback: "/bin/bash")
        #expect(shell == "/opt/homebrew/bin/fish")
    }

    @Test("falls back on empty output")
    func fallsBackOnEmptyOutput() {
        let shell = LoginShell.parse(dsclOutput: "", fallback: "/bin/bash")
        #expect(shell == "/bin/bash")
    }

    @Test("output without a colon-space separator is used verbatim, not treated as unparseable")
    func noSeparatorUsesWholeString() {
        // components(separatedBy: ": ") returns the whole string as a single element when there's
        // no match, and .last of that is non-empty — so this doesn't fall back. Not reachable from
        // real dscl output, but pinning it documents the actual (rather than assumed) behavior.
        let shell = LoginShell.parse(dsclOutput: "not what we expected", fallback: "/bin/bash")
        #expect(shell == "not what we expected")
    }

    @Test("trims surrounding whitespace and the trailing newline")
    func trimsWhitespace() {
        let shell = LoginShell.parse(dsclOutput: "UserShell: /bin/zsh \n", fallback: "/bin/bash")
        #expect(shell == "/bin/zsh")
    }

    @Test("fallbackShell reflects the process's $SHELL, defaulting to /bin/zsh")
    func fallbackShellMatchesEnvironment() {
        let expected = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        #expect(LoginShell.fallbackShell() == expected)
    }

    @Test("current resolves to a plausible absolute shell path on this machine")
    func currentResolvesToAbsolutePath() {
        #expect(LoginShell.current.hasPrefix("/"))
    }
}
