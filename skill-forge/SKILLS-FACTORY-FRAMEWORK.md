# Skills Factory Framework

**Version:** 1.0
**Created:** 2026-04-04
**Proven by:** Rust Skills Package (8 skills, single session, from zero to deployed)

This framework codifies the exact process for building language-specific or platform-specific AI coding skills packages. It was reverse-engineered from the first successful execution (Rust, April 2026) after months of failed attempts.

---

## Why Previous Attempts Failed

1. **Monolithic skill files** — tried cramming everything into one SKILL.md. Hit "lost in the middle" — AI ignored rules buried in 2,000+ line files.
2. **No research phase** — jumped straight to writing rules from general knowledge. Rules were generic, lacked citations, missed ecosystem-specific patterns.
3. **No anti-rationalization rules** — skills told AI what TO do but not what it would be TEMPTED to do wrong. AI found loopholes.
4. **No difficulty layering** — mixed beginner and expert patterns. AI couldn't distinguish "always do this" from "consider this in advanced cases."
5. **No provenance** — rules without citations are opinions. Citations make rules verifiable and trustworthy.

---

## The 7-Phase Pipeline

### Phase 0: Scope Definition (30 minutes)

**Input:** A language/platform the user wants AI agents to write better code in.

**Process:**
1. Find the original motivation. What project will USE these skills? (Rust → triumvirate daemon)
2. Identify the "modes of work" — distinct categories of coding activity that use different mental models, libraries, and failure modes.
3. Each mode becomes a separate skill. Target: 6-10 modes per language.

**Output:** A taxonomy table:

```
| # | Mode | What You're Doing | AI Failure Mode | Skill Name |
|---|------|-------------------|-----------------|------------|
| 1 | Fundamentals | Writing any code | Lifetime soup, .unwrap() | mx-{lang}-core |
| 2 | Async | Concurrent work | Deadlocks, blocking | mx-{lang}-async |
| ... | | | | |
```

**Quality gate:** Each mode must have a distinct AI failure mode. If two modes share the same failure mode, merge them.

### Phase 1: Existing Work Discovery (15 minutes)

**Input:** The taxonomy from Phase 0.

**Process:**
Run 3-5 quicksearches specifically for:
1. Existing GitHub repos with AI coding rules for this language
2. Cursor rules / .cursorrules files for this language
3. Claude Code skills packages that already exist
4. AI-specific coding guidelines or best practices

**Output:** A list of repos to clone/analyze, with notes on what they cover and what they miss.

**Why this matters:** Don't reinvent. The Rust package found `leonardomso/rust-skills` (179 rules), `Rannar/rustic-prompt`, and `aipack-ai/packs-pro`. These become seed material.

### Phase 2: Quicksearch Saturation (2-3 hours)

**Input:** The taxonomy + existing repos.

**Process:**
- Run **4-5 Gemini quicksearches per mode** (target ~5 per mode unless the domain is exceptionally broad)
- Only exceed 5 per mode if initial searches reveal significant unexplored depth that would be lost
- All searches in main context window (no agent delegation — you need to see and synthesize)
- Batch 6 searches at a time (parallel MCP calls)
- **Persist findings to disk after every 2 batches** (context compaction will eat unsaved results)

**Search categories per mode:**
1. Best practices + patterns (what TO do)
2. Common errors + anti-patterns (what NOT to do)
3. Ecosystem crates/libraries (what tools exist)
4. AI-specific patterns (what compiles on first try for AI-generated code)
5. Prior art (how do production projects handle this?)
6. FAQ / troubleshooting (what do developers struggle with?)
7. **Performance optimization** (how to make this mode FAST — not just "not slow")
8. **Observability & monitoring** (how to know this mode is healthy in production)
9. Testing patterns specific to this mode
10. Configuration / setup patterns
11. Advanced / expert patterns

**Categories 7 and 8 are MANDATORY for every mode.** These are cross-cutting concerns — every skill must address "how do you make this fast?" and "how do you know it's working?" They are not optional searches to skip when time is short.

