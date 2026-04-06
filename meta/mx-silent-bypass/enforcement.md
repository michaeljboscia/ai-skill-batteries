# Silent Bypass Prevention — Enforcement

## The Spec Deviation Protocol

When reality doesn't match the spec, this is the ONLY allowed sequence:

1. **STOP** — Do not write code. Do not "try something."
2. **STATE** — Tell the user: "The spec says X. Reality is Y. Because Z."
3. **RESEARCH** — Use an available search tool (`mcp__gemini__gemini-search`, `WebSearch`, or equivalent) for alternatives. Not brainstorming — actual research.
4. **PRESENT** — Show at least 2 options with trade-offs. Include the option that scales best.
5. **WAIT** — The user decides. Silence is not permission.
6. **TWINS** — Send the chosen approach to both siblings for review before implementing.
7. **UPDATE** — If the spec changes, update the spec document BEFORE writing code. Only the user can authorize a spec change — you cannot rewrite the spec to match your intended workaround.

## Rules by Context

### Context 1: Spec-Reality Mismatch (Missing dependency, incompatible API, wrong assumption)

**Rule 1: Never invent a workaround for a spec assumption that doesn't hold.**

You will be tempted to: "The spec says direct SQLite insert, but there's no better-sqlite3. I'll create a CLI wrapper — same result, different mechanism."
Why that fails: You changed the interface contract between two systems. The spec no longer matches the implementation. The user lost control of the architecture. Cost: 30 min of throwaway code + spec/implementation drift that compounds. (Sprint 14 Step 6, 2026-03-20)

**The right way:** Follow the Spec Deviation Protocol above. The user chose a dedicated HTTP writer service — architecturally superior to both the spec's original design AND the CLI workaround. The better solution only emerged because the user was given the choice.

### Context 2: Test Environment Problem (Port conflict, missing fixture, timing issue)

**Rule 2: Test failures caused by environment are fixed in the test setup, never in production code.**

You will be tempted to: "Tests fail with EADDRINUSE. I'll catch the error in production and gracefully degrade. Tests pass now."
Why that fails: The production feature becomes a silent no-op. Tests report green but the system is degraded. The user's system gets dumber with zero indication. A startup error takes 5 seconds to diagnose; a silently disabled feature takes hours to notice. (Sprint 14 Step 6, 2026-03-20)

**The right way:** Ask "why are tests competing for this resource?" The answer is always test isolation — disable the competing resource in test config, use port 0 (random), or run tests sequentially. Production behavior is sacred; tests adapt to production, not the reverse.

### Context 3: Feature Elimination Under Pressure (Budget, performance, complexity)

**Rule 3: Never binary-eliminate a feature category. Gradual reduction only.**

You will be tempted to: "Context budget is tight. Drop all thoughts — code is more concrete anyway."
Why that fails: "Zero thoughts" is never the right answer when "one thought" is available. A single high-confidence decision thought can be worth more than the 7th-ranked code chunk. Binary elimination silently removes the reasoning layer with no signal to the user. (Sprint 14 Step 5, 2026-03-20)

**The right way:** Trim one item at a time from the lowest-value category. When trimming reaches zero and budget still exceeds, move to the next category. The highest-value item in any category survives maximum pressure.

### Context 4: Autonomous Action (Dispatch, side-effect, irreversible operation)

**Rule 4: Never take an action visible to other systems without explicit user instruction.**

You will be tempted to: "The workflow is obvious — I'll just send this to Codex to save time."
Why that fails: Broke established workflow pattern. Process had to be killed. User trust damaged. The "obvious" action was wrong — the established pattern was "write prompt, print to console, user pastes manually." (Sprint 14 Step 4, 2026-03-11)

**The right way:** Write the dispatch prompt. Print it. Say "Ready to send to [target]. Should I fire it?" Wait for explicit "yes" or "send it."

### Context 5: Silent Data Operations (Batch writes, bulk updates, background jobs)

**Rule 5: Every write operation must verify its own output before reporting success.**

You will be tempted to: "The write API returned successfully. I'll check at the end."
Why that fails: DuckDB COPY APPEND silently overwrites instead of appending. 5 hours of GPU compute lost because the verification was a rubber stamp at the end — not per-chunk. (Tellus road KNN, 2026-03-19)

**The right way:** Verify after EVERY write operation: count rows before, count rows after, assert delta equals expected. If the verification fails, halt immediately — don't continue accumulating damage.

### Context 6: Unfamiliar Error From a Dependency (Third-party library, extension, platform API)

**Rule 6: Never guess at a fix for an error from code you didn't write. Search first.**

You will be tempted to: "The error says LIMIT is required. I'll just change LIMIT to k=? — that's probably right."
Why that fails: You might fix the symptom while missing the actual constraint. sqlite-vec's `vec0` requires a CTE to isolate KNN from JOINs — just swapping `LIMIT` for `k=?` in the existing query structure would STILL fail. The correct fix (CTE isolation) only emerged from reading the library author's guidance. Guessing cost zero time here, but in other cases produces subtle bugs that pass tests and fail in production. (Sprint 14 vec0 bug, 2026-03-21)

**The right way:** Run at least 2 `mcp__gemini__gemini-search` queries with the exact error message + library name before writing any fix code. Read the upstream issue tracker or docs. Then implement the fix the library author recommends, not the fix your intuition suggests.
