# GCP Operations Enforcement

## Universal Tier: gcp-observe (ALWAYS FIRES)

### Rule 0: Mandatory Cost Attribution Labels
Every GCP resource MUST have labels applied at creation time. No exceptions. Labels flow to billing export and are the only way to attribute costs to projects/tasks.

**Required labels (ALL resources — VMs, BQ jobs, GCS buckets, disks):**
- `project` — which project this serves (e.g., `backend-api`, `data-pipeline`, `ml-training`)
- `task` — what work this is doing (e.g., `inference`, `batch-etl`, `api-scrape`, `monitoring`)

**Optional labels:**
- `owner` — who launched it (e.g., `team-backend`, `ci-pipeline`, `deploy-bot`)
- `ttl` — expected lifetime (e.g., `4h`, `1d`, `persistent`)

**Compute Engine:**
```bash
gcloud compute instances create my-vm \
  --labels=project=backend-api,task=batch-etl,owner=ci-pipeline,ttl=4h
```

**BigQuery jobs:**
```bash
bq query --label=project:analytics --label=task:daily-export \
  --use_legacy_sql=false 'SELECT ...'
```

**Python BigQuery client:**
```python
job_config = bigquery.QueryJobConfig(labels={"project": "data-pipeline", "task": "daily-export"})
client.query(query, job_config=job_config)
```

**This is a hard gate.** If you create a VM or run a BQ job without labels, the billing dashboard shows anonymous UUIDs instead of project names. We learned this the hard way: $586 in March 2026 with zero attribution until after-the-fact forensics.

### Rule 1: No Blind Boxes
Every GCP VM must have observability deployed BEFORE workloads start. Not after. Not "when we have time." Before.

Minimum observability stack (ALL required, not pick-and-choose):
- GCP Ops Agent OR node_exporter on :9100 (hardware metrics)
- AND structured JSON logs to `/var/log/<project>/` (never stdout with `\r`)
- AND long-running jobs in tmux/screen session (never nohup)
- AND health file or HTTP endpoint updated every N seconds with current status
- AND CPU reservation: never use more than vCPUs-4 workers

**Fail-closed rule:** If observability cannot be confirmed as deployed, the workload MUST NOT start. This is not a checklist item — it is a hard gate. Observability must be in the startup script or Packer image, not a manual step.

**You will be tempted to:** "Just SSH in and tail the logs — I'll add monitoring later."
**Why that fails:** On 2026-03-19, 32 workers saturated a 48-vCPU VM. SSH died. Zero visibility into a $2.09/hr machine for 40+ minutes. User stayed up until 3 AM. You designed the fix and STILL deployed blind VMs afterward. "Later" never comes.

**The right way:**
1. Bake Ops Agent into a Packer golden image or startup script (runs before workload)
2. Configure Ops Agent YAML for structured JSON log parsing + DCGM v2 GPU metrics
3. App logs write JSON with `severity` and `timestamp` keys to `/var/log/<project>/app.log`
4. Add a `shutdown-script` metadata key that flushes state in the 30-second preemption window
5. Emit a custom heartbeat metric (e.g., `tasks_processed_per_minute`) — alert if it flatlines for >10 min while VM is still running
6. Startup script emits lifecycle stages to Cloud Logging — alert if `startup_complete` isn't seen within 5 min of VM creation

```yaml
# /etc/google-cloud-ops-agent/config.yaml
logging:
  receivers:
    app_logs:
      type: files
      include_paths: ["/var/log/<project>/*.log"]
  processors:
    parse_json:
      type: parse_json
      time_key: timestamp
      time_format: "%Y-%m-%dT%H:%M:%S.%L%z"
  service:
    pipelines:
      app: { receivers: [app_logs], processors: [parse_json] }
metrics:
  receivers:
    dcgm_v2:
      type: dcgm
      collection_interval: 10s
```

### Rule 2: Multi-Source Verification
Never declare GCP state from a single API or CLI command. Always verify with a second source.

- Quotas: `accelerator-types list` for existence + Cloud Quotas API (v1beta, project NUMBER) for limits
- Never use `gcloud compute regions describe` as sole quota source — it's blind to newer GPU types
- If user evidence (email, screenshot, console) contradicts CLI → investigate the CLI, not the evidence

