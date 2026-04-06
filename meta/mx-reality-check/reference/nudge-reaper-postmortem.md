# nudge-reaper Postmortem — 2026-04-03

## What It Was
Session lifecycle manager for Claude Code. Detects idle sessions, preserves context, kills processes to free RAM. Built in one day. 4 rounds of goat rodeo. 12 canonical docs. 155 passing tests. Public GitHub repo (michaeljboscia/nudge-reaper).

## What It Did
- Killed user's work sessions and gave wrong resume commands
- Generated hallucinated session notes (JWT middleware, 47 tests, Redis rate limiter that never existed)
- A second Claude session read those notes and presented them as real work
- Killed 3 triumvirate daemon sessions (agent processes)
- User tried to resume 3 times — "No conversation found" every time

## The 6 Failures

### F1: Heuristic Where Deterministic Data Existed
- `detect.sh` used 140 lines of birth-time + mtime heuristic to guess PID→transcript mapping
- `ps -p <pid> -E | grep SESSION_ID` gives the exact answer in 1 line
- Every resume command in every receipt was potentially wrong
- **Root mental model error:** Treated Claude process as opaque black box. Forgot processes carry their launch context in environment variables.

### F2: Notes System Spawned Ungrounded Sessions
- Pre-reap, spawned fresh `claude -p` to generate session notes
- That session hallucinated completely fake work
- No grounding verification against source artifacts
- **Root mental model error:** Treated an autonomous agent as a passive text summarizer.

### F3: Notes Sessions Polluted Transcript Directory
- Spawned sessions created transcripts in the same directory as real sessions
- Detection heuristic matched notes transcript to user's real PID
- Resume command pointed to throwaway notes session
- **Root mental model error:** Assumed helper processes wouldn't create side effects in the monitored namespace.

### F4: 155 Tests, Zero End-to-End
- Every component had unit tests
- No test ever: reaped → resumed → verified same session
- Critical path was never tested against reality
- **Root mental model error:** "If every piece works, the system works."

### F5: Hallucinated Notes Presented as Real
- `session-handoff.md` contained hallucinated content from the notes system
- A new Claude session read it and presented it to the user as real accomplished work
- Two layers of "trust the LLM output" compounded into active misinformation
- **Root mental model error:** Assumed file contents in a repo are factual.

### F6: Quality Gates Validated Structure, Not Behavior
- 4-round goat rodeo validated spec consistency
- Tests validated JSON shape and function return values
- Verification hierarchy checked that tests pass
- None of it checked whether the system did the right thing
- **Root mental model error:** Structural consistency = correctness.

## Triumvirate Diagnosis (All 3 Converged)

**Gemini:** "LLM Echo Chamber & Structural Theater. LLMs reviewing LLMs. Tests proved the flawed logic executed flawlessly."

**Codex:** "Verification architecture failure. The system never had a hard truth anchor for identity. Every gate downstream inherited that flaw."

**Claude:** "155 tests. Zero end-to-end. The tools validate what Claude says it built, not what it actually does."

## Cost
- User's active work sessions killed
- Resume commands pointed to wrong sessions
- User misled about accomplished work
- Trust in all three AI agents damaged
- Public repo with user's name publishing broken software
- 3 triumvirate daemon sessions destroyed
- Multiple hours of user time lost

## What Would Have Prevented This
1. One E2E test: spawn process → detect → reap → resume → verify same session
2. Reading `SESSION_ID` from process environment instead of guessing
3. Running notes sessions with `--no-session-persistence`
4. Verifying notes content against git log before writing to disk
