---
name: mx-gcp-compute
description: Use when creating GCE VMs, choosing machine types, configuring startup scripts, managing instance groups, using Spot VMs, selecting disk types, or optimizing compute costs. Also use when the user mentions 'gcloud compute instances create', 'machine type', 'e2-', 'n2-', 'c3-', 'spot VM', 'preemptible', 'startup script', 'instance template', 'managed instance group', 'MIG', 'autoscaling', 'health check', 'rolling update', 'persistent disk', 'pd-ssd', 'pd-balanced', 'committed use discount', 'CUD', 'right-sizing', or 'instance group'.
---

# GCP Compute — VMs, Instance Groups & Cost Optimization for AI Coding Agents

**This skill loads when you're creating or managing GCP Compute Engine resources.**

## When to also load
- `mx-gcp-iam` — service account attachment, IAP SSH access
- `mx-gcp-networking` — VPC, subnets, firewall rules for VMs
- `mx-gcp-security` — **ALWAYS load** — no secrets in metadata, CMEK for disks, Shielded VMs, OS Login enforcement, no public IPs without justification
- `mx-gpu-inference` — GPU VM provisioning, VRAM sizing

---

## Level 1: VM Creation & Machine Types (Beginner)

### Machine type decision tree

| Workload | Family | Example | Why |
|----------|--------|---------|-----|
| Dev/test, low-cost | E2 | `e2-medium` | Cheapest, dynamic resource mgmt |
| Production web/API | N2/N4 | `n2-standard-4` | Better per-core perf, SUDs apply |
| HPC, latency-sensitive | C3/C3D | `c3-standard-8` | Highest per-core perf, DDR5 |
| In-memory DB (SAP) | M3/M4 | `m3-megamem-128` | Up to 30TB RAM |
| ML training/inference | A2/A3/G2 | `g2-standard-4` | GPU attached |
| Scale-out APIs, batch | T2A/T2D | `t2a-standard-4` | Arm-based, best $/perf |

### Create a production VM

```bash
gcloud compute instances create web-server \
  --zone=us-east1-b \
  --machine-type=n2-standard-4 \
  --subnet=web-subnet \
  --no-address \
  --service-account=vm-web-api@my-project.iam.gserviceaccount.com \
  --scopes=cloud-platform \
  --image-family=debian-12 --image-project=debian-cloud \
  --boot-disk-type=pd-balanced --boot-disk-size=50GB \
  --metadata-from-file startup-script=startup.sh \
  --tags=web-server
```

**Key flags to always include:**
- `--no-address` — no external IP (use IAP or Cloud NAT)
- `--service-account` — dedicated SA, never default compute SA
- `--boot-disk-type=pd-balanced` — SSD performance at lower cost than pd-ssd

### Startup script delivery methods

| Method | Flag | When to use |
|--------|------|-------------|
| Inline | `--metadata startup-script='...'` | Short scripts (<256 bytes) |
| Local file | `--metadata-from-file startup-script=FILE` | Development |
| GCS URL | `--metadata startup-script-url=gs://BUCKET/FILE` | Production (version-controlled) |

```bash
# BAD — secrets in metadata (visible via gcloud compute instances describe)
--metadata startup-script='#!/bin/bash
export DB_PASS=secretpassword123'

# GOOD — fetch secrets at runtime
--metadata startup-script='#!/bin/bash
DB_PASS=$(gcloud secrets versions access latest --secret=db-password-prod)'
```

**Startup scripts run on EVERY boot.** For one-time setup, use a marker file:
```bash
if [[ -f /etc/startup_done ]]; then exit 0; fi
# ... setup code ...
touch /etc/startup_done
```

---

## Level 2: Spot VMs & Instance Groups (Intermediate)

### Spot VMs (replaces Preemptible)

```bash
# Create Spot VM (60-91% cheaper, no 24hr limit)
gcloud compute instances create batch-worker \
  --zone=us-east1-b \
  --machine-type=e2-standard-8 \
  --provisioning-model=SPOT \
  --instance-termination-action=STOP \
  --service-account=vm-batch@my-project.iam.gserviceaccount.com
```

| Flag | Value | Effect |
|------|-------|--------|
| `--provisioning-model` | `SPOT` | 60-91% discount, can be preempted |
| `--instance-termination-action` | `STOP` | Preserves disks on preemption (vs DELETE) |

