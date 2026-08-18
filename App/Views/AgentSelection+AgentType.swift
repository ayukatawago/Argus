import AgentStateKit
import ArgusConfigKit

/// The one place `AgentSelection` (config) and `AgentType` (agent state) are mapped onto each
/// other — `AgentStateKit` cannot import `ArgusConfigKit` (see CONVENTIONS.md's module table), so
/// this lives in the App target instead of being duplicated at each call site.
extension AgentSelection {
    var agentType: AgentType {
        switch self {
        case .claude: .claude
        case .codex: .codex
        }
    }
}

extension AgentType {
    var agentSelection: AgentSelection {
        switch self {
        case .claude: .claude
        case .codex: .codex
        }
    }
}
