---
name: mx-gcp-iam
description: Use when managing GCP identity, service accounts, IAM bindings, workload identity federation, impersonation, IAP, custom roles, or org policies. Also use when the user mentions 'gcloud iam', 'service account', 'IAM binding', 'roles/editor', 'roles/owner', 'workload identity', 'WIF', 'impersonate', 'Identity-Aware Proxy', 'IAP', 'org policy', 'iam.disableServiceAccountKeyCreation', 'serviceAccountTokenCreator', 'serviceAccountUser', 'custom role', 'SetIamPolicy', or 'least privilege'.
---

# GCP IAM — Identity & Access Management for AI Coding Agents

**This skill loads when you're creating, modifying, or auditing GCP identity and access controls.**

## When to also load
- `mx-gcp-networking` — firewall rules for IAP, VPC Service Controls
- `mx-gcp-security` — Secret Manager, KMS, SCC integration
- `mx-gcp-gke` — Workload Identity for GKE pods
- `mx-gcp-compute` — VM service account attachment

---

## Level 1: Patterns That Always Work (Beginner)

### Never use basic roles in production

| BAD | GOOD |
|-----|------|
| `roles/editor` | `roles/storage.objectViewer` |
| `roles/owner` | `roles/cloudsql.client` |
| `roles/viewer` | `roles/logging.viewer` |

Basic roles grant thousands of permissions. Always use predefined roles scoped to the specific service.

### Service account naming convention

```bash
# BAD — generic, reveals tooling
gcloud iam service-accounts create sa-1
gcloud iam service-accounts create jenkins

# GOOD — prefix + purpose, no info disclosure
gcloud iam service-accounts create vm-web-api \
  --display-name="Web API VM service account" \
  --description="Attached to web-api GCE instances. Owner: platform-team@"

gcloud iam service-accounts create wif-github-deploy \
  --display-name="GitHub Actions deployer (WIF)" \
  --description="Used by WIF pool for CI/CD. No keys."
```

**Prefixes:** `vm-` (VM-attached), `wi-` (Workload Identity), `wif-` (WIF), `cf-` (Cloud Function), `cr-` (Cloud Run), `onprem-` (on-premises).

### One service account per workload

```bash
# BAD — shared SA across workloads
gcloud compute instances create web-server --service-account=shared-sa@proj.iam.gserviceaccount.com
gcloud compute instances create batch-worker --service-account=shared-sa@proj.iam.gserviceaccount.com

# GOOD — dedicated SA per workload
gcloud compute instances create web-server --service-account=vm-web-server@proj.iam.gserviceaccount.com
gcloud compute instances create batch-worker --service-account=vm-batch-worker@proj.iam.gserviceaccount.com
```

### Grant at resource level, not project level

```bash
# BAD — project-level binding (all buckets in project)
gcloud projects add-iam-policy-binding my-project \
  --member="serviceAccount:vm-web-api@my-project.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"

# GOOD — resource-level binding (one bucket)
gcloud storage buckets add-iam-policy-binding gs://my-bucket \
  --member="serviceAccount:vm-web-api@my-project.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"
```

---

## Level 2: Workload Identity & Impersonation (Intermediate)

### Authentication decision tree

| Workload runs on... | Auth method | Key command |
|---------------------|-------------|-------------|
| GCE / GKE / Cloud Run / Cloud Functions | Attached service account | `--service-account=SA_EMAIL` at creation |
| GitHub Actions / GitLab CI / AWS / Azure | Workload Identity Federation | Configure WIF pool + provider |
| Developer laptop (local dev) | Impersonation via ADC | `gcloud auth application-default login --impersonate-service-account=SA` |
| On-premises server (no IdP) | SA key (LAST RESORT) | `gcloud iam service-accounts keys create` |

**Rule: If you reach for `keys create`, you chose wrong.** Go back and check if WIF or impersonation works.

### Workload Identity Federation (WIF) setup

```bash
# 1. Create pool
gcloud iam workload-identity-pools create github-pool \
  --location="global" \
  --display-name="GitHub Actions Pool"

# 2. Create provider with attribute conditions
gcloud iam workload-identity-pools providers create-oidc github-provider \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository=='my-org/my-repo'"

# 3. Grant SA impersonation to the federated identity
gcloud iam service-accounts add-iam-policy-binding wif-github-deploy@my-project.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/attribute.repository/my-org/my-repo"
```

**Critical WIF rules:**
- ONE provider per pool (prevents subject collisions)
- ALWAYS use `--attribute-condition` with multi-tenant IdPs (GitHub, GitLab)
- Map immutable attributes only (not display names or emails that can change)
- Dedicated project for WIF pools — use org policy to prevent creation elsewhere

