---
name: run-argus
description: This skill should be used when the user asks to "rebuild and relaunch Argus", "rebuild Argus", "relaunch Argus", "restart Argus", "install Argus", "run the app", "try it in the app", or wants a code change to take effect in the Argus instance they are actually using. Covers the build → install to /Applications → relaunch sequence.
---

Rebuild Argus and get the new binary into the running instance.

Argus is a macOS GUI app that is normally used **installed at `/Applications/Argus.app`**, not run
out of DerivedData. Keep that path stable: macOS TCC grants (Full Disk Access, per-folder Desktop/
Documents/… access, Screen Recording) are keyed to the bundle path, and Argus needs them because it
spawns a login shell per pane. Launching the DerivedData build directly is a separate app to TCC and
re-prompts for everything.

## The sequence

### 1. Build

```sh
xcodegen generate    # only after editing project.yml
xcodebuild -scheme Argus -configuration Debug build
```

SwiftLint runs as a pre-build phase — lint **errors** fail the build (line length > 160). A clean
incremental rebuild takes ~2s; a full one ~75s.

Resolve the product path rather than hardcoding it — the DerivedData directory carries a
machine-specific hash:

```sh
SRC=$(xcodebuild -scheme Argus -configuration Debug -showBuildSettings 2>/dev/null \
  | awk '/ BUILT_PRODUCTS_DIR =/ {print $3}')/Argus.app
```

### 2 & 3. Install and relaunch

Run this **detached** (`nohup … &`), not in the foreground — see Gotchas.

```sh
osascript -e 'quit app "Argus"' || true         # graceful; lets panes tear down
# wait for exit, then fall back to pkill if it hangs
rm -rf /Applications/Argus.app
ditto "$SRC" /Applications/Argus.app            # ditto, not cp -r: preserves the code signature
open -a /Applications/Argus.app
```

Use `ditto`. Plain `cp -r` mangles the bundle's signature and macOS then refuses to launch it or
silently drops entitlements.

## Verify it came back

Liveness alone is weak — check that the panes rehydrated:

```sh
pgrep -lf "/Applications/Argus.app/Contents/MacOS/Argus"
tmux list-sessions                              # argus-a-* / argus-s-* should show (attached)
find ~/Library/Logs/DiagnosticReports -name "Argus*" -mmin -5
```

Then actually drive it — this exercises the URL handler and the diff-review window end to end:

```sh
./script/argus diff "$PWD" --from origin/main
```

Sessions that show unattached are only worktrees whose panes Argus hasn't opened yet; their
scrollback is intact and they reattach on selection.

## Gotchas

| Gotcha | Why / what to do |
|---|---|
| **You are probably running inside Argus** | An agent pane's shell is a child of Argus. Quitting it kills that shell. The panes are tmux-backed and the tmux server is a separate daemon, so the session survives and reattaches — but run the quit/install/relaunch as a detached `nohup script &` so nothing in the chain depends on the pane surviving. |
| `screencapture` fails | `could not create image from display` — the invoking process lacks Screen Recording permission. There is no screenshot-based verification available; use the liveness + tmux + `script/argus diff` checks above. |
| Debug builds are **ad-hoc signed** | `project.yml` sets `CODE_SIGN_IDENTITY: "Argus Local Dev"` under the Argus target's `debug:` block, but XcodeGen ignores bare `debug:`/`release:` keys under a target's `settings:` — they must be nested under `settings: configs:`. The generated Debug config carries only the `base:` values, so builds come out `Signature=adhoc`. Ad-hoc signatures change every build, so TCC grants do **not** reliably survive a rebuild despite what CLAUDE.md's "Debug code signing" section claims. Expect occasional re-prompts until `project.yml` is fixed. |
| Don't use this for Release | The local `Argus Local Dev` identity is self-signed and must never sign a distribution build. |

## Workflow

1. Build; stop and fix if SwiftLint errors or compile errors appear.
2. Resolve `BUILT_PRODUCTS_DIR`; confirm the binary's mtime is from this build.
3. Quit → `ditto` → `open`, detached.
4. Run the verification checks; report what actually came back, not just "relaunched".
