import Testing

@testable import ArgusConfigKit

@Suite("PaneRole")
struct PaneRoleTests {
    @Test("tmux session type chars are 's'/'a'/'x' and distinct")
    func tmuxSessionTypeChars() {
        #expect(PaneRole.shell.tmuxSessionType == "s")
        #expect(PaneRole.claude.tmuxSessionType == "a")
        #expect(PaneRole.codex.tmuxSessionType == "x")
        let chars = Set([PaneRole.shell, .claude, .codex].map(\.tmuxSessionType))
        #expect(chars.count == 3)
    }

    @Test("AgentSelection.paneRole round-trips through PaneRole.agent")
    func paneRoleRoundTrips() {
        for selection in AgentSelection.allCases {
            #expect(selection.paneRole.agent == selection)
        }
        #expect(PaneRole.shell.agent == nil)
    }
}
