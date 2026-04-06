---
name: mx-gcp-security
description: Use when working with GCP Secret Manager, Cloud KMS, encryption keys, VPC Service Controls, Security Command Center, Binary Authorization, or any GCP security hardening. Also use when the user mentions 'gcloud secrets', 'Secret Manager', 'KMS', 'CMEK', 'encryption key', 'key rotation', 'VPC Service Controls', 'security perimeter', 'Binary Authorization', 'attestor', 'Security Command Center', 'SCC', 'Security Health Analytics', 'data exfiltration', 'defense in depth', or 'supply chain security'.
---

# GCP Security — Secrets, Encryption, Perimeters & Supply Chain for AI Coding Agents

**This skill loads when you're managing GCP security infrastructure: secrets, keys, perimeters, or container verification.**

## When to also load
- `mx-gcp-iam` — IAM bindings for secret/key access, org policies
- `mx-gcp-networking` — VPC Service Controls, firewall rules
- `mx-gcp-gke` — Binary Authorization, Workload Identity
- `mx-gcp-cicd` — Container scanning, attestation in pipelines

---

## Level 1: Secret Manager (Beginner)

### Create and access secrets

```bash
# Create secret with automatic replication
gcloud secrets create payments-api-key-prod \
  --replication-policy="automatic"

# Add a version (NOTE: echo -n prevents trailing newline)
echo -n "sk_live_abc123xyz" | gcloud secrets versions add payments-api-key-prod --data-file=-

# Access latest version
gcloud secrets versions access latest --secret=payments-api-key-prod

# Access specific version (PREFER THIS in production)
gcloud secrets versions access 3 --secret=payments-api-key-prod
```

### Secret naming convention

```
{service}-{type}-{environment}
```

Examples: `payments-api-key-prod`, `db-password-staging`, `oauth-client-secret-dev`

### IAM for secrets — least privilege

| Role | Who gets it | What it does |
|------|------------|--------------|
| `roles/secretmanager.secretAccessor` | Service accounts that READ secrets | Can access secret versions only |
| `roles/secretmanager.secretVersionManager` | CI/CD pipelines | Can add/disable/enable versions |
| `roles/secretmanager.admin` | Platform team only | Full lifecycle management |

```bash
# Grant read-only access at secret level (not project level)
gcloud secrets add-iam-policy-binding payments-api-key-prod \
  --member="serviceAccount:vm-web-api@proj.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

### Version management

```bash
# Disable a version (reversible — secret data preserved)
gcloud secrets versions disable 2 --secret=payments-api-key-prod

# Destroy a version (IRREVERSIBLE after 24hr window)
gcloud secrets versions destroy 1 --secret=payments-api-key-prod
```

**Always disable before destroy.** Destruction has a 24-hour scheduled window — after that, data is gone permanently.

---

## Level 2: Cloud KMS & Encryption (Intermediate)

### Encryption decision tree

| Scenario | Encryption type | What to use |
|----------|----------------|-------------|
| Default protection, no compliance needs | Google-managed | Nothing to configure — automatic |
| Compliance requires key control | CMEK | Cloud KMS keys you manage |
| Compliance requires key custody outside GCP | EKM | External Key Manager |
| Highest tamper-resistance | Cloud HSM | FIPS 140-2 Level 3 HSM-backed keys |

### KMS hierarchy

```
Project → KeyRing → CryptoKey → CryptoKeyVersion
```

**KeyRings and CryptoKeys CANNOT be deleted.** Only CryptoKeyVersions can be destroyed. Plan names carefully.

```bash
# Create keyring (permanent — choose name wisely)
gcloud kms keyrings create my-keyring --location=us-east1

# Create key with automatic rotation
gcloud kms keys create my-key \
  --keyring=my-keyring --location=us-east1 \
  --purpose=encryption \
  --rotation-period=90d \
  --next-rotation-time=$(date -u +"%Y-%m-%dT%H:%M:%SZ" -d "+90 days")

