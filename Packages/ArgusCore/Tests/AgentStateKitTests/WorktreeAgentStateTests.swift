import Testing

@testable import AgentStateKit

@Suite("WorktreeAgentState.aggregate")
struct WorktreeAgentStateTests {
    private static let allStates: [AgentState] = [.idle, .running, .done, .waitingForApproval]

    @Test("displayPriority orders idle < running < done < waitingForApproval")
    func displayPriorityOrdering() {
        #expect(AgentState.idle.displayPriority < AgentState.running.displayPriority)
        #expect(AgentState.running.displayPriority < AgentState.done.displayPriority)
        #expect(AgentState.done.displayPriority < AgentState.waitingForApproval.displayPriority)
    }

    @Test("an empty input aggregates to idle/claude")
    func emptyInputIsIdleClaude() {
        let result = WorktreeAgentState.aggregate([:])
        #expect(result == .idle)
    }

    @Test("a single agent's state passes straight through")
    func singleAgentInputPassesThrough() {
        #expect(WorktreeAgentState.aggregate([.codex: .running]) == WorktreeAgentState(state: .running, agent: .codex))
        #expect(WorktreeAgentState.aggregate([.claude: .done]) == WorktreeAgentState(state: .done, agent: .claude))
    }

    @Test("ties resolve to Claude", arguments: allStates)
    func tiesResolveToClaude(state: AgentState) {
        let result = WorktreeAgentState.aggregate([.claude: state, .codex: state])
        #expect(result == WorktreeAgentState(state: state, agent: .claude))
    }

    @Test(
        "the full priority matrix: the higher-priority agent's state and identity always wins",
        arguments: allStates, allStates
    )
    func aggregatePriorityMatrix(claudeState: AgentState, codexState: AgentState) {
        let result = WorktreeAgentState.aggregate([.claude: claudeState, .codex: codexState])
        if claudeState.displayPriority >= codexState.displayPriority {
            #expect(result == WorktreeAgentState(state: claudeState, agent: .claude))
        } else {
            #expect(result == WorktreeAgentState(state: codexState, agent: .codex))
        }
    }
}
