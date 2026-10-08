import Foundation

extension ArgusConfig {
    /// Escape hatch for `AgentPaneDisplayWatcher` (App/) — an override for the built-in regex
    /// vocabulary `AgentStateKit.AgentPaneDisplayParser.Patterns` uses to scrape a live agent
    /// pane's on-screen state. Lives in ArgusConfigKit rather than AgentStateKit because it's
    /// plain config data with no tmux/regex knowledge of its own — ArgusConfigKit cannot import
    /// AgentStateKit (see the module layout's "no edges between those four" rule), so it's App/
    /// that merges this with `Patterns.claudeDefaults`/`.codexDefaults` at read time.
    ///
    /// Each field is nil by default (Swift's synthesized `Decodable` treats a missing JSON key as
    /// nil for an `Optional`-typed property, needing no custom decoder here) so a CLI's TUI
    /// wording can be worked around one pattern at a time without an app release, without having
    /// to restate every other pattern. An absent or empty array both mean "use the built-in
    /// default for this field" — the merge itself happens on the AgentStateKit side, which is
    /// what actually knows what "default" means for a given field.
    public struct AgentDisplayPatterns: Codable, Equatable, Sendable {
        public var claude: AgentDisplayPatternOverrides?
        public var codex: AgentDisplayPatternOverrides?

        public init(claude: AgentDisplayPatternOverrides? = nil, codex: AgentDisplayPatternOverrides? = nil) {
            self.claude = claude
            self.codex = codex
        }
    }

    /// One agent's override fields within `AgentDisplayPatterns` — a sibling of that type, rather
    /// than nested inside it, to stay within SwiftLint's one-level type-nesting limit.
    public struct AgentDisplayPatternOverrides: Codable, Equatable, Sendable {
        public var running: [String]?
        public var finished: [String]?
        public var ready: [String]?
        public var awaitingApproval: [String]?
        public var agentUI: [String]?

        public init(
            running: [String]? = nil,
            finished: [String]? = nil,
            ready: [String]? = nil,
            awaitingApproval: [String]? = nil,
            agentUI: [String]? = nil
        ) {
            self.running = running
            self.finished = finished
            self.ready = ready
            self.awaitingApproval = awaitingApproval
            self.agentUI = agentUI
        }
    }
}
