---
name: mx-aws-storage
description: S3 storage classes, lifecycle rules, Intelligent-Tiering, Glacier tiers, S3 Express One Zone, multipart upload, Transfer Acceleration, EFS throughput modes, FSx Lustre/ONTAP, replication, and AI-generated anti-patterns
---

# AWS Storage — S3, EFS, FSx for AI Coding Agents

**Load this skill when configuring S3 buckets/policies, choosing storage classes, setting up EFS/FSx, or designing data lifecycle management.**

## When to also load
- `mx-aws-compute` — EBS volumes, instance store
- `mx-aws-security` — KMS encryption, bucket policies, Block Public Access
- `mx-aws-cdn-lb` — CloudFront + S3 origin, versioned URLs
- `mx-aws-gpu` — FSx Lustre for training data, S3 for checkpoints

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: Block Public Access at Account Level
```bash
aws s3control put-public-access-block --account-id $ACCOUNT \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```
One command. Every S3 bucket in the account is protected. Apply via SCP for the entire Organization.

### Pattern 2: Disable ACLs — Bucket Owner Enforced
| BAD | GOOD |
|-----|------|
| `ObjectOwnership: BucketOwnerPreferred` (ACLs active) | `ObjectOwnership: BucketOwnerEnforced` (ACLs disabled, default) |

ACLs are a legacy access mechanism. Bucket policies are clearer, auditable, and sufficient.

### Pattern 3: Encryption by Default
- **SSE-S3** (default, free): sufficient for most workloads
- **SSE-KMS**: for audit trails (who decrypted what) + cross-account key sharing
- **SSE-C**: being disabled April 2026 — do not use
- Enable versioning on production buckets. MFA Delete for critical data

### Pattern 4: Lifecycle Rules on Every Bucket
| BAD | GOOD |
|-----|------|
| All data in Standard forever | Lifecycle rule: Standard → IA (30d) → Glacier (90d) → Deep Archive (365d) |

**Minimum storage durations matter:** 30d (Standard-IA), 90d (Glacier Instant/Flexible), 180d (Deep Archive). Early deletion = charges for remaining duration.

### Pattern 5: Size Filter for Small Objects
Objects <128KB no longer auto-transition to IA/Glacier tiers. Explicitly set size filter in lifecycle rules. Small objects in Intelligent-Tiering stay in Frequent Access tier.

---

## Level 2: Performance & Intelligent-Tiering (Intermediate)

### S3 Performance Optimization

| Technique | When to Use | Impact |
|-----------|-------------|--------|
| **Multipart upload** | Objects >100MB | Mandatory. 64-100MB chunks. Parallelized |
| **Transfer Acceleration** | Long-distance uploads | 50-500% speedup via CloudFront Edge |
| **S3 Express One Zone** | Single-digit ms latency needed | 10x faster, 50% cheaper requests. Single-AZ |
| **Byte-range fetches** | Partial reads, parallel downloads | Fetch only needed bytes |
| **CRT-based S3 clients** | High-throughput applications | HTTP/2, async I/O, auto parallelization |

**Request rate scaling:** 3,500 PUT + 5,500 GET per second per prefix. S3 auto-partitions on prefixes. Use date-based prefixes for time-series, hashed prefixes for max throughput.

### Intelligent-Tiering Decision

| Scenario | Use Intelligent-Tiering? |
|----------|------------------------|
| Unknown access patterns | **Yes** — auto-optimizes, no retrieval charges |
| All-hot data (accessed daily) | **No** — monitoring fee with no savings |
| All-cold data (archive) | **No** — Glacier is cheaper |
| Mixed access, hard to predict | **Yes** — default choice |

- Enable archive access tiers explicitly (not enabled by default)
- 0-day lifecycle transition to IT = immediate monitoring
- No minimum storage duration. No retrieval charges for auto-tiered data

### Glacier Tier Decision

| Tier | Retrieval Time | Min Duration | Use Case |
|------|---------------|--------------|----------|
| **Glacier Instant** | Milliseconds | 90 days | Quarterly access (68% savings vs IA) |
| **Glacier Flexible** | Minutes to 12hr | 90 days | Annual access (10% cheaper than Instant) |
| **Deep Archive** | 9-48hr | 180 days | 7-10yr retention (80%+ savings) |

### EFS vs FSx Decision Tree

| Need | Service | Why |
|------|---------|-----|
| Shared NFS (web, containers, dev) | **EFS** (Elastic throughput) | Auto-scales, serverless, multi-AZ |
| HPC / ML training data | **FSx for Lustre** | Sub-ms, millions IOPS, S3 integration |
| Enterprise mixed SMB/NFS | **FSx for NetApp ONTAP** | Multi-protocol, sub-ms, NVMe read cache |
| Temporary HPC scratch | **FSx Lustre SCRATCH_2** | Cheaper, no replication |

---

## Level 3: EFS/FSx Production Patterns (Advanced)

