import Foundation

extension AgentPaneDisplayParser.Patterns {
    /// These patterns with any non-empty override substituted, field by field. A `nil` or empty
    /// override array means "use the built-in pattern for this field", never "match nothing" — so a
    /// config that restates only one pattern can't silently disable the others.
    ///
    /// Takes plain arrays (not `ArgusConfig`'s override type) because AgentStateKit cannot import
    /// ArgusConfigKit; `App/` passes the config fields through.
    public func overriding(
        running: [String]?, finished: [String]?, ready: [String]?, awaitingApproval: [String]?, agentUI: [String]?
    ) -> Self {
        func pick(_ override: [String]?, _ fallback: [String]) -> [String] {
            guard let override, !override.isEmpty else { return fallback }
            return override
        }
        return Self(
            running: pick(running, self.running),
            finished: pick(finished, self.finished),
            ready: pick(ready, self.ready),
            awaitingApproval: pick(awaitingApproval, self.awaitingApproval),
            agentUI: pick(agentUI, self.agentUI)
        )
    }
}
