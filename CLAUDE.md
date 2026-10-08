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
    ArgusSupport/     Foundation only — ProcessRunner, LoginShell, JSONLCursor/JSONLTailer,
                       PollingTask, TmuxSessionName, ShellQuote, TmuxCommand, ArgusURLRequest,
                       CorruptFileBackup
    ArgusConfigKit/   Foundation only — ArgusConfig struct, ArgusConfigStore, AgentSelection/
                       WindowLayout/PaneRole/AgentPaneMode enums, AgentTabs, LeaderKey,
                       PaneLayoutResolver
    AgentStateKit/    Foundation only — AgentState/AgentType/AgentKey, WorktreeAgentState
                       aggregate, IPC bus, hook manager, ClaudeSettingsPatcher, CodexSessionParser
    Workspaces/       Foundation only — git repo/worktree scanning and store,
                       WorktreeListParser, RepoScanner, RepoOrdering
    Monitors/         Foundation only — GitHubClient + PR categorization/highlighting, disk cleanup
                       catalog/filter/sort, Codex usage summary, tmux pane parsing
  DiffReviewKit/     SPM package (macOS 14+, Swift 6) — side-by-side diff review UI + headless agent runner
Sources/
  GhosttyBridge/     libghostty-spm (GhosttyTerminal) + Foundation — PTY, terminal surface, URL-open
App/
  ShellStateBus.swift  Shell-busy tracking (fish hooks / tmux fallback), feeds the sidebar border
  Views/             SwiftUI + AppKit — all UI (sidebar, panes, monitors, popups, diff review host)
  ArgusApp.swift     NSApplicationDelegate, leader-key monitor, top-level wiring
