import ArgusConfigKit
import SwiftUI

extension View {
    /// The leader-key bindings for both tab bars (new / next / previous / close) and the
    /// agent-pane split toggle — factored out of `AppShellView.coreView` to keep its body under
    /// SwiftLint's line-count limit, and out of an `AppShellView` extension because its stored
    /// properties are `private` to that file. The four tab actions are context-sensitive on
    /// `focusedRole`: on the shell pane they drive `TerminalTabsStore` (a tmux mirror); on the
    /// agent pane they drive `AgentTabsStore` (plain Argus state — see its doc comment). Both
    /// degrade a refused action to a no-op rather than a surprise: `t` when both agent tabs are
    /// already open, or `x` on the last one, does nothing.
    func onReceiveTabBindings(
        focusedRole: Binding<PaneRole>, terminalTabs: TerminalTabsStore, agentTabs: AgentTabsStore, pool: PanePool
    ) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .newTerminalTab)) { _ in
            runTabAction(.new, focusedRole: focusedRole, terminalTabs: terminalTabs, agentTabs: agentTabs, pool: pool)
        }
        .onReceive(NotificationCenter.default.publisher(for: .nextTerminalTab)) { _ in
            runTabAction(
                .next, focusedRole: focusedRole, terminalTabs: terminalTabs, agentTabs: agentTabs, pool: pool)
        }
        .onReceive(NotificationCenter.default.publisher(for: .previousTerminalTab)) { _ in
            runTabAction(
                .previous, focusedRole: focusedRole, terminalTabs: terminalTabs, agentTabs: agentTabs, pool: pool)
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeTerminalTab)) { _ in
            runTabAction(
                .close, focusedRole: focusedRole, terminalTabs: terminalTabs, agentTabs: agentTabs, pool: pool)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleAgentSplit)) { _ in
            agentTabs.toggleMode()
        }
    }

    /// `WorktreeContentView`'s `onShellActivated`/`onAgentActivated` callbacks only fire from tab-bar
    /// clicks. Clicking directly into a terminal's content area makes it first responder — and updates
    /// its border via `TerminalHost.hasFocus` — without going through either callback, so `focusedRole`
    /// (which the tab bindings above route on) would otherwise go stale. Mirror `hasFocus` here so the
    /// two always agree on which pane is focused.
    func onReceiveFocusSync(focusedRole: Binding<PaneRole>, pool: PanePool) -> some View {
        onReceive(pool.shellHost.$hasFocus) { focused in
            if focused { focusedRole.wrappedValue = .shell }
        }
        .onReceive(pool.claudeHost.$hasFocus) { focused in
            if focused { focusedRole.wrappedValue = .claude }
        }
        .onReceive(pool.codexHost.$hasFocus) { focused in
            if focused { focusedRole.wrappedValue = .codex }
        }
    }
}

/// Which tab action a leader-key binding requests, before `runTabAction` routes it to whichever
/// pane has focus.
private enum PaneTabAction {
    case new, next, previous, close
}

@MainActor
private func runTabAction(
    _ action: PaneTabAction, focusedRole: Binding<PaneRole>, terminalTabs: TerminalTabsStore,
    agentTabs: AgentTabsStore, pool: PanePool
) {
    if focusedRole.wrappedValue == .shell {
        runShellTabAction(action, terminalTabs: terminalTabs, pool: pool, focusedRole: focusedRole)
    } else {
        runAgentTabAction(action, agentTabs: agentTabs, pool: pool, focusedRole: focusedRole)
    }
}

/// Mirrors `TerminalTabBarView`'s mouse actions: run the tmux command, then focus the shell pane
/// once it completes.
@MainActor
private func runShellTabAction(
    _ action: PaneTabAction, terminalTabs: TerminalTabsStore, pool: PanePool, focusedRole: Binding<PaneRole>
) {
    let task: Task<Void, Never>
    switch action {
    case .new:
        task = terminalTabs.newTab()

    case .next:
        task = terminalTabs.selectRelative(1)

    case .previous:
        task = terminalTabs.selectRelative(-1)

    case .close:
        guard let index = terminalTabs.windows.first(where: \.isActive)?.index else { return }
        task = terminalTabs.close(index: index)
    }
    focusedRole.wrappedValue = .shell
    Task {
        await task.value
        pool.shellHost.focusActiveTerminal()
    }
}

/// Mirrors `AgentTabBarView`'s mouse actions: apply the (synchronous) store action, then focus the
/// pane that ends up active. `close` is the one action with a tmux session to wait on.
@MainActor
private func runAgentTabAction(
    _ action: PaneTabAction, agentTabs: AgentTabsStore, pool: PanePool, focusedRole: Binding<PaneRole>
) {
    func focusActiveAgent() {
        let role = agentTabs.tabs.active.paneRole
        focusedRole.wrappedValue = role
        Task { @MainActor in pool.host(for: role).focusActiveTerminal() }
    }
    switch action {
    case .new:
        guard agentTabs.openClosedTab() else { return }
        focusActiveAgent()

    case .next:
        guard agentTabs.selectRelative(1) else { return }
        focusActiveAgent()

    case .previous:
        guard agentTabs.selectRelative(-1) else { return }
        focusActiveAgent()

    case .close:
        let task = agentTabs.closeTab(agentTabs.tabs.active)
        Task {
            await task.value
            focusActiveAgent()
        }
    }
}
