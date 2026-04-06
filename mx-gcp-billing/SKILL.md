---
name: mx-gcp-billing
description: Use when creating budgets, analyzing costs, configuring billing exports, managing Committed Use Discounts (CUDs), labeling resources for cost allocation, or optimizing GCP spend. Also use when the user mentions 'billing', 'budget', 'cost', 'spend', 'CUD', 'committed use', 'billing export', 'BigQuery billing', 'cost allocation', 'labels', 'billing account', 'invoice', 'pricing calculator', 'sustained use discount', 'spot pricing', 'recommendations', or 'cost optimization'.
---

# GCP Billing — Budgets, CUDs, Cost Labels & Optimization for AI Coding Agents

**This skill loads when you're managing GCP costs, budgets, or billing configuration.**

## When to also load
- `mx-gcp-iam` — Billing IAM roles, billing account access
- `mx-gcp-compute` — VM rightsizing, Spot VMs, CUDs for compute
- `mx-gcp-bigquery` — Billing export queries, cost analysis

---

## Level 1: Budgets & Alerts (Beginner)

### Create a budget with alerts

```bash
# Create budget: $500/month with alerts at 50%, 80%, 100%
gcloud billing budgets create \
  --billing-account=BILLING_ACCOUNT_ID \
  --display-name="Production Monthly Budget" \
  --budget-amount=500 \
  --threshold-rule=percent=0.5 \
  --threshold-rule=percent=0.8 \
  --threshold-rule=percent=1.0 \
  --threshold-rule=percent=1.2,basis=forecasted-spend \
  --all-updates-rule-monitoring-notification-channels=projects/my-project/notificationChannels/CHANNEL_ID
```

**Budget types:**

| Type | What it does |
|------|-------------|
| Specified amount | Fixed dollar amount per month |
| Last month's spend | Auto-adjusts to previous month |
| Forecasted spend threshold | Alerts when projected spend exceeds target |

**Budgets don't stop spending.** They only send notifications. To actually cap spend, combine budgets with Cloud Functions that disable billing or shut down resources when thresholds are hit.

### Label resources for cost allocation

```bash
# Label a VM
gcloud compute instances update my-vm \
  --update-labels=team=backend,environment=production,cost-center=eng-001

# Label a GKE cluster
gcloud container clusters update my-cluster \
  --update-labels=team=platform,environment=production

# Label a Cloud SQL instance
gcloud sql instances patch my-db \
  --database-flags= \
  --update-labels=team=data,environment=production
```

**Mandatory labels for cost allocation:**

| Label | Purpose | Example values |
|-------|---------|---------------|
| `team` | Which team owns it | backend, frontend, data, ml |
| `environment` | Dev/staging/prod | dev, staging, production |
| `cost-center` | Finance mapping | eng-001, mktg-002 |
| `service` | Which application | api, worker, scheduler |

---

## Level 2: Billing Export & Analysis (Intermediate)

### Enable billing export to BigQuery

```bash
# Enable standard billing export (daily granularity)
gcloud billing accounts describe BILLING_ACCOUNT_ID

# Via Console: Billing > Billing export > BigQuery export
# Enable both Standard and Detailed usage cost exports
# Dataset: billing_export in your analytics project
```

**Note:** Billing export setup requires the Console — `gcloud` doesn't support creating the export directly. But once exported, you query with `gcloud` or BigQuery.

### Essential billing queries