```

Cross-module import rule: only `App/` imports everything; other modules may only import siblings listed in CONVENTIONS.md. `Packages/ArgusCore` and `Packages/DiffReviewKit` are local SPM packages embedded via Xcode's local package dependency. `DiffReviewKit` doesn't import any other module — `App/` wires it up (agent selection, worktree path) from the outside. `ArgusCore`'s five targets have their own internal graph — `ArgusConfigKit`/`AgentStateKit`/`Workspaces`/`Monitors` each depend only on `ArgusSupport`, with no edges between those four — so `swift test` in `Packages/ArgusCore` runs in seconds with no libghostty/AppKit/SwiftUI in the build graph at all.

## Agent state system

The sidebar's per-agent indicator is fed by three sources of differing trust, arbitrated by
`AgentStateBus` via `StateSource` (`Packages/ArgusCore/Sources/AgentStateKit/AgentStateBus.swift`):

1. **`.display`** (primary, for any pane Argus itself hosts) — `AgentPaneDisplayWatcher` (App/,
   `App/AgentPaneDisplayWatcher.swift`) polls every live Claude/Codex tmux pane once a second and
   scrapes what the TUI actually renders via a single batched `tmux capture-pane` call (pure
   batching/parsing logic in `Packages/ArgusCore/Sources/Monitors/TmuxPaneCaptureBatch.swift`,
   text-to-signal classification in `AgentPaneDisplayParser.swift`). Because this reads a
   continuously-re-asserted signal rather than inferring liveness from a timeout, it is immune to
   the false-idle failure mode described below: a single tool call or a `Task` subagent run lasting
   longer than 15 minutes (both observed live) no longer demotes a genuinely busy agent to idle.
   `AgentPaneDisplayWatcher` lives in App/, not AgentStateKit, because it needs
   `Tmux.executable`/`WorktreePane.sessionName(for:path:)` from GhosttyBridge, which AgentStateKit
   cannot import.
2. **`.inference`** (fallback) — the transcript/rollout polling described below, for a worktree with
   no live Argus-hosted agent pane (an agent started in an external terminal, or a tab not yet
   opened). `AgentStateBus.setDisplayCovered(_:)`, republished every `.display` poll, is what
   suppresses `.inference` payloads for any key `.display` currently covers, so the two sources
   never race for the same key.
3. **`.hook`** — `PermissionRequest`, never suppressed (see below).

An agent pane's on-screen text is matched against a small built-in regex vocabulary
(`AgentPaneDisplayParser.Patterns`) — verified live against real Claude Code/Codex panes, not
hand-written approximations — with a config escape hatch (`ArgusConfig.agentDisplayPatterns`) for
working around a future CLI wording change without an app release. The parser is deliberately
conservative: no pattern match means `nil` (indeterminate — the caller keeps whatever state is
already published), and idle is only ever inferred from a *positive* signal (no agent chrome on
screen at all, or the tmux session disappearing), never from the mere absence of a running marker —
a live pane blocked on a background subagent shows text ("Waiting for N background agent(s) to
finish") that matches neither `running` nor `finished`, and must not be misread as either. Both
CLIs' `running`/`finished` patterns learned this the hard way from live false positives: Claude's are
anchored to a line that *starts* with one of its four spinner glyphs (`(?m)^\s*[✻✽✶✳]`) after
ordinary quoted scrollback text like "Worked for 3m 37s" once matched a bare `finished` pattern
anywhere in the pane; Codex's are anchored to the same dot-delimited `· Working ·`/`· Thinking ·`
status-line slot after bare-word matches on "Working"/"Reviewing" once fired on unrelated scrollback
("Working tree is clean.", a directory-trust prompt, "Reviewing approval request").

Each poll's raw signal is reduced through `AgentPaneSignalReducer` (pure, unit-testable, one
`KeyState` per `AgentKey`) before ever reaching `AgentStateBus.apply` — without it, the watcher would
re-publish on every poll a decisive signal is found, including polls where nothing actually changed.
Claude's on-screen "finished" marker persists unchanged until the *next* turn starts, so re-asserting
`.done` every second would stomp right back over a user's dismissal within one poll interval; the
reducer's own `lastEmitted` memory (deliberately independent of what `AgentStateBus` currently
publishes, since dismissal is meant to be free to diverge from it) only lets a *change* through. The
same reducer also latches Codex's ambiguous `ready` signal (shown both before the first turn and
after one finishes) via `hasRunSinceObserved`, and debounces a `waitingForApproval` downgrade for two
consecutive non-approval polls — collapsing what a pane merely *doesn't* show right this instant is
the recurring hazard here, not just `finished`'s persistence, hence one shared reducer rather than
three ad hoc special cases. Relatedly, a poll bails out and retries rather than treating a failed
`tmux list-panes` launch/exit (e.g. around system sleep/wake) as "zero live sessions": feeding that
empty output through as a real signal would force-idle and wipe every key's reducer memory, and the
next successful poll would then read the same still-on-screen marker against fresh memory as a
brand-new signal — a periodic idle-then-done flicker with nothing having actually happened.

Claude Code state is *additionally* inferred by polling the session transcript JSONL files Claude
Code writes unconditionally under `~/.claude/projects/*/*.jsonl` (`ClaudeTranscriptWatcher`, 500ms
poll, `Packages/ArgusCore/Sources/AgentStateKit/ClaudeTranscriptWatcher.swift` +
`ClaudeTranscriptParser.swift`) — the same no-hook-trust approach `CodexSessionWatcher` already
used for Codex, and still the only source for a worktree `.display` doesn't cover. This path has its
own false-idle fix: `ClaudeTranscriptWatcher` also tracks each session's `Task`-subagent sidechain
transcripts (`<project>/<sessionId>/subagents/*.jsonl`) purely for liveness — never state — so a
subagent run that keeps the *parent* transcript silent for longer than the 15-minute staleness
window no longer ages a genuinely-running parent observation out of it (see
`ClaudeTranscriptWatcher.applySidechainLiveness`). One hook remains: `PermissionRequest`, because
nothing is written to the transcript while a permission dialog is open. All three sources feed
`AgentStateBus.apply(_:source:)`.

`AgentStateBus` tracks state per **(worktree, agent)** — `states: [AgentKey: AgentState]` — because
Claude and Codex can each have an open agent tab at once (see Window layout & pane pool below) and
each tab's chip needs its own indicator. `state(for:agent:)` reads one agent's state;
`worktreeState(for:)` collapses both into the single `WorktreeAgentState` a worktree-level indicator
(sidebar dot/row, window tint) shows, via `WorktreeAgentState.aggregate` — highest
`AgentState.displayPriority` wins (`waitingForApproval > done > running > idle`), ties resolve to
Claude. `reset(for:)` clears every agent for a worktree (panes released); `reset(for:agent:)` clears
one (a specific tmux session was killed); `dismissAttentionStates(for:)` is the "user interacted,
clear the border" path and deliberately downgrades only `.done`/`.waitingForApproval`, never a
concurrently `.running` agent.

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
| No transcript entry newer than 15 minutes (crash, `kill -9`, or a normal `/exit` — no hook covers either) | `idle` |

Liveness is judged by the newest **in-file** entry `timestamp`, not the transcript file's mtime —
Claude Code rewrites transcripts in place without appending, so mtime alone can be hours or days
newer than the session's actual last activity and would otherwise resurrect a long-finished
session's final `stop_reason` as if it had just happened. `ClaudeTranscriptParser.scan(tail:)`
returns both the decisive state and this activity timestamp from the same read; a worktree with
several transcripts bound to it (multiple sessions, or a headless diff-review run sharing the same
cwd — excluded outright via its `entrypoint: "sdk-cli"` marker) resolves to whichever one has the
most recent in-file activity, via `SessionActivityArbiter`.

`assistant` entries with `stop_reason: tool_use` (or unset — a message still being generated) are
deliberately **not** decisive. Every content block of one assistant message — thinking, text,
tool_use — is written with the same final `stop_reason` already attached, all at once, once the
whole message resolves. So a freshly-written `stop_reason: tool_use` line lands at exactly the
instant a permission check may or may not happen, indistinguishable from "already executing, no
approval needed" purely from the transcript. Treating it as `running` would race the
`PermissionRequest` hook and could silently clobber `waitingForApproval` back to `running` while the
dialog is still open — so the watcher stays quiet on that line instead, and the next unambiguous
`tool_result` re-asserts `running` once the ambiguity resolves.

### Codex session inference (`CodexSessionWatcher` + `CodexSessionParser`)

Codex state is inferred the same way, polling `~/.codex/sessions/<year>/<month>/<day>/*.jsonl`
(today + yesterday only) every 500ms and reading each session's `event_msg.payload.type`:

| `payload.type` | State |
|---|---|
| `task_started` / `turn_started` | `running` |
| `task_complete` / `turn_complete` | `done` |
| `turn_aborted` (Codex's Esc-abort) | `idle` — aligned with Claude's interrupt-to-idle behavior |
| `exec_approval_request` / `apply_patch_approval_request` / `request_user_input` / `elicitation_request` | `waitingForApproval` |
| Session file untouched for 15 minutes | `idle`, same rationale/timeout as Claude |

Unlike Claude's transcripts, a Codex rollout's mtime IS a trustworthy activity signal on its own —
Codex appends and never rewrites a rollout file in place — so liveness here still keys off mtime
directly rather than an in-file timestamp. Multiple rollouts sharing a cwd (a resumed session plus
a newly started one) are resolved the same way as Claude's, via `SessionActivityArbiter`.

The `waitingForApproval` mapping is transcript-inferred and **unverified** — this codebase's Codex
projects are all `trust_level = "trusted"`, so no approval prompt has ever been observed in a real
rollout file; the event names come from Codex's `EventMsg` enum, recovered from the binary. Unlike
Claude's, there is no Codex hook backing this state. Codex also has a `.codex/hooks/hooks.json`
`PermissionRequest` hook available (Claude-compatible shape) as a fallback if the transcript route
turns out not to persist these events.

Codex writes one rollout file per **subagent** as well as the top-level session, all sharing the
parent's `cwd`. `CodexSessionWatcher` reads each file's `thread_source` from its `session_meta`
header and skips any file where it's `"subagent"` — only the top-level thread drives worktree state,
otherwise every subagent spawn/finish would flap the sidebar dot.

### IPC path (PermissionRequest only)

The one remaining hook script lives at `~/Library/Application Support/argus/hooks/claude-waiting-approval.sh`, written once on first pane open. It appends JSON lines to `/private/tmp/argus-$UID-hook-events.jsonl` (`HookIPC.eventLogPath`) because sandboxed Codex hook processes cannot connect to Argus's Unix socket. Argus still opens `/private/tmp/argus-$UID-hook.sock` (`HookIPC.socketPath`) for best-effort direct IPC.

`WorktreeHookManager.install(worktreePath:)` is idempotent: it overwrites the script, removes the eight scripts an older Argus version wrote for events now inferred from the transcript, and delegates the `.claude/settings.local.json` merge to `ClaudeSettingsPatcher`, which upserts the PermissionRequest entry and prunes those eight retired events without disturbing other hook entries. That file is gitignored.

## Window layout & pane pool

`WindowLayout` (`Packages/ArgusCore/Sources/ArgusConfigKit/ArgusConfig.swift`, config key `layout`) selects one of two per-app layouts, rendered by `App/Views/WorktreeContentView.swift`: `terminalAgent` (terminal | agent view) and `agentsOverTerminal` (agent view / full-width terminal below, 70/30 split via `RatioVSplitView`). There is no longer a "show both agents" layout — that is now the agent view's own display mode (see below), available in both layouts.

The agent view (`App/Views/AgentPaneView.swift`) is a single pane holding up to two **agent tabs** — Claude and Codex — with its own tab bar (`App/Views/AgentTabBarView.swift`). Only the default agent has a tab when a worktree is first selected; the other opens on demand (`+` chip, or leader `t` while the agent pane has focus). That default is `config.agent` unless the worktree's repo has a per-project override — set from the sidebar repo header's context menu, persisted in `ArgusConfig.projectAgents` (keyed by repo `mainPath`) and resolved via `ArgusConfig.agent(forProjectPath:)` — in which case the override wins; switching a project's override has no effect on a worktree already seeded, same as changing `config.agent` itself. `AgentTabsStore` (`App/Views/AgentTabsStore.swift`) owns each worktree's open/active tabs (`ArgusConfigKit.AgentTabs`) and the app-global **display mode** (`ArgusConfigKit.AgentPaneMode`, persisted): `full` shows only the active tab; `split` shows every open tab side by side (Claude left, Codex right), toggled by the toolbar button or leader `s`. Unlike the terminal tab bar below, agent tabs are **not** a tmux mirror — `AgentTabsStore` is the source of truth, and `PanePool` role registration is its projection.

`App/Views/PanePool.swift` owns all three `TerminalHost`s (shell/claude/codex). `PaneLayoutResolver.requiredRoles(tabs:)` (`Packages/ArgusCore/Sources/ArgusConfigKit/PaneLayoutResolver.swift`) returns every role a worktree's *open* agent tabs need, visible or not — a hidden tab keeps its agent running, like a background tmux window — so the Codex session is never spun up until its tab is opened. `PaneLayoutResolver.visibleAgentRoles(tabs:mode:)` is what the agent view actually renders. There is no more "primary agent role" concept: leader `a` (`reloadAgentPane`) targets whichever tab is **active**. Closing an agent tab (`AgentTabsStore.closeTab`) kills that agent's tmux session outright — like the terminal tab bar's `kill-window` — so reopening it starts a fresh `claude --continue` / `codex resume` rather than re-attaching; relaunching Argus, by contrast, re-attaches a still-running session because `tmux new-session -A` ignores the launch command on an existing session.

`PanePool.closeRole`/`reloadAgentPanes` always kill a role's tmux session *before* releasing its
cached `AppTerminalView` (`WorktreePane.discardView`), never after: releasing a pane's last strong
reference synchronously tears down its native ghostty surface on the main thread, joining that
surface's IO threads. If the tmux client is still alive in that pane's pty at that moment, that join
can hang indefinitely — observed live as an 80+ second app freeze on tab close. Killing the session
first lets the pty's child process exit and its IO threads unblock before teardown ever has to wait
on them.

### Terminal tabs and agent tabs

The shell pane's tmux session (`WorktreePane`'s `.shell` role) runs with `status off`, so its windows are otherwise invisible; `App/Views/TerminalTabBarView.swift` renders them as a tab bar above the shell `TerminalHostView` in every layout, sourced from `App/Views/TerminalTabsStore.swift`. One tmux window = one tab, nothing more — the store is a control surface and mirror over tmux (`list-windows`/`select-window`/`new-window`/`kill-window`), never a second source of truth, so a window opened from inside tmux (`ctrl-b ctrl-b c`) appears on the next poll same as one Argus creates. Tab labels are the current directory's folder name (`TmuxWindow.label` in `Packages/ArgusCore/Sources/Monitors/TmuxWindowParser.swift`, derived from `#{pane_current_path}`), not a process name, and are not renameable. A new tab replays the same `EnvExportPreamble` + `LoginShell` command tab 0 uses so its environment matches.

Leader `t`/`]`/`[`/`x` are **context-sensitive on the focused pane** (`App/Views/AppShellView+TabBindings.swift`): on the shell pane they create/next/prev/close a tmux window as above; on the agent pane they open the other agent's tab, cycle between open tabs, and close the active tab (refused on the last one) instead. Leader `s` toggles the agent view's full/split display mode.

## Diff review

`Packages/DiffReviewKit` (a local SPM package) provides a side-by-side diff review UI with PR-style inline comments; `App/Views/DiffReviewWindow.swift` hosts it as a floating popup (95% of the screen) opened via leader `w` or the toolbar's "Review diff" button (`.openDiffReview`), one window per worktree.

It uses the same `AgentSelection` (`.claude`/`.codex`) resolution as a newly selected worktree's default tab — `config.agent`, or the worktree's repo's `ArgusConfig.projectAgents` override if one is set — unaffected by which agent tabs the worktree happens to have open; there is no separate per-worktree diff-review agent. Each comment's **Reply** (read-only) and **Apply** (edits + refreshes the diff) button spawns an **independent headless** `$SHELL -l -c` process (`claude -p --output-format stream-json` / `codex exec --json`) — it never attaches to, or shares context with, a live interactive agent pane. A per-comment session id (from the CLI's own stream output) is kept in memory so a follow-up Reply/Apply on the *same* comment resumes that thread; all of this state — comments, replies, session ids — lives only in `DiffReviewModel` and is discarded when the review window closes (no disk persistence).

Package layout: `Agent/` (`AgentRunner` spawns/streams the CLI, `DiffReviewAgent` picks the CLI + env, `PromptComposer` builds the per-comment prompt), `Git/` (git exec, diff, revision resolution), `Model/` (parsed diff, review comments, size/test classification, intraline diff), `Syntax/` (highlighting), `UI/` (`DiffReviewView` is the public entry point).

## Shell-busy detection

`App/ShellStateBus.swift` publishes the set of worktree paths whose shell pane has a foreground command running, which drives an animated sidebar border (`App/Views/SidebarComponents.swift`, accent-tinted when the row is selected). This is independent of the Claude/agent hook system above.

- **Fish login shells (preferred):** `WorktreeHookManager.installFishHooksIfNeeded()` writes `~/.config/fish/conf.d/argus.fish`, registering `fish_preexec`/`fish_postexec` hooks that append JSON lines to `HookIPC.shellEventLogPath` (`/private/tmp/argus-$UID-shell-events.jsonl`); `ShellStateBus` tails that file every 200ms.
- **Non-fish fallback:** polls `tmux list-panes -a` every 400ms, marking a worktree busy when any pane in its shell session (there can be more than one — see Terminal tabs above) has a current command that isn't a known shell name.

## Sidebar monitors

- **GitHub PR monitor** (`App/Views/PRMonitorStore.swift`, `PRMonitorView.swift`): fetches via the GitHub REST API directly (`GitHubClient` in `Monitors`: `URLSession` + bearer token, injectable for tests; 100 results per search), not the `gh` CLI. A refresh is re-entrancy-guarded and re-resolves the username when the token or API base changes. Configured on the Settings → GitHub page (`apiBaseURL`, `token`, `refreshIntervalSeconds`). Groups PRs into My Open / My Drafts / Assigned / a collapsed "Do Not Merge" section; highlights PRs whose approvals changed since the last poll; grays out approved/draft PRs. Each row has a hover "hide" button (`PRHiddenList.hide`, `Monitors` target); a hidden PR's section header shows the hidden count and a reveal-all button (`PRHiddenList.reveal`) rather than dropping the header, so an all-hidden section stays recoverable. Hidden ids persist to `~/Library/Application Support/argus/hidden-prs.json` (`PRHiddenFile`) and are pruned against each successful fetch so merged/closed/unassigned PRs don't linger in the file.
- **Disk space monitor** (`App/Views/DiskMonitorStore.swift`, `DiskCleanupScanner.swift`, `DiskStatusView.swift`, `DiskStatusWindow.swift`): opened via leader `d` or a low-disk banner. Shows a free-space gauge and cleanup candidates (Xcode DerivedData, package manager caches, `~/Library/Caches|Logs|Developer/*`, workspace git repos) sized via `du -sk` at concurrency 4, sortable by name/size with a size filter. Discovery and the deletion rules live in `DiskCleanupCatalog` (`Monitors`): Remove Selected deletes only items that are selected *and* currently visible under the size filter *and* pass `isSafeToDelete` (strictly inside `$HOME`, not a protected folder, never a symlink); selection survives the background reload; git repos need a second, repo-naming confirmation. `~/.claude`/`~/.codex` are deliberately not offered. Config block `diskMonitor` (`checkIntervalSeconds`, `alertThresholdPercent`, `sizeCheckIntervalSeconds`).

## Codex usage monitor

The toolbar's Codex usage chip (`App/Views/AppShellView+Toolbar.swift`'s `codexUsageChip`, opened via
click or leader `u`) shows today's total Codex tokens and estimated USD cost; its popover
(`App/Views/CodexUsageView.swift`) breaks both down per model.

Codex writes no aggregate usage anywhere — no CLI subcommand, no sqlite table, nothing in
`config.toml`. The only signal is the `token_usage_record` line Codex appends to a session's
rollout JSONL (`~/.codex/sessions/<year>/<month>/<day>/*.jsonl`) after every API response; the
model name isn't on that line, only on the same turn's `turn_context` line, so
`CodexUsageParser.scanDaily` (`Packages/ArgusCore/Sources/Monitors/`) does a single pass collecting
both, then joins each usage record to its model by `turn_id` (falling back to `root_turn_id`, then
`unknownModel`) once the whole file has been seen — correct regardless of line order, unlike relying
on `turn_context` always preceding its records (true in every rollout observed locally, but not
guaranteed). `CodexUsageStore` (App/) polls this on a `PollingTask` timer, caching each file's parsed
per-day totals by `(mtime, size)` so only actively-growing files are re-parsed.

Unlike `CodexSessionWatcher` (which excludes `thread_source: "subagent"` rollouts so a subagent
spawn/finish doesn't flap the sidebar's *state* dot), the usage scan **includes** subagent rollouts —
they cost real tokens, and usage is additive rather than a single state pick. The scan also looks
back `codexUsage.scanDayWindow` days (default 7), not just today's directory: `codex resume` keeps
appending to a session's *original* day's rollout file indefinitely, so a session resumed days past
its creation would otherwise vanish from every subsequent day's total. "Today" itself is decided
per-record from its own `timestamp` (UTC) against the local calendar, not from which day-directory a
file lives in or its mtime — a single rollout can span several calendar days once resumed.

Because Codex records no pricing data, USD cost is entirely user-supplied on the Settings → Usage
page (`App/Views/UsageSettingsView.swift`): a price per model is USD per 1M tokens, split into four
rates — fresh input, cached-read input, cache-write input, and output (`CodexUsageCost.cost`).
`usage.input_tokens` already includes both `cached_input_tokens` (a cache hit) and
`cache_write_input_tokens` (a subset of the uncached remainder — writing a prefix to cache for later
reuse is itself billed, typically at a premium over the plain input rate); `CodexTokenUsage
.freshInputTokens` is what's left of `input_tokens` after removing both, so each input token is
billed at exactly one of the three input rates, never two. A model with no price set shows `—`, not
a misleading `$0.00`, both in the chip and in the popover's per-row breakdown.

## Key files

| File | Role |
|---|---|
| `App/ArgusApp.swift` | App entry, keyboard leader |
| `App/Views/AppShellView.swift` | Main split layout, agent state border/tint |
| `App/Views/SidebarView.swift` | Repo/worktree list, `AgentDot`, drag reorder |
| `App/Views/WorktreeContentView.swift` | Per-worktree layout (terminal pane + agent view per `WindowLayout`) |
| `App/Views/AgentPaneView.swift` | The agent view: tab bar + one (full) or two (split) agent `TerminalHost`s |
| `App/Views/AgentTabBarView.swift` | Tab bar UI above the agent view, one chip per open agent tab |
| `App/Views/AgentTabsStore.swift` | Per-worktree open/active agent tabs + the app-global full/split display mode; drives `PanePool` role registration (not a tmux mirror) |
| `Packages/ArgusCore/Sources/ArgusConfigKit/PaneLayoutResolver.swift` | Pure rules: required/visible/ordered pane roles for a worktree's open agent tabs + display mode |
| `App/Views/PanePool.swift` | Owns shell/claude/codex `TerminalHost`s; role registration driven by the open agent tabs |
| `App/Views/TerminalTabsStore.swift` | Polls the selected worktree's shell tmux session's windows; issues select/new/close tmux commands |
| `App/Views/TerminalTabBarView.swift` | Tab bar UI above the shell pane, one tab per tmux window |
| `Packages/ArgusCore/Sources/ArgusConfigKit/LeaderActionCatalog.swift` | Pure: `LeaderAction` enum + `LeaderActionCatalog.entries/target(forKey:)` — the one table leader dispatch, the which-key HUD and the command palette all read; `App/LeaderAction+Notification.swift` maps each action to its `Notification.Name` |
| `App/LeaderModeState.swift` / `App/Views/LeaderHUDView.swift` | Leader-pending state driven by `AppDelegate`'s key monitor, and the which-key overlay shown ~300 ms after the leader press |
| `App/Views/CommandPaletteView.swift` | ⌘K / leader `/` palette: fuzzy-switch worktrees or run any leader action/popup by name (`PaletteItem` built in `AppShellView.paletteItems`) |
| `Packages/ArgusCore/Sources/ArgusSupport/FuzzyMatcher.swift` | Pure: case-insensitive subsequence scoring/ranking shared by the palette and sidebar filter |
| `Packages/ArgusCore/Sources/Workspaces/SidebarFilter.swift` | Pure: narrows repos/worktrees by query and/or an attention-ID set; `WorktreeNavigator.nextAttention` backs leader `e` (jump to waiting/done agent) |
| `App/Views/AppShellView+TabBindings.swift` | Routes new/next/previous/close-tab and split-toggle leader keys to the terminal or agent tab store based on focused pane (next/previous tab ship with no default key) |
| `App/Views/AppShellView+TmuxPaneBindings.swift` | Routes leader `h`/`j`/`k`/`l` to a literal `tmux select-pane -L/-D/-U/-R` against the focused role's tmux session |
| `Packages/ArgusCore/Sources/Monitors/TmuxWindowParser.swift` | Parses `tmux list-windows` output into `TmuxWindow` (folder-name label from `pane_current_path`) |
| `App/Views/PopupTerminalWindow.swift` | User-defined popup terminal windows (key/command/size), incl. lazygit default |
| `App/Views/NvimWindow.swift` | nvim popup with tmux-persisted session |
| `App/Views/MarkdownPreviewWindow.swift` | Markdown preview popup (⌘F search, local images, file tree) |
| `App/Views/DiffReviewWindow.swift` | Floating diff-review popup host (one per worktree) |
| `App/Views/PRMonitorStore.swift` / `PRMonitorView.swift` | GitHub PR fetch/categorize + sidebar section |
| `Packages/ArgusCore/Sources/Monitors/PRHiddenList.swift` | Pure hide/reveal/prune/split logic over a set of hidden PR ids |
| `Packages/ArgusCore/Sources/Monitors/PRHiddenFile.swift` | hidden-prs.json read/write against an injectable URL |
| `App/Views/DiskMonitorStore.swift` / `DiskCleanupScanner.swift` / `DiskStatusWindow.swift` | Disk space poll, cleanup candidate scan, popup host |
| `App/Views/CodexUsageStore.swift` | Polls Codex rollout JSONL files, publishes today's per-model token usage for the toolbar chip |
| `App/Views/CodexUsageView.swift` | Toolbar chip's popover — per-model token/cost breakdown table |
| `App/Views/UsageSettingsView.swift` | Settings UI — Usage page (per-model USD prices, scan refresh interval/lookback window) |
| `Packages/ArgusCore/Sources/Monitors/CodexUsageParser.swift` | Pure: joins `token_usage_record` lines to their model via `turn_context`, buckets by local day |
| `Packages/ArgusCore/Sources/Monitors/CodexUsageCost.swift` | Pure: USD cost from token usage + per-model input/cached-input/output rates |
| `Packages/ArgusCore/Sources/ArgusSupport/CodexRolloutLocator.swift` | Pure: `~/.codex/sessions/<year>/<month>/<day>/` path math for a multi-day lookback window |
| `Packages/ArgusCore/Sources/ArgusSupport/JSONLCursor.swift` | Pure: offset + carry + truncation/rotation detection; yields only complete lines (used by `JSONLTailer` and `JSONLFileReader`) |
| `Packages/ArgusCore/Sources/ArgusSupport/ShellQuote.swift` / `TmuxCommand.swift` | Pure: POSIX single-quote escaping; tmux binary discovery (`ARGUS_TMUX`), `new-session -A` command line and argv builders, `listing(from:)` ("no server running" = empty listing). `Sources/GhosttyBridge/Tmux.swift` is the one runner |
| `Packages/ArgusCore/Sources/ArgusSupport/ArgusURLRequest.swift` | Pure: parses/validates `argus://diff` and `argus://capture` (capture output needs a `.png`/`.mov`/`.mp4` extension and may only replace a regular file) |
| `Packages/ArgusCore/Sources/ArgusSupport/JSONQuotedValue.swift` | Pure: escape-decoding `"key":"value"` scan for hot paths / truncated windows (cwd, entrypoint, timestamp) |
| `Packages/ArgusCore/Sources/Monitors/DiskCleanupCatalog.swift` / `GitHubClient.swift` / `CodexUsageSummary.swift` | Pure-ish: cleanup discovery + deletion safety rules; injectable GitHub REST client + PR models; today's per-model Codex cost summary shared by the chip and its popover |
| `Packages/ArgusCore/Sources/ArgusSupport/JSONLFileReader.swift` | Bounded-memory whole-file JSONL line reader (vs. `JSONLTailer`'s append-streaming) |
| `App/Views/SettingsWindow.swift` | Settings UI — Agent page (agent picker + commands) and GitHub/Environment pages |
| `App/Views/KeyboardSettingsView.swift` | Settings UI — Keyboard page (key bindings + popup terminal shortcuts editor) |
| `App/ShellStateBus.swift` | Shell-busy tracking (fish hooks / tmux fallback) → sidebar border |
| `App/AgentPaneDisplayWatcher.swift` | Polls every live Claude/Codex tmux pane Argus hosts, scrapes on-screen state via batched `tmux capture-pane`, feeds `AgentStateBus` as the primary `.display` source |
| `Packages/ArgusCore/Sources/AgentStateKit/AgentPaneDisplayParser.swift` | Pure: classifies one pane capture into running/finished/ready/awaitingApproval/noAgentUI, or `nil` if indeterminate |
| `Packages/ArgusCore/Sources/AgentStateKit/AgentPaneSignalReducer.swift` | Pure: per-key latch/debounce/dedup turning a poll's raw signal into at most one published state change |
| `Packages/ArgusCore/Sources/Monitors/TmuxPaneCaptureBatch.swift` | Pure: batches several tmux panes' `capture-pane` calls into one subprocess invocation, and splits the combined output back apart |
| `Packages/ArgusCore/Sources/AgentStateKit/AgentStateBus.swift` | `@MainActor` ObservableObject; per-(worktree, agent) state, owns the socket/JSONL hook reader, `CodexSessionWatcher`, and `ClaudeTranscriptWatcher`; arbitrates `.display`/`.inference`/`.hook` via `StateSource` |
| `Packages/ArgusCore/Sources/AgentStateKit/WorktreeAgentState.swift` | Pure aggregate: collapses a worktree's per-agent states into the single state/agent a sidebar dot or window tint shows |
| `Packages/ArgusCore/Sources/AgentStateKit/ClaudeTranscriptWatcher.swift` / `ClaudeTranscriptParser.swift` | Polls `~/.claude/projects/*/*.jsonl` (plus each session's `Task`-subagent sidechains, for liveness only) to infer running/done/interrupted-idle/stale-idle without hooks |
| `Packages/ArgusCore/Sources/AgentStateKit/SessionActivityArbiter.swift` | Pure per-cwd arbitration: resolves several transcripts/rollouts bound to one worktree to the single state (newest activity wins) that watcher polls publish |
| `Packages/ArgusCore/Sources/AgentStateKit/WorktreeHookManager.swift` | Writes the one remaining hook script (PermissionRequest); delegates the settings.local.json merge to `ClaudeSettingsPatcher` |
| `Packages/ArgusCore/Sources/ArgusConfigKit/ArgusConfig.swift` | `ArgusConfig` struct, `AgentSelection`/`WindowLayout` enums; nested blocks are split into `ArgusConfig+KeyBindings.swift`, `+Monitors.swift` (`diskMonitor`/`github`/`popupShortcuts`, lenient per-key decoding, `sanitizedInterval`/`intervalNanoseconds`), `+AgentDisplayPatterns.swift`, `+CodexUsage.swift`; `ArgusConfigStore.swift`; persistence is `ArgusConfigFile.swift` (`~/.config/argus/argus.json`, an unreadable file is backed up via `CorruptFileBackup` before defaults overwrite it) |
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
