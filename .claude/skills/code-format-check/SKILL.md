---
name: code-format-check
description: This skill should be used when the user asks to "check swift-format", "check swiftlint", "run lint", "check formatting", "fix lint warnings", "fix swift-format warnings", "check for warnings before committing", or wants to verify the codebase has zero swift-format and SwiftLint warnings.
---

Check and fix swift-format and SwiftLint issues in the kotty project.

## Config

- SwiftLint: `.swiftlint.yml` — line length error at 160, warning at 120; `force_cast` and `force_unwrapping` are errors
- swift-format: `.swift-format` — 4-space indent, line length 120, `NeverForceUnwrap` and `NeverUseForceTry` enforced

## Check for Issues

Run both tools and collect all output before fixing anything:

```sh
# SwiftLint — warnings and errors
swiftlint --config .swiftlint.yml --quiet

# swift-format lint — formatting violations (exit 1 if any found)
xcrun swift-format lint --recursive --parallel Sources App
```

Treat any output from either command as a failure. The commit pre-check in the `commit` skill requires zero output from both.

## Fix Issues

### swift-format (auto-fixable)

```sh
xcrun swift-format --in-place --recursive Sources App
```

Then re-run the lint check to confirm no remaining violations.

### SwiftLint (partially auto-fixable)

```sh
swiftlint --fix --config .swiftlint.yml
```

`--fix` handles a subset of rules. Re-run the lint check after — remaining output requires manual fixes.

## Common Manual Fixes

| Warning | Fix |
|---|---|
| Line too long (>120/160 chars) | Break the line; extract a local `let` for long expressions |
| `force_unwrapping` (`!`) | Use `guard let` / `if let` or `??` with a default |
| `force_cast` (`as!`) | Use `as?` with a guard or conditional cast |
| `sorted_imports` | Reorder `import` statements alphabetically |
| `redundant_type_annotation` | Remove explicit type when the compiler can infer it |
| `trailing_comma` | Add trailing comma to last element in multi-line collection |
| `explicit_init` | Replace `Foo.init(...)` with `Foo(...)` |
| `empty_count` | Replace `.count == 0` with `.isEmpty` |

## Workflow

1. Run both check commands and capture output.
2. Run auto-fix commands if violations exist.
3. Re-run both checks.
4. Fix any remaining violations manually using the table above.
5. Re-run checks one final time — proceed only when both produce no output.