### Service account impersonation

```bash
# Per-command impersonation
gcloud storage ls gs://target-bucket/ \
  --impersonate-service-account=reader@target-project.iam.gserviceaccount.com

# Per-session impersonation
gcloud config set auth/impersonate_service_account reader@target-project.iam.gserviceaccount.com
# ... all subsequent commands use this SA ...
gcloud config unset auth/impersonate_service_account  # ALWAYS clean up

# ADC impersonation (for local app development)
gcloud auth application-default login \
  --impersonate-service-account=reader@target-project.iam.gserviceaccount.com
```

**Required role on target SA:** `roles/iam.serviceAccountTokenCreator`

**Chained impersonation:** Max 4 SAs in chain. Each needs TokenCreator on the next.

---

## Level 3: Org Policies, Custom Roles & Terraform (Advanced)

### Organization policy constraints — enforce these

| Constraint | What it does | Default (post-May 2024) |
|-----------|--------------|------------------------|
| `iam.disableServiceAccountKeyCreation` | Blocks `keys create` | ON |
| `iam.managed.disableServiceAccountApiKeyCreation` | Blocks API keys for SAs | ON |
| `iam.automaticIamGrantsForDefaultServiceAccounts` | Blocks auto-Editor on defaults | ON |
| `iam.managed.disableServiceAccountCreation` | Blocks new SA creation | OFF |

```bash
# Check if key creation is blocked
gcloud resource-manager org-policies describe \
  iam.disableServiceAccountKeyCreation --organization=ORG_ID

# Enforce at org level
gcloud resource-manager org-policies set-policy policy.yaml --organization=ORG_ID
# policy.yaml:
# constraint: constraints/iam.disableServiceAccountKeyCreation
# booleanPolicy:
#   enforced: true
```

### Custom roles decision tree

| Situation | Use predefined or custom? |
|-----------|--------------------------|
| Predefined role exists with exactly the permissions needed | **Predefined** — auto-updates |
| Predefined role is close but has 2-3 extra dangerous permissions | **Custom** — subtract from predefined |
| Need permissions from 3+ predefined roles in one binding | **Custom** — combine minimally |
| Predefined role is close enough | **Predefined** — custom role maintenance cost > marginal risk |

```bash
# Create custom role from predefined template
gcloud iam roles create storageReaderNoDelete \
  --project=my-project \
  --title="Storage Reader (No Delete)" \
  --description="Like storage.objectViewer but explicit - read and list only" \
  --permissions="storage.objects.get,storage.objects.list,storage.buckets.get"
```

**Limits:** 300 custom roles/org, 300/project, 3000 permissions/role. Cannot create at folder level.

### Terraform IAM resources — danger ladder

| Resource | Behavior | Safety |
|----------|----------|--------|
| `google_project_iam_member` | Adds ONE member to ONE role | **SAFE** — additive |
| `google_project_iam_binding` | Sets ALL members for ONE role | **CAUTION** — replaces members |
| `google_project_iam_policy` | Replaces ENTIRE project policy | **DANGEROUS** — can lock you out |

```hcl
# SAFE — always prefer this
resource "google_project_iam_member" "web_api_storage" {
  project = "my-project"
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:vm-web-api@my-project.iam.gserviceaccount.com"
}

# DANGEROUS — never use unless you're managing the entire project policy as IaC
# resource "google_project_iam_policy" "project" { ... }
```

### Service account lifecycle — disable before delete

```bash
# Step 1: Disable (keeps bindings intact, stops auth)
gcloud iam service-accounts disable old-sa@my-project.iam.gserviceaccount.com

# Step 2: Wait 30 days, verify nothing breaks

# Step 3: Delete (bindings become orphaned)
gcloud iam service-accounts delete old-sa@my-project.iam.gserviceaccount.com
```

**Never delete default SAs** — disable them. Deleting a default SA can break service integrations in ways that are not recoverable.

---

## Performance: Make It Fast

### IAM Recommender — automated least-privilege

```bash
# List role recommendations for a project (unused permissions)
gcloud recommender recommendations list \
  --project=my-project \
  --location=global \
  --recommender=google.iam.policy.Recommender \
  --format="table(content.operationGroups[0].operations[0].resource, content.operationGroups[0].operations[0].value.bindings[0].role)"
```

- Recommender analyzes 90 days of permission usage
- Apply recommendations to shrink roles to actual usage
- Run quarterly — permissions accumulate faster than they're revoked

### IAM policy size limits

- Max 1500 members per policy binding
- Max 250 policy bindings per resource
- Exceeding these causes `SetIamPolicy` failures — use Google Groups instead of individual members
- Groups also make IAM changes O(1) instead of O(n) — one group add vs n member adds

