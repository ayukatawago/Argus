import Testing

@testable import ArgusConfigKit

@Suite("PaneLayoutResolver")
struct PaneLayoutResolverTests {
    // MARK: - requiredRoles

    @Test("only the default agent's tab requires a role beyond shell")
    func requiredRolesClaudeOnly() {
        let roles = PaneLayoutResolver.requiredRoles(tabs: AgentTabs(defaultAgent: .claude))
        #expect(Set(roles) == Set([.shell, .claude]))
        #expect(!roles.contains(.codex))
    }

    @Test("codex as the default agent requires shell and codex, never claude")
    func requiredRolesCodexOnly() {
        let roles = PaneLayoutResolver.requiredRoles(tabs: AgentTabs(defaultAgent: .codex))
        #expect(Set(roles) == Set([.shell, .codex]))
        #expect(!roles.contains(.claude))
    }

    @Test("both tabs open requires all three roles regardless of which is active")
    func requiredRolesBothOpen() {
        var tabs = AgentTabs(defaultAgent: .claude)
        tabs.open(.codex)
        let roles = PaneLayoutResolver.requiredRoles(tabs: tabs)
        #expect(Set(roles) == Set([.shell, .claude, .codex]))
    }

    // MARK: - visibleAgentRoles

    @Test("full mode shows only the active agent")
    func visibleAgentRolesFull() {
        var tabs = AgentTabs(defaultAgent: .claude)
        tabs.open(.codex)
        tabs.activate(.claude)
        #expect(PaneLayoutResolver.visibleAgentRoles(tabs: tabs, mode: .full) == [.claude])
        tabs.activate(.codex)
        #expect(PaneLayoutResolver.visibleAgentRoles(tabs: tabs, mode: .full) == [.codex])
    }

    @Test("split mode with both tabs open shows both, Claude first")
    func visibleAgentRolesSplitBothOpen() {
        var tabs = AgentTabs(defaultAgent: .codex)
        tabs.open(.claude)
        #expect(PaneLayoutResolver.visibleAgentRoles(tabs: tabs, mode: .split) == [.claude, .codex])
    }

    @Test("split mode with only one tab open degenerates to full")
    func visibleAgentRolesSplitDegeneratesWithOneTab() {
        let tabs = AgentTabs(defaultAgent: .claude)
        #expect(PaneLayoutResolver.visibleAgentRoles(tabs: tabs, mode: .split) == [.claude])
    }

    // MARK: - orderedRoles

    @Test("terminalAgent orders shell then the visible agent(s)")
    func orderedRolesTerminalAgent() {
        let claudeOnly = AgentTabs(defaultAgent: .claude)
        let claudeOrdered = PaneLayoutResolver.orderedRoles(layout: .terminalAgent, tabs: claudeOnly, mode: .full)
        #expect(claudeOrdered == [.shell, .claude])

        var both = AgentTabs(defaultAgent: .claude)
        both.open(.codex)
        #expect(
            PaneLayoutResolver.orderedRoles(layout: .terminalAgent, tabs: both, mode: .split)
                == [.shell, .claude, .codex])
    }

    @Test("agentsOverTerminal orders the visible agent(s) then shell")
    func orderedRolesAgentsOverTerminal() {
        let codexOnly = AgentTabs(defaultAgent: .codex)
        #expect(
            PaneLayoutResolver.orderedRoles(layout: .agentsOverTerminal, tabs: codexOnly, mode: .full)
                == [.codex, .shell])

        var both = AgentTabs(defaultAgent: .codex)
        both.open(.claude)
        #expect(
            PaneLayoutResolver.orderedRoles(layout: .agentsOverTerminal, tabs: both, mode: .split)
                == [.claude, .codex, .shell])
    }

    // MARK: - Invariant

    @Test(
        "every visible/ordered role is always a required (registered) role",
        arguments: [WindowLayout.terminalAgent, .agentsOverTerminal], [AgentPaneMode.full, .split]
    )
    func orderedRolesAreAlwaysRequired(layout: WindowLayout, mode: AgentPaneMode) {
        for defaultAgent in AgentSelection.allCases {
            for openBoth in [false, true] {
                var tabs = AgentTabs(defaultAgent: defaultAgent)
                if openBoth { tabs.open(defaultAgent == .claude ? .codex : .claude) }
                let required = Set(PaneLayoutResolver.requiredRoles(tabs: tabs))
                let ordered = Set(PaneLayoutResolver.orderedRoles(layout: layout, tabs: tabs, mode: mode))
                #expect(ordered.isSubset(of: required))
            }
        }
    }
}
