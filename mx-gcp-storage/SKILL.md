---
name: mx-gcp-storage
description: Use when creating GCS buckets, configuring lifecycle policies, generating signed URLs, setting CORS, managing storage classes, or optimizing Cloud Storage costs. Also use when the user mentions 'gcloud storage', 'gsutil', 'GCS bucket', 'Cloud Storage', 'lifecycle', 'signed URL', 'CORS', 'Nearline', 'Coldline', 'Archive', 'storage class', 'uniform bucket-level access', 'public access prevention', 'object versioning', 'retention policy', or 'transfer service'.
---

# GCP Storage — Cloud Storage for AI Coding Agents

**This skill loads when you're creating or managing GCS buckets and objects.**

## When to also load
- `mx-gcp-iam` — Bucket IAM, signed URL service accounts
- `mx-gcp-security` — CMEK encryption, VPC Service Controls
- `mx-gcp-networking` — Private Google Access for bucket access

---

## Level 1: Bucket Creation & Security (Beginner)

### Create a production bucket

```bash
gcloud storage buckets create gs://my-project-data-prod \
  --location=us-east1 \
  --default-storage-class=standard \
  --uniform-bucket-level-access \
  --public-access-prevention=enforced \
  --soft-delete-duration=7d
```

**Always set these flags:**
- `--uniform-bucket-level-access` — IAM only, no legacy ACLs (simpler, auditable)
- `--public-access-prevention=enforced` — blocks accidental public exposure
- `--location` — same region as compute for performance and cost

### Storage class decision tree

| Class | Access frequency | Min duration | Retrieval cost | Use case |
|-------|-----------------|-------------|---------------|----------|
| Standard | Frequent | None | Free | Hot data, serving, active workloads |
| Nearline | < 1x/month | 30 days | $0.01/GB | Monthly backups, infrequent reads |
| Coldline | < 1x/quarter | 90 days | $0.02/GB | Quarterly reports, DR copies |
| Archive | < 1x/year | 365 days | $0.05/GB | Compliance, legal holds, long-term |

**Early deletion fees apply.** Deleting a Nearline object at day 15 = charged for 30 days of storage.

### Lifecycle policies

```bash
# lifecycle.json
cat > lifecycle.json << 'EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
        "condition": {"age": 30, "matchesStorageClass": ["STANDARD"]}
      },
      {
        "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
        "condition": {"age": 90, "matchesStorageClass": ["NEARLINE"]}
      },
      {
        "action": {"type": "Delete"},
        "condition": {"age": 365}
      }
    ]
  }
}
EOF

gcloud storage buckets update gs://my-project-data-prod --lifecycle-file=lifecycle.json
```

---

## Level 2: Signed URLs, CORS & Versioning (Intermediate)

### Signed URLs (time-limited access without IAM)

```bash
# Generate signed URL (requires SA key or impersonation)
gcloud storage sign-url gs://my-bucket/report.pdf \
  --duration=1h \
  --private-key-file=sa-key.json

# Better: use impersonation (no key file needed)
gcloud storage sign-url gs://my-bucket/report.pdf \
  --duration=1h \
  --impersonate-service-account=signing-sa@my-project.iam.gserviceaccount.com
```

**Signed URL rules:**
- Max duration: 7 days (V4 signing)
- SA needs `iam.serviceAccountTokenCreator` for impersonation signing
- Never embed signed URLs in source code — generate at request time
- Use V4 signing (default, more secure than V2)

### CORS configuration

```bash
cat > cors.json << 'EOF'
[
  {
    "origin": ["https://app.mycompany.com"],
    "method": ["GET", "PUT", "POST"],
    "responseHeader": ["Content-Type", "x-goog-resumable"],
    "maxAgeSeconds": 3600
  }
]
EOF

gcloud storage buckets update gs://my-upload-bucket --cors-file=cors.json
```

**CORS gotchas:**
- `"origin": ["*"]` is a security risk — always specify exact origins
- `x-goog-resumable` header required for resumable uploads from browsers
- CORS only applies to browser requests (not server-to-server)

### Object versioning

```bash
# Enable versioning
gcloud storage buckets update gs://my-bucket --versioning

# List versions
gcloud storage ls --all-versions gs://my-bucket/important-file.txt

# Restore a previous version
gcloud storage cp gs://my-bucket/important-file.txt#1234567890 gs://my-bucket/important-file.txt
```

Add lifecycle rule to clean old versions:
```json
{"action": {"type": "Delete"}, "condition": {"numNewerVersions": 3, "isLive": false}}
```

---

## Level 3: Performance & Advanced Patterns (Advanced)

### Use `gcloud storage` not `gsutil`

| Feature | `gsutil` | `gcloud storage` |
|---------|---------|------------------|
| Auto-parallelization | Needs `-m` flag | Automatic |
| Upload speed (100x100MB) | Baseline | **33% faster** |
| Download speed (1x10GB) | Baseline | **94% faster** |
| Composite uploads | Manual config | Automatic |
| Status | Legacy | **Recommended** |

