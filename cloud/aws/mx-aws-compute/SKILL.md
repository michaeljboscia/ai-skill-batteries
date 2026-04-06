---
name: mx-aws-compute
description: EC2 instances, EBS volumes, AMIs, Auto Scaling Groups, Spot Fleet, placement groups, Graviton migration, warm pools, ENA networking, Image Builder, and AI-generated anti-patterns
---

# AWS Compute (EC2) — Infrastructure Primitives for AI Coding Agents

**Load this skill when provisioning EC2 instances, configuring EBS volumes, building AMIs, setting up Auto Scaling, or choosing instance types.**

## When to also load
- `mx-aws-lambda` — when deciding EC2 vs Lambda for workload
- `mx-aws-containers` — when deciding EC2 vs Fargate/ECS for containers
- `mx-aws-eks` — EC2-backed EKS node groups, Karpenter
- `mx-aws-networking` — VPC, subnets, security groups for EC2
- `mx-aws-iam` — instance profiles, least privilege roles

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: gp3 Over gp2 — Always
| BAD | GOOD |
|-----|------|
| `VolumeType: gp2` (legacy, burst credits, more expensive) | `VolumeType: gp3` (20% cheaper, baseline 3000 IOPS + 125 MB/s) |

gp3 is independently configurable up to **80K IOPS + 2 GiB/s** (Sep 2025 increase). gp2 has burst credit cliffs. There is zero reason to use gp2 for any new workload.

### Pattern 2: Graviton by Default
| BAD | GOOD |
|-----|------|
| `InstanceType: m6i.xlarge` (x86, more expensive) | `InstanceType: m7g.xlarge` (Graviton3, 40% better price-perf) |

Graviton works for: Java 11+, Python, Node.js, Go, .NET 6+, containers, RDS, ElastiCache, Lambda. Start with stateless workloads, then migrate databases. Use Graviton Transition Planner in Compute Optimizer.

### Pattern 3: Launch Templates Over Launch Configurations
Launch Configurations are deprecated. Always use **Launch Templates** — they support versioning, mixed instance types, and Graviton.

### Pattern 4: Enable EBS Encryption Account-Wide
```
aws ec2 enable-ebs-encryption-by-default --region us-east-1
```
One command. Every new EBS volume in the account is encrypted. No per-volume configuration needed.

### Pattern 5: Instance Family Decision Tree

| Workload | Family | Why |
|----------|--------|-----|
| General purpose | M7g/M7i | Balanced CPU/memory |
| Compute-heavy (batch, encoding) | C7g/C7i | High CPU:memory ratio |
| Memory-heavy (caches, in-memory DB) | R7g/R7i | High memory:CPU ratio |
| Burstable (dev, small apps) | T3/T3a | CPU credits — NOT for sustained load |
| GPU/ML training | P5/P5e | NVIDIA H100/H200 |
| GPU inference | G6/Inf2 | Cost-optimized inference |

**T instances are NOT general purpose.** They have CPU credit limits. Under sustained load they throttle to baseline.

---

## Level 2: Scaling & Cost Optimization (Intermediate)

### Auto Scaling Strategy

| Strategy | When to Use | Config |
|----------|-------------|--------|
| **Target Tracking** | Steady traffic, maintain metric | `TargetValue: 50` (CPU%), start here |
| **Predictive Scaling** | Recurring patterns (daily cycles) | Enable `ForecastOnly` first, observe 2 weeks |
| **Step Scaling** | Complex scaling rules | Multiple thresholds with different actions |
| **Scheduled** | Known events (Black Friday) | Cron-based pre-scaling |

### Warm Pools
Pre-initialized instances in Stopped/Running/Hibernated state. Reduces scale-out time from minutes to seconds.
- Use for slow-starting applications (large AMIs, complex init)
- Enable instance reuse to return to warm pool on scale-in
- Supported with mixed instances policy (Nov 2025)

### Spot Instances

| Setting | Value | Why |
|---------|-------|-----|
| Allocation strategy | `capacity-optimized` | Minimizes interruptions |
| Instance diversity | 10+ types across families/sizes | Prevents capacity shortages |
| Mixed policy | 30% On-Demand base + 70% Spot | Keeps minimum capacity guaranteed |
| Interruption handling | Capacity Rebalance + checkpointing | 2-min warning via metadata + EventBridge |

Use **attribute-based instance type selection** to auto-diversify instead of listing specific types.

### EBS Volume Decision Tree

| Need | Volume | Max IOPS | Max Throughput |
|------|--------|----------|----------------|
| Default / most workloads | **gp3** | 80,000 | 2 GiB/s |
| Critical database (<0.5ms latency) | **io2 Block Express** | 256,000 | 4 GiB/s |
| Big data / streaming logs | **st1** (HDD) | 500 | 500 MB/s |
| Archive / cold infrequent | **sc1** (HDD) | 250 | 250 MB/s |
| Highest IOPS (ephemeral OK) | **NVMe instance store** | 1M+ | Varies |