**You will be tempted to:** "I checked the CLI three times, the metric doesn't exist."
**Why that fails:** On 2026-03-20, dismissed a legitimate quota approval email because `gcloud compute regions describe` showed no RTX Pro 6000 metric. Console showed 16 GPUs the whole time. The CLI queries a legacy API that doesn't surface newer accelerator types.

**The right way:**
```bash
# Step 1: Does the GPU type exist in target zones?
gcloud compute accelerator-types list --filter="name=nvidia-h100-80gb AND zone~us-"

# Step 2: What's my quota? (Cloud Quotas API — v1beta + project NUMBER)
curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://cloudquotas.googleapis.com/v1beta/projects/<PROJECT_NUMBER>/locations/global/services/compute.googleapis.com/quotaInfos?pageSize=500" \
  | python3 -c "import json,sys; [print(q['quotaId'],q.get('dimensionsInfos',[{}])[0].get('details',{}).get('value','?')) for q in json.load(sys.stdin).get('quotaInfos',[]) if 'H100' in q.get('quotaId','')]"

# Step 3: If either disagrees with user evidence, trust the user evidence and investigate the API
```

---

## Tier: gcp-provision (GPUs, VMs, Accelerators, Quotas)

### Rule 2.5: Check Golden Images Before Building Anything (HARD GATE)

Before provisioning any GPU VM or running any Packer build, check whether a golden image already exists for the workload.

```bash
gcloud compute images list --project=<your-project-id> --filter="name~gpu-golden" --format="table(name,status)"
```

Full specs and launch commands: see your project's golden image reference docs.

**You will be tempted to:** "I'll just build a fresh image to make sure I have the right versions."
**Why that fails:** On 2026-03-25, a T4 embedding image was built from scratch (15 min Packer build) only to discover gte-Qwen2 cannot run on sm_75 — a fact that was in the reference file. The existing L4 embedding image already worked. 45+ minutes wasted.

**The right way:**
1. Run the `images list` command above
2. If an image family covers the workload → use it, do not rebuild
3. Only rebuild if driver/container/model versions actually need updating (check `reference/golden-images.md` for rebuild criteria)

### Rule 3: Zone Capacity Is Not Guaranteed
Never assume a zone has capacity for any accelerator type. Always have fallback zones.

- Query available zones: `gcloud compute accelerator-types list --filter="name=<type>"`
- For GPU workloads, identify 3+ zones across at least 2 regions before attempting provisioning
- Prefer non-throttled regions for spot (us-west1, us-south1, us-east5 over us-central1, us-east4)
- Note: `accelerator-types list` confirms existence, not live capacity — provisioning can still fail

**You will be tempted to:** "us-central1-a is the default, it'll have T4s."
**Why that fails:** On 2026-03-06, us-central1-a was completely exhausted of T4 capacity. Deployment blocked until manually rewriting scripts for us-central1-b.