```sql
-- Monthly cost by service
SELECT
  invoice.month,
  service.description AS service,
  ROUND(SUM(cost) + SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)), 2) AS net_cost
FROM `project.billing_export.gcp_billing_export_v1_XXXXX`
WHERE invoice.month = '202604'
GROUP BY 1, 2
ORDER BY net_cost DESC;

-- Cost by label (team)
SELECT
  labels.value AS team,
  ROUND(SUM(cost), 2) AS total_cost
FROM `project.billing_export.gcp_billing_export_v1_XXXXX`,
  UNNEST(labels) AS labels
WHERE labels.key = 'team'
  AND invoice.month = '202604'
GROUP BY 1
ORDER BY total_cost DESC;

-- Daily spend trend (detect anomalies)
SELECT
  DATE(usage_start_time) AS day,
  ROUND(SUM(cost), 2) AS daily_cost
FROM `project.billing_export.gcp_billing_export_v1_XXXXX`
WHERE usage_start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY 1
ORDER BY 1;

-- Top 10 most expensive resources
SELECT
  resource.name,
  service.description,
  ROUND(SUM(cost), 2) AS cost
FROM `project.billing_export.gcp_billing_export_v1_XXXXX`
WHERE invoice.month = '202604'
GROUP BY 1, 2
ORDER BY cost DESC
LIMIT 10;
```

### Committed Use Discounts (CUDs)

```bash
# Purchase compute CUD (1-year, 37% discount)
gcloud compute commitments create my-cud \
  --region=us-east1 \
  --resources=vcpu=16,memory=64GB \
  --plan=twelve-month \
  --type=GENERAL_PURPOSE

# List active commitments
gcloud compute commitments list --region=us-east1
```

**CUD decision tree:**

| Workload type | Discount type | Savings |
|---------------|--------------|---------|
| Steady-state VMs (always running) | 1-year CUD | 37% |
| Steady-state VMs (3+ year horizon) | 3-year CUD | 57% |
| Variable but predictable | Sustained Use Discount (auto) | Up to 30% |
| Fault-tolerant batch | Spot VMs | 60-91% |
| Cloud SQL (always running) | Cloud SQL CUD | 25-52% |

**CUDs are non-refundable, non-transferable commitments.** Only commit to workloads you're confident will run for the full term. Start with 1-year and upgrade to 3-year after validating the pattern.

---

## Level 3: Cost Optimization & Governance (Advanced)

### Recommender API (automated suggestions)

```bash
# Get VM rightsizing recommendations
gcloud recommender recommendations list \
  --project=my-project \
  --location=us-east1-b \
  --recommender=google.compute.instance.MachineTypeRecommender \
  --format='table(name,primaryImpact.costProjection.cost.units,content.overview.resourceName)'

# Get idle resource recommendations
gcloud recommender recommendations list \
  --project=my-project \
  --location=us-east1-b \
  --recommender=google.compute.instance.IdleResourceRecommender
```

### Org-level cost governance

```bash
# Set org policy to restrict expensive machine types
gcloud org-policies set-policy - <<'EOF'
name: projects/my-project/policies/compute.restrictMachineTypes
spec:
  rules:
  - values:
      allowedValues:
      - "zones/us-east1-b/machineTypes/e2-*"
      - "zones/us-east1-b/machineTypes/n2-standard-*"
      deniedValues:
      - "zones/*/machineTypes/a2-*"  # Block expensive GPU types
      - "zones/*/machineTypes/m2-*"  # Block memory-optimized
EOF
```

### Quota management

```bash
# Check current quota usage
gcloud compute project-info describe --project=my-project \
  --format='table(quotas.metric,quotas.limit,quotas.usage)'

# Request quota increase (via Console or support)
# Quotas prevent accidental resource explosion
```

---

## Performance: Make It Fast

- **Billing export queries** — always filter by `invoice.month` or `usage_start_time` range. The billing export table grows continuously and a full-table scan is expensive and slow.
- **Label early, label consistently** — retroactive labeling is impossible for billing export. Unlabeled resources from last month stay unlabeled in the billing data forever. Label at creation time.
- **Recommendations API first** — before manual optimization, check `google.compute.instance.MachineTypeRecommender` and `IdleResourceRecommender`. They analyze actual usage patterns and suggest concrete changes with projected savings.
- **Spot VMs for batch** — 60-91% cheaper than on-demand. Combine with MIGs and preemption handling for fault-tolerant workloads.
- **Sustained Use Discounts are automatic** — if a VM runs >25% of the month, GCP auto-applies SUD. No action needed. But SUD and CUD don't stack — CUD replaces SUD.

