---
name: argus-diff
description: This skill should be used when the user asks to "review this diff in Argus", "open the diff in Argus", "show this in Argus's diff review", "compare <branch> to <branch> in Argus", or otherwise wants to open Argus's side-by-side diff-review popup for a git repo/worktree from the command line via the `argus` CLI. Requires the `argus` CLI (from https://github.com/ayukatawago/argus) to be installed; macOS only.
---

Open Argus's diff-review popup for a git repo/worktree using the `argus` CLI.

## What this does

`argus` is a small command-line dispatcher shipped with the Argus macOS app
(a git-worktree-aware terminal manager). Its `diff` subcommand opens Argus's
side-by-side diff-review popup — comment threads, syntax highlighting, range
comments, hidden-line expansion — for a base/head ref pair, without needing
the target repo to already be a tracked workspace in Argus's sidebar. It
works whether or not Argus is currently running: `open` launches the app if
needed and activates it either way.

`diff` is the first of what will grow into a small family of `argus`
subcommands — treat `argus --help` (or `argus <command> --help`) as the
source of truth if this doc and the installed CLI ever drift.

## Requirements

- macOS (the CLI shells out to `open` against a custom `argus://` URL
  scheme registered by the Argus app).
- The `argus` CLI reachable one of two ways — check in this order:

  ```sh
  # 1. Already on PATH
  command -v argus

  # 2. Argus.app is installed but not linked onto PATH — the CLI ships
  #    bundled inside the app itself, so this works with zero setup
  #    beyond having installed the app.
  ls /Applications/Argus.app/Contents/Resources/argus
  ```

  If neither is found, Argus isn't installed at all. Don't guess a path to
  a local checkout — tell the user and point them at
  https://github.com/ayukatawago/argus. Once installed, prefer running the
  bundled copy directly (`/Applications/Argus.app/Contents/Resources/argus
  diff ...`) over a symlink unless the user wants `argus` typeable bare —
  in that case:
  `ln -s /Applications/Argus.app/Contents/Resources/argus /opt/homebrew/bin/argus`.
  (A future Homebrew cask would set this symlink up automatically.)

## Usage

```sh
argus diff <workspace> --from <ref> [--to <ref>]
```

- `<workspace>` — path to the git repo or worktree to review (absolute or
  relative; resolved via `cd`/`pwd`, so `.` works for "the current repo").
- `--from <ref>` — required. Base commit SHA or branch to diff from.
- `--to <ref>` — optional, defaults to `HEAD`.

## Examples

```sh
# Review uncommitted work against main in the current repo
argus diff . --from main

# Review a specific branch against a specific base, in another checkout
argus diff ~/code/some-project --from origin/main --to feature/my-branch
```
