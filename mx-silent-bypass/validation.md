# Silent Bypass Prevention — Validation Checklist

Run AFTER completing any implementation step, BEFORE claiming it's done.

## First Pass (Belt) — Self-Check

- [ ] No new files created that aren't in the implementation plan
- [ ] No new imports added for modules not already used in the file (unless specced)
- [ ] No changes to package.json, config schemas, or integration surface files to work around a blocker
- [ ] No catch blocks that suppress errors without throw/reject/log
- [ ] No default values changed (enabled→disabled, port numbers, feature flags) to make tests pass
- [ ] No production code was modified solely to address a test environment issue — fixes for test failures belong in test setup/config only
- [ ] No feature, output category, or logging was binary-eliminated to save tokens/time/complexity
- [ ] No actions visible to external systems (MCP calls, API requests, CLI dispatches) were executed without explicit user permission
- [ ] No existing test assertions were weakened or mock boundaries changed to accommodate failing code
- [ ] Test count is equal to or greater than the previous run
- [ ] Every spec deviation was surfaced to the user BEFORE code was written or tools were executed
- [ ] Every write operation has per-operation verification (not just end-of-batch) — verify data integrity, not just row counts
- [ ] Every fix for a third-party/dependency error was preceded by at least 2 search queries (gemini-search or equivalent) — no guessing at fixes for code you didn't write

- [ ] Integration test ran against real dependencies and passed — not unit tests, not mocks, the full pipeline (`node scripts/integration-test.mjs`). "Tests pass" means BOTH unit AND integration.

## Second Pass (Suspenders) — Triumvirate

At twin review checkpoints, dispatch the current diff + this checklist to Gemini AND Codex.
Ask: "Does this diff contain any silent bypass patterns? Check each item."
Majority vote (2/3). Disagreement → surface to user.
