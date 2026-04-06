---
name: skill-forge
description: Build a complete AI coding skills package for any language, framework, or platform. Use when the user says "skill pack," "skill forge," "build skills for [X]," "skill-forge," or wants to create a multi-skill package for a technology. Orchestrates the full research-to-deployment pipeline.
---

# Skill Forge — Build AI Coding Skills Packages

**Invoke this skill when the user wants to create a skills package for a language, framework, or platform.**

This is a multi-hour workflow. It produces 4-10 focused SKILL.md files from deep research, writes them to `~/.claude/skills/`, and pressure-tests them. The full reference framework lives at `~/.claude/skill-forge/SKILLS-FACTORY-FRAMEWORK.md` — read it if you need the rationale behind any step.

---

## Compaction Safety

This workflow spans hours. Context WILL compact. Every phase must:
1. Write outputs to disk before moving to the next phase
2. Update the session log at `~/.claude/skill-forge/{topic}/session-log.md`
3. The session log is your recovery point — read it first after compaction

**Session log header (write at Phase 0):**
```
# Session Log: {Topic} Skill Package
**Working Directory:** ~/.claude/skill-forge/{topic}/
**Phase:** {current phase number and name}
**Skills Planned:** {count}
**Quicksearches Done:** {n}/{target}
**Deep Research Done:** {n}/{target}
**Skills Written:** {n}/{total}
**Skills Promoted:** {n}/{total}
```

Update these counters after every batch of work.

---

## Pre-Flight: Worktree Isolation (MANDATORY)

**Every skill-forge run MUST start by creating an isolated git worktree. No exceptions.**

All skill-forge work happens in the `~/.claude/skill-forge/` repo. Before touching anything:

```bash
cd ~/.claude/skill-forge
git worktree add -b skill-forge/{topic} ./{topic}-worktree
cd ./{topic}-worktree
```

If `~/.claude/skill-forge/` is not yet a git repo, initialize it first:

```bash
cd ~/.claude/skill-forge
git init && git add -A && git commit -m "Initial skill-forge repo"
git worktree add -b skill-forge/{topic} ./{topic}-worktree
cd ./{topic}-worktree
```

**All work for this skill battery happens inside the worktree.** Research, drafts, deep-research JSONs, pressure tests, test apps — everything. When the battery ships, merge the worktree branch back to main and clean up:

```bash
cd ~/.claude/skill-forge
git merge skill-forge/{topic}
git worktree remove ./{topic}-worktree
```

This is not optional. Do not proceed to Phase 0 without an active worktree.

---

## Phase 0: Scope Definition

**Goal:** Define the skill boundaries. Every skill maps to a distinct "mode of work."

### Steps:
1. Ask the user: **"What's the project that will USE these skills?"** (Motivation anchors scope.)
2. Together, identify 4-10 **modes of work** — distinct categories where the AI uses different libraries, mental models, and makes different mistakes.
3. Build the taxonomy table:

```
| # | Mode | What You're Doing | AI Failure Mode | Skill Name |
|---|------|-------------------|-----------------|------------|
```

**Quality gate:** Each mode MUST have a distinct AI failure mode. If two modes share the same failure, merge them.

### Mandatory co-default skills:
Every pack MUST include these two skills, and they MUST co-load with the core skill on ANY work in that language:

1. **Observability** — structured logging, tracing, metrics, health checks. Co-default because code without observability ships blind. The description field must include the phrase "any {language} work" to trigger alongside core.
2. **Performance** — profiling, data structure selection, build optimization. Co-default because every function the AI writes should follow perf-aware patterns by default, not only when someone says "optimize."

Both skills must have their `description:` field written to trigger on any work in that language (same trigger as core), not just on keyword mentions like "logging" or "profiling." The body must state: **"This skill co-loads with mx-{topic}-core for ANY {language} work."**

### Scaffold:
```bash
mkdir -p ~/.claude/skill-forge/{topic}/{research,deep-research,drafts,pressure-tests}
```

Write the taxonomy table + session log to disk. Then move to Phase 1.

---

## Phase 1: Existing Work Discovery

**Goal:** Find what already exists. Never reinvent.

