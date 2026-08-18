# Argus

A native macOS app for running AI agents in parallel across git worktrees.

Built with Swift + SwiftUI/AppKit, powered by [libghostty](https://github.com/ghostty-org/ghostty).

## Features

### Layout & agents

- Sidebar listing git repos and their worktrees; drag-and-drop reordering of repos
- Two selectable window layouts (toolbar): Terminal + Agent, and Agents / Terminal (70/30 split)
- A single agent view with a Claude tab and a Codex tab — only the default agent's tab opens automatically; the other spins up on demand — shown full-width or side by side (toolbar toggle / leader `s`)
- Choose the default AI agent (Claude Code or Codex) with user-editable launch commands via Settings (⌘,)
- Create and force-delete worktrees directly from the sidebar
- Per-worktree terminal sessions with release button to free resources
- Restores the last selected worktree on relaunch

### Agent & shell status

- Visual agent status — idle / running / waitingForApproval / done — driven by Claude Code hooks
- Sidebar dot and border color change to reflect agent state at a glance
- Animated sidebar border when a shell pane has a foreground command running, via fish hooks (accent-tinted when the worktree is selected)

### Diff review

- Side-by-side diff review popup (leader `w`) for the selected worktree: file tree, base/head revision picker with an "include uncommitted" toggle, total/production/test size breakdown, syntax highlighting, and changed-span (intraline) highlighting
- PR-style inline comments whose **Reply**/**Apply** buttons run a headless Claude Code / Codex agent in the worktree — Apply lets it edit files, then refreshes the diff

### Sidebar monitors

- GitHub PR monitor: your open/draft PRs plus PRs assigned to you, with target branch, review status, draft/approved styling, new/updated highlighting, and a collapsed "Do Not Merge" section (configured on the Settings → GitHub page)
- Disk space monitor (leader `d`, or a low-space banner): free-space gauge and cleanup candidates (DerivedData, caches, workspace git repos, …) with size and last-modified date, sortable and size-filterable, with move-to-Trash

### Utilities

- Markdown preview (leader `m`) with in-page search (⌘F), local-image rendering, and a `.md` file tree
- User-configurable popup terminals (Settings → Keyboard) — run any command in a floating pane via leader + a key; lazygit ships as the default (leader `g`)
- nvim popup (leader `v` or ⌘⇧N) with a tmux-persisted session; close with ⌘H
- Cmd+click `https` links in the terminal to open them in the browser
- Global environment variables injected into every new terminal/agent pane (Settings → Environment)

### Shortcuts

- Leader key shortcuts (default `Ctrl+B` prefix): `n`/`p` to cycle worktrees, `h`/`l` to focus panes, `a` to reload the agent pane, `w` diff review, `d` disk status, `m` markdown preview, `v` nvim, `r` refresh workspace, `,` settings
- `t`/`]`/`[`/`x` act on whichever pane has focus — new/next/previous/close a tmux window in the terminal, or open/cycle/close an agent tab in the agent view; `s` toggles the agent view between full-width and side by side
- Configurable leader key, timeout, key bindings, and popup terminals via Settings (⌘,); saved to `~/.config/argus/argus.json`

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16.0 or later
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- [SwiftLint](https://github.com/realm/SwiftLint): `brew install swiftlint`

## Building

```sh
# 1. Generate the Xcode project
xcodegen generate

# 2. Open in Xcode
open Argus.xcodeproj

# Or build from the command line
xcodebuild -scheme Argus -configuration Debug build
```

## Setup for contributors

```sh
# Install the pre-commit hook (runs SwiftLint and swift-format --lint)
script/setup.sh
```

## Code formatting

```sh
# Format all Swift files in place
script/format.sh
```

See [CONVENTIONS.md](CONVENTIONS.md) for coding standards.

## Architecture

See [CLAUDE.md](CLAUDE.md) for module layout, the hook IPC system, and build notes.

## License

MIT — see [LICENSE](LICENSE).
