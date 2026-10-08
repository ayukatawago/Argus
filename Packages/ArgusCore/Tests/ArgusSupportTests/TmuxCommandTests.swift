import Foundation
import Testing

@testable import ArgusSupport

@Suite("TmuxCommand")
struct TmuxCommandTests {
    @Test("the ARGUS_TMUX override wins when executable")
    func overrideWins() {
        let path = TmuxCommand.executablePath(environment: ["ARGUS_TMUX": "/custom/tmux"]) { _ in true }
        #expect(path == "/custom/tmux")
    }

    @Test("a non-executable override is skipped in favour of the first existing install location")
    func overrideSkipped() {
        let path = TmuxCommand.executablePath(environment: ["ARGUS_TMUX": "/custom/tmux"]) {
            $0 == "/usr/local/bin/tmux"
        }
        #expect(path == "/usr/local/bin/tmux")
    }

    @Test("install locations are probed in order")
    func probeOrder() {
        #expect(TmuxCommand.executablePath(environment: [:]) { _ in true } == "/opt/homebrew/bin/tmux")
        #expect(TmuxCommand.executablePath(environment: [:]) { $0 == "/usr/bin/tmux" } == "/usr/bin/tmux")
    }

    @Test("with nothing executable it falls back to the bare name")
    func fallback() {
        #expect(TmuxCommand.executablePath(environment: [:]) { _ in false } == "tmux")
    }

    @Test("attachOrCreate keeps ordinary words bare and quotes the launch command")
    func attachOrCreateShape() {
        let line = TmuxCommand.attachOrCreate(
            tmux: "/opt/homebrew/bin/tmux", session: "argus-c-ab12",
            command: ["/bin/zsh", "-l", "-c", "claude --continue || exec /bin/zsh -l"])
        #expect(
            line
                == "/opt/homebrew/bin/tmux new-session -A -s argus-c-ab12 /bin/zsh -l -c 'claude --continue || exec /bin/zsh -l'"
                + " \\; set -s extended-keys on \\; set-option -t argus-c-ab12 status off")
    }

    @Test("a single quote in the launch command no longer breaks out of its quoting")
    func quoteInCommand() async {
        let line = TmuxCommand.attachOrCreate(tmux: "echo", session: "s", command: ["sh", "-c", "echo it's fine"])
        // Run the produced line through /bin/sh with `echo` as the "tmux": the words arrive intact.
        let result = await ProcessRunner.run(
            "/bin/sh", ["-c", line.replacingOccurrences(of: " \\; ", with: " ; true ; echo ")])
        #expect(result.standardOutput.hasPrefix("new-session -A -s s sh -c echo it's fine\n"))
    }

    @Test("a tmux path with spaces is quoted")
    func tmuxPathQuoted() {
        let line = TmuxCommand.attachOrCreate(tmux: "/Apps/my tools/tmux", session: "s", command: ["x"])
        #expect(line.hasPrefix("'/Apps/my tools/tmux' new-session"))
    }

    @Test("argv builders")
    func argv() {
        #expect(TmuxCommand.killSession("s") == ["kill-session", "-t", "s"])
        #expect(TmuxCommand.selectWindow(session: "s", index: 3) == ["select-window", "-t", "s:3"])
        #expect(TmuxCommand.killWindow(session: "s", index: 2) == ["kill-window", "-t", "s:2"])
        #expect(
            TmuxCommand.newWindow(session: "s", directory: "/d", shellCommand: "exec zsh -l")
                == ["new-window", "-a", "-t", "s:{end}", "-c", "/d", "exec zsh -l"])
        #expect(TmuxCommand.listWindows(session: "s", format: "#{x}") == ["list-windows", "-t", "s", "-F", "#{x}"])
        #expect(TmuxCommand.selectPane(session: "s", direction: "-L") == ["select-pane", "-t", "s", "-L"])
        #expect(TmuxCommand.listAllPanes(format: "#{a}") == ["list-panes", "-a", "-F", "#{a}"])
    }
}
