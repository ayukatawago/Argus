---
name: argus-capture
description: This skill should be used when the user asks to "take a screenshot of Argus", "capture Argus's window", "record a video of Argus", "show me what Argus looks like", or otherwise wants an image or screen recording of the Argus macOS app's own window from the command line via the `argus` CLI. Requires the `argus` CLI (from https://github.com/ayukatawago/argus) to be installed; macOS only.
---

Capture a screenshot or screen recording of Argus's own window using the `argus` CLI.

## What this does

`argus` is a small command-line dispatcher shipped with the Argus macOS app
(a git-worktree-aware terminal manager). Its `capture` subcommand grabs
Argus's own main window — a real on-screen capture (via ScreenCaptureKit),
including the terminal panes' rendered content, not just a UI re-render — and
writes it to a PNG (`capture screenshot`) or a `.mov` recording
(`capture video`). It works whether or not Argus is currently running:
`open` launches the app if needed and activates it either way.

Unlike `argus diff`, `capture` blocks until the capture is finished (or
fails) and prints the resulting file path on success — read that file
directly afterwards (e.g. with the Read tool for a screenshot) to see what
Argus currently looks like.

`diff` and `capture` are the `argus` subcommands implemented today — treat
`argus --help` (or `argus <command> --help`) as the source of truth if this
doc and the installed CLI ever drift.

## Requirements

- macOS (the CLI shells out to `open` against a custom `argus://` URL
  scheme registered by the Argus app).
- Argus must have **Screen Recording** permission (System Settings → Privacy
  & Security → Screen Recording). If a capture fails with a permission-
  related error, tell the user to grant it there and relaunch Argus — this
  can't be granted from the command line.
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
  capture ...`) over a symlink unless the user wants `argus` typeable bare —
  in that case:
  `ln -s /Applications/Argus.app/Contents/Resources/argus /opt/homebrew/bin/argus`.
  (A future Homebrew cask would set this symlink up automatically.)

## Usage

```sh
argus capture screenshot [--output <path>]
argus capture video --duration <seconds> [--output <path>]
```

- `--output <path>` — optional. Where to write the capture. Defaults to a
  generated path under `/private/tmp` when omitted; the CLI always prints
  the final path on success, so passing `--output` is only needed to control
  where the file lands.
- `--duration <seconds>` — required for `video`. How long to record.

Both commands exit non-zero and print an error to stderr on failure
(including a timeout if Argus never finishes writing the file) — check the
exit code before treating stdout as a valid path.

## Examples

```sh
# Screenshot Argus to a generated temp path, then read it
path="$(argus capture screenshot)"

# Screenshot to a specific path
argus capture screenshot --output ~/Desktop/argus.png

# Record 10 seconds of Argus's window
argus capture video --duration 10 --output ~/Desktop/argus-demo.mov
```
