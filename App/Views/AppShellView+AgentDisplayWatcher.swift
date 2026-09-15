import AgentStateKit
import SwiftUI
import Workspaces

extension View {
    /// Starts/stops `AgentPaneDisplayWatcher` and keeps it fed with the full known-worktree set —
    /// factored out of `AppShellView.coreView` to keep its body under SwiftLint's line-count limit
    /// (mirrors `onReceiveTabBindings`), and out of an `AppShellView` extension because its stored
    /// properties are `private` to that file.
    ///
    /// `repos` comes from `store.repos` — every known worktree, not just `pool.activeIDs` — because
    /// an agent's tmux session persists across a worktree's pane being released (see
    /// `WorktreePane`'s doc comment), so the display watcher must keep covering it even after its
    /// pane is no longer open in the UI.
    func withAgentDisplayWatcher(
        _ watcher: AgentPaneDisplayWatcher, agentBus: AgentStateBus, repos: [GitRepo]
    ) -> some View {
        onAppear {
            watcher.attach(agentBus: agentBus)
            watcher.updateKnownPaths(Set(repos.flatMap(\.worktrees).map(\.path)))
            watcher.start()
        }
        .onDisappear { watcher.stop() }
        .onChange(of: repos) { _, newRepos in
            watcher.updateKnownPaths(Set(newRepos.flatMap(\.worktrees).map(\.path)))
        }
    }
}