## Observability: Know It's Working

```bash
# Check billing account info
gcloud billing accounts list
gcloud billing accounts describe BILLING_ACCOUNT_ID

# List budgets
gcloud billing budgets list --billing-account=BILLING_ACCOUNT_ID

# Check active CUDs
gcloud compute commitments list --region=us-east1

# Get cost recommendations
gcloud recommender recommendations list \
  --project=my-project --location=us-east1-b \
  --recommender=google.compute.instance.MachineTypeRecommender
```

| Alert | Severity |
|-------|----------|
| Budget at 80% with 50%+ of month remaining | **HIGH** (overspend trajectory) |
| Budget at 100% | **CRITICAL** |
| Forecasted spend >120% of budget | **HIGH** |
| Unlabeled resources detected | **MEDIUM** |
| Idle VM recommendation (>14 days) | **MEDIUM** |
| CUD utilization <70% | **MEDIUM** (over-committed) |

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Always enable billing export to BigQuery
**You will be tempted to:** Rely on the Cloud Console billing dashboard because "it shows enough."
**Why that fails:** The Console dashboard shows aggregate costs but can't answer "which team's Cloud Run services cost the most last quarter?" or "what's our daily BigQuery spend trend?" Without export, you can't write custom queries, build team-level dashboards, detect anomalies, or do year-over-year comparison.
**The right way:** Enable both Standard and Detailed billing export to a BigQuery dataset in your analytics project. The export is free (you only pay for BQ storage). Query it monthly for cost allocation and anomaly detection.

### Rule 2: Label every resource at creation time
**You will be tempted to:** Skip labels because "we'll add them later" or "it's just a dev resource."
**Why that fails:** Billing export records the labels present AT THE TIME OF USAGE. Adding labels retroactively doesn't fix historical billing data. An unlabeled VM from January will show up as "unlabeled" in January's billing forever. Without labels, cost allocation by team/service/environment is impossible.
**The right way:** Every `gcloud` create command includes `--labels=team=X,environment=Y,cost-center=Z`. Enforce via org policy `constraints/compute.requireLabels` or pre-commit hooks on Terraform.

### Rule 3: Create budgets for every project, not just the billing account
**You will be tempted to:** Create one budget for the entire billing account because "that covers everything."
**Why that fails:** A billing account budget with a $5,000 threshold can't tell you that one project is spending $3,000 while another is at $200. A runaway resource in a small project hides inside the aggregate. By the time you notice, the bill has already spiked.
**The right way:** Per-project budgets with thresholds at 50%, 80%, and 100% of expected monthly spend. Add a 120% forecasted-spend threshold to catch runaway costs before month-end. Route alerts to the owning team, not just finance.

### Rule 4: Never purchase CUDs without 3 months of usage data
**You will be tempted to:** Buy a 1-year CUD immediately because "the savings are obvious."
**Why that fails:** CUDs are non-refundable commitments. If workload patterns change (migration to serverless, seasonal variation, project cancellation), you pay for committed resources you're not using. A 37% discount on resources you don't need is a 63% loss.
**The right way:** Run the workload for 3+ months. Analyze usage patterns via billing export. Confirm the baseline is stable. Start with 1-year CUDs on the MINIMUM steady-state usage. Only upgrade to 3-year CUDs after 6+ months of validated patterns.

### Rule 5: Check Recommender API before any manual cost optimization
**You will be tempted to:** Manually review instance types and guess at rightsizing because "I know my workloads."
**Why that fails:** Human intuition about resource utilization is unreliable. You provisioned n2-standard-8 because "8 vCPUs seemed right" but actual peak usage is 2.3 vCPUs. The Recommender API analyzes actual CPU, memory, and disk metrics over 14+ days and suggests specific machine types with projected cost impact.
**The right way:** `gcloud recommender recommendations list` with `MachineTypeRecommender` and `IdleResourceRecommender` before any manual optimization. Apply recommendations that have high confidence and significant savings. Recheck monthly.