### EFS Throughput Modes
- **Elastic** (default, recommended): auto-scales, pay per read/write. No capacity planning
- **Bursting**: scales with storage size. Monitor `BurstCreditBalance` — depletion = throttling
- **Provisioned**: fixed throughput independent of storage. For predictable high-throughput needs
- Access Points: up to 10,000 per filesystem (Feb 2025). Enforce user identity + root directory per app

### FSx for Lustre
- Performance scales linearly with size. EFA + GPUDirect Storage = up to 1,200 Gbps on P5 instances
- S3 integration: lazy loading from S3 data repository. Auto-export back to S3
- Stripe files across all OSTs. LZ4 compression for compressible data
- Limit directories to <100K files (metadata bottleneck)
- SCRATCH_2 for temporary data (cheaper). PERSISTENT_2 for sustained workloads

### S3 Replication
- Cross-Region Replication (CRR): versioning required on both buckets
- Replication Time Control (RTC): 99.99% within 15 minutes. For compliance/SLA requirements
- Apply lifecycle policies on replicated data for cost optimization
- S3 Storage Lens: track lifecycle activity, validate rules, catch misconfigurations

---

## Performance: Make It Fast

### S3 Throughput Checklist
1. **Multipart upload** for objects >100MB — parallelized, resumable
2. **Prefix distribution** — hashed prefixes for max throughput, date-based for time-series
3. **S3 Express One Zone** for latency-sensitive workloads — co-locate compute in same AZ
4. **Transfer Acceleration + multipart** for long-distance uploads
5. **CRT-based clients** — AWS Common Runtime for optimized HTTP/2 with auto parallelization
6. **Byte-range fetches** for partial reads — don't download entire objects

### EFS/FSx Performance
- EFS: use Elastic throughput (auto-scales). NFSv4.1. Parallelize across clients
- FSx Lustre: ensure EFA enabled on compute nodes. Stripe across OSTs. SCRATCH_2 for temp data
- FSx ONTAP: Gen-2 for up to 72 GBps. Enable NVMe read cache

---

## Observability: Know It's Working

### What to Monitor

| Signal | Tool | What to Watch |
|--------|------|--------------|
| S3 costs | S3 Storage Lens | Storage class distribution, lifecycle effectiveness |
| S3 access | CloudTrail S3 data events + S3 Access Logs | Unusual access patterns, unauthorized reads |
| S3 replication | `ReplicationLatency`, `OperationsPendingReplication` | Lag > 15min for RTC = investigate |
| EFS performance | `BurstCreditBalance`, `PercentIOLimit` | Credit depletion = imminent throttling |
| FSx Lustre | `FreeDataStorageCapacity`, `DataReadBytes/WriteBytes` | Capacity exhaustion, throughput utilization |

- **S3 Storage Lens**: organization-wide view of storage usage, cost trends, lifecycle effectiveness
- **EFS BurstCreditBalance**: if using Bursting mode, this is your most critical metric. Switch to Elastic if credits deplete regularly
- **S3 Inventory**: weekly/daily reports on object metadata. Use for compliance audits and lifecycle validation

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Data in Standard Forever
**You will be tempted to:** Skip lifecycle rules because "storage is cheap"
**Why that fails:** S3 Standard is $0.023/GB/month. Deep Archive is $0.00099/GB. At 100TB, that's $2,300/month vs $99/month. Storage grows silently
**The right way:** Lifecycle rule on every bucket. Even a simple Standard → IA at 30d saves 40%

### Rule 2: No Public Buckets
**You will be tempted to:** Make a bucket public for "quick sharing" or "static hosting"
**Why that fails:** Public buckets are the #1 cause of S3 data breaches. Bots scan for open buckets continuously
**The right way:** Block Public Access at account level. Use CloudFront + OAC for static hosting. Pre-signed URLs for temporary sharing

### Rule 3: No Ignoring Minimum Storage Durations
**You will be tempted to:** Transition objects to Glacier and delete them before the minimum duration
**Why that fails:** Deleting an object in Glacier Flexible before 90 days = you're charged for the full 90 days anyway
**The right way:** Factor minimum durations into lifecycle rules. Don't transition objects you'll need to delete within the minimum period

### Rule 4: No EFS Bursting Mode Without Monitoring Credits
**You will be tempted to:** Use EFS Bursting mode because it's "automatic"
**Why that fails:** Burst credits deplete under sustained load. When credits hit zero, throughput drops to baseline (proportional to storage size). Silent performance degradation
**The right way:** Use Elastic throughput mode (recommended default). If using Bursting, alarm on `BurstCreditBalance` < 50%

### Rule 5: No Single-AZ for Production Data
**You will be tempted to:** Use S3 Express One Zone or FSx SCRATCH_2 for production because they're faster/cheaper
**Why that fails:** Single-AZ = single point of failure. AZ outage = data unavailable (SCRATCH_2) or potential data loss
**The right way:** S3 Express One Zone for transient/reproducible data only. SCRATCH_2 for temporary HPC. Production data in multi-AZ (Standard S3, EFS, FSx PERSISTENT_2)
