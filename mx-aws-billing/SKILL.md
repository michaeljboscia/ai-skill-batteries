---
name: mx-aws-billing
description: Cost Explorer rightsizing, Compute Optimizer recommendations, Savings Plans vs Reserved Instances, CUR 2.0 data exports, cost anomaly detection, Budget alerts, tagging strategy, FinOps practices, and AI-generated cost anti-patterns
---

# AWS Billing & Cost Management — FinOps for AI Coding Agents

**Load this skill when optimizing AWS costs, configuring budgets, choosing commitment strategies, or implementing cost allocation.**

## When to also load
- `mx-aws-compute` — EC2 right-sizing, Spot, Graviton
- `mx-aws-lambda` — Lambda Power Tuning, ARM64 cost savings
- `mx-aws-containers` — Fargate Spot, capacity provider strategies
- `mx-aws-observability` — CloudWatch cost management, log retention

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: Tagging Strategy — Enforce From Day One
| Tag | Purpose | Example |
|-----|---------|---------|
| `Environment` | Dev/staging/prod separation | `production` |
| `Project` | Cost allocation by project | `payment-service` |
| `Owner` | Accountability | `team-platform` |
| `CostCenter` | Finance chargeback | `CC-1234` |
| `Service` | Application identification | `api-gateway` |

Activate as **cost allocation tags** in Billing. Enforce with Tag Policies in Organizations. CI/CD pipeline integration for pre-deploy validation.

### Pattern 2: Budgets with Auto-Alert
| BAD | GOOD |
|-----|------|
| Check Cost Explorer monthly | AWS Budgets: alert at 50%, 80%, 100% of threshold. Auto-actions at 100% |

Set budgets per account, per service, per tag. Budget actions can auto-stop EC2 instances or restrict IAM actions when thresholds are exceeded.

### Pattern 3: Savings Plans Over Reserved Instances
| Commitment | Flexibility | Savings |
|------------|-------------|---------|
| **Compute Savings Plans** | Any EC2/Fargate/Lambda, any region/family/OS | Up to 66% |
| **EC2 Instance Savings Plans** | Specific family in region, any size/OS | Up to 72% |
| **Reserved Instances** | Specific type/size/region | Up to 75% (zonal capacity guarantee) |

**Savings Plans first** for broad flexibility. RIs only when you need zonal capacity reservation or specific database commitments. **Database Savings Plans** now available (re:Invent 2025).

### Pattern 4: Cost Anomaly Detection — Free
ML-based anomaly detection. Rolling 24-hour windows (Nov 2025 improvement). Custom thresholds. Email/SNS alerts. **Free** (only SNS charges). Start with one account-wide monitor.

### Pattern 5: Instance Scheduler for Non-Prod
Stop dev/test instances during off-hours. 12hr/day × 5 days/week = 64% savings on non-prod compute.

---

## Level 2: Rightsizing & CUR (Intermediate)

### Rightsizing Stack

| Tool | Coverage | Depth |
|------|----------|-------|
| **Cost Explorer rightsizing** | EC2 only | Same-family recommendations |
| **Compute Optimizer** | EC2, EBS, Lambda, ASGs, Fargate | ML-based, cross-family (14d or 3mo analysis) |
| **Trusted Advisor** | Cost optimization checks | Basic recommendations |

Compute Optimizer: below 40% utilization = downsize candidate. **2025**: apply recommendations directly (including EBS volume type upgrades). Enable enhanced metrics for 3-month analysis window.

### CUR 2.0 (AWS Data Exports)
- **Consistent schema**, nested data (less sparse than CUR 1.0)
- SQL-customizable exports: select specific columns, filter sensitive data
- Recurring exports to S3. Analyze with Athena for advanced chargeback
- Hourly granularity, all resource IDs for precise cost attribution

### Savings Plans Strategy
1. Analyze 30-day usage in Cost Explorer SP recommendations
2. Start with **Compute SP** at 70% of steady baseline (conservative)
3. Add **EC2 Instance SP** for specific instance families you're committed to
4. Cover remaining 30% with On-Demand + Spot
5. Review quarterly — adjust as usage patterns change

### Cost Anomaly Detection Tuning
- Threshold: $100/day or 2-5% of monthly spend (whichever is larger)
- Investigate within 24 hours. Combine with Budgets for hard limits
- Managed monitors auto-adapt. Up to 5,000 values across accounts

---

## Level 3: FinOps & Advanced (Advanced)