**Spot VM fault tolerance checklist:**
1. Idempotent tasks (safe to retry)
2. Checkpoint every 15min for long jobs
3. Spread across 3+ zones
4. Use MIGs for auto-replacement
5. Shutdown script for graceful cleanup (30s window)

### Managed Instance Groups (MIGs)

```bash
# 1. Create instance template
gcloud compute instance-templates create web-template \
  --machine-type=n2-standard-2 \
  --image-family=debian-12 --image-project=debian-cloud \
  --boot-disk-type=pd-balanced --boot-disk-size=20GB \
  --service-account=vm-web-api@my-project.iam.gserviceaccount.com \
  --no-address \
  --metadata-from-file startup-script=startup.sh

# 2. Create regional MIG (multi-zone HA)
gcloud compute instance-groups managed create web-mig \
  --template=web-template \
  --size=3 \
  --region=us-east1

# 3. Configure autoscaling
gcloud compute instance-groups managed set-autoscaling web-mig \
  --region=us-east1 \
  --min-num-replicas=2 --max-num-replicas=10 \
  --target-cpu-utilization=0.7 \
  --cool-down-period=120

# 4. Set up autohealing health check
gcloud compute health-checks create http web-health \
  --port=8080 --request-path=/health \
  --check-interval=30s --timeout=10s \
  --healthy-threshold=2 --unhealthy-threshold=5

gcloud compute instance-groups managed update web-mig \
  --region=us-east1 \
  --health-check=web-health \
  --initial-delay=300
```

**Health check firewall rule required:**
```bash
gcloud compute firewall-rules create allow-health-checks \
  --network=my-vpc --action=ALLOW --rules=tcp:8080 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-service-accounts=vm-web-api@my-project.iam.gserviceaccount.com
```

### Rolling updates (zero-downtime)

```bash
# Create new template with updated app
gcloud compute instance-templates create web-template-v2 \
  --machine-type=n2-standard-2 \
  --metadata-from-file startup-script=startup-v2.sh \
  # ... same config as before

# Roll out with zero downtime
gcloud compute instance-groups managed rolling-action start-update web-mig \
  --region=us-east1 \
  --version=template=web-template-v2 \
  --max-unavailable=0 --max-surge=2
```

---

## Level 3: Disk Types & Cost Optimization (Advanced)

### Disk type decision tree

| Disk | IOPS/GiB | Max IOPS | Use case | Cost |
|------|----------|----------|----------|------|
| `pd-standard` | 0.75 | 7,500 | Cold storage, backups | $ |
| `pd-balanced` | 6 | 80,000 | **Default for most workloads** | $$ |
| `pd-ssd` | 30 | 80,000 | Databases, latency-sensitive | $$$ |
| `pd-extreme` | Provisionable | 120,000 | SAP, Oracle, max IOPS | $$$$ |
| Hyperdisk | Provisionable | 350,000+ | Highest tier | $$$$$ |

**IOPS has TWO bottlenecks:** disk size AND vCPU count. A large disk on a small VM won't hit max IOPS.

```bash
# Size disk for target IOPS (pd-balanced example)
# Need 30,000 IOPS → 30,000 / 6 IOPS per GiB = 5,000 GiB minimum
gcloud compute disks create data-disk \
  --type=pd-balanced --size=5000GB --zone=us-east1-b

# Resize disk online (only larger, never smaller)
gcloud compute disks resize data-disk --size=8000GB --zone=us-east1-b
```

### Cost optimization ladder

| Strategy | Savings | Commitment | Best for |
|----------|---------|------------|----------|
| Right-sizing | 20-40% | None | All workloads — check Recommender first |
| Spot VMs | 60-91% | None | Batch, CI/CD, fault-tolerant |
| SUDs (automatic) | Up to 30% | None | VMs running >25% of month |
| CUD (resource-based) | Up to 57% | 1yr or 3yr | Stable baseline compute |
| CUD (spend-based/flexible) | 28-46% | 1yr or 3yr | Variable across services |
| Custom machine types | 5-15% | None | Workloads that don't fit predefined sizes |
| Off-hours shutdown | 40-70% | None | Dev/test environments |

```bash
# Check right-sizing recommendations
gcloud recommender recommendations list \
  --project=my-project --location=us-east1-b \
  --recommender=google.compute.instance.MachineTypeRecommender \
  --format="table(content.operationGroups[0].operations[0].resource,content.operationGroups[0].operations[0].value)"
```

