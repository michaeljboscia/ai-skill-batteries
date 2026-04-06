# AI Skill Batteries

Production-grade skill packages for AI coding agents. 150 skills, 55,000+ lines, 17 technology domains.

These skills encode expert engineering judgment as behavioral constraints — not tutorials or style guides. Each skill starts from **"how does the AI screw this up?"** and builds anti-rationalization rules that structurally prevent the mistake.

## What's a skill?

A skill is a `SKILL.md` file that an AI coding agent (Claude Code, Cursor, etc.) loads into context when working in a specific technology domain. It contains:

- **Decision trees** — when to use what pattern, with tradeoffs
- **Anti-rationalization rules** — hard behavioral blocks the AI cannot shortcut past
- **Failure modes** — specific ways AI agents get this technology wrong
- **Verification checkpoints** — how to prove correctness

Skills are designed for [Claude Code](https://claude.ai/code) but the patterns are portable to any AI coding agent that supports custom instructions.

## Repository Structure

```
cloud/
  aws/           25 skills — Lambda, EKS, IAM, DynamoDB, S3, CDN, CI/CD, networking, security
  gcp/           16 skills — GKE, Vertex AI, BigQuery, Cloud Run, IAM, networking, security
  gpu/            3 skills — model inference, RunPod, Vast.ai

languages/
  go/            10 skills — concurrency, HTTP, CLI, data, testing, observability, performance
  python/        10 skills — asyncio, FastAPI, SQLAlchemy, Polars, pytest, structlog, OTel
  rust/          10 skills — async, networking, data, systems, testing, observability, performance
  typescript/     8 skills — strict typing, async, Node.js, validation, testing, performance

frameworks/
  gsap/           4 skills — React integration, text animation, performance, debugging
  lottie/         4 skills — loading, interactivity, performance, observability
  nextjs/         8 skills — App Router, RSC, data fetching, middleware, SEO, deployment
  react/          8 skills — components, state, effects, forms, routing, data, testing, perf
  tailwind/       8 skills — v4 design systems, components, layout, animation, responsive, perf

platforms/
  hubspot/       16 skills — contacts, deals, companies, marketing, CMS, automation, commerce
  supabase/      10 skills — auth/RLS, schema, Edge Functions, queries, indexes, Realtime
  wordpress/      7 skills — WPGraphQL, ACF Pro, auth, media, deployment, observability

meta/             3 skills — reality-check, silent-bypass, signal-grounded-email

skill-forge/      The factory — build your own skill packages with /skill-forge
```

## Quick Start

```bash
# Clone and install everything
git clone https://github.com/michaeljboscia/ai-skill-batteries.git
cd ai-skill-batteries
./install.sh

# Or install just one package
./install.sh python

# Skills auto-load in Claude Code based on what you're working on.
# No manual invocation needed.
```

## Installation

### Install everything

```bash
git clone https://github.com/michaeljboscia/ai-skill-batteries.git
cd ai-skill-batteries
./install.sh
```

### Install specific packages

```bash
./install.sh python          # Just Python skills
./install.sh aws gcp         # AWS + GCP
./install.sh react nextjs    # React + Next.js
```

### Manual install

Copy any skill directory into `~/.claude/skills/`:

```bash
cp -r languages/python/mx-py-core ~/.claude/skills/
```

Claude Code automatically discovers skills in `~/.claude/skills/` and loads them based on the `description` field in each `SKILL.md` frontmatter.

To remove skills, delete the corresponding directory from `~/.claude/skills/`. To update, re-run `./install.sh` -- it overwrites existing files.

### Cursor

Copy the `SKILL.md` content into a `.cursorrules` file or Cursor's rules configuration. The anti-rationalization rules translate directly to Cursor's instruction format.

### Other AI Coding Tools

The `SKILL.md` files are plain Markdown with YAML frontmatter. Paste into any tool that supports custom instructions or system prompts.

## How skills work

Each skill has a `description` field that tells the AI agent **when** to load it:

```yaml
---
name: mx-react-core
description: React component architecture, JSX, props, composition patterns...
---
```

When you're working on React components, the agent loads `mx-react-core`. When you're writing Supabase RLS policies, it loads `mx-supa-auth`. The routing is automatic — you don't manually invoke skills.

### Anti-rationalization rules

The core innovation. Every skill contains rules like:

> **You will be tempted to:** Use `supabase.auth.getSession()` in a server action because it's faster than `getUser()`.
>
> **Why that fails:** `getSession()` reads from local storage — the JWT is unverified and spoofable. Any security decision based on it is bypassable.
>
> **The right way:** Use `supabase.auth.getUser()` for all server-side security decisions.

These aren't suggestions. They're structural constraints that prevent the AI from taking shortcuts that look correct but fail in production.

## Build Your Own Skills

The repo includes `skill-forge/` — the same multi-phase factory process used to build every package in this repo. Install it and run `/skill-forge` in Claude Code:

```bash
./install.sh skill-forge
```

Then in any Claude Code session:
```
/skill-forge react-native
```

It walks through 6 phases: scope definition, existing work discovery, quicksearch saturation, deep research, skill writing, and pressure testing with independent compliance evaluators. Each phase persists to disk so you can resume after context compaction.

## Philosophy

1. **Failure-mode-first** — every skill starts from "how does the AI get this wrong?" not "what does good code look like?"
2. **Anti-rationalization** — the AI will always have a plausible reason to take a shortcut. The rules block the rationalization, not just the behavior.
3. **Verification built-in** — every skill includes observability and performance sections with specific things to measure.
4. **Co-loading** — performance and observability skills auto-load alongside their domain skill. You can't write React code without the perf skill also being active.

## Attribution

See [ATTRIBUTION.md](ATTRIBUTION.md) for the full list of sources, repositories, documentation, and tools that informed these skills.

## License

MIT

## Author

Michael Boscia ([@michaeljboscia](https://github.com/michaeljboscia))

Built with [Claude Code](https://claude.ai/code). Each skill package is pressure-tested with independent compliance evaluators before release.
