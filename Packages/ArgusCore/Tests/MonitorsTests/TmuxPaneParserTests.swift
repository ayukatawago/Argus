import Testing

@testable import Monitors

@Suite("TmuxPaneParser")
struct TmuxPaneParserTests {
    @Test("a session running a non-shell command is busy")
    func nonShellCommandIsBusy() {
        let output = "argus-s-repo-abc123|npm\n"
        let busy = TmuxPaneParser.busySessions(from: output, activeSessions: ["argus-s-repo-abc123"])
        #expect(busy == ["argus-s-repo-abc123"])
    }

    @Test(
        "a session sitting at a shell prompt is not busy",
        arguments: ["bash", "zsh", "fish", "sh", "dash", "ksh", "tcsh", "csh"]
    )
    func shellPromptIsNotBusy(shellName: String) {
        let output = "argus-s-repo-abc123|\(shellName)\n"
        let busy = TmuxPaneParser.busySessions(from: output, activeSessions: ["argus-s-repo-abc123"])
        #expect(busy.isEmpty)
    }

    @Test("a session absent from the tmux output entirely is not busy")
    func sessionNotInOutputIsNotBusy() {
        let output = "some-other-session|npm\n"
        let busy = TmuxPaneParser.busySessions(from: output, activeSessions: ["argus-s-repo-abc123"])
        #expect(busy.isEmpty)
    }

    @Test("only active sessions are considered, even if other busy sessions appear in the output")
    func onlyActiveSessionsConsidered() {
        let output = "argus-s-repo-a|npm\nargus-s-repo-b|npm\n"
        let busy = TmuxPaneParser.busySessions(from: output, activeSessions: ["argus-s-repo-a"])
        #expect(busy == ["argus-s-repo-a"])
    }

    @Test("multiple busy sessions are all returned")
    func multipleBusySessions() {
        let output = "argus-s-repo-a|npm\nargus-s-repo-b|make\n"
        let busy = TmuxPaneParser.busySessions(
            from: output, activeSessions: ["argus-s-repo-a", "argus-s-repo-b"])
        #expect(busy == ["argus-s-repo-a", "argus-s-repo-b"])
    }

    @Test("a malformed line without a pipe separator is skipped")
    func malformedLineSkipped() {
        let output = "no-pipe-here\nargus-s-repo-a|npm\n"
        let commands = TmuxPaneParser.parseSessionCommands(from: output)
        #expect(commands["no-pipe-here"] == nil)
        #expect(commands["argus-s-repo-a"] == "npm")
    }

    @Test("a command containing a pipe character is preserved via maxSplits")
    func commandWithPipeCharacterPreserved() {
        let output = "argus-s-repo-a|grep foo | wc -l\n"
        let commands = TmuxPaneParser.parseSessionCommands(from: output)
        #expect(commands["argus-s-repo-a"] == "grep foo | wc -l")
    }

    @Test("empty output produces no busy sessions")
    func emptyOutput() {
        let busy = TmuxPaneParser.busySessions(from: "", activeSessions: ["argus-s-repo-a"])
        #expect(busy.isEmpty)
    }

    @Test("empty active sessions produces no busy sessions regardless of output")
    func emptyActiveSessions() {
        let busy = TmuxPaneParser.busySessions(from: "argus-s-repo-a|npm\n", activeSessions: [])
        #expect(busy.isEmpty)
    }
}