# Encrypt data
gcloud kms encrypt \
  --key=my-key --keyring=my-keyring --location=us-east1 \
  --plaintext-file=secret.txt --ciphertext-file=secret.enc

# Decrypt data
gcloud kms decrypt \
  --key=my-key --keyring=my-keyring --location=us-east1 \
  --ciphertext-file=secret.enc --plaintext-file=secret.txt
```

### Separation of duties

| Role | Who | Cannot |
|------|-----|--------|
| `roles/cloudkms.admin` | Key administrators | Encrypt or decrypt data |
| `roles/cloudkms.cryptoKeyEncrypterDecrypter` | Application service accounts | Manage keys |

**Never give both roles to the same identity.** The person who manages keys should not be able to read the data those keys protect.

---

## Level 3: VPC Service Controls & SCC (Advanced)

### VPC Service Controls — data exfiltration prevention

```bash
# Create access policy (org-level, one per org)
gcloud access-context-manager policies create \
  --organization=ORG_ID --title="My Org Policy"

# Create perimeter
gcloud access-context-manager perimeters create my-perimeter \
  --policy=POLICY_ID \
  --title="Production Data Perimeter" \
  --resources="projects/PROJECT_NUMBER" \
  --restricted-services="bigquery.googleapis.com,storage.googleapis.com,secretmanager.googleapis.com" \
  --type=PERIMETER_TYPE_REGULAR

# Test with dry-run FIRST (logs violations without blocking)
gcloud access-context-manager perimeters dry-run create my-perimeter-test \
  --policy=POLICY_ID \
  --resources="projects/PROJECT_NUMBER" \
  --restricted-services="bigquery.googleapis.com,storage.googleapis.com"
```

**VPC SC deployment pattern:**
1. Map ALL dependencies (CI/CD, monitoring, shared services, third-party integrations)
2. Create dry-run perimeter — run for 2+ weeks
3. Analyze violation logs for legitimate traffic
4. Create ingress/egress rules for legitimate paths
5. Enforce the perimeter
6. Monitor continuously

### Security Command Center

```bash
# List active findings (Premium/Enterprise tier)
gcloud scc findings list ORGANIZATION_ID \
  --filter="state=\"ACTIVE\" AND severity=\"CRITICAL\""

# List findings for a specific project
gcloud scc findings list ORGANIZATION_ID \
  --filter="resourceName:\"projects/my-project\" AND state=\"ACTIVE\""

# Mute a finding (acknowledged, won't alert)
gcloud scc findings update FINDING_NAME \
  --organization=ORGANIZATION_ID --mute=MUTED
```

**SCC tiers:**

| Feature | Standard (free) | Premium | Enterprise |
|---------|----------------|---------|------------|
| Security Health Analytics | Basic detectors | All detectors | All + custom |
| Web Security Scanner | Manual only | Managed scans | Managed + custom |
| Event Threat Detection | No | Yes | Yes |
| Container Threat Detection | No | Yes | Yes |
| Attack exposure scoring | No | No | Yes |

### Binary Authorization

```bash
# Enable Binary Authorization on a GKE cluster
gcloud container clusters update my-cluster \
  --enable-binauthz --zone=us-east1-b

# Create attestor
gcloud container binauthz attestors create my-attestor \
  --attestation-authority-note=my-note \
  --attestation-authority-note-project=my-project

# Update policy to require attestation
gcloud container binauthz policy export > policy.yaml
# Edit policy.yaml to require attestors
gcloud container binauthz policy import policy.yaml
```

**Default policy allows ALL images** — you must configure it to restrict.

---

## Performance: Make It Fast

### Secret Manager caching

- Secret access API calls have latency (~50-100ms) — don't call per-request
- Cache secrets in-memory with TTL matching your rotation period
- Use `latest` alias only in dev — pin versions in production for predictable deploys
- Batch secret access at app startup, not on each API call

### KMS performance

- Symmetric encryption: ~100K operations/min per key
- Asymmetric: much lower — batch if needed
- Use envelope encryption: encrypt data with a local DEK, encrypt the DEK with KMS
- This minimizes KMS API calls and keeps large data encryption fast

### VPC Service Controls latency

- Perimeter enforcement adds ~0 latency to API calls (policy evaluated at Google's edge)
- But: misconfigured perimeters cause hard PERMISSION_DENIED errors that look like IAM issues
- Always check VPC SC logs before debugging IAM when a cross-project call fails

---

## Observability: Know It's Working

### Secret Manager audit

```bash
# Who accessed which secrets in the last 24h
gcloud logging read \
  'protoPayload.methodName="google.cloud.secretmanager.v1.SecretManagerService.AccessSecretVersion"' \
  --project=my-project --freshness=1d \
  --format="table(timestamp,protoPayload.authenticationInfo.principalEmail,protoPayload.resourceName)"
