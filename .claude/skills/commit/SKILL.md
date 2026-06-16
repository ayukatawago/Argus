---
name: commit
description: This skill should be used when the user asks to "commit", "create a commit", "commit my changes", "commit staged changes", or wants to commit work following the project convention. Creates a Conventional Commits-formatted git commit.
---

Create a git commit following the Argus project's Conventional Commits convention.

## Convention

Format: `type: brief description`

| Type | When to use |
| --- | --- |
| `feat` | New user-visible feature or capability |
| `fix` | Bug fix |
| `chore` | Build config, tooling, deps, scaffolding — no production logic |
| `refactor` | Code restructuring without behaviour change |
| `test` | Adding or updating tests |
| `docs` | Documentation only |
| `ci` | CI/CD pipeline changes |

Rules:
- Lowercase throughout
- Imperative mood ("add X", not "added X" or "adds X")
- No trailing period
- Max 72 characters for the title line
- Always append the `Co-authored-by` trailer

## Body (optional, between title and footer)

Leave the body empty when the title is self-explanatory. Include it when:
- The **why** is not obvious from the diff (e.g. a workaround for a known bug, a constraint imposed by a dependency)
- The change has **non-trivial motivation** a future reader would wonder about
- A **breaking change** needs explanation

Format:
- Separate from the title with one blank line
- Wrap at ~72 characters per line
- Use imperative mood, same as the title
- Focus on *why*, not *what* — the diff already shows what changed
- Multiple short paragraphs are fine; do not use bullet lists

```
feat: replace DispatchQueue with async/await in WorkspaceStore

libghostty callbacks arrive on the main thread and must not be
dispatched off it. Switching to structured concurrency makes the
constraint explicit at compile time via Swift 6 strict concurrency.

Co-authored-by: Claude Code <claude@anthropic.com>
```

## Workflow

1. Run `git status` and `git diff --cached` to inspect staged changes.
2. If nothing is staged, run `git diff` to see unstaged changes, then ask the user which files to stage (or stage all with their confirmation).
3. **Pre-commit check — run format/lint checks then the build; fail fast if anything is wrong:**
   - First invoke the `code-format-check` skill and resolve all violations (zero output from both `swiftlint` and `swift-format lint`) before building.
   - Then build:
   ```
   xcodebuild -scheme Argus -configuration Debug build 2>&1 \
     | grep -E "warning:|error:" \
     | grep -v "appintentsmetadata"
   ```
   - If any Swift compiler **warnings** appear, stop and fix them before committing.
   - If the build itself fails (errors), stop and fix before committing.
   - Only proceed when the output of the above command is empty.
4. Analyse the diff to determine:
   - The appropriate **type** from the table above
   - A concise **description** in imperative mood that says *what changed and why*, not just *what files changed*
5. If the change is large or spans multiple concerns, propose splitting into separate commits and ask the user.
6. Show the proposed commit message to the user before creating it.
7. Create the commit:

```
git commit -m "$(cat <<'EOF'
type: description

Co-authored-by: Claude Code <claude@anthropic.com>
EOF
)"
```

8. Confirm success by showing the one-line git log entry.

## Examples

```
feat: embed libghostty with single interactive terminal surface
fix: restore keyboard focus after Canvas overlay is dismissed
chore: vendor libghostty.a at ghostty commit abc1234
refactor: replace DispatchQueue calls with async/await in WorkspaceStore
test: add OSCParser round-trip tests for BEL and ST terminators
docs: document worktree management workflow in README
```
