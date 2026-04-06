# GCP Operations Validation Checklist

Run AFTER planning/executing any GCP operation, BEFORE claiming completion.

## First Pass (Belt) — Self-Check

### Universal (gcp-observe) — Always Run
- [ ] Resource has cost attribution labels: `project` + `task` (required), `owner` + `ttl` (optional)
- [ ] VM has observability deployed (Ops Agent or node_exporter) BEFORE workload starts
- [ ] Long-running jobs are in tmux/screen, not nohup
- [ ] Structured logs go to a file or external store, not stdout with `\r`
- [ ] CPU reservation: workers ≤ vCPUs - 4
- [ ] Health endpoint or status file exists and is being updated
- [ ] GCP state verified via 2+ sources (never single CLI command)

### gcp-provision (if provisioning GPUs/VMs)
- [ ] Checked `accelerator-types list` for GPU existence in target zone
- [ ] Checked Cloud Quotas API (v1beta + project number) for quota limits
- [ ] Identified 3+ fallback zones for accelerator provisioning
- [ ] Verified interconnect type (NVLink vs PCIe) matches workload requirements
- [ ] Disk IOPS provisioned for workload, not just storage capacity (pd-ssd if DB-heavy)

### gcp-batch-compute (if running batch/spot workloads)
- [ ] Work is checkpointed per-chunk, not end-of-job
- [ ] Artifact freezing (uploads, exports) happens on non-preemptible instance
- [ ] VM reports results to external store before self-terminating
- [ ] Silent skips are logged — VM MUST report "skipped: reason" not just exit 0
- [ ] Disk space math accounts for intermediate files (tar amplification, sort temp)

### gcp-deploy (if deploying containers/networking/auth)
- [ ] Container images built with `--platform=linux/amd64` if targeting GCP from ARM
- [ ] Network and subnet explicitly specified (not relying on defaults or hardcoded VPC names)
- [ ] Auth mechanism verified in target environment before first real use
- [ ] `gcloud storage` used instead of snap-packaged `gsutil`

### gcp-bigquery (if querying BigQuery — HARD GATE)
- [ ] Query has labels: `--label=project:<name> --label=task:<name>`
- [ ] Alternatives exhausted first (APIs, sample tables, cached exports, public extracts)
- [ ] Every query dry-run first (`--dry_run`) with cost estimate shown
- [ ] Cost estimate displayed: `bytes / 1e12 * $6.25 = $X.XX`
- [ ] User approved any query estimated > $1.00
- [ ] Partition filters applied (e.g., `date = '...'` for time-partitioned tables)
- [ ] Column pruning — no `SELECT *` on wide tables
- [ ] `LIMIT` used during development/exploration
- [ ] Cumulative session spend tracked (alert at $10, hard-stop at $25)

## Second Pass (Suspenders) — Triumvirate

For critical GCP operations (production deployments, >$50/hr compute, multi-VM fleets):
1. Dispatch this checklist + operation plan to Gemini AND Codex
2. Majority vote (2/3) on each checklist item
3. Disagreement → surface to user before proceeding
