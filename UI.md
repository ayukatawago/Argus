# UI Structure

## Window hierarchy

```
ArgusApp (App)
└── Window("Argus")  — ArgusApp.swift
    └── ContentView  — ContentView.swift  (thin wrapper)
        └── AppShellView  — AppShellView.swift  (root layout + state ownership)
            ├── NavigationSplitView
            │   ├── sidebar: SidebarView  — SidebarView.swift
            │   └── detail:  WorktreeContentView  — WorktreeContentView.swift
            └── (overlay: popup terminal windows)  — PopupTerminalWindow.swift
```

`AppDelegate` (also in `ArgusApp.swift`) installs global `NSEvent` monitors for the keyboard leader and mouse clicks, and posts `NotificationCenter` events that views observe.

---

## AppShellView — state root

`AppShellView` owns every top-level state object and is the single source of truth for which worktree is selected. Some of its logic is split across sibling files as `extension AppShellView` (`AppShellView+Toolbar.swift`, `AppShellView+TabBindings.swift`) purely to stay under SwiftLint's type-body-length limit — for that reason `configStore`, `agentTabs`, and `focusedRole` are declared without `private` (Swift's `private` is same-file-only, even across extensions of the same type).

| Property | Type | Role |
|---|---|---|
| `store` | `WorkspaceStore` | Git repo/worktree list, persistence |
| `pool` | `PanePool` | Owns the shell/claude/codex `TerminalHost`s and `WorktreePane` instances |
| `agentTabs` | `AgentTabsStore` | Per-worktree open/active agent tabs + the full/split display mode |
| `terminalTabs` | `TerminalTabsStore` | The selected worktree's shell tmux windows, mirrored as tabs |
| `agentBus` | `AgentStateBus` | Per-(worktree, agent) state from hook IPC + transcript/session polling |
| `shellStateBus` | `ShellStateBus` | Per-worktree shell-busy tracking (sidebar border) |
| `popups` | `PopupTerminalManager` | User-configured popup terminal windows (default: lazygit) |
| `selectedWorktreeID` | `String?` | Which worktree row is active |
| `focusedRole` | `PaneRole` | Which pane (`.shell`/`.claude`/`.codex`) directional focus and the tab-key bindings target |
| `isCanvasMode` | `Bool` | Whether the grid-of-all-worktrees canvas view is showing |

`PanePool` (`App/Views/PanePool.swift`) holds three shared `TerminalHost` NSViews (shell/claude/codex) and a dictionary of `WorktreePane` instances keyed by worktree id. Which roles are registered for a worktree is decided *outside* `PanePool` — by `PaneLayoutResolver.requiredRoles(tabs:)` given that worktree's `AgentTabs` — and passed in as an explicit `roles:` argument; `PanePool` itself has no notion of layout or open tabs.

The agent-state visual (background tint on the detail area) is computed in `AppShellView` from `agentBus.worktreeState(for: selectedWorktreeID)` — the worktree-level aggregate across both agents — and applied as `.background` on `terminalDetail`. Per-agent borders are drawn per pane inside `AgentPaneView` instead (see below).

---

## SidebarView

```
SidebarView
└── ScrollView
    └── LazyVStack
        └── repoSection(for:)  [repeated per GitRepo]
            ├── RepoHeader  — repo name, +worktree, remove, unhide buttons
            │   └── (draggable for repo reordering)
            └── WorktreeRow  [repeated per Worktree]
                ├── AgentDot  — colored dot (idle/running/waitingForApproval/done)
                ├── worktree name
                ├── release button  (if terminal is active)
                └── delete button  (if not the main worktree)
```

`WorktreeRow` wraps its content in `AgentStateBackground`, which applies a subtle colored background matching the dot color when the state is non-idle.

`SidebarView` receives `agentBus` as an `@ObservedObject` and passes `agentBus.worktreeState(for: worktree.id)` — the aggregate across both agents, see CLAUDE.md's Agent state system section — down to each row as `agentState`/`agentType`; rows do not observe the bus directly.

---

## Detail area — terminal + agent view

```
WorktreeContentView (SwiftUI View)
├── .terminalAgent:       HSplitView { shellPane | agentPane }
└── .agentsOverTerminal:  RatioVSplitView { agentPane / shellPane }  (70/30, draggable)

shellPane
├── TerminalTabBarView   — tmux-window tabs, mirrors the shell session
└── TerminalHostView(shellHost)

agentPane = AgentPaneView
├── AgentTabBarView      — Claude/Codex tabs, one chip per open agent
└── one TerminalHostView (full mode) or an HSplitView of two (split mode)
```

Both layouts render the same two pieces — `shellPane` and `agentPane` — just arranged differently; there is no longer a three-column "show every agent" layout, because showing both agents is now `AgentPaneView`'s own **split** display mode (`AgentPaneMode`, toggled by the toolbar button or leader `s`), orthogonal to layout.

### TerminalHost