---

## Level 3: Production Patterns (Advanced)

### Placement Groups

| Type | Use Case | Constraint |
|------|----------|------------|
| **Cluster** | HPC, low-latency (single AZ) | Same instance type, single `RunInstances` call |
| **Spread** | Max isolation (HA critical) | 7 instances per AZ |
| **Partition** | Distributed systems (Kafka, HDFS) | Failure isolation by partition |

### ENA & Network Performance
- **ENA**: SR-IOV, up to 200 Gbps. Enabled by default on Nitro instances
- **ENA Express** (Nitro v4): 170 Gbps per network card, hardware-offloaded
- Enable **jumbo frames** (MTU 9001) within VPC for throughput-sensitive workloads
- Nitro NVMe instance store: detailed I/O stats (queue length, IOPS, latency histograms) at no cost (Sep/Nov 2025)

### Golden AMI Pipeline
1. **EC2 Image Builder** pipeline: base AMI + CIS hardening + app deps + security patches
2. Tag with build date, source commit, OS version
3. Share via AWS Organizations (never make public)
4. **Deregister old AMIs** to avoid cost and confusion
5. Prefer Image Builder over Packer for AWS-native. Use Packer for multi-cloud only.

---

## Performance: Make It Fast

### Optimization Checklist
1. **Graviton** — 40% better price-perf. Benchmark first, but it almost always wins
2. **gp3 with tuned IOPS** — don't accept defaults if your workload needs more. Online modification, no downtime
3. **Placement groups** — cluster for HPC, spread for HA
4. **ENA Express** — hardware-offloaded networking on Nitro v4
5. **Warm EBS before benchmarking** — new volumes from snapshots need first-read initialization
6. **Compute Optimizer** — ML-based right-sizing. Can save 30-70%. Cross-family recommendations

### Benchmarking
- `fio` for disk, `iperf3` for network, `sysbench` for CPU/memory
- 3+ iterations, take median
- Warm EBS volumes before benchmarking (read all blocks once)

---

## Observability: Know It's Working

### What to Monitor

| Signal | Metric | Alert Threshold |
|--------|--------|-----------------|
| CPU | `CPUUtilization` | >80% sustained (scale out) or <20% sustained (right-size down) |
| Memory | CloudWatch Agent custom metric | >85% (not collected by default!) |
| Disk | `VolumeReadOps/WriteOps`, queue length | Queue length >1 for gp3 = investigate |
| Network | `NetworkIn/Out`, `NetworkPacketsIn/Out` | Baseline + 2 std devs |
| Spot | `CapacityRebalanceRecommendation` event | Any = prepare for replacement |
| Credits | `CPUCreditBalance` (T instances) | <50 = about to throttle |

- **Memory is NOT collected by default.** Install CloudWatch Agent for memory + disk metrics
- Use **high-resolution metrics** (1-second) for ASG scaling responsiveness
- **Compute Optimizer**: opt-in, analyzes 14 days (or 3 months with enhanced). Check weekly for right-sizing recommendations

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No gp2 for New Volumes
**You will be tempted to:** Use `gp2` because it appears in training data examples
**Why that fails:** gp2 is 20% more expensive, has burst credit cliffs, and maxes at 16K IOPS. gp3 is strictly better
**The right way:** `VolumeType: gp3`. Always. Set IOPS/throughput explicitly if workload needs more than baseline

### Rule 2: No 0.0.0.0/0 on Any Port
**You will be tempted to:** Open SSH (22) or app ports to `0.0.0.0/0` for "testing"
**Why that fails:** Bots scan the entire internet in minutes. You will be compromised
**The right way:** SG-to-SG referencing for internal comms. Specific CIDRs for external. Session Manager for SSH-less access

### Rule 3: No Hardcoded Secrets in User Data
**You will be tempted to:** Put API keys, passwords, or tokens in EC2 user data scripts
**Why that fails:** User data is visible in console, API responses, and instance metadata. It's plaintext
**The right way:** Secrets Manager or SSM Parameter Store (SecureString). Fetch at boot via IAM role

### Rule 4: No T Instances for Production Workloads
**You will be tempted to:** Use `t3.medium` because it's cheap and "general purpose"
**Why that fails:** T instances have CPU credit limits. Under sustained load they throttle to 20-40% baseline CPU. Silent performance degradation
**The right way:** M-family for general purpose, C-family for compute-heavy. T-family is for dev/test/low-traffic only

### Rule 5: No x86 Without Justification
**You will be tempted to:** Default to `m6i`/`c6i` (x86) because more examples exist
**Why that fails:** 40% cost premium vs Graviton for equivalent performance. Graviton supports all major languages and runtimes
**The right way:** Default to `m7g`/`c7g`/`r7g` (Graviton3). Only use x86 if you have compiled x86-only dependencies that cannot be recompiled
