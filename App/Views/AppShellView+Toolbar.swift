import ArgusConfigKit
import SwiftUI

/// The window-layout and agent-pane-mode toolbar controls, factored out of `AppShellView.swift` to
/// keep its type body under SwiftLint's line-count limit.
extension AppShellView {
    /// A toolbar toggle, not a row in `layoutPicker`: the display mode is orthogonal to layout —
    /// available in both — so folding it into a single-selection layout menu would read as a
    /// third layout, exactly the confusion dropping `terminalClaudeCodex` was meant to remove.
    var agentPaneModeToggle: some View {
        let bindings = configStore.config.keyBindings
        let help =
            "Agent panes: \(agentTabs.mode.toggled.displayName)"
            + " (\(configStore.config.leaderKey) then \(bindings.toggleAgentSplit))"
        return Button(action: agentTabs.toggleMode) {
            Image(systemName: agentTabs.mode.toolbarIcon)
        }
        .help(help)
        .disabled(agentTabs.tabs.open.count < 2)
    }

    var layoutPicker: some View {
        let config = configStore.config
        return Menu {
            ForEach(WindowLayout.allCases) { layout in
                Button {
                    selectLayout(layout)
                } label: {
                    Label(layout.displayName, systemImage: layout.toolbarIcon)
                }
            }
        } label: {
            Image(systemName: config.layout.toolbarIcon)
        }
        .help("Window layout")
    }

    func selectLayout(_ layout: WindowLayout) {
        configStore.config.layout = layout
        configStore.save()
        // A layout switch never changes which roles are required — both layouts show the shell
        // plus the agent view — so there is nothing to register here, only focus to clamp.
        clampFocusedRole()
    }

    /// A role can stop being visible without a layout change — toggling split/full, or a tab
    /// close/switch changing which agent is active — leaving `focusedRole` pointing at an
    /// unmounted host if not re-clamped against `orderedRoles`.
    func clampFocusedRole() {
        let ordered = PaneLayoutResolver.orderedRoles(
            layout: configStore.config.layout, tabs: agentTabs.tabs, mode: agentTabs.mode)
        if !ordered.contains(focusedRole) {
            focusedRole = ordered.first ?? .shell
        }
    }
}