---

## Performance: Make It Fast

### Custom images for faster boot

```bash
# Create image from configured instance (skip startup script on boot)
gcloud compute images create web-golden-v1 \
  --source-disk=web-server --source-disk-zone=us-east1-b \
  --family=web-golden

# Use image family in templates (auto-picks latest)
gcloud compute instance-templates create web-template \
  --image-family=web-golden --image-project=my-project
```

Golden images boot in seconds. Startup scripts can take minutes. For autoscaling, golden images = faster scale-out.

### Local SSD for temporary high-perf storage

```bash
gcloud compute instances create high-io-vm \
  --machine-type=n2-standard-16 --zone=us-east1-b \
  --local-ssd=interface=NVME,size=375
```

Local SSDs: 680K IOPS read, but data is LOST on stop/preemption. Only for ephemeral scratch space.

---

## Observability: Know It's Working

### Key metrics to monitor

```bash
# List idle VMs (candidates for deletion)
gcloud recommender recommendations list \
  --project=my-project --location=us-east1-b \
  --recommender=google.compute.instance.IdleResourceRecommender

# Check MIG status
gcloud compute instance-groups managed describe web-mig \
  --region=us-east1 --format="yaml(status)"

# List instances with their current status
gcloud compute instance-groups managed list-instances web-mig \
  --region=us-east1
```

### What to alert on

| Event | Metric | Severity |
|-------|--------|----------|
| Spot VM preempted | `compute.googleapis.com/instance/uptime` drops | **INFO** |
| MIG autohealing triggered | `autoscaler/scaling_state` | **MEDIUM** |
| Disk IOPS at limit | `disk/read_ops_count` near max | **HIGH** |
| CPU >90% sustained | `instance/cpu/utilization` | **MEDIUM** |
| VM created with external IP | Audit log: `compute.instances.insert` with `accessConfigs` | **HIGH** |

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never create VMs with external IPs
**You will be tempted to:** Add `--address=EXTERNAL` or omit `--no-address` because "I need to SSH in."
**Why that fails:** External IPs expose VMs to the entire internet. Port scanners find them within minutes. Your `infrastructure.md` says zero-trust by default.
**The right way:** Use `--no-address` and SSH via IAP: `gcloud compute ssh VM --tunnel-through-iap`. For outbound internet, use Cloud NAT.

### Rule 2: Never use the default compute service account
**You will be tempted to:** Skip `--service-account` because "the default works fine."
**Why that fails:** The default Compute Engine SA often has `roles/editor` — full read/write to every service in the project. A compromised VM with the default SA = full project compromise.
**The right way:** Create a dedicated SA with minimum required roles: `gcloud iam service-accounts create vm-{purpose}`. Attach it with `--service-account`.

### Rule 3: Use pd-balanced as your default disk, not pd-standard
**You will be tempted to:** Use `pd-standard` because "it's cheaper" or omit `--boot-disk-type` (which defaults to pd-standard on some images).
**Why that fails:** pd-standard is HDD-backed. Boot times are 2-5x slower, application performance degrades under any I/O load, and the cost difference is small ($0.04/GB/mo vs $0.10/GB/mo for pd-balanced).
**The right way:** Always specify `--boot-disk-type=pd-balanced`. For databases, use `pd-ssd`.

### Rule 4: Never put secrets in instance metadata
**You will be tempted to:** Pass API keys or passwords via `--metadata` because "the startup script needs them."
**Why that fails:** Metadata is visible to anyone with `compute.instances.get` permission. It appears in `gcloud compute instances describe` output. It's stored unencrypted.
**The right way:** Startup script fetches from Secret Manager at runtime. Cloud Run uses `--set-secrets`. For VMs: `gcloud secrets versions access latest --secret=NAME`.

### Rule 5: Use Spot VMs for batch — not on-demand
**You will be tempted to:** Use standard on-demand VMs for batch jobs because "I don't want them interrupted."
**Why that fails:** You're paying 60-91% more for no benefit. Batch jobs are inherently retryable. If your batch job can't tolerate interruption, it has a design problem, not a provisioning problem.
**The right way:** `--provisioning-model=SPOT` with checkpointing and MIG auto-replacement. Design for interruption — it's cheaper AND more resilient.
