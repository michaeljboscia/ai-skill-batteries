# Reality Check — Enforcement by Tier

## Universal Gate (applies to ALL tiers)

Before ANY tier-specific verification, these three checks are mandatory:

1. **Name the critical path.** In one sentence, what is the one thing that — if wrong — makes this system harmful? If you can't name it, you don't understand what you built.
2. **Find the ground truth.** For every piece of data your system infers, guesses, or correlates: is there a deterministic source you could read directly instead? If yes, read it. Delete the inference code.
3. **Verify LLM output.** If any LLM-generated content will be presented as fact, diff it against source artifacts before presenting.

---

## Tier 1: CLI / Process Tooling

**Trigger:** Anything touching PIDs, signals, sessions, daemons, filesystems, process trees.

### Rule T1-1: Assert Against OS Truth, Not Tool Output
Your tool says it killed a process. Did it? `kill -0 $PID` tells you. Your tool says it found the session ID. Did it? `ps -p $PID -E | grep SESSION_ID` tells you. Never trust your own output — ask the OS.

**You will be tempted to:** "The function returned success and the JSON looks right."
**Why that fails:** nudge-reaper's detect.sh returned valid JSON with wrong session IDs for every receipt. The JSON was beautiful. The data was wrong.
**The right way:** After every process operation, verify with an independent OS query. Spawn a real process with `env SESSION_ID=test_123 sleep 1000 &`, run your tool, then verify with `kill -0` and `ps -E`.

### Rule T1-2: Never Mock Process State
Unit tests that mock `ps` output, `stat` results, or file mtimes prove nothing. Process tooling must be tested against real processes on a real OS.

**You will be tempted to:** "Mocking is faster and more predictable for CI."
**Why that fails:** BSD `ps` and GNU `ps` format columns differently. File birth times behave differently on APFS vs ext4. Mocked tests validated the heuristic perfectly. Reality broke it.
**The right way:** Use `bats-core` for bash testing. Spawn real processes in test setup, kill them in teardown. If CI can't support it, run the E2E suite locally before shipping.

### Rule T1-3: Spawned Helper Processes Must Be Isolated
Any process you spawn for auxiliary work (notes, health checks, cleanup) must not write artifacts into the same namespace as production data.

**You will be tempted to:** "It's the same project, I'll just run it in the same directory."
**Why that fails:** nudge-reaper's notes system spawned Claude sessions that created transcripts in the real transcript directory. The detector matched those transcripts to user PIDs.
**The right way:** Use `--no-session-persistence` for throwaway processes. Or write to a dedicated temp directory. Or use `--bare` mode.

### Minimum Viable E2E (T1):
```bash
# Setup: real process with known session ID
env SESSION_ID=test_e2e_$(date +%s) sleep 1000 &
TEST_PID=$!

# Action: run your tool
RESULT=$(your-tool detect $TEST_PID)

# Assert: session ID matches
DETECTED_SID=$(echo "$RESULT" | jq -r '.session_id')
REAL_SID=$(ps -p $TEST_PID -E 2>/dev/null | grep -o 'SESSION_ID=[^ ]*' | cut -d= -f2)
[[ "$DETECTED_SID" == "$REAL_SID" ]] || echo "FAIL: detected $DETECTED_SID but real is $REAL_SID"

# Cleanup
kill $TEST_PID
```

---

## Tier 2: Data Pipelines

**Trigger:** Batch processing, ETL, sensors, pre-compute, database operations.

### Rule T2-1: Source-to-Sink Reconciliation After Every Chunk
After each chunk of data moves through the pipeline, query the destination and verify the count increased. If it didn't, STOP immediately.

**You will be tempted to:** "I'll check the totals at the end. Per-chunk checking is slow."
**Why that fails:** DuckDB COPY APPEND silently overwrites instead of appending. A 5-hour road KNN run lost all output because nobody checked until the end.
**The right way:** After each INSERT: `SELECT COUNT(*) FROM target WHERE batch_id = $CURRENT`. Log the running total. If count didn't increase, halt and investigate.

### Rule T2-2: Poison Pill Testing
Inject at least one malformed/null/boundary-case record into test data. Verify it's caught and routed to error handling, not silently dropped or — worse — silently accepted.

**You will be tempted to:** "The happy path works. Edge cases are unlikely."
**Why that fails:** Silent data corruption is worse than a crash. A pipeline that accepts bad data without flagging it produces results you trust but shouldn't.
**The right way:** Golden dataset of 10 valid + 1 poison pill. Assert valid count = 10 in destination, poison count = 1 in dead letter queue.

### Rule T2-3: Zero-Row Success Is a Failure
A pipeline that processes 0 records and returns success is lying. Check input count before processing. If input is empty, that's either expected (and logged) or a failure — never silent success.

**You will be tempted to:** "The code didn't throw an exception, so it succeeded."
**Why that fails:** An upstream API returns empty. Your pipeline reports SUCCESS. You don't discover the data gap until someone asks why the dashboard is blank.
**The right way:** Assert `input_count > 0` before processing. If empty, check if that's expected (weekend, no new data) or an error (API failure, auth expired).

