---
name: mx-gcp-operations
description: Use when provisioning GCP VMs, GPUs, or accelerators, running batch/spot workloads, deploying containers to GCP, configuring GCP networking or auth, querying BigQuery, or any operation touching GCP Compute Engine, Cloud Run, GKE, or BigQuery. Also use when the user mentions 'gcloud', 'GCP', 'Google Cloud', 'Compute Engine', 'spot VM', 'preemptible', 'GPU quota', 'accelerator', 'startup script', 'BigQuery', 'bq', 'HTTP Archive', or 'CRuX dataset'.
---

# GCP Operations Matrix

**Core principle:** GCP is an opaque policy engine, not a transparent scaling layer. Local assumptions do not transfer. Every abstraction has hidden behaviors. Fixes designed but not deployed as code are nonexistent.

## Operating Mode

| Mode | When | Claude's Role |
|---|---|---|
| **Build** | Creating infrastructure (Terraform, startup scripts, Packer images) | Infrastructure engineer — enforce all rules |
| **Execute** | Running workloads on existing infra | Operator — enforce runtime rules (observe, batch, preemption) |
| **Direct** | Querying GCP state (quotas, zones, pricing) | Investigator — enforce verification rules (multi-source, never trust one API) |

## Routing

Determine which tiers apply. **Observe tier fires for Build and Execute modes.**

| If the task involves... | Load these tiers |
|---|---|
| GPUs, accelerators, quotas, machine types | `gcp-provision` + `gcp-observe` |
| Batch jobs, spot/preemptible VMs, long-running compute | `gcp-batch-compute` + `gcp-observe` |
| Docker, containers, networking, auth, cross-platform deploy | `gcp-deploy` + `gcp-observe` |
| BigQuery queries, data warehouse access, HTTP Archive, CRuX | `gcp-bigquery` (HARD GATE — cost forecast before any query) |
| Querying GCP state only (Direct mode) | Only the relevant tier (provision/batch/deploy) — skip observe |
| Any GCP operation not covered above | `gcp-observe` (minimum) |

Read `enforcement.md` for rules. Run `validation.md` checklist before completing any GCP operation.

## Cross-References

| If the task also involves... | Co-load this matrix |
|---|---|
| AI models, VRAM sizing, serving frameworks, quantization | `mx-gpu-inference` — handles the AI/ML layer on top of GCP infra |
| Batch processing, parallel workers, long-running compute | `batch-compute-discipline` — per-chunk verification, contention analysis |

**GPU deployments ALWAYS fire both `mx-gcp-operations` AND `mx-gpu-inference`.** This matrix handles provisioning, networking, auth, and observability. `mx-gpu-inference` handles model selection, VRAM math, serving config, and cost control.
