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
            └── (overlay: LazygitWindow NSPanel)  — LazygitWindow.swift
```

`AppDelegate` (also in `ArgusApp.swift`) installs global `NSEvent` monitors for the keyboard leader and mouse clicks, and posts `NotificationCenter` events that views observe.

---

## AppShellView — state root

`AppShellView` owns every top-level state object and is the single source of truth for which worktree is selected:

| Property | Type | Role |
|---|---|---|
| `store` | `WorkspaceStore` | Git repo/worktree list, persistence |
| `pool` | `PanePool` | Creates and holds all `WorktreePane` instances |
| `lazygit` | `LazygitWindow` | Lazygit `NSPanel` |
| `agentBus` | `AgentStateBus` | Per-worktree agent state from hook IPC |
| `selectedWorktreeID` | `String?` | Which worktree row is active |

`PanePool` is a private `ObservableObject` defined in `AppShellView.swift`. It holds two shared `TerminalHost` NSViews (one for the shell column, one for the Claude Code column) and a dictionary of `WorktreePane` instances keyed by worktree path. When a worktree is first selected, `pool.getOrCreate(id:workingDirectory:)` spawns the terminal pair and calls `WorktreeHookManager.install` to wire the Claude Code hooks.

The agent-state visual (background tint and border around the detail area) is computed in `AppShellView` from `agentBus.state(for: selectedWorktreeID)` and applied as `.background` and `.overlay` on the `terminalDetail` view.

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

`SidebarView` receives `agentBus` as an `@ObservedObject` and passes `agentBus.state(for: worktree.id)` down to each row; rows do not observe the bus directly.

---

## Detail area — terminal split

```
WorktreeContentView (NSViewRepresentable)
└── SplitTerminalView (NSView + NSSplitViewDelegate)
    └── NSSplitView (isVertical = true)
        ├── shellHost (TerminalHost)   — left pane: interactive shell
        └── agentHost (TerminalHost)   — right pane: Claude Code
```

`WorktreeContentView` is a thin `NSViewRepresentable`. It creates a `SplitTerminalView` once and never updates it — all terminal switching is handled imperatively by `TerminalHost.activate(id:)`.

### TerminalHost

`TerminalHost` is an `NSView` that keeps every worktree's `AppTerminalView` (a ghostty Metal surface) alive, but only mounts one at a time as a subview. When a worktree is deactivated, its view is removed from the hierarchy (pausing the Metal display link) but retained in a dictionary so its session and scrollback survive. Switching worktrees is instant.

### WorktreePane

`WorktreePane` (in `Sources/GhosttyBridge/`) owns one `AppTerminalView` for the shell and one for the Claude Code agent. The agent view launches:

```sh
$SHELL -l -c 'claude --continue || exec $SHELL -l'
```

so that `claude` is found via the user's login-shell PATH (Homebrew, nvm, etc.), and falls back to an interactive shell if `claude` exits.

---

## Lazygit popup

`LazygitWindow` is a separate `NSPanel` (floating window) that launches `lazygit` in a ghostty terminal at the current worktree's path. It is opened by `⌘⇧G` or the leader sequence `Ctrl+B → g`.

---

## Cross-component notifications

Components communicate through `NotificationCenter` rather than direct references, keeping `AppDelegate` and deeply nested views decoupled from `AppShellView`:

| Notification | Posted by | Handled by |
|---|---|---|
| `.workspaceInteracted` | `AppDelegate` (any keypress or click) | `AppShellView` — dismisses `done`/`waitingForApproval` indicator |
| `.openLazygit` | `AppDelegate`, menu item | `AppShellView` — opens `LazygitWindow` |
| `.focusShellPane` | `AppDelegate` (leader `h`) | `AppShellView` — focuses shell `TerminalHost` |
| `.focusAgentPane` | `AppDelegate` (leader `l`) | `AppShellView` — focuses agent `TerminalHost` |
| `.selectNextWorktree` | `AppDelegate` (leader `n`) | `AppShellView` — advances `selectedWorktreeID` |
| `.selectPreviousWorktree` | `AppDelegate` (leader `p`) | `AppShellView` — retreats `selectedWorktreeID` |
| `.refreshWorkspace` | `AppDelegate` (leader `r`) | `AppShellView` — calls `store.refresh()` |

---

## Agent state flow

```
Claude Code hook fires
    → bash script sends JSON to Unix socket
    → HookIPC (background Task) reads payload
    → AgentStateBus.apply() updates states[worktreePath]
    → AppShellView re-renders terminalBorder / terminalBackground
    → SidebarView re-renders AgentDot + AgentStateBackground
```

See [CLAUDE.md](CLAUDE.md) for the full hook → state mapping table.
