# kotty

A native macOS terminal for running AI agents in parallel across git worktrees.

Built with Swift + SwiftUI/AppKit, powered by [libghostty](https://github.com/ghostty-org/ghostty).

## Features (planned)

- Sidebar with workspaces (git repos) and their worktrees
- Visual agent status — idle / running / done — for Claude Code, Codex, and other CLI agents
- Multiple terminal tabs per workspace
- Split panes within a tab (horizontal and vertical)
- Canvas overlay (`⌘⇧Space`) — see all live terminals at a glance

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
open kotty.xcodeproj

# Or build from the command line
xcodebuild -scheme kotty -configuration Debug build
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

See the [implementation plan](https://github.com/takkyuuplayer/kotty) for the full milestone breakdown and design decisions.

## License

MIT — see [LICENSE](LICENSE).
