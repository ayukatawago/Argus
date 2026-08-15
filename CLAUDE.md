# CLAUDE.md — Argus

## Build

```sh
xcodegen generate          # regenerate Argus.xcodeproj from project.yml
xcodebuild -scheme Argus -configuration Debug build
```

SwiftLint runs as an Xcode build phase and as a pre-commit hook. Lint errors block the build; warnings do not. The relevant limits enforced as errors: line length ≤ 160 characters.

To regenerate the Xcode project after editing `project.yml`:

```sh
xcodegen generate
```

### Debug code signing

Debug builds sign with a local identity named `Argus Local Dev` instead of ad-hoc (`-`), so macOS's
per-folder file-access grants (Desktop, Documents, Downloads, Movies, Music, Pictures — needed
because Argus spawns a login shell per pane) survive rebuilds instead of re-prompting every launch.
This identity is a self-signed certificate that lives only in your local login keychain — it is not
committed and does not chain to Apple's root, so it must never be used for Release/distribution
builds (see `project.yml`'s `debug:` vs `release:` settings). To create it on a new machine:

```sh
TMPDIR=$(mktemp -d)
openssl req -x509 -newkey rsa:2048 -keyout "$TMPDIR/argus-codesign.key" -out "$TMPDIR/argus-codesign.crt" \
  -days 3650 -nodes -subj "/CN=Argus Local Dev" \
  -addext "extendedKeyUsage=codeSigning" -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature"
security import "$TMPDIR/argus-codesign.key" -k ~/Library/Keychains/login.keychain-db -A
security import "$TMPDIR/argus-codesign.crt" -k ~/Library/Keychains/login.keychain-db -A
security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db "$TMPDIR/argus-codesign.crt"
rm -rf "$TMPDIR"
```

Also grant Argus **Full Disk Access** in System Settings → Privacy & Security — Argus hosts an
arbitrary shell like Terminal.app/iTerm2, so macOS expects that grant rather than per-folder consent.

## Module layout

```
Packages/
  ArgusCore/        local SPM package (macOS 14+, Swift 6) — testable logic, no AppKit/SwiftUI
    ArgusSupport/     Foundation only — ProcessRunner, LoginShell, JSONLTailer, PollingTask,
                       TmuxSessionName, CanvasLayout
    ArgusConfigKit/   Foundation only — ArgusConfig struct, ArgusConfigStore, AgentSelection/
                       WindowLayout/PaneRole enums, LeaderKey, PaneLayoutResolver
    AgentStateKit/    Foundation only — agent state enum, IPC bus, hook manager,
                       ClaudeSettingsPatcher, CodexSessionParser
    Workspaces/       Foundation only — git repo/worktree scanning and store,
                       WorktreeListParser, RepoScanner, RepoOrdering
    Monitors/         Foundation only — PR categorization/highlighting, disk cleanup
                       filter/sort, tmux pane parsing
  DiffReviewKit/     SPM package (macOS 14+, Swift 6) — side-by-side diff review UI + headless agent runner
Sources/
  GhosttyBridge/     GhosttyKit (C lib) + Foundation — PTY, terminal surface, URL-open
App/
  ShellStateBus.swift  Shell-busy tracking (fish hooks / tmux fallback), feeds the sidebar border
  Views/             SwiftUI + AppKit — all UI (sidebar, panes, monitors, popups, diff review host)
  ArgusApp.swift     NSApplicationDelegate, leader-key monitor, top-level wiring
```

Cross-module import rule: only `App/` imports everything; other modules may only import siblings listed in CONVENTIONS.md. `Packages/ArgusCore` and `Packages/DiffReviewKit` are local SPM packages embedded via Xcode's local package dependency. `DiffReviewKit` doesn't import any other module — `App/` wires it up (agent selection, worktree path) from the outside. `ArgusCore`'s five targets have their own internal graph — `ArgusConfigKit`/`AgentStateKit`/`Workspaces`/`Monitors` each depend only on `ArgusSupport`, with no edges between those four — so `swift test` in `Packages/ArgusCore` runs in seconds with no GhosttyKit/AppKit/SwiftUI in the build graph at all.

## Agent state system

Claude Code state is inferred by polling the session transcript JSONL files Claude Code writes
unconditionally under `~/.claude/projects/*/*.jsonl` (`ClaudeTranscriptWatcher`, 500ms poll,
`Packages/ArgusCore/Sources/AgentStateKit/ClaudeTranscriptWatcher.swift` +
`ClaudeTranscriptParser.swift`) — the same no-hook-trust approach `CodexSessionWatcher` already
used for Codex. One hook remains: `PermissionRequest`, because nothing is written to the transcript
while a permission dialog is open. Both feed `AgentStateBus.apply(_:)`.

### States (`Packages/ArgusCore/Sources/AgentStateKit/AgentState.swift`)

| State | Meaning | Visual |
|---|---|---|
| `idle` | No agent activity | No indicator |
| `running` | Agent is executing | Pulsing peach dot + border |
| `waitingForApproval` | Agent blocked on permission dialog | Orange dot + thick orange border |
| `done` | Agent stopped, awaiting user reply | Green dot + green border |

`done` and `waitingForApproval` borders dismiss when the user interacts with the workspace (click or keypress). `waitingForApproval` also clears automatically when the agent resumes.

### Transcript → state inference (`ClaudeTranscriptParser.inferState`)

| Transcript signal | State |
|---|---|
| A `user`-type entry (a real prompt, or a tool_result) | `running` |
| `assistant` entry with `stop_reason` `end_turn`/`stop_sequence` | `done` |
| The synthetic `[Request interrupted by user…]` entry Claude Code writes on Escape | `idle` |
| Transcript untouched for 5 minutes (crash, `kill -9`, or a normal `/exit` — no hook covers either) | `idle` |

`assistant` entries with `stop_reason: tool_use` (or unset — a message still being generated) are
deliberately **not** decisive. Every content block of one assistant message — thinking, text,
tool_use — is written with the same final `stop_reason` already attached, all at once, once the
whole message resolves. So a freshly-written `stop_reason: tool_use` line lands at exactly the
instant a permission check may or may not happen, indistinguishable from "already executing, no
approval needed" purely from the transcript. Treating it as `running` would race the
`PermissionRequest` hook and could silently clobber `waitingForApproval` back to `running` while the
dialog is still open — so the watcher stays quiet on that line instead, and the next unambiguous
`tool_result` re-asserts `running` once the ambiguity resolves.

### IPC path (PermissionRequest only)

The one remaining hook script lives at `~/Library/Application Support/argus/hooks/claude-waiting-approval.sh`, written once on first pane open. It appends JSON lines to `/private/tmp/argus-$UID-hook-events.jsonl` (`HookIPC.eventLogPath`) because sandboxed Codex hook processes cannot connect to Argus's Unix socket. Argus still opens `/private/tmp/argus-$UID-hook.sock` (`HookIPC.socketPath`) for best-effort direct IPC.

`WorktreeHookManager.install(worktreePath:)` is idempotent: it overwrites the script, removes the eight scripts an older Argus version wrote for events now inferred from the transcript, and delegates the `.claude/settings.local.json` merge to `ClaudeSettingsPatcher`, which upserts the PermissionRequest entry and prunes those eight retired events without disturbing other hook entries. That file is gitignored.

## Window layout & pane pool

`WindowLayout` (`Packages/ArgusCore/Sources/ArgusConfigKit/ArgusConfig.swift`, config key `layout`) selects one of three per-app layouts, rendered by `App/Views/WorktreeContentView.swift`: `terminalAgent` (single agent + terminal, `AgentSelection` picks Claude or Codex), `agentsOverTerminal` (Codex + Claude side by side on top, terminal full-width below, 70/30 split via `RatioVSplitView`), and `terminalClaudeCodex` (three columns: terminal, Claude, Codex).

`App/Views/PanePool.swift` owns all three `TerminalHost`s (shell/claude/codex). Which roles a layout actually needs is decided by `PaneLayoutResolver.requiredRoles(layout:agent:)` (`Packages/ArgusCore/Sources/ArgusConfigKit/PaneLayoutResolver.swift`) — the Codex terminal/session is not spun up unless a layout requires it, so switching into `terminalAgent` with Claude selected never launches Codex. `PaneLayoutResolver.primaryAgentRole(layout:agent:)` determines which agent session the canvas view and `reloadAgentPane` (leader `a`) target.

## Diff review

`Packages/DiffReviewKit` (a local SPM package) provides a side-by-side diff review UI with PR-style inline comments; `App/Views/DiffReviewWindow.swift` hosts it as a floating popup (95% of the screen) opened via leader `w` or the toolbar's "Review diff" button (`.openDiffReview`), one window per worktree.

It always uses the app's single global `AgentSelection` (`.claude`/`.codex`) — there is no per-worktree agent override. Each comment's **Reply** (read-only) and **Apply** (edits + refreshes the diff) button spawns an **independent headless** `$SHELL -l -c` process (`claude -p --output-format stream-json` / `codex exec --json`) — it never attaches to, or shares context with, a live interactive agent pane. A per-comment session id (from the CLI's own stream output) is kept in memory so a follow-up Reply/Apply on the *same* comment resumes that thread; all of this state — comments, replies, session ids — lives only in `DiffReviewModel` and is discarded when the review window closes (no disk persistence).

Package layout: `Agent/` (`AgentRunner` spawns/streams the CLI, `DiffReviewAgent` picks the CLI + env, `PromptComposer` builds the per-comment prompt), `Git/` (git exec, diff, revision resolution), `Model/` (parsed diff, review comments, size/test classification, intraline diff), `Syntax/` (highlighting), `UI/` (`DiffReviewView` is the public entry point).

## Shell-busy detection

`App/ShellStateBus.swift` publishes the set of worktree paths whose shell pane has a foreground command running, which drives an animated sidebar border (`App/Views/SidebarComponents.swift`, accent-tinted when the row is selected). This is independent of the Claude/agent hook system above.

- **Fish login shells (preferred):** `WorktreeHookManager.installFishHooksIfNeeded()` writes `~/.config/fish/conf.d/argus.fish`, registering `fish_preexec`/`fish_postexec` hooks that append JSON lines to `HookIPC.shellEventLogPath` (`/private/tmp/argus-$UID-shell-events.jsonl`); `ShellStateBus` tails that file every 200ms.
- **Non-fish fallback:** polls `tmux list-panes -a` every 400ms, marking a worktree busy when its shell pane's current command isn't a known shell name.

## Sidebar monitors

- **GitHub PR monitor** (`App/Views/PRMonitorStore.swift`, `PRMonitorView.swift`): fetches via the GitHub REST API directly (`URLSession` + bearer token), not the `gh` CLI. Configured on the Settings → GitHub page (`apiBaseURL`, `token`, `refreshIntervalSeconds`). Groups PRs into My Open / My Drafts / Assigned / a collapsed "Do Not Merge" section; highlights PRs whose approvals changed since the last poll; grays out approved/draft PRs.
- **Disk space monitor** (`App/Views/DiskMonitorStore.swift`, `DiskCleanupScanner.swift`, `DiskStatusView.swift`, `DiskStatusWindow.swift`): opened via leader `d` or a low-disk banner. Shows a free-space gauge and cleanup candidates (Xcode DerivedData, package manager caches, workspace git repos, `~/Library` subdirectories, …) sized via `du -sk` at concurrency 4, sortable by name/size with a size filter. Config block `diskMonitor` (`checkIntervalSeconds`, `alertThresholdPercent`, `sizeCheckIntervalSeconds`).

## Key files

| File | Role |
|---|---|
| `App/ArgusApp.swift` | App entry, keyboard leader, canvas overlay |
| `App/Views/AppShellView.swift` | Main split layout, agent state border/tint |
| `App/Views/SidebarView.swift` | Repo/worktree list, `AgentDot`, drag reorder |
| `App/Views/WorktreeContentView.swift` | Per-worktree layout (terminal/agent panes per `WindowLayout`) |
| `App/Views/PanePool.swift` | Owns shell/claude/codex `TerminalHost`s; lazy per-layout role registration |
| `App/Views/PopupTerminalWindow.swift` | User-defined popup terminal windows (key/command/size), incl. lazygit default |
| `App/Views/NvimWindow.swift` | nvim popup with tmux-persisted session |
| `App/Views/MarkdownPreviewWindow.swift` | Markdown preview popup (⌘F search, local images, file tree) |
| `App/Views/DiffReviewWindow.swift` | Floating diff-review popup host (one per worktree) |
| `App/Views/PRMonitorStore.swift` / `PRMonitorView.swift` | GitHub PR fetch/categorize + sidebar section |
| `App/Views/DiskMonitorStore.swift` / `DiskCleanupScanner.swift` / `DiskStatusWindow.swift` | Disk space poll, cleanup candidate scan, popup host |
| `App/Views/SettingsWindow.swift` | Settings UI — Agent page (agent picker + commands) and GitHub/Environment pages |
| `App/Views/KeyboardSettingsView.swift` | Settings UI — Keyboard page (key bindings + popup terminal shortcuts editor) |
| `App/ShellStateBus.swift` | Shell-busy tracking (fish hooks / tmux fallback) → sidebar border |
| `Packages/ArgusCore/Sources/AgentStateKit/AgentStateBus.swift` | `@MainActor` ObservableObject; owns the socket/JSONL hook reader, `CodexSessionWatcher`, and `ClaudeTranscriptWatcher` |
| `Packages/ArgusCore/Sources/AgentStateKit/ClaudeTranscriptWatcher.swift` / `ClaudeTranscriptParser.swift` | Polls `~/.claude/projects/*/*.jsonl` to infer running/done/interrupted-idle/stale-idle without hooks |
| `Packages/ArgusCore/Sources/AgentStateKit/WorktreeHookManager.swift` | Writes the one remaining hook script (PermissionRequest); delegates the settings.local.json merge to `ClaudeSettingsPatcher` |
| `Packages/ArgusCore/Sources/ArgusConfigKit/ArgusConfig.swift` | `ArgusConfig` struct, `ArgusConfigStore`, `AgentSelection`/`WindowLayout` enums, `github`/`diskMonitor`/`environmentVariables`/`popupShortcuts` config blocks; persistence itself is `ArgusConfigFile.swift` (`~/.config/argus/argus.json`) |
| `Packages/ArgusCore/Sources/Workspaces/WorkspaceStore.swift` | Repo/worktree scanning orchestrator; parsing (`WorktreeListParser`) and discovery (`RepoScanner`) are separate testable files in the same target |
| `Packages/ArgusCore/Package.swift` | ArgusCore's five targets + their internal dependency graph — edit this to add a file to a new target |
| `Sources/GhosttyBridge/WorktreePane.swift` | ghostty surface lifecycle per pane |
| `Sources/GhosttyBridge/TerminalViewState+URLOpen.swift` | Cmd+click terminal links → open in browser |
| `Packages/DiffReviewKit/Sources/DiffReviewKit/DiffReviewModel.swift` | Diff-review state owner + agent-run orchestration |
| `Packages/DiffReviewKit/Sources/DiffReviewKit/Agent/AgentRunner.swift` | Spawns headless Claude/Codex CLI, streams stream-json |
| `project.yml` | XcodeGen project definition — edit this, not the `.xcodeproj` |

## Conventions

See [CONVENTIONS.md](CONVENTIONS.md) for Swift style, concurrency, and error handling rules.

See [UI.md](UI.md) for how the view hierarchy maps to source files.

Commit format: `type: brief description` (Conventional Commits, lowercase imperative, ≤ 72 chars). See `.claude/skills/commit/`.
