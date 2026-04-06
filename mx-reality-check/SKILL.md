---
name: mx-reality-check
description: Use when writing tests, verifying work, or completing any task that produces code/infrastructure/content. Routes to tier-specific verification playbooks. Also use when reviewing test suites to check if they verify behavior or just structure.
---

# Reality Check Matrix

## Operating Mode

| Mode | When | Claude's Role |
|---|---|---|
| **Build** | Writing new tests or verification for a system | Test engineer — write E2E tests per tier |
| **Execute** | System exists, need to verify it works | Verifier — run the playbook, report results |
| **Review** | Reviewing existing tests or quality gates | Auditor — check if tests exercise critical path |

## Tier Routing

Determine which tier applies to the current work:

| Tier | Trigger | Verification Method |
|---|---|---|
| **T1: CLI/Process** | Anything touching PIDs, signals, sessions, daemons, filesystems | Spawn real processes, assert OS truth |
| **T2: Data Pipelines** | Batch processing, ETL, sensors, pre-compute, database operations | Source-to-sink reconciliation, poison pill |
| **T3: Web/UI** | Frontends, prototypes, user-facing pages, APIs | Headless browser E2E, persistence checks |
| **T4: LLM Content** | Summaries, notes, classifications, any LLM output presented as fact | Grounding verification against source |
| **T5: Infrastructure** | Cloud resources, deployments, IAM, networking, containers | Provision → hit → verify → destroy |

Multiple tiers can apply to one system. nudge-reaper was T1 + T4 and needed verification for both.

Read `enforcement.md` for per-tier rules. Run `validation.md` checklist before presenting output.
