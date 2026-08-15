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

## Split by concern: code, test, docs

Default to **separate commits per concern**, not one commit mixing them. Classify every staged
file into exactly one bucket:

- **docs** — `*.md` files that document the codebase/product (`CLAUDE.md`, `README.md`, `CONVENTIONS.md`, `UI.md`, `docs/**`)
- **test** — files under a `Tests/` directory, or named `*Tests.swift`
- **code** — everything else, including production Swift, `project.yml`, entitlements, scripts, and tooling/config markdown such as `.claude/**` (skills, commands, agent definitions) — these aren't documentation *about* the codebase, they're config, so they take whichever type actually fits (usually `chore`, occasionally `feat`/`fix`), never `docs`

Only split when **more than one bucket is actually present** in the staged changes. A change
confined to a single bucket (a docs-only fix, a test-only addition) is just one commit — don't
force an empty split.

When more than one bucket is present, commit them in this order: **code → test → docs**. This
keeps every intermediate commit in a buildable state — production code lands before the tests that
exercise it, and docs land last since they describe the finished behavior.

This is a distinct concern from step 5 below (splitting *within* a bucket when it mixes unrelated
features/fixes) — apply both: first split by bucket, then, within the code bucket, check whether it
still mixes unrelated concerns.

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
   - Run this once against the full staged set — not per bucket. Splitting the actual `git add`/`git commit` calls happens later in step 6; there's no need to lint/build each slice separately.
4. Classify the staged files into the code/test/docs buckets above.
5. Within the **code** bucket specifically, check whether it still mixes unrelated concerns (e.g. two unrelated bug fixes, or a feature plus an incidental refactor). If so, propose splitting further and ask the user; otherwise treat the code bucket as one commit.
6. For each non-empty bucket, in **code → test → docs** order, analyse that bucket's diff alone to determine:
   - The appropriate **type** from the table above (a docs bucket is always `docs`; a test bucket is always `test`; the code bucket is whatever `feat`/`fix`/`chore`/`refactor`/`ci` fits)
   - A concise **description** in imperative mood that says *what changed and why*, not just *what files changed*
7. Show the user the **full list of proposed commits** (message for each bucket, in commit order) before creating any of them.
8. Create each commit in order — stage only that bucket's files, then commit:

```
git add <bucket files>
git commit -m "$(cat <<'EOF'
type: description

Co-authored-by: Claude Code <claude@anthropic.com>
EOF
)"
```

9. Confirm success by showing `git log --oneline` for the new commits (one line per bucket committed).

## Examples

Single-bucket change (no split needed):

```
docs: document worktree management workflow in README
```

Multi-bucket change (split code → test → docs):

```
fix: infer idle state correctly after /compact completes
test: cover /compact's isCompactSummary idle mapping
docs: document codex session-state inference rules
```