**Output:** Research wave files persisted to `~/.claude/skill-forge/{lang}/research/`

**Quality gate:** Every mode has 4-5 searches covering the mandatory categories. Only add more if a mode has clear unexplored depth after the initial pass.

### Phase 3: Deep Research (30-60 minutes)

**Input:** Quicksearch findings.

**Process:**
- For each mode, synthesize quicksearch findings to identify the 2-3 MOST IMPORTANT topics
- Fire **1 Gemini deep research prompt per mode** (7-10 total)
- Each prompt should be 200-400 words, highly specific, requesting:
  - Code examples that compile on first try
  - Decision trees for common choices
  - Anti-rationalization rules
  - Architecture patterns described in text

**Deep research prompt template:**
```
Create a comprehensive guide for [specific topic] in [language]. Cover:
(1) [Pattern A] — exact code patterns with examples
(2) [Pattern B] — decision tree for when to use which approach
(3) [Pattern C] — common mistakes and their fixes
(4) [Pattern D] — production configuration with code
(5) [Pattern E] — integration with [ecosystem tool]
Include runnable code examples and anti-rationalization rules
(what AI will be tempted to do wrong and why it fails).
Format: Technical reference with code examples, decision trees, and anti-rationalization rules.
```

**Output:** Deep research JSON files at `~/.claude/gemini-output/`

**Timing:** Fire all prompts in parallel. Set up a `/loop` to poll for completion every 3 minutes.

**Quality gate:** Each deep research result should be 3,000-8,000 words with code examples.

### Phase 4: Skill File Writing (1-2 hours)

**Input:** Quicksearch wave files + deep research results.

**Process:**
Write one SKILL.md per mode. Each follows this exact structure:

```markdown
---
name: mx-{lang}-{mode}
description: [200-300 char trigger description with all relevant keywords]
---

# {Lang} {Mode} — {Subtitle} for AI Coding Agents

**[One sentence explaining when this loads.]**

## When to also load
- [Cross-references to other skills in the package]

---

## Level 1: Patterns That Always Work (Beginner)
[3-5 patterns with BAD/GOOD code examples]

## Level 2: {Intermediate Topic} (Intermediate)
[3-5 patterns with decision trees and code]

## Level 3: {Advanced Topic} (Advanced)
[2-3 patterns for expert scenarios]

---

## Performance: Make It Fast
[2-3 optimization patterns specific to THIS mode. Not generic advice —
concrete techniques that make this specific mode measurably faster.
BAD/GOOD pairs showing naive vs optimized approaches.]

## Observability: Know It's Working
[2-3 monitoring/instrumentation patterns specific to THIS mode.
What to measure, what thresholds to alert on, what dashboards to check.
How to detect when this mode is degrading in production.]

---

## Enforcement: Anti-Rationalization Rules

### Rule N: [Short name]
**You will be tempted to:** [exact rationalization AI uses]
**Why that fails:** [concrete production failure scenario]
**The right way:** [exact pattern with code reference]
```

**Constraints:**
- Each SKILL.md < 500 lines (prevents "lost in the middle")
- Decision trees as tables, not prose
- Code examples with BAD/GOOD pairs
- 3-5 anti-rationalization rules per skill
- Cross-references to sibling skills ("When to also load")
- Keyword-rich `description:` field for auto-trigger routing

**Output:** Draft SKILL.md files at `~/.claude/skill-forge/{lang}/drafts/`

### Phase 5: Promotion (5 minutes)

**Input:** Draft skill files.

**Process:**
```bash
for skill in mx-{lang}-*; do
  mkdir -p ~/.claude/skills/$skill/reference
  cp ~/.claude/skill-forge/{lang}/drafts/$skill/SKILL.md ~/.claude/skills/$skill/
done
```

**Verification:** Skills appear in Claude's skill list on next message.

### Phase 6: Pressure Test (next session)

**Input:** Deployed skills.

**Process:**
1. Open the target project (e.g., triumvirate for Rust)
2. Ask the AI to write a non-trivial piece of code that exercises multiple modes
3. **Does it compile on first try?**
4. **Does it follow the patterns from the skills?**
5. **Does it avoid the anti-patterns?**