### Run 3-5 quicksearches for:
1. GitHub repos with AI coding rules for this technology
2. `.cursorrules` / Cursor rules files
3. Existing Claude Code skills packages
4. AI-specific coding guidelines or best practices
5. Style guides + official recommendations

Use `mcp__gemini__gemini-search` for all searches.

### Output:
- List of repos to analyze (with URLs and what they cover)
- Gaps: what the existing work DOESN'T cover that your taxonomy needs
- Persist to `~/.claude/skill-forge/{topic}/research/existing-work.md`

---

## Phase 2: Quicksearch Saturation

**Goal:** Build the evidence base. This is where the real value comes from — ecosystem-specific, citation-backed patterns that generic AI knowledge misses.

### Search plan:
- **4-5 searches per mode** (only exceed 5 if initial searches reveal significant unexplored depth that would be lost)
- Use `mcp__gemini__gemini-search` — batch up to 6 in parallel
- **Persist findings to disk after every 2 batches** (12 searches max before a disk write)

### Search categories per mode:
1. Best practices + idiomatic patterns
2. Common errors + anti-patterns
3. Ecosystem libraries/tools (the "crate ecosystem" for this mode)
4. AI-specific patterns (what compiles/works on first try from AI-generated code)
5. Production usage patterns (how real projects handle this)
6. FAQ / common developer struggles
7. **Performance optimization** (how to make this mode FAST — not just "not slow")
8. **Observability & monitoring** (how to know this mode is healthy in production)
9. Testing patterns specific to this mode

**Categories 7 and 8 are MANDATORY for every mode.** These are cross-cutting concerns. Every skill must address "how do you make this fast?" and "how do you know it's working?" Do not skip these searches.

### Output format (one file per wave):
```markdown
# {Topic} Skill Research — Wave {N}

## Search {N}: {query}
**Key findings:**
- [finding with citation]
- [finding with citation]
**Patterns for skill:** [which skill this feeds]
```

Write to: `~/.claude/skill-forge/{topic}/research/{topic}-research-wave{N}.md`

### Quality gate:
- Every mode has 4-5 dedicated searches covering the mandatory categories
- Only add more if a mode has clear unexplored depth after the initial pass
- Update session log counters after each wave file is written

---

## Phase 3: Deep Research + Reference Population

**Goal:** Get 3,000-8,000 word technical references with runnable code examples, then immediately wire them into the skill directories as on-demand reference material.

### Process:
1. For each mode, review the quicksearch findings
2. Identify the 1-2 topics that need the MOST depth (complex patterns, many competing approaches, high AI failure rate)
3. Fire **1 deep research prompt per mode** using `mcp__gemini__gemini-deep-research`

### Deep research prompt template:
```
Create a comprehensive guide for {specific topic} in {technology}. Cover:
(1) {Pattern A} — exact code patterns with working examples
(2) {Pattern B} — decision tree for when to use which approach
(3) {Pattern C} — common mistakes and their fixes
(4) {Pattern D} — production configuration with code
(5) {Pattern E} — integration with {ecosystem tool}
Include runnable code examples and anti-rationalization rules
(what AI will be tempted to do wrong and why it fails).
Format: Technical reference with code examples, decision trees, and anti-rationalization rules.
```

### Monitoring:
- Fire all prompts in parallel
- Use `/loop 3m` to poll with `mcp__gemini__gemini-check-research` until all return
- Deep research IDs go in the session log

### Reference Population (MANDATORY — not optional):
When deep research completes, **immediately** extract the markdown content from each result and write it to the draft skill's reference directory:

```bash
# For each completed deep research result:
mkdir -p ~/.claude/skill-forge/{topic}/drafts/mx-{topic}-{mode}/reference
# Extract outputs[1]['text'] from the JSON → deep-research.md
```

The extraction path for Gemini deep research JSONs:
```python
data['outputs'][1]['text']  # The full markdown report
```

This is NOT Phase 7. This happens NOW, before Phase 4 writing begins. The reference material:
- Gives the skill writer access to the full research context during writing
- Gets promoted alongside SKILL.md in Phase 5 (the entire draft directory copies)
- Loads on-demand when the AI hits an edge case beyond what SKILL.md covers