```bash
# BAD — old tool, needs manual parallelism
gsutil -m cp -r ./data/ gs://my-bucket/

# GOOD — auto-parallelized, faster hashing
gcloud storage cp -r ./data/ gs://my-bucket/
```

### Large file uploads

- Files >100MB: automatic parallel composite upload (splits into chunks)
- Resumable uploads: auto-resume on interruption
- Avoid sequential filenames (e.g., `file-001`, `file-002`) — causes hotspotting on same backend shard
- Prefix with hash for high-throughput bulk uploads

### Bucket IAM — resource-level

```bash
# Grant read access to specific bucket (not project-level)
gcloud storage buckets add-iam-policy-binding gs://my-bucket \
  --member="serviceAccount:vm-web-api@my-project.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"
```

---

## Performance: Make It Fast

- Co-locate buckets with compute (same region)
- Use `gcloud storage` over `gsutil` (auto-optimized)
- For >1TB transfers: Storage Transfer Service with multipart uploads (300% faster)
- Large requests (~1MB) get best throughput; parallelize small requests
- Enable buffered reads for large sequential file reads
- VM network bandwidth limits transfer speed — use larger instances for bulk transfers

## Observability: Know It's Working

```bash
# Check bucket metadata and settings
gcloud storage buckets describe gs://my-bucket

# List lifecycle rules
gcloud storage buckets describe gs://my-bucket --format="json(lifecycle)"

# Audit public access
gcloud storage buckets list --format="table(name,iamConfiguration.publicAccessPrevention)"
```

### What to alert on

| Event | Severity |
|-------|----------|
| Bucket created without public access prevention | **CRITICAL** |
| Object made public (allUsers/allAuthenticatedUsers) | **CRITICAL** |
| Large egress spike (data exfiltration indicator) | **HIGH** |
| Early deletion from Nearline/Coldline/Archive | **MEDIUM** |
| Bucket without lifecycle policy | **INFO** |

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Always enable uniform bucket-level access
**You will be tempted to:** Skip `--uniform-bucket-level-access` because "ACLs give more flexibility."
**Why that fails:** Mixed IAM + ACL creates a confusing, unauditable permission model. ACLs can grant access that IAM policies don't show. Uniform access means all permissions are in one place (IAM), visible in Cloud Asset Inventory, and enforceable via org policies.
**The right way:** `--uniform-bucket-level-access` on every bucket. Use IAM for all access control. Org policy `constraints/storage.uniformBucketLevelAccess` enforces this org-wide.

### Rule 2: Always enable public access prevention
**You will be tempted to:** Leave public access prevention off because "I might need to share a file publicly later."
**Why that fails:** One misconfigured IAM binding with `allUsers` or `allAuthenticatedUsers` makes the entire bucket or object public. This is the #1 cause of cloud data breaches. "Later" scenarios should use signed URLs, not public buckets.
**The right way:** `--public-access-prevention=enforced` on every bucket. For temporary public sharing, use signed URLs (time-limited, revocable, auditable).

### Rule 3: Always set lifecycle policies
**You will be tempted to:** Skip lifecycle rules because "we might need the data later."
**Why that fails:** Storage costs accumulate silently. Without lifecycle rules, Standard storage stays Standard forever. A 10TB bucket at Standard costs ~$260/yr; at Archive it's ~$12/yr. Multiply by 50 buckets.
**The right way:** Every bucket gets a lifecycle policy on creation: Standard → Nearline at 30d, Nearline → Coldline at 90d, delete or Archive at 365d. Adjust per use case, but never leave it blank.

### Rule 4: Use `gcloud storage`, not `gsutil`
**You will be tempted to:** Use `gsutil` because "that's what the Stack Overflow answer showed" or "that's what I know."
**Why that fails:** `gsutil` is legacy. `gcloud storage` is 33-94% faster with automatic parallelization, composite uploads, and optimized hashing. Using `gsutil` without `-m` means serial transfers — catastrophically slow for bulk operations.
**The right way:** `gcloud storage cp`, `gcloud storage rsync`, `gcloud storage ls`. Drop-in replacement for most `gsutil` commands.

### Rule 5: Never use `allUsers` or `allAuthenticatedUsers` on bucket IAM
**You will be tempted to:** Grant `roles/storage.objectViewer` to `allUsers` to make a file downloadable.
**Why that fails:** `allUsers` means literally everyone on the internet. `allAuthenticatedUsers` means anyone with a Google account (not just your org). Both are permanent until removed and apply to ALL objects in the bucket (or all current + future objects if set at bucket level).
**The right way:** Signed URLs for temporary access. Cloud CDN with backend bucket for public static content. Never direct public IAM bindings.
