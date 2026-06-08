# Coding Conventions

## Language and style

- **Swift 6.0**, strict concurrency enforced by the compiler.
- Follow [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) for all naming.
- 4-space indentation, no tabs.
- Trailing comma on the last element of multi-line collections and argument lists.
- Sorted imports (enforced by swift-format).

## Module boundaries

Each folder under `Sources/` is a logical module. The rule:

| Module | Allowed to import |
| --- | --- |
| `AgentState` | Foundation, Darwin |
| `Workspaces` | Foundation, CoreServices |
| `GhosttyBridge` | AppKit, GhosttyTerminal (the C library), Foundation, Darwin |
| App target (`App/`) | All of the above + SwiftUI + AppKit |

**Only `GhosttyBridge` imports `GhosttyTerminal`.** All other modules interact with the terminal engine through `GhosttyBridge` types.

## Concurrency

- Prefer `@Observable` + `@MainActor` for view models.
- Use structured concurrency (`async/await`, `Task`, `AsyncStream`) — no `DispatchQueue` in new code.
- Mark `@MainActor` where a type must run on the main thread. libghostty callbacks run on the main thread; do not dispatch them off-thread.

## Error handling

- `throws` over returning `Optional` for operations that can fail with a diagnosable reason.
- Use typed errors (`enum MyError: Error { case … }`) over `NSError` or string errors.
- Reserve `fatalError` for programmer errors (violated invariants), not user-facing failures.

## No force-unwrap or force-cast

SwiftLint enforces `force_unwrapping` and `force_cast` as errors. There are no exceptions.

## SwiftLint limits

| Rule | Warning | Error |
| --- | --- | --- |
| Line length | 120 | 160 |
| File length | 400 lines | 600 lines |
| Type body length | 300 lines | 400 lines |
| Function body length | 50 lines | 80 lines |

Lint errors block the build. Warnings do not.

## Comments

Write a comment only when the **why** is non-obvious — a hidden constraint, a subtle invariant, a workaround for a specific bug. Do not describe what the code does; well-named identifiers already do that.
