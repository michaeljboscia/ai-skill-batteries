# Contributing to AI Skill Batteries

## Adding a Skill

Every skill is a `SKILL.md` file inside a directory under the appropriate category (`languages/`, `frameworks/`, `platforms/`, `cloud/`, `meta/`).

### Required structure

```markdown
---
name: mx-{topic}-{mode}
description: 200-300 char trigger description with ALL relevant keywords
---

# {Technology} {Mode} — {Subtitle} for AI Coding Agents

## When to also load
- Cross-references to sibling skills

## Level 1: Patterns That Always Work (Beginner)
## Level 2: {Intermediate Topic} (Intermediate)
## Level 3: {Advanced Topic} (Advanced)

## Performance: Make It Fast
## Observability: Know It's Working

## Enforcement: Anti-Rationalization Rules
```

### Required elements

- **YAML frontmatter** with `name` and `description` fields. The `description` field is how auto-routing discovers the skill -- make it keyword-rich.
- **Three levels** (Beginner, Intermediate, Advanced) with code examples at each level.
- **BAD/GOOD code pairs** showing the wrong way and the right way.
- **Decision tables** for choosing between approaches (tables, not prose).
- **Performance section** with mode-specific optimization patterns.
- **Observability section** with monitoring/instrumentation patterns.
- **3-5 anti-rationalization rules** in the Enforcement section, each following the format:
  - "You will be tempted to:" (the exact shortcut the AI will try)
  - "Why that fails:" (concrete production failure)
  - "The right way:" (exact pattern with code)

### Constraints

- Each SKILL.md must be under 500 lines (prevents "lost in the middle" context degradation).
- No generic advice -- every rule must be backed by real failure modes or research.
- Cross-reference sibling skills in the "When to also load" section.

## Building a New Package with Skill Forge

To create a complete multi-skill package for a new technology:

1. Install the skill-forge: `./install.sh skill-forge`
2. In a Claude Code session, run `/skill-forge {technology}`
3. Follow the 6-phase process: scope, discovery, research, deep research, writing, pressure testing

See `skill-forge/SKILLS-FACTORY-FRAMEWORK.md` for the full factory process and rationale.

## PR Requirements

Before submitting a pull request:

1. **Anti-rationalization rules are mandatory.** Every skill must have 3-5 rules in the "You will be tempted to / Why that fails / The right way" format.
2. **BAD/GOOD pairs are mandatory.** Every Level 1-2 pattern must show the wrong way and the right way with code.
3. **Decision tables are mandatory.** When choosing between approaches, present a table with tradeoffs -- not prose paragraphs.
4. **Performance and Observability sections are mandatory.** Every skill must address "how do you make this fast?" and "how do you know it's working?"
5. **Skill must be under 500 lines.** If it's longer, split into multiple skills.
6. **Description field must be keyword-rich.** This is the routing mechanism -- if it doesn't contain the right keywords, the skill won't load when needed.
7. **Namespace prefix.** Use a consistent prefix for your skills (e.g., `mx-`, `acme-`). Don't use bare names.

## File Organization

```
{category}/{package}/mx-{prefix}-{mode}/
  SKILL.md           # The skill file (required)
  reference/         # Deep research and supplementary material (optional)
```

Categories: `cloud/`, `languages/`, `frameworks/`, `platforms/`, `meta/`
