# Reality Check — Validation Checklist

Run AFTER work is complete, BEFORE declaring done. Every item requires PROOF — command output, file path, log snippet, or screenshot. Self-attestation is the failure mode this matrix exists to prevent.

## Anti-Gaming Rules

- **Multi-tier tasks require ALL applicable tiers.** nudge-reaper was T1 + T4. If you classify into only one tier to dodge checks, you repeat the failure.
- **"Not convenient" is not a reason to skip deterministic sources.** Document that you searched for a deterministic source and could not find one. Show the search.
- **Dry-run tests do not count as E2E.** If your E2E uses --dry-run, safe-mode, or mocked system calls, it is a unit test. Re-do it.

## First Pass (Belt) — Self-Check with Evidence

### Universal Gate
- [ ] Critical path named: `_______________` (one sentence)
- [ ] E2E test command: `_______________` (paste exact command or test file path)
- [ ] E2E proof: no --dry-run, no unittest.mock on system behavior, no in-memory substitutes
- [ ] Negative path tested: `_______________` (what the system correctly did NOT do)
- [ ] Deterministic sources: `_______________` (if heuristic used, paste search evidence for why no deterministic source exists)
- [ ] LLM grounding: `_______________` (for each claim, cite verification command used)
- [ ] Helper isolation: `_______________` (flag/config that prevents namespace pollution)

### Tier-Specific (check all that apply)

#### T1: CLI/Process
- [ ] Tested against real processes, not mocked ps/stat output
- [ ] Asserted outcomes via OS queries (kill -0, ps -E), not tool return values
- [ ] Spawned helpers use --no-session-persistence or isolated directories

#### T2: Data Pipelines
- [ ] Source-to-sink count reconciliation after each chunk
- [ ] Poison pill injected and verified caught
- [ ] Zero-row input is detected and handled (not silent success)

#### T3: Web/UI
- [ ] Page reloaded after action — data persisted, not just cached
- [ ] Tested in real browser (Playwright), not jsdom
- [ ] Full stack running during test (backend + DB, not mocked)

#### T4: LLM Content
- [ ] Each factual claim verified against source (grep, ls, git log)
- [ ] Verification token injected and recovered
- [ ] No fabricated content added beyond source material

#### T5: Infrastructure
- [ ] Real resources provisioned and hit with traffic
- [ ] Positive test (authorized access → 200) passed
- [ ] Negative test (unauthorized access → 403) passed
- [ ] Resources destroyed after test, no orphans

## Second Pass (Suspenders) — Triumvirate

Dispatch the completed work + this checklist to Gemini AND Codex:

"Review this work against the reality-check validation checklist. For each item marked complete, verify the evidence exists. For each item not applicable, confirm it's truly not applicable. Flag any item that is checked but lacks evidence."

Majority vote (2/3). Disagreement → surface to user.
