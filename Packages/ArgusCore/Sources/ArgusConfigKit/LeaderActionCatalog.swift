import Foundation

/// One leader-key action: the single description the dispatcher, the which-key HUD and the
/// command palette all read, so they can never drift apart.
public enum LeaderAction: CaseIterable, Hashable, Sendable {
    case focusPaneLeft, focusPaneRight
    case tmuxPaneLeft, tmuxPaneDown, tmuxPaneUp, tmuxPaneRight
    case selectNextWorktree, selectPreviousWorktree
    case openNvim, refreshWorkspace, openMarkdownPreview, openSettings
    case reloadAgentPane, openDiskStatus, openDiffReview, openCodexUsage
    case newTerminalTab, nextTerminalTab, previousTerminalTab, closeTerminalTab
    case toggleAgentSplit, openCommandPalette, jumpToAttention, focusSidebarFilter

    public var title: String { Self.table[self]?.title ?? "" }

    public func key(in bindings: ArgusConfig.KeyBindings) -> String {
        Self.table[self].map { bindings[keyPath: $0.keyPath] } ?? ""
    }

    private struct Row: Sendable {
        let title: String
        let keyPath: KeyPath<ArgusConfig.KeyBindings, String> & Sendable

        init(_ title: String, _ keyPath: KeyPath<ArgusConfig.KeyBindings, String> & Sendable) {
            self.title = title
            self.keyPath = keyPath
        }
    }

    private static let table: [LeaderAction: Row] = [
        .focusPaneLeft: Row("Focus pane left", \.focusPaneLeft),
        .focusPaneRight: Row("Focus pane right", \.focusPaneRight),
        .tmuxPaneLeft: Row("Tmux pane left", \.tmuxPaneLeft),
        .tmuxPaneDown: Row("Tmux pane down", \.tmuxPaneDown),
        .tmuxPaneUp: Row("Tmux pane up", \.tmuxPaneUp),
        .tmuxPaneRight: Row("Tmux pane right", \.tmuxPaneRight),
        .selectNextWorktree: Row("Next worktree", \.selectNextWorktree),
        .selectPreviousWorktree: Row("Previous worktree", \.selectPreviousWorktree),
        .openNvim: Row("Open nvim", \.openNvim),
        .refreshWorkspace: Row("Refresh workspace", \.refreshWorkspace),
        .openMarkdownPreview: Row("Open markdown preview", \.openMarkdownPreview),
        .openSettings: Row("Open settings", \.openSettings),
        .reloadAgentPane: Row("Reload agent pane", \.reloadAgentPane),
        .openDiskStatus: Row("Open disk status", \.openDiskStatus),
        .openDiffReview: Row("Open diff review", \.openDiffReview),
        .openCodexUsage: Row("Open Codex usage", \.openCodexUsage),
        .newTerminalTab: Row("New tab", \.newTerminalTab),
        .nextTerminalTab: Row("Next tab", \.nextTerminalTab),
        .previousTerminalTab: Row("Previous tab", \.previousTerminalTab),
        .closeTerminalTab: Row("Close tab", \.closeTerminalTab),
        .toggleAgentSplit: Row("Toggle agent side-by-side", \.toggleAgentSplit),
        .openCommandPalette: Row("Command palette", \.openCommandPalette),
        .jumpToAttention: Row("Jump to waiting agent", \.jumpToAttention),
        .focusSidebarFilter: Row("Filter sidebar", \.focusSidebarFilter),
    ]
}

/// What a leader keypress resolves to.
public enum LeaderTarget: Equatable, Sendable {
    case action(LeaderAction)
    case popup(id: String)
}

public struct LeaderEntry: Equatable, Sendable {
    public let title: String
    public let key: String
    public let target: LeaderTarget
}

public enum LeaderActionCatalog {
    /// Every bound leader key, built-in actions first (in `LeaderAction` order), then popup
    /// shortcuts. Unbound (empty) keys are skipped; when two entries share a key the first wins,
    /// matching dispatch order (built-in actions shadow popup shortcuts).
    public static func entries(config: ArgusConfig) -> [LeaderEntry] {
        var seen = Set<String>()
        var result: [LeaderEntry] = []
        func append(_ entry: LeaderEntry) {
            guard !entry.key.isEmpty, seen.insert(entry.key).inserted else { return }
            result.append(entry)
        }
        for action in LeaderAction.allCases {
            append(LeaderEntry(title: action.title, key: action.key(in: config.keyBindings), target: .action(action)))
        }
        for shortcut in config.popupShortcuts {
            append(LeaderEntry(title: shortcut.name, key: shortcut.key, target: .popup(id: shortcut.id)))
        }
        return result
    }

    /// The target a leader's second keypress `char` dispatches to, or nil if unbound.
    public static func target(forKey char: String, config: ArgusConfig) -> LeaderTarget? {
        entries(config: config).first(where: { $0.key == char })?.target
    }
}