### Output:
- Raw JSONs saved to `~/.claude/skill-forge/{topic}/deep-research/`
- Extracted markdown saved to `~/.claude/skill-forge/{topic}/drafts/mx-{topic}-{mode}/reference/deep-research.md`
- Update session log with completion status
- **Phase 3 is NOT complete until references are populated**

---

## Phase 4: Skill File Writing

**Goal:** Synthesize research into focused, deployable SKILL.md files.

### Read before writing:
- All quicksearch wave files
- All deep research results
- Any existing repos/rules identified in Phase 1

### SKILL.md structure (MANDATORY — every skill follows this):

```markdown
---
name: mx-{topic}-{mode}
description: {200-300 char trigger description with ALL relevant keywords — this is how auto-routing finds the skill}
---

# {Technology} {Mode} — {Subtitle} for AI Coding Agents

**{One sentence: when this skill loads.}**

## When to also load
- {Cross-references to sibling skills in this package}

---

## Level 1: Patterns That Always Work (Beginner)
{3-5 patterns with BAD/GOOD code examples}

## Level 2: {Intermediate Topic} (Intermediate)
{3-5 patterns with decision trees as tables and code}

## Level 3: {Advanced Topic} (Advanced)
{2-3 patterns for expert scenarios}

---

## Performance: Make It Fast
{2-3 optimization patterns specific to THIS mode. Not generic advice —
concrete techniques that make this specific mode measurably faster.
BAD/GOOD pairs showing naive vs optimized approaches.}

## Observability: Know It's Working
{2-3 monitoring/instrumentation patterns for THIS mode.
What to measure, what thresholds to alert on, what to check.
How to detect when this mode is degrading in production.}

---

## Enforcement: Anti-Rationalization Rules

### Rule N: {Short name}
**You will be tempted to:** {exact rationalization AI uses}
**Why that fails:** {concrete production failure scenario}
**The right way:** {exact pattern with code reference}
```

### Constraints (hard limits):
- Each SKILL.md < 500 lines (prevents "lost in the middle")
- Decision trees as TABLES, not prose
- Code examples with BAD/GOOD pairs
- 3-5 anti-rationalization rules per skill
- Cross-references to sibling skills in "When to also load"
- Keyword-rich `description:` field — this is the routing mechanism
- No generic advice — every rule must be backed by research findings
- **EVERY skill MUST have a "Performance: Make It Fast" section** — no exceptions
- **EVERY skill MUST have an "Observability: Know It's Working" section** — no exceptions
- These sections contain mode-specific optimization and monitoring patterns, not generic advice

### Write order:
Write the core/fundamentals skill first (it cross-references everything). Then write the rest in any order.

### Output:
- Draft files at `~/.claude/skill-forge/{topic}/drafts/mx-{topic}-{mode}/SKILL.md`
- Update session log after each skill is written

---

## Phase 5: Promotion

**Goal:** Deploy skills + reference material to production.

```bash
for skill_dir in ~/.claude/skill-forge/{topic}/drafts/mx-{topic}-*/; do
  skill_name=$(basename "$skill_dir")
  # Copy SKILL.md
  mkdir -p ~/.claude/skills/$skill_name
  cp "$skill_dir/SKILL.md" ~/.claude/skills/$skill_name/
  # Copy reference directory (deep research, populated in Phase 3)
  if [ -d "$skill_dir/reference" ]; then
    cp -r "$skill_dir/reference" ~/.claude/skills/$skill_name/
  fi
done
```

### Verification:
- Skills appear in Claude's skill auto-discovery list on the next message
- Count should match the taxonomy from Phase 0
- Each skill directory has both `SKILL.md` and `reference/deep-research.md`

---

## Phase 6: Pressure Test (MANDATORY — not optional)

**Goal:** Prove the skills produce correct code on first try AND that every skill level gets exercised.

### Lesson from Rust + TypeScript packs:
Self-checking agents pass their own code 100% of the time. Independent evaluators catch 5-8 defects per pack. **You MUST use the 2-wave pattern: write agents + independent review agents.**

### Step 1: Design test matrix