**The right way:**
- Use `--region` instead of `--zone` with `gcloud compute instances bulk create` — GCP auto-selects a zone with capacity
- Or use Regional Managed Instance Groups (MIGs) — they auto-spread across zones
- Match machine family to GPU: A3 → H100, A2 → A100, G2 → L4, N1 → T4/V100
- Always set `--maintenance-policy=TERMINATE` (GPU state can't live-migrate)
- Use `--restart-on-failure=true` for on-demand VMs (auto-reboot after maintenance)
- Use DLVM images (`--image-family=pytorch-latest-gpu --image-project=deeplearning-platform-release`) or `--metadata=install-nvidia-driver=True`

### Rule 4: Know Your Interconnect Before Multi-GPU
Multi-GPU does not mean linear scaling. The interconnect determines whether tensor parallelism is viable.

- NVLink (A100, H100, H200, B200): viable for tensor parallelism
- PCIe (T4, L4, RTX Pro 6000): pipeline parallelism or independent models only
- Check `maximumCardsPerInstance` via `accelerator-types describe`

**You will be tempted to:** "4x T4 = 64GB VRAM, should run a 70B model via tensor parallelism."
**Why that fails:** On 2026-03-04, 4x T4 tensor-parallel was slower than 4 independent small models. PCIe bandwidth (~32 GB/s) vs NVLink (~900 GB/s) is a 28x gap. That's physics, not config.

### Rule 5: Disk IOPS Scale With Disk Size, Not VM Size
GCP persistent disk IOPS are a function of provisioned disk GB, not vCPU count.

- pd-standard: 0.75 read IOPS/GB, 1.5 write IOPS/GB
- pd-ssd: 30 read IOPS/GB, 30 write IOPS/GB
- A 100GB pd-standard on a 48-vCPU machine = 75 read IOPS (bicycle tires on a freight train)
- For database workloads: provision disk for IOPS, not just storage capacity

**You will be tempted to:** "48 vCPUs should make the database fast."
**Why that fails:** A 48-vCPU GCP VM benchmarked at 30 parcels/sec vs 42 on a local server. The CPU was starving waiting for disk I/O. More vCPUs made it worse (more contention on the same slow disk).

**The right way:**
- Use **Local SSDs** for data staging (copy from GCS to local SSD before processing) — millions of IOPS, no throttling
- Use **Hyperdisk Extreme** when you need persistent high-IOPS storage — decouple IOPS from disk size
- Never save checkpoints to Local SSDs (wiped on termination) — stream checkpoints to GCS or pd-ssd
- Boot disk stays small (40-100GB pd-ssd) — all heavy I/O on separate volumes
- Calculate IOPS budget: `desired_throughput_MB_s / 0.004` = minimum pd-ssd GB needed

---

## Tier: gcp-batch-compute (Spot/Preemptible, Batch Jobs)

### Rule 6: Spot VMs Are Actively Hostile to State
Never design a workflow where spot VM preemption causes data loss or requires restart from scratch.

- All work must be checkpointed (per-chunk, not end-of-job)
- Artifact freezing (model uploads, result exports) must happen on non-preemptible instances
- If you care whether it finishes → it shouldn't be spot

**You will be tempted to:** "The upload is only 18GB, the VM will live long enough."
**Why that fails:** On 2026-03-06, a preemptible VM was terminated mid-upload of an 18GB model tarball. Preemption is non-deterministic — any design requiring uninterrupted time on spot is structurally doomed.

**The right way:**
- Add a `shutdown-script` that catches the 30-second ACPI G2 preemption signal — flush buffers, save emergency state (batch index, RNG seed) to GCS
- Use `--instance-termination-action=STOP` to preserve the persistent disk on preemption (data survives)
- Checkpoint to GCS every 15-20 min via async I/O (don't pause the main thread) — use GCS FUSE with local SSD caching for near-native speed
- Use the Pub/Sub queue-worker pattern: tasks pulled from queue → processed → results written to GCS → ACK sent. If preempted before ACK, task auto-retries on another VM
- For fleet management: wrap spot VMs in Regional MIGs or use GCP Batch (native spot retry + task tracking)
- Freeze/upload artifacts on a separate non-preemptible VM or stream directly: `tar czf - . | gcloud storage cp - gs://bucket/archive.tar.gz`

### Rule 7: Ephemeral VMs Must Report or Fail Loudly
A spot VM that runs code and self-terminates without reporting results is indistinguishable from one that failed silently.

- Every VM must write results to an external store (Supabase, GCS) before termination
- Every VM must log "work completed: N items processed" or "work skipped: reason" to external store
- If code logic causes a skip (e.g., `already_collected()`), the VM MUST report the skip, not silently die

**You will be tempted to:** "The script handles its own logic — if it skips, that's correct behavior."
**Why that fails:** On 2026-03-13, spot VMs ran, executed skip logic, and self-terminated looking "successful." Zero data collected. No way to distinguish success from silent failure without SSH-ing into VMs that no longer exist.

### Rule 8: Disk Space Math — Cloud VMs Are Not Your Laptop
Cloud VM boot disks are tightly provisioned. Operations that temporarily amplify storage (tar, sort, intermediate files) can fill them.

- tar + upload pattern requires 2x the data size in free space
- Use streaming patterns: `tar czf - . | gcloud storage cp - gs://bucket/file.tar.gz`
- Provision scratch disk separately for large intermediate files

**You will be tempted to:** "Standard tar → upload, same as always."
**Why that fails:** On 2026-03-06, creating an 18GB tarball on a boot disk with ~20GB free filled the disk before upload could start. Standard Unix patterns fail when disk provisioning is tight.

---

## Tier: gcp-deploy (Containers, Networking, Auth, Cross-Platform)

### Rule 9: Explicit Architecture Tags on All Container Builds
Never assume container architecture portability between local dev and cloud.

- Always build with `--platform=linux/amd64` when targeting GCP from Apple Silicon
- Never deploy locally-cached images to cloud without verifying architecture
- If `exec format error` → architecture mismatch, not a config issue

**You will be tempted to:** "It works on my Mac, just deploy the same image."
**Why that fails:** On 2026-03-17, ARM64 container images from Apple Silicon caused `exec format error` crash loops on x86 GCP VMs.

**The right way:**
- Use `docker buildx` to create OCI manifest lists that bundle AMD64 + ARM64 under one tag:
  `docker buildx build --platform=linux/amd64,linux/arm64 -t us-central1-docker.pkg.dev/$PROJECT/repo/app:v1 --push .`
- In Cloud Build, add QEMU emulation step before multi-arch builds
- Always use multi-arch base images (official Debian, Alpine, Distroless)
- For Artifact Registry auth: use `gcloud auth configure-docker us-central1-docker.pkg.dev` (credential helper, no raw tokens)
- On Compute Engine VMs: attach a Service Account with `roles/artifactregistry.reader` — container runtime auto-authenticates via metadata server, no `docker login` needed
- Never use long-lived JSON SA keys in CI/CD — use Workload Identity Federation (WIF) instead

### Rule 10: Explicit Network Targeting Per Project
Never hardcode VPC names or assume network topology across GCP projects.

- Always specify `--network` and `--subnet` explicitly in VM creation
- Verify target project's network topology before deploying: `gcloud compute networks list --project=<id>`
- Code reused from other projects MUST have network params updated

**You will be tempted to:** "Just reuse the launch script from the last project."
**Why that fails:** On 2026-03-13, VMs launched into `prod-vpc` from an old project instead of the target's default network. Deployment failed until the network parameter was manually corrected.

### Rule 11: IAP Tunneling Requires Both Firewall AND IAM
IAP SSH tunneling (`use_iap = true` in Packer, `--tunnel-through-iap` in gcloud) has two independent requirements. Missing either one causes silent hangs with no error message.

**Required for IAP SSH:**
1. **Firewall rule:** Allow `35.235.240.0/20` → `tcp:22` on the target VM's network tag
2. **IAM role:** `roles/iap.tunnelResourceAccessor` on the calling user/service account

**Also required for outbound internet (apt, Docker pulls) on VMs with no external IP:**
3. **Cloud NAT** on the VPC subnet — without it, `omit_external_ip = true` VMs can't reach package repos, GHCR, or HuggingFace

**You will be tempted to:** "The firewall rule exists and allows the IAP range, so IAP should work."
**Why that fails:** On 2026-03-24, Packer builds hung indefinitely at `Step Launch IAP Tunnel...` for 2+ hours, stranding GPU builder VMs. The `allow-iap-ssh` firewall rule was correct, but no user had `roles/iap.tunnelResourceAccessor`. The IAP API silently refused to create the tunnel — no error, no timeout, just a hang.

**The right way (verify before any IAP operation):**
```bash
# Check 1: Firewall rule exists for IAP range
gcloud compute firewall-rules list --filter="sourceRanges~35.235.240.0" --format="table(name,targetTags,allowed)"

# Check 2: IAM role exists
gcloud projects get-iam-policy <PROJECT> --format=json | \
  python3 -c "import json,sys; [print(b['role'],'→',b['members']) for b in json.load(sys.stdin).get('bindings',[]) if 'iap' in b['role'].lower()]"

# Check 3: Cloud NAT exists (if omit_external_ip = true)
gcloud compute routers list --format="table(name,region,network)"

# Fix if missing:
gcloud projects add-iam-policy-binding <PROJECT> \
  --member="user:$(gcloud config get-value account)" \
  --role="roles/iap.tunnelResourceAccessor"
```

**Packer-specific:** When `use_iap = true` in a Packer template, also set `omit_external_ip = true` and `use_internal_ip = true` for full zero-trust. The VM gets outbound internet via Cloud NAT, and SSH goes through IAP. Never set `use_iap = true` with `omit_external_ip = false` — that's belt-and-suspenders that obscures which path SSH is actually using.

### Rule 12: Verify Auth Toolchain Before First Use
GCP auth paths vary by environment. Never assume the same auth mechanism works everywhere.

---

## Tier: gcp-bigquery (Data Warehouse Queries)

### Rule 13: BigQuery Access Is Cost-Gated — No Query Without a Forecast
BigQuery on-demand pricing ($6.25/TB scanned) is a silent budget destroyer. No BigQuery query executes without a cost forecast first. This is a HARD GATE — not a guideline, not a best practice.

**Gate sequence (ALL steps required before ANY query executes):**
1. **Dry-run first:** Every query runs with `--dry_run` to get bytes scanned BEFORE execution
2. **Cost calculation:** `bytes_scanned / 1e12 * 6.25 = estimated_cost_USD` — display to user
3. **User approval:** If estimated cost > $1.00, STOP and show the estimate. Do not proceed without explicit user approval
4. **Cumulative tracking:** Track total session spend. Alert at $10, hard-stop at $25 without explicit override
5. **Alternative check:** Before BigQuery, exhaust alternatives first (APIs, sample tables, cached exports, public extracts)

**You will be tempted to:** "It's just one quick query to check the schema / validate the approach."
**Why that fails:** On 2026-03-02, "just checking" turned into iterative development against HTTP Archive's `crawl.pages` table (~8M rows, wide columns). Six scripts, 4-5 full table scans, zero dry-runs. $331.50 in a single overnight session — 58% of the entire month's GCP bill. The data landed in Supabase successfully, but the cost was 10x what it should have been.

**The right way:**
```python
from google.cloud import bigquery

client = bigquery.Client()

# STEP 1: ALWAYS dry-run first
job_config = bigquery.QueryJobConfig(dry_run=True, use_query_cache=False)
dry_run = client.query(query, job_config=job_config)

bytes_scanned = dry_run.total_bytes_processed
cost_estimate = bytes_scanned / 1e12 * 6.25

print(f"This query will scan {bytes_scanned / 1e9:.2f} GB")
print(f"Estimated cost: ${cost_estimate:.2f}")

# STEP 2: Only proceed if cost is acceptable
if cost_estimate > 1.00:
    raise RuntimeError(f"Query costs ${cost_estimate:.2f} — requires user approval")
```

**Cost reduction patterns (use ALL that apply):**
- **Sample tables first:** HTTP Archive publishes `sample_data.*` — use for dev, full tables for final run only
- **Partition filters:** Always include partition column in WHERE (e.g., `date = '2026-02-01'` for HTTP Archive)
- **Column pruning:** `SELECT *` on wide tables is financial malpractice — select only needed columns
- **LIMIT during dev:** Use `LIMIT 1000` for schema exploration and query validation
- **Materialized views:** If querying the same base table repeatedly, create a materialized view after the first run
- **Export to GCS → local:** For iterative analysis, export once to CSV/Parquet via GCS, then work locally
- **BigQuery Sandbox:** 1TB free/month on-demand — check if workload fits within free tier
- **Flat-rate slots:** For predictable heavy usage, flat-rate pricing caps costs regardless of data scanned

- `gsutil` via snap ignores instance metadata credentials — use `gcloud storage` instead
- Homebox/hybrid machines may lack `gcloud` CLI entirely — verify before planning Docker push flows
- Service Account key auth ≠ metadata auth ≠ Application Default Credentials — know which you're using

**You will be tempted to:** "gsutil works on this VM, same as any other."
**Why that fails:** On 2026-03-06, snap-packaged gsutil silently ignored instance metadata credentials despite correct SA permissions. Hours of auth debugging before discovering the snap sandbox was the root cause.