**Test prompt template:**
```
Write a Rust program that:
1. Spawns a PTY subprocess running `bash`
2. Reads its output asynchronously
3. Streams the output to a WebSocket client via axum
4. Handles graceful shutdown on SIGTERM
5. Logs everything with the tracing crate
```

This exercises: core, async, systems, network — 4 of 8 skills simultaneously.

**Quality gate:** Code compiles. Code follows skill patterns. Code avoids anti-patterns. If any fail, update the skill and re-test.

### Phase 7: Reference Population (optional, next session)

**Input:** Deep research JSON files.

**Process:**
- Extract the full deep research results from JSON
- Write them as markdown in each skill's `reference/` directory
- These are the citation-rich backing material that AI reads on demand

```
~/.claude/skills/mx-rust-async/
  SKILL.md              ← Rules (always loaded)
  reference/
    channels.md         ← Full deep research on channel patterns (loaded on demand)
    select-patterns.md  ← Full deep research on select! (loaded on demand)
```

---

## Skill Forge Directory Structure

```
~/.claude/skill-forge/
  README.md                          ← What this is
  SKILLS-FACTORY-FRAMEWORK.md        ← This document
  {lang}/                            ← One directory per language
    research/                          ← Quicksearch wave files
    deep-research/                     ← Deep research results (or symlinks to gemini-output/)
    drafts/                            ← SKILL.md drafts before promotion
      mx-{lang}-{mode}/
        SKILL.md
        reference/
    session-log.md                     ← Session notes
```

---

## Time Expectations

| Phase | Time | Notes |
|-------|------|-------|
| Phase 0: Scope | 30min | Define taxonomy |
| Phase 1: Discovery | 15min | 3-5 quicksearches |
| Phase 2: Quicksearch | 2-3hrs | 40-100 quicksearches |
| Phase 3: Deep Research | 30-60min | 7-10 deep research prompts (parallel) |
| Phase 4: Writing | 1-2hrs | Synthesis from research |
| Phase 5: Promotion | 5min | Copy files |
| Phase 6: Pressure Test | 30min | Next session |
| **Total** | **~5-7 hours** | Single session possible |

---

## Anti-Patterns in Skill Development

### 1. Don't Skip Research
Writing skills from "what I already know" produces generic rules that AI already knows. The value is in ecosystem-specific, citation-backed patterns.

### 2. Don't Use Agents for Research
The person writing skills MUST see every search result to synthesize correctly. Delegating research to sub-agents produces shallow, disconnected findings.

### 3. Don't Write One Big Skill
"Lost in the middle" is real. 8 focused skills beat 1 monolithic skill. If your SKILL.md exceeds 500 lines, split it.

### 4. Don't Forget Anti-Rationalization
Rules without "you will be tempted to" are suggestions. Rules WITH them are guardrails. AI will find the loophole in every suggestion. Anti-rationalization rules close the loopholes.

### 5. Don't Persist Research Only in Context
Context compacts. Search results vanish. Write to disk after every 2 batches. If you lose research to compaction, you're starting over.

### 6. Don't Skip the Pressure Test
Skills that sound good but produce code that doesn't compile are worthless. The test is binary: does AI-generated code compile on first try? Yes or no.

---

## Candidate Languages/Platforms for Next Packages

| Language | Motivation | Est. Modes |
|----------|-----------|------------|
| Go | Triumvirate v2 was almost Go. Common AI target. | 6-8 |
| TypeScript/Node | Edge functions, Svelte dashboard, MCP servers | 8-10 |
| Python | AI/ML pipelines, Prefect flows, FastAPI | 6-8 |
| SQL/PostGIS | Supabase, spatial queries, migrations | 4-6 |
| Terraform/Pulumi | Infrastructure as code | 3-5 |
| Bash/Shell | Hooks, automation scripts, CI | 3-4 |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-04-04 | Initial framework from Rust skills package execution |