### Minimum Viable E2E (T2):
```
1. Seed: 10 valid rows + 1 poison pill in source
2. Run: full pipeline execution
3. Assert: COUNT(*) == 10 in destination
4. Assert: COUNT(*) == 1 in error/DLQ table
5. Assert: pipeline logged per-chunk counts
```

---

## Tier 3: Web / UI

**Trigger:** Frontends, prototypes, user-facing pages, APIs.

### Rule T3-1: Test Persistence, Not Optimistic UI
After performing an action, reload the page. If the data isn't there after reload, it never persisted — you were testing the frontend cache.

**You will be tempted to:** "The UI updated after the click. It works."
**Why that fails:** Optimistic UI updates show data immediately but the backend save can fail silently. The user thinks they saved. They didn't.
**The right way:** Playwright: `page.click('Save')` → `page.reload()` → `expect(page.locator('text=Test')).toBeVisible()`.

### Rule T3-2: Test Real Stack, Not jsdom
Headless browser tests against real backend + real database. Mock only external third-party APIs (Stripe, Twilio), never your own backend.

**You will be tempted to:** "jsdom is faster for CI. We'll add browser tests later."
**Why that fails:** Component renders perfectly in jsdom but breaks in a real browser due to missing Browser APIs, z-index overlays blocking clicks, or CSS that hides elements.
**The right way:** `docker compose up` → Playwright test suite → `docker compose down`. Budget the 30 seconds of startup.

### Minimum Viable E2E (T3):
```
1. Start full stack (backend + frontend + DB)
2. Navigate → Login → Perform action → Save
3. Reload page
4. Assert data survived the reload
```

---

## Tier 4: LLM-Generated Content

**Trigger:** Summaries, notes, classifications, any LLM output presented to the user as fact.

### Rule T4-1: Ground Every Claim Against Source
Before presenting LLM output as fact, verify each factual claim against the source material. If the LLM says "47 tests pass" — check if there are 47 tests. If it says "JWT middleware implemented" — check if that file exists.

**You will be tempted to:** "The summary reads well and seems accurate. I'll just relay it."
**Why that fails:** nudge-reaper's notes system hallucinated JWT middleware, 47 tests, and a Redis rate limiter. A second Claude session read those notes and presented them to the user as real work. Two layers of "trust the output" compounded into active misinformation.
**The right way:** For each factual claim in LLM output: `grep`, `ls`, `git log`, or query to verify. If you can't verify a claim, label it as unverified.

### Rule T4-2: Never Use an Agent as a Stateless Summarizer
Claude, Gemini, and Codex are agents, not text completion APIs. When you pipe data into them with a summarization prompt, they don't passively extract — they complete patterns, infer conclusions, and state them as fact.

**You will be tempted to:** "I'll just pipe the transcript into Claude with a summarization prompt."
**Why that fails:** The agent engaged its full reasoning loop, inferred that unfinished tasks were completed, and wrote hallucinated accomplishments into the notes as fact.
**The right way:** Use `--print` mode with structured extraction (JSON schema). Or use a local model (Ollama) with constrained output. Or extract data mechanically (jq, grep) and only use LLM for formatting verified facts.

### Rule T4-3: Needle Verification
Inject a unique, verifiable marker into source context. Verify it appears in the output (recall) AND verify no fabricated content was added (precision).

**You will be tempted to:** "The output looks reasonable. It probably got the details right."
**Why that fails:** LLMs produce fluent, confident text that reads as authoritative regardless of accuracy.
**The right way:** Inject `VERIFICATION_TOKEN=BANANA-42` into source. Assert it appears in output. Then ask an evaluator: "Does the output claim anything not in the source?"

### Minimum Viable E2E (T4):
```
1. Source: document with known facts + injected verification token
2. Run: LLM summarization/generation
3. Assert: verification token present in output (recall)
4. Assert: no claims in output that aren't in source (precision)
5. Cross-check: one factual claim verified against filesystem/git
```

---

## Tier 5: Infrastructure

**Trigger:** Cloud resources, deployments, IAM, networking, containers.

### Rule T5-1: Provision → Hit → Verify → Destroy
Infrastructure tests must provision real resources, send real traffic, verify the response, AND verify unauthorized access is rejected. Then destroy everything.

**You will be tempted to:** "`terraform plan` looks clean. Ship it."
**Why that fails:** Security groups can block 100% of ingress while terraform reports success. IAM roles can grant read but not decrypt. Pods report Running but fail readiness probes.
**The right way:** Deploy to sandbox. `curl` the endpoint. Assert 200. Then `curl` without credentials. Assert 403. Then `terraform destroy`.

### Rule T5-2: Test the Negative Path
Every access control test must include at least one unauthorized attempt that should fail. If you only test "can I access this?" you've proven the door is open. You haven't proven the lock works.

**You will be tempted to:** "I verified the endpoint works. IAM is configured correctly."
**Why that fails:** An endpoint that returns 200 to everyone isn't secured. It's open.
**The right way:** Positive test (authorized → 200) AND negative test (unauthorized → 403).

### Minimum Viable E2E (T5):
```
1. Deploy to isolated sandbox
2. Hit endpoint with valid credentials → assert 200
3. Hit endpoint without credentials → assert 403
4. Destroy sandbox
5. Assert destroy succeeded (no orphan resources)
```