```

### KMS key usage monitoring

- Alert on `CryptoKeyVersions.destroy` — someone destroying a key version
- Alert on key version creation outside of automated rotation
- Monitor `cloudkms.googleapis.com/crypto_key_version/algorithm` for unexpected changes

### VPC Service Controls violations

```bash
# Check for VPC SC violations
gcloud logging read \
  'protoPayload.metadata.@type="type.googleapis.com/google.cloud.audit.VpcServiceControlAuditMetadata"' \
  --project=my-project --freshness=7d
```

### What to alert on

| Event | Severity |
|-------|----------|
| Secret version destroyed | **CRITICAL** |
| KMS key version destroyed | **CRITICAL** |
| VPC SC perimeter changed | **HIGH** |
| Secret accessed from unexpected SA | **HIGH** |
| SCC CRITICAL finding created | **CRITICAL** |
| Binary Authorization bypass (break-glass) | **CRITICAL** |

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never store secrets in environment variables or files
**You will be tempted to:** Pass secrets via `--set-env-vars=DB_PASS=xxx` on Cloud Run or write them to `.env` files.
**Why that fails:** Env vars appear in process listings, crash dumps, and Cloud Run revision metadata. Files persist in container layers and can be extracted.
**The right way:** Use Secret Manager API directly via client library. Cloud Run supports `--set-secrets=DB_PASS=db-password:latest` which mounts from Secret Manager.

### Rule 2: Never use `latest` alias for secrets in production
**You will be tempted to:** Use `versions/latest` because "it always gets the newest secret."
**Why that fails:** A bad secret version (typo, wrong value, encoding error) immediately breaks all services that reference `latest`. No rollback without adding another version.
**The right way:** Pin to specific version numbers. Update version references as part of your deployment process, not secret rotation.

### Rule 3: KMS KeyRings and keys cannot be deleted
**You will be tempted to:** Create a key called `test-key` in a keyring called `test` to try things out.
**Why that fails:** That keyring and key name are permanently consumed in that project. You can destroy key *versions* but not the key or ring resource itself. This clutters your KMS namespace permanently.
**The right way:** Use a naming convention from the start: `{project}-{purpose}-{env}`. Test in a disposable project if you need to experiment.

### Rule 4: Always dry-run VPC Service Controls before enforcing
**You will be tempted to:** Enforce a VPC SC perimeter immediately because "I know what traffic flows through."
**Why that fails:** You don't know all the dependencies. BigQuery scheduled queries, Looker Studio dashboards, Connected Sheets, CI/CD pipelines, monitoring tools — all make cross-project API calls you haven't mapped. Enforcing without dry-run causes immediate, widespread service outages.
**The right way:** Dry-run for 2+ weeks. Analyze every violation log entry. Create explicit ingress/egress rules for legitimate paths. THEN enforce.

### Rule 5: Separate key admin from key user
**You will be tempted to:** Give a service account both `cloudkms.admin` and `cloudkms.cryptoKeyEncrypterDecrypter` because "it needs to manage and use keys."
**Why that fails:** This violates separation of duties — the entity that controls key lifecycle can also decrypt all data. A compromised account with both roles can destroy keys AND exfiltrate data.
**The right way:** Key administrators manage key lifecycle. Application service accounts encrypt/decrypt. These should never be the same identity.
