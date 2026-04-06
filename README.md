# AI Skill Batteries

Production-grade skill packages for AI coding agents. 135 skills, 51,000+ lines, 15 technology domains.

These skills encode expert engineering judgment as behavioral constraints — not tutorials or style guides. Each skill starts from **"how does the AI screw this up?"** and builds anti-rationalization rules that structurally prevent the mistake.

## What's a skill?

A skill is a `SKILL.md` file that an AI coding agent (Claude Code, Cursor, etc.) loads into context when working in a specific technology domain. It contains:

- **Decision trees** — when to use what pattern, with tradeoffs
- **Anti-rationalization rules** — hard behavioral blocks the AI cannot shortcut past
- **Failure modes** — specific ways AI agents get this technology wrong
- **Verification checkpoints** — how to prove correctness

Skills are designed for [Claude Code](https://claude.ai/code) but the patterns are portable to any AI coding agent that supports custom instructions.

## Packages

| Package | Skills | Domain |
|---------|--------|--------|
| `mx-aws-*` | 25 | AWS services — Lambda, EKS, IAM, DynamoDB, S3, CDN, CI/CD, networking, security, observability |
| `mx-gcp-*` | 16 | Google Cloud — GKE, Vertex AI, BigQuery, Cloud Run, IAM, networking, security, observability |
| `mx-hubspot-*` | 16 | HubSpot API — contacts, deals, companies, marketing, CMS, automation, admin, commerce |
| `mx-go-*` | 10 | Go — concurrency, HTTP, CLI, data, testing, observability, performance |
| `mx-rust-*` | 10 | Rust — async, networking, data, systems, testing, observability, performance |
| `mx-supa-*` | 10 | Supabase — auth/RLS, schema, Edge Functions, queries, indexes, diagnostics, Realtime |
| `mx-react-*` | 8 | React — components, state, effects, forms, routing, data fetching, testing, performance |
| `mx-nextjs-*` | 8 | Next.js App Router — RSC, data fetching, middleware, SEO, deployment, observability |
| `mx-ts-*` | 8 | TypeScript — strict typing, async, Node.js, validation, testing, observability, performance |
| `mx-tw-*` | 8 | Tailwind CSS v4 — design systems, components, layout, animation, responsive, performance |
| `mx-wp-*` | 7 | Headless WordPress — WPGraphQL, ACF Pro, auth, media, deployment, observability |
| `mx-gsap-*` | 4 | GSAP animation — React integration, text animation, performance, debugging |
| `mx-gpu-*` | 3 | GPU infrastructure — model inference, RunPod, Vast.ai |
| `mx-reality-check` | 1 | Universal verification gate — 7 rules + 5-tier matrix for any task completion |
| `mx-silent-bypass` | 1 | Plan execution discipline — prevents silent workarounds during implementation |

## Installation

### Claude Code

Copy any skill directory into `~/.claude/skills/`:

```bash
# Single skill
cp -r mx-react-core ~/.claude/skills/

# Entire package
cp -r mx-react-* ~/.claude/skills/

# Everything
cp -r mx-* ~/.claude/skills/
```

Claude Code automatically discovers skills in `~/.claude/skills/` and loads them based on the `description` field in each `SKILL.md` frontmatter.

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

## Philosophy

1. **Failure-mode-first** — every skill starts from "how does the AI get this wrong?" not "what does good code look like?"
2. **Anti-rationalization** — the AI will always have a plausible reason to take a shortcut. The rules block the rationalization, not just the behavior.
3. **Verification built-in** — every skill includes observability and performance sections with specific things to measure.
4. **Co-loading** — performance and observability skills auto-load alongside their domain skill. You can't write React code without the perf skill also being active.

## License

MIT

## Author

Michael Boscia ([@michaeljboscia](https://github.com/michaeljboscia))

Built with Claude Code, pressure-tested against real production systems.