### Avoid `getIamPolicy` → modify → `setIamPolicy` race conditions

```bash
# BAD — manual get-modify-set (race condition with concurrent changes)
gcloud projects get-iam-policy my-project > policy.yaml
# ... edit policy.yaml ...
gcloud projects set-iam-policy my-project policy.yaml

# GOOD — atomic add/remove
gcloud projects add-iam-policy-binding my-project \
  --member="serviceAccount:sa@proj.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"

gcloud projects remove-iam-policy-binding my-project \
  --member="serviceAccount:sa@proj.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"
```

---

## Observability: Know It's Working

### Audit log queries — copy-paste ready

```bash
# All IAM policy changes in last 24h
gcloud logging read 'protoPayload.methodName="SetIamPolicy"' \
  --project=my-project --freshness=1d \
  --format="table(timestamp,protoPayload.authenticationInfo.principalEmail,protoPayload.resourceName)"

# Service account key creation events (should be zero)
gcloud logging read 'protoPayload.methodName="google.iam.admin.v1.CreateServiceAccountKey"' \
  --project=my-project --freshness=7d

# Changes by specific user
gcloud logging read 'protoPayload.methodName="SetIamPolicy" AND protoPayload.authenticationInfo.principalEmail="user@example.com"' \
  --project=my-project --freshness=7d
```

### What to alert on

| Event | Log filter | Severity |
|-------|-----------|----------|
| Any `roles/owner` grant | `SetIamPolicy` + `bindingDeltas.role="roles/owner"` | **CRITICAL** |
| SA key created | `CreateServiceAccountKey` | **HIGH** |
| Basic role granted | `SetIamPolicy` + `roles/editor` or `roles/viewer` | **HIGH** |
| Bulk role changes (>5 in 1hr) | Count `SetIamPolicy` per hour | **MEDIUM** |
| `allAuthenticatedUsers` added | `SetIamPolicy` + `allAuthenticatedUsers` | **CRITICAL** |

### IAP monitoring

- IAP access logs show who accessed what and when — enable Data Access logs for IAP
- `35.235.240.0/20` must reach your VMs for IAP TCP tunneling
- If `gcloud compute start-iap-tunnel` fails, add `--verbosity=debug`
- Check: `gcloud compute firewall-rules list --filter="sourceRanges:35.235.240.0/20"`

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No basic roles ever
**You will be tempted to:** Use `roles/editor` because "it's just for development" or "I'll fix it later."
**Why that fails:** Basic roles grant 3000+ permissions including ability to create more SAs, modify IAM, and access every service. "Temporary" broad access in dev becomes permanent in prod via copy-paste.
**The right way:** Use the most specific predefined role. If you don't know which role, use `gcloud iam list-grantable-roles --resource=RESOURCE` to find it.

### Rule 2: No service account keys
**You will be tempted to:** Run `gcloud iam service-accounts keys create` because "WIF is complicated" or "I just need it to work."
**Why that fails:** Keys are 10-year credentials with no MFA, portable to any machine, and their theft is undetectable. One leaked key = full access to everything the SA can touch.
**The right way:** Use the authentication decision tree above. WIF for CI/CD, attached SA for GCP workloads, impersonation for local dev.

### Rule 3: Never use `google_project_iam_policy` in Terraform
**You will be tempted to:** Use the authoritative `iam_policy` resource because "I want to manage everything in code."
**Why that fails:** It replaces the ENTIRE project IAM policy. If your Terraform state diverges or you miss a binding, you lock out users, break service accounts, and potentially lose project access.
**The right way:** Use `google_project_iam_member` for individual bindings. Use `google_project_iam_binding` only when you need to authoritatively manage ALL members of a specific role.

### Rule 4: Always scope IAM to the resource, not the project
**You will be tempted to:** Grant `roles/storage.admin` at project level because "the SA needs access to multiple buckets."
**Why that fails:** Project-level grants apply to ALL current AND FUTURE resources of that type. A new bucket created next month inherits the binding you forgot about.
**The right way:** Grant at resource level. If you need access to multiple specific resources, make multiple bindings. If you truly need project-wide access, document WHY and get explicit approval.

### Rule 5: Verify org policy before creating keys or SAs
**You will be tempted to:** Create a service account or key and get a cryptic error, then try to "fix" it by changing permissions.
**Why that fails:** The error is likely an org policy constraint (`iam.disableServiceAccountKeyCreation`), not a permissions issue. Changing permissions won't help and wastes time.
**The right way:** Before any SA/key operation, check: `gcloud resource-manager org-policies describe iam.disableServiceAccountKeyCreation --project=PROJECT_ID`. If enforced, use WIF or impersonation instead.
