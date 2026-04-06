---
name: mx-silent-bypass
description: Use when hitting any obstacle during plan execution — missing dependency, failing test, spec assumption that doesn't match reality, or architectural blocker. Also use when tempted to catch-and-continue, change production behavior to fix tests, add dependencies not in the spec, or create files not in the implementation plan.
---

# Silent Bypass Prevention

## Core Principle

When you hit a wall during execution, the wall is the signal. Routing around it silently is the failure mode this matrix exists to prevent.

## Operating Mode

| Mode | When | Your Role |
|---|---|---|
| **Execute** | Working through an implementation plan | Follow spec exactly; any deviation = halt |
| **Debug** | Test failure or unexpected behavior | Fix the root cause; never hide the symptom |
| **Design** | Making architectural choices | Present options; never choose silently |

## Detection Signals

You are about to silently bypass if ANY of these are true:

1. You're adding an `import` for a module not already used in the file AND not in the spec — OR using an existing import (e.g., `child_process`, `fs`) for a purpose not in the spec
2. You're creating a file not listed in the implementation plan
3. You're editing `package.json`, config schemas, or files with `server|api|router|handler|adapter|integration|mcp` in the path to work around a blocker
4. You're writing a `catch` block that suppresses an error to keep tests passing
5. You're changing a default value (enabled/disabled, port, feature flag) to avoid a test failure
6. Your inner monologue includes "this is obvious" or "I can just" when the spec says something different
7. You're modifying test assertions, mocks, or expected values to make a failing test pass instead of fixing the production code
8. You're about to execute an MCP tool, API call, or CLI command that affects external systems without explicit user instruction
9. You're writing a fix for a third-party library error without first searching for the exact error message (gemini-search or equivalent) — guessing at dependency fixes is a bypass

**If any signal fires: STOP. Read `enforcement.md`. Follow the Spec Deviation Protocol.**

Read `enforcement.md` for rules. Run `validation.md` checklist before claiming any step is complete.
