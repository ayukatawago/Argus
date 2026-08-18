import Foundation

/// The agent tabs open for one worktree: which agents have a tab, and which one is active. Never
/// empty — closing the last tab is refused, mirroring `TerminalTabsStore.close`'s
/// `windows.count > 1` guard (agent tabs aren't a tmux mirror, but the same "there must always be
/// something to show" rule applies). `open` is kept in `AgentSelection.allCases` order, not
/// insertion order, so chip order and side-by-side geometry stay put across a close/reopen.
public struct AgentTabs: Equatable, Sendable {
    public private(set) var open: [AgentSelection]
    public private(set) var active: AgentSelection

    public init(defaultAgent: AgentSelection) {
        open = [defaultAgent]
        active = defaultAgent
    }

    /// The agent without a tab — what the `+` button would open. `nil` when both are open.
    public var closed: AgentSelection? {
        AgentSelection.allCases.first { !open.contains($0) }
    }

    /// Opens (and activates) `agent`. Returns `false` when it was already open (still activates).
    @discardableResult
    public mutating func open(_ agent: AgentSelection) -> Bool {
        let wasOpen = open.contains(agent)
        if !wasOpen {
            open = AgentSelection.allCases.filter { open.contains($0) || $0 == agent }
        }
        active = agent
        return !wasOpen
    }

    /// Closes `agent`, moving `active` to the survivor. Returns `nil` (and changes nothing) when
    /// `agent` is the last open tab.
    @discardableResult
    public mutating func close(_ agent: AgentSelection) -> AgentSelection? {
        guard open.count > 1, let index = open.firstIndex(of: agent) else { return nil }
        open.remove(at: index)
        guard let survivor = open.first else { return nil }
        if active == agent { active = survivor }
        return survivor
    }

    /// Returns `false` when `agent` isn't open or is already active.
    @discardableResult
    public mutating func activate(_ agent: AgentSelection) -> Bool {
        guard open.contains(agent), active != agent else { return false }
        active = agent
        return true
    }

    /// Wrapping relative activation, for leader `]` / `[` on the agent pane.
    @discardableResult
    public mutating func activateRelative(_ delta: Int) -> Bool {
        guard open.count > 1, let currentIndex = open.firstIndex(of: active) else { return false }
        let count = open.count
        let nextIndex = ((currentIndex + delta) % count + count) % count
        return activate(open[nextIndex])
    }
}
