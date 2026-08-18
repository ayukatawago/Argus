import Testing

@testable import AgentStateKit

@Suite("AgentType/AgentState hook mapping")
struct AgentStateMappingTests {
    @Test(
        "AgentType(hookAgent:) maps codex/claude/nil to a type, anything else to nil",
        arguments: [
            (Optional("codex"), Optional(AgentType.codex)), (Optional("claude"), Optional(AgentType.claude)),
            (nil, Optional(AgentType.claude)),
            (Optional("shell"), nil), (Optional("CODEX"), nil), (Optional(""), nil), (Optional("gemini"), nil),
        ] as [(String?, AgentType?)]
    )
    func agentTypeMapping(raw: String?, expected: AgentType?) {
        #expect(AgentType(hookAgent: raw) == expected)
    }

    @Test(
        "AgentState(hookState:) maps the three known states, everything else to idle",
        arguments: [
            ("running", AgentState.running), ("waitingForApproval", .waitingForApproval),
            ("done", .done), ("idle", .idle), ("", .idle), ("garbage", .idle),
        ] as [(String, AgentState)]
    )
    func agentStateMapping(raw: String, expected: AgentState) {
        #expect(AgentState(hookState: raw) == expected)
    }
}