Every skill must appear in at least one test. Every skill LEVEL (1, 2, 3) must be exercised somewhere. Build a coverage matrix:

```
| Test | Skills Exercised | Levels Hit |
|------|-----------------|------------|
| Test 1 | A + B + C + D | A:L1, B:L1-2, C:L1, D:L1-2 |
| Test 2 | E + F + G | E:L1-2, F:L1-3, G:L1 |
| Test 3 | H + A + C | H:L1-3, A:L2-3, C:L2 |
```

**Quality gate:** If a skill's Level 2-3 patterns don't appear in ANY test, add a dedicated test for that skill.

### Step 2: Wave 1 — Writing agents (parallel)

Launch 1 agent per test. Each agent:
1. Reads the relevant SKILL.md files + reference/deep-research.md
2. Writes code that exercises all listed patterns
3. Self-checks against the anti-rationalization rules
4. Reports compliance

### Step 3: Wave 2 — Independent compliance evaluators (parallel)

Launch 1 NEW agent per test. Each evaluator:
1. Reads the FULL SKILL.md for every skill the test exercises (not a summary — the whole file)
2. Reads the test code written by Wave 1
3. Checks EVERY anti-rationalization rule, EVERY Level 1/2/3 pattern
4. Reports with this format:

```
### {skill} Compliance
✅ [Rule]: [evidence]
❌ [Rule]: [violation + file:line + fix needed]

### DEFECTS FOUND: {count}
### VERDICT: PASS / FAIL
```

### Step 4: Fix defects

If any evaluator reports defects, fix them and re-run ONLY the failed evaluator (not the whole suite).

### Step 5: Persist results

Write `COMPLIANCE_REPORT.md` to the pressure-tests directory with:
- Self-check results (Wave 1)
- Independent eval results (Wave 2)
- Defects found and fixes applied
- Final verdict per test

**Phase 6 is NOT complete until Wave 2 evaluators all return PASS.**

---

## Naming Convention

- Skill directory: `mx-{topic}-{mode}` (e.g., `mx-nextjs-routing`, `mx-go-concurrency`)
- The `mx-` prefix is a namespace convention to avoid collisions with other skills. Pick your own prefix (e.g., `mx-`, `acme-`, `co-`) and use it consistently across your packages
- Keep mode names to one word when possible

---

## Time Expectations

| Phase | Time |
|-------|------|
| 0: Scope | 15-30min |
| 1: Discovery | 15min |
| 2: Quicksearch | 1.5-3hrs |
| 3: Deep Research | 30-60min |
| 4: Writing | 1-2hrs |
| 5: Promotion | 5min |
| 6: Pressure Test | 30min |
| **Total** | **~4-7 hours** |

---

## Anti-Patterns (Things That Kill Skill Packs)

1. **Skipping research** — Writing from "what I already know" produces generic rules AI already has. The value is ecosystem-specific, citation-backed patterns.
2. **Delegating research to sub-agents** — The skill writer MUST see every search result to synthesize. Sub-agents produce shallow, disconnected findings.
3. **One monolithic skill** — "Lost in the middle" is real. 8 focused skills beat 1 monster file. Split at 500 lines.
4. **No anti-rationalization rules** — Rules without "you will be tempted to" are suggestions. AI WILL find the loophole in every suggestion.
5. **Research only in context, not on disk** — Context compacts. Write to disk after every 2 batches. Losing research to compaction means starting over.
6. **Skipping the pressure test** — Skills that sound good but produce broken code are worthless. Binary test: does AI-generated code work on first try?
7. **Self-checking without independent review** — Writing agents pass themselves 100% of the time. Both Rust and TypeScript packs had ~6 defects that ONLY independent evaluators caught. The 2-wave pattern (write + independent review) is mandatory.
8. **Shallow cross-cutting coverage** — If you have dedicated performance/observability skills, the pressure tests MUST exercise their Level 2-3 patterns, not just graze Level 1. Build a coverage matrix before designing tests.
9. **Reference as afterthought** — Deep research results must be extracted into `reference/` directories DURING Phase 3, not as a post-hoc Phase 7. The reference material informs skill writing and ships alongside the skills.
