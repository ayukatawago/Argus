import ArgusConfigKit
import Foundation

extension LeaderAction {
    /// The notification `AppDelegate` posts when this action's leader key is pressed — the App/
    /// half of the mapping `LeaderActionCatalog` (pure) can't hold.
    var notificationName: Notification.Name { Self.notificationNames[self] ?? .refreshWorkspace }

    private static let notificationNames: [LeaderAction: Notification.Name] = [
        .focusPaneLeft: .focusPaneLeft,
        .focusPaneRight: .focusPaneRight,
        .tmuxPaneLeft: .tmuxPaneLeft,
        .tmuxPaneDown: .tmuxPaneDown,
        .tmuxPaneUp: .tmuxPaneUp,
        .tmuxPaneRight: .tmuxPaneRight,
        .selectNextWorktree: .selectNextWorktree,
        .selectPreviousWorktree: .selectPreviousWorktree,
        .openNvim: .openNvim,
        .refreshWorkspace: .refreshWorkspace,
        .openMarkdownPreview: .openMarkdownPreview,
        .openSettings: .openSettings,
        .reloadAgentPane: .reloadAgentPane,
        .openDiskStatus: .openDiskStatus,
        .openDiffReview: .openDiffReview,
        .openCodexUsage: .openCodexUsage,
        .newTerminalTab: .newTerminalTab,
        .nextTerminalTab: .nextTerminalTab,
        .previousTerminalTab: .previousTerminalTab,
        .closeTerminalTab: .closeTerminalTab,
        .toggleAgentSplit: .toggleAgentSplit,
        .openCommandPalette: .openCommandPalette,
        .jumpToAttention: .jumpToAttention,
        .focusSidebarFilter: .focusSidebarFilter,
    ]
}