`TerminalHost` is an `NSView` that keeps every worktree's `AppTerminalView` (a ghostty Metal surface) alive, but only mounts one at a time as a subview. When a worktree is deactivated, its view is removed from the hierarchy (pausing the Metal display link) but retained in a dictionary so its session and scrollback survive. Switching worktrees is instant. The same suspend/resume mechanism is what makes switching agent tabs in full mode cheap: the inactive agent's `TerminalHost` container simply isn't in the SwiftUI tree that frame.

### AgentPaneView / AgentTabBarView / AgentTabsStore

`AgentTabsStore` (`App/Views/AgentTabsStore.swift`) is the source of truth for which agent tabs a worktree has open and which is active (`ArgusConfigKit.AgentTabs`), plus the app-global `AgentPaneMode`. Unlike `TerminalTabsStore`, it is **not** a tmux mirror — there is no tmux concept of "open agent tabs" — so opening/closing a tab is plain Argus state, with `PanePool.openRole`/`closeRole` as its side effects. `AgentPaneView` renders `AgentTabBarView` plus `PaneLayoutResolver.visibleAgentRoles(tabs:mode:)` worth of `TerminalHostView`s, each with its own `focusBorder`/`agentStateBorder` sourced from `agentBus.state(for:agent:)` — so a Codex `waitingForApproval` border paints around the Codex pane, not Claude's.

### WorktreePane

`WorktreePane` (in `Sources/GhosttyBridge/`) owns one `AppTerminalView` per `PaneRole` (shell/claude/codex), created lazily. The agent views launch:

```sh
$SHELL -l -c 'claude --continue || exec $SHELL -l'
```

so that `claude` (or `codex resume`) is found via the user's login-shell PATH (Homebrew, nvm, etc.), and falls back to an interactive shell if the CLI exits. `discardView(for:)` drops a role's cached surface/state so a later `view(for:)` call (after an agent tab is closed and reopened) builds a fresh one against a fresh tmux session.

---

## Popup terminals

`PopupTerminalManager` (in `PopupTerminalWindow.swift`) owns one `PopupTerminalWindow` — a floating `NSWindow` running a shell command in a ghostty terminal at the current worktree's path — per configured `ArgusConfig.PopupShortcut`. Shortcuts (name, leader key, command, window size) are user-defined in Settings → Keyboard; `lazygit` ships as the default entry (leader sequence `Ctrl+B → g`). Unlike the nvim popup (`NvimWindow.swift`), these run the command fresh each open with no persistent session.

---

## Cross-component notifications

Components communicate through `NotificationCenter` rather than direct references, keeping `AppDelegate` and deeply nested views decoupled from `AppShellView`:

| Notification | Posted by | Handled by |
|---|---|---|
| `.workspaceInteracted` | `AppDelegate` (any keypress or click) | `AppShellView` — `dismissAttentionIfNeeded()`, clearing `done`/`waitingForApproval` for the selected worktree |
| `.openPopupTerminal` | `AppDelegate` (leader key, dynamic per `popupShortcuts`) | `AppShellView` — opens `PopupTerminalManager` window for the matched shortcut |
| `.focusPaneLeft` / `.focusPaneRight` | `AppDelegate` (leader `h`/`l`) | `AppShellView.stepFocus` — walks `PaneLayoutResolver.orderedRoles(layout:tabs:mode:)`, skipping panes hidden by the current display mode |
| `.selectNextWorktree` / `.selectPreviousWorktree` | `AppDelegate` (leader `n`/`p`) | `AppShellView` — advances/retreats `selectedWorktreeID` |
| `.refreshWorkspace` | `AppDelegate` (leader `r`) | `AppShellView` — calls `store.refresh()` |
| `.newTerminalTab` / `.nextTerminalTab` / `.previousTerminalTab` / `.closeTerminalTab` | `AppDelegate` (leader `t`/`]`/`[`/`x`) | `View.onReceiveTabBindings` (`AppShellView+TabBindings.swift`) — routed to `TerminalTabsStore` or `AgentTabsStore` based on `focusedRole` |
| `.toggleAgentSplit` | `AppDelegate` (leader `s`) | `AppShellView+TabBindings.swift` — `agentTabs.toggleMode()` |
| `.reloadAgentPane` | `AppDelegate` (leader `a`) | `AppShellView` — kills every open agent tab's tmux session via `pool.reloadAgentPanes`, resets their state |

---

## Agent state flow

```
Claude Code hook fires (or transcript/session poll infers a state)
    → HookPayload{worktreePath, state, agent}
    → AgentStateBus.apply() updates states[AgentKey(worktreePath, agent)]
    → AppShellView re-renders terminalBackground from agentBus.worktreeState(selected)
    → AgentPaneView re-renders each visible pane's border from agentBus.state(path, agent)
    → AgentTabBarView re-renders each chip's AgentDot from agentBus.state(path, agent)
    → SidebarView re-renders AgentDot + AgentStateBackground from agentBus.worktreeState(worktree.id)
```

See [CLAUDE.md](CLAUDE.md) for the full hook → state mapping table and the per-agent aggregation rule.
