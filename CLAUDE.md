# CLAUDE.md — kotty

## Build

```sh
xcodegen generate          # regenerate kotty.xcodeproj from project.yml
xcodebuild -scheme kotty -configuration Debug build
```

SwiftLint runs as an Xcode build phase and as a pre-commit hook. Lint errors block the build; warnings do not. The relevant limits enforced as errors: line length ≤ 160 characters.

To regenerate the Xcode project after editing `project.yml`:

```sh
xcodegen generate
```

## Module layout

```
Sources/
  AgentState/       Foundation only — agent state enum, IPC bus, hook manager
  GhosttyBridge/    GhosttyKit (C lib) + Foundation — PTY and terminal surface
  Workspaces/       Foundation only — git repo/worktree scanning and store
App/
  Views/            SwiftUI + AppKit — all UI (sidebar, shell, main shell)
  kottyApp.swift    NSApplicationDelegate, top-level wiring
```

Cross-module import rule: only `App/` imports everything; source modules may only import siblings listed in CONVENTIONS.md.

## Agent state system

Claude Code hooks write JSON payloads to a Unix socket; kotty reads them and updates per-worktree state.

### States (`Sources/AgentState/AgentState.swift`)

| State | Meaning | Visual |
|---|---|---|
| `idle` | No agent activity | No indicator |
| `running` | Agent is executing | Pulsing peach dot + border |
| `waitingForApproval` | Agent blocked on permission dialog | Orange dot + thick orange border |
| `done` | Agent stopped, awaiting user reply | Green dot + green border |

`done` and `waitingForApproval` borders dismiss when the user interacts with the workspace (click or keypress). `waitingForApproval` also clears automatically when the agent resumes.

### Hook → state mapping (`Sources/AgentState/WorktreeHookManager.swift`)

| Claude Code hook | State sent | Script |
|---|---|---|
| `PreToolUse` | `running` | `claude-running.sh` |
| `Stop` | `done` | `claude-done.sh` |
| `PermissionRequest` | `waitingForApproval` | `claude-waiting-approval.sh` |
| `UserPromptSubmit` | `running` | `claude-user-prompt.sh` |
| `PreCompact` | `running` | `claude-pre-compact.sh` |
| `PostCompact` | `done` | `claude-post-compact.sh` |

Note: `Stop` does **not** fire when `/compact` finishes — `PostCompact` covers that case.

### IPC path

Scripts live in `~/Library/Application Support/kotty/hooks/` and are written once on first pane open. They send to the Unix socket at `~/Library/Application Support/kotty/hook.sock` (`HookIPC.socketPath`).

`WorktreeHookManager.install(worktreePath:)` is idempotent: it overwrites the scripts and upserts kotty's entries in `.claude/settings.local.json` without disturbing other hook entries. That file is gitignored.

## Key files

| File | Role |
|---|---|
| `App/kottyApp.swift` | App entry, keyboard leader, canvas overlay |
| `App/Views/AppShellView.swift` | Main split layout, agent state border/tint |
| `App/Views/SidebarView.swift` | Repo/worktree list, `AgentDot`, drag reorder |
| `App/Views/WorktreeContentView.swift` | Per-worktree dual-pane (Claude + shell) |
| `App/Views/LazygitWindow.swift` | Lazygit popup window (`⌘G`) |
| `Sources/AgentState/AgentStateBus.swift` | `@MainActor` ObservableObject, socket reader |
| `Sources/AgentState/WorktreeHookManager.swift` | Hook script writer + settings patcher |
| `Sources/Workspaces/WorkspaceStore.swift` | Repo/worktree scanning, persistence |
| `Sources/GhosttyBridge/WorktreePane.swift` | ghostty surface lifecycle per pane |
| `project.yml` | XcodeGen project definition — edit this, not the `.xcodeproj` |

## Conventions

See [CONVENTIONS.md](CONVENTIONS.md) for Swift style, concurrency, and error handling rules.

See [UI.md](UI.md) for how the view hierarchy maps to source files.

Commit format: `type: brief description` (Conventional Commits, lowercase imperative, ≤ 72 chars). See `.claude/skills/commit/`.
