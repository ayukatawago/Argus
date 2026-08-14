import Testing

@testable import ArgusConfigKit

@Suite("PaneLayoutResolver")
struct PaneLayoutResolverTests {
    // MARK: - requiredRoles

    @Test("terminalAgent + claude requires only shell and claude, never codex")
    func requiredRolesTerminalAgentClaude() {
        let roles = PaneLayoutResolver.requiredRoles(layout: .terminalAgent, agent: .claude)
        #expect(roles == [.shell, .claude])
        #expect(!roles.contains(.codex))
    }

    @Test("terminalAgent + codex requires only shell and codex, never claude")
    func requiredRolesTerminalAgentCodex() {
        let roles = PaneLayoutResolver.requiredRoles(layout: .terminalAgent, agent: .codex)
        #expect(roles == [.shell, .codex])
        #expect(!roles.contains(.claude))
    }

    @Test(
        "agentsOverTerminal and terminalClaudeCodex require all three roles regardless of agent",
        arguments: [WindowLayout.agentsOverTerminal, .terminalClaudeCodex], [AgentSelection.claude, .codex]
    )
    func requiredRolesAlwaysThreeForMultiAgentLayouts(layout: WindowLayout, agent: AgentSelection) {
        let roles = PaneLayoutResolver.requiredRoles(layout: layout, agent: agent)
        #expect(Set(roles) == Set([.shell, .claude, .codex]))
    }

    // MARK: - primaryAgentRole

    @Test("terminalAgent's primary role follows the agent selection")
    func primaryAgentRoleTerminalAgent() {
        #expect(PaneLayoutResolver.primaryAgentRole(layout: .terminalAgent, agent: .claude) == .claude)
        #expect(PaneLayoutResolver.primaryAgentRole(layout: .terminalAgent, agent: .codex) == .codex)
    }

    @Test(
        "agentsOverTerminal and terminalClaudeCodex always primary claude, regardless of agent selection",
        arguments: [WindowLayout.agentsOverTerminal, .terminalClaudeCodex], [AgentSelection.claude, .codex]
    )
    func primaryAgentRoleAlwaysClaudeForMultiAgentLayouts(layout: WindowLayout, agent: AgentSelection) {
        #expect(PaneLayoutResolver.primaryAgentRole(layout: layout, agent: agent) == .claude)
    }

    // MARK: - orderedRoles

    @Test("terminalAgent orders shell then the selected agent")
    func orderedRolesTerminalAgent() {
        #expect(PaneLayoutResolver.orderedRoles(layout: .terminalAgent, agent: .claude) == [.shell, .claude])
        #expect(PaneLayoutResolver.orderedRoles(layout: .terminalAgent, agent: .codex) == [.shell, .codex])
    }

    @Test(
        "agentsOverTerminal orders codex, claude, then shell regardless of agent selection",
        arguments: [AgentSelection.claude, .codex]
    )
    func orderedRolesAgentsOverTerminal(agent: AgentSelection) {
        let roles = PaneLayoutResolver.orderedRoles(layout: .agentsOverTerminal, agent: agent)
        #expect(roles == [.codex, .claude, .shell])
    }

    @Test(
        "terminalClaudeCodex orders shell, claude, then codex regardless of agent selection",
        arguments: [AgentSelection.claude, .codex]
    )
    func orderedRolesTerminalClaudeCodex(agent: AgentSelection) {
        let roles = PaneLayoutResolver.orderedRoles(layout: .terminalClaudeCodex, agent: agent)
        #expect(roles == [.shell, .claude, .codex])
    }
}