### FinOps Operating Model
- **Cross-functional team**: finance + engineering + product. Shared responsibility
- **Showback/chargeback**: allocate costs by team/project using tags + CUR
- **Real-time cost visibility**: dashboards for all stakeholders, not just finance
- **Regular audits**: quarterly SP/RI review, monthly rightsizing review, weekly anomaly review

### AI/ML Cost Management (2025 FinOps trend)
- Bedrock: track per-model token costs. Use application inference profiles for per-workload tracking
- SageMaker: Spot for training, right-size endpoints, Savings Plans for steady inference
- GPU instances: Capacity Blocks for guaranteed GPU, Spot for fault-tolerant training

### Cost Optimization Priorities (FinOps Foundation 2025)
1. **Waste reduction** (#1 priority): unused resources, over-provisioned instances
2. **Commitment optimization**: SP/RI coverage analysis
3. **Architecture optimization**: Graviton, serverless, right storage class
4. **Sustainability**: carbon-aware spending, region selection for renewables

---

## Performance: Make It Fast

### Quick Wins (Immediate Savings)
1. **gp3 over gp2** everywhere — 20% savings, better performance
2. **Graviton instances** — 40% better price-performance
3. **S3 lifecycle rules** — archive cold data to Glacier (80%+ savings)
4. **Gateway Endpoints** for S3/DynamoDB — free (eliminates NAT costs)
5. **Instance Scheduler** for non-prod — 64% compute savings
6. **Unused EIP cleanup** — $0.005/hr per idle EIP adds up

### Monthly Review Checklist
- [ ] Cost Explorer: month-over-month trend by service
- [ ] Compute Optimizer: new rightsizing recommendations
- [ ] SP/RI utilization: coverage gaps or over-commitment
- [ ] Anomaly alerts: investigated and resolved
- [ ] Tag compliance: untagged resources identified and fixed

---

## Observability: Know It's Working

### What to Monitor

| Signal | Tool | Alert Threshold |
|--------|------|-----------------|
| Budget | AWS Budgets | 80% threshold = investigate, 100% = action |
| Anomaly | Cost Anomaly Detection | Any detection = 24hr investigation |
| RI/SP coverage | Cost Explorer | Coverage < 70% baseline = review |
| Untagged resources | Tag Editor / Config rules | >0 untagged = tag enforcement gap |
| Waste | Compute Optimizer | Over-provisioned resources = rightsizing opportunity |

- **Cost Explorer Cost Comparisons (2025)**: auto-identifies major cost changes with explanations
- **CUR + Athena dashboards**: per-team/service/project cost trends
- **Budget actions**: auto-stop instances, restrict IAM at budget threshold

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Resources Without Tags
**You will be tempted to:** Deploy resources without cost allocation tags "temporarily"
**Why that fails:** Untagged resources are invisible to cost allocation. You can't optimize what you can't measure. "Temporary" becomes "we have $50K/month in unattributed costs"
**The right way:** Tag Policies in Organizations. CI/CD pre-deploy validation. Reject untagged resources

### Rule 2: No RIs Before Rightsizing
**You will be tempted to:** Buy Reserved Instances to save money on current usage
**Why that fails:** If instances are over-provisioned (and they probably are), you're locking in the wrong size for 1-3 years. Right-size first, commit second
**The right way:** Compute Optimizer → right-size → analyze stable baseline → Savings Plans → RIs only for specific zonal capacity needs

### Rule 3: No Ignoring Cost Anomaly Alerts
**You will be tempted to:** Dismiss anomaly alerts as "probably normal"
**Why that fails:** $500/day anomaly × 30 days = $15K surprise bill. Most anomalies are real — misconfigured resources, runaway Lambda, Athena full-table scans
**The right way:** Investigate every anomaly within 24 hours. Set a $100/day minimum threshold. Better to investigate a false positive than miss a real one

### Rule 4: No gp2 or x86 by Default
**You will be tempted to:** Use default instance types and EBS volume types from training data
**Why that fails:** gp2 is 20% more expensive than gp3. x86 is 40% more expensive than Graviton. These are pure waste
**The right way:** gp3 for all EBS. Graviton (arm64) for all compute unless compiled deps require x86. Make the cost-effective choice the default

### Rule 5: No Production Data in Standard S3 Forever
**You will be tempted to:** Skip lifecycle rules because "we might need the data"
**Why that fails:** S3 Standard = $0.023/GB/month. At 100TB, that's $2,300/month. Glacier Deep Archive = $0.00099/GB = $99/month for the same data. 96% savings
**The right way:** Lifecycle rules on every bucket. Standard → IA (30d) → Glacier (90d) → Deep Archive (365d). Intelligent-Tiering for unknown access patterns
