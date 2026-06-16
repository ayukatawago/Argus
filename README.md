# Argus

A native macOS app for running AI agents in parallel across git worktrees.

Built with Swift + SwiftUI/AppKit, powered by [libghostty](https://github.com/ghostty-org/ghostty).

## Features

- Sidebar listing git repos and their worktrees
- Split layout: Claude Code pane (left) + shell terminal (right) per worktree
- Visual agent status — idle / running / waitingForApproval / done — driven by Claude Code hooks
- Sidebar dot and border color change to reflect agent state at a glance
- Lazygit popup (`⌘G`) per worktree
- Leader key shortcuts (`Ctrl+B` prefix): `j`/`k` to cycle worktrees, `n`/`d` to create/delete
- Drag-and-drop reordering of repos in the sidebar
- Create and force-delete worktrees directly from the sidebar
- Per-worktree terminal sessions with release button to free resources
- Restores the last selected worktree on relaunch

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
