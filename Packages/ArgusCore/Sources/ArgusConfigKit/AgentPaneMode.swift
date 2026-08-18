import Foundation

/// How the agent view renders its open tabs: one at a time, or all of them side by side.
public enum AgentPaneMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case full
    case split

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .full: "Full width"
        case .split: "Side by side"
        }
    }

    public var toolbarIcon: String {
        switch self {
        case .full: "rectangle"
        case .split: "rectangle.split.2x1"
        }
    }

    public var toggled: AgentPaneMode {
        self == .full ? .split : .full
    }
}
