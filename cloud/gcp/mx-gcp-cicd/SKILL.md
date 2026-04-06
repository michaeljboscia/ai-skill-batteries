---
name: mx-gcp-cicd
description: Use when configuring Cloud Build pipelines, managing Artifact Registry repositories, setting up Cloud Deploy delivery pipelines, or automating GCP deployments. Also use when the user mentions 'Cloud Build', 'cloudbuild.yaml', 'Artifact Registry', 'Cloud Deploy', 'gcloud builds', 'gcloud artifacts', 'gcloud deploy', 'container registry', 'Docker push', 'build trigger', 'substitution', 'delivery pipeline', 'release', 'rollout', 'canary deployment', 'build step', or 'CI/CD'.
---

# GCP CI/CD — Cloud Build, Artifact Registry & Cloud Deploy for AI Coding Agents

**This skill loads when you're building CI/CD pipelines on GCP.**

## When to also load
- `mx-gcp-iam` — Service accounts for build steps, Workload Identity
- `mx-gcp-security` — **ALWAYS load** — Binary Authorization, CMEK for artifacts, supply chain security, container scanning
- `mx-gcp-gke` — Deploying to GKE via Cloud Deploy
- `mx-gcp-serverless` — Deploying to Cloud Run

---

## Level 1: Cloud Build & Artifact Registry (Beginner)

### Create an Artifact Registry repository

```bash
# Docker repository
gcloud artifacts repositories create my-repo \
  --repository-format=docker \
  --location=us-east1 \
  --description="Production container images" \
  --enable-vulnerability-scanning

# Configure Docker auth
gcloud auth configure-docker us-east1-docker.pkg.dev
```

**Always use Artifact Registry, not Container Registry.** Container Registry (gcr.io) is deprecated. Artifact Registry supports Docker, Maven, npm, Python, Go, and more — all in one service.

### Basic Cloud Build config (cloudbuild.yaml)

```yaml
steps:
  # Run tests
  - name: 'golang:1.23'
    entrypoint: 'go'
    args: ['test', './...']

  # Build container
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', '${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_IMAGE}:$SHORT_SHA', '.']

  # Push to Artifact Registry
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', '${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_IMAGE}:$SHORT_SHA']

substitutions:
  _REGION: us-east1
  _REPO: my-repo
  _IMAGE: my-api

options:
  logging: CLOUD_LOGGING_ONLY
  machineType: E2_HIGHCPU_8
```

### Create a build trigger

```bash
gcloud builds triggers create github \
  --name=main-build \
  --repo-owner=myorg \
  --repo-name=my-api \
  --branch-pattern='^main$' \
  --build-config=cloudbuild.yaml \
  --service-account=projects/my-project/serviceAccounts/cloudbuild@my-project.iam.gserviceaccount.com \
  --substitutions=_REGION=us-east1,_REPO=my-repo,_IMAGE=my-api
```

**Always specify `--service-account`** — the default Cloud Build service account has `roles/editor` (way too broad). Create a dedicated SA with only the permissions the build needs.

---

## Level 2: Multi-Stage Builds & Cloud Deploy (Intermediate)

### Production cloudbuild.yaml pattern

```yaml
steps:
  # Test
  - name: 'golang:1.23'
    id: 'test'
    entrypoint: 'go'
    args: ['test', '-race', '-count=1', './...']

  # Lint
  - name: 'golangci/golangci-lint:v1.62'
    id: 'lint'
    args: ['golangci-lint', 'run', './...']
    waitFor: ['-']  # Run in parallel with test

  # Build (wait for test + lint)
  - name: 'gcr.io/cloud-builders/docker'
    id: 'build'
    args:
      - 'build'
      - '--cache-from=${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_IMAGE}:latest'
      - '-t=${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_IMAGE}:$SHORT_SHA'
      - '-t=${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_IMAGE}:latest'
      - '.'
    waitFor: ['test', 'lint']

  # Push
  - name: 'gcr.io/cloud-builders/docker'
    id: 'push'
    args: ['push', '--all-tags', '${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_IMAGE}']

  # Deploy to Cloud Run (staging)
  - name: 'gcr.io/cloud-builders/gcloud'
    id: 'deploy-staging'
    args:
      - 'run'
      - 'deploy'
      - '${_IMAGE}-staging'
      - '--image=${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_IMAGE}:$SHORT_SHA'
      - '--region=${_REGION}'
      - '--no-traffic'  # Deploy but don't route traffic yet
```

**Use `waitFor` for parallelism** — steps without dependencies run concurrently. `waitFor: ['-']` means "start immediately." Without `waitFor`, steps run sequentially.

### Cloud Deploy delivery pipeline

```bash
# Create delivery pipeline (dev → staging → prod)
gcloud deploy delivery-pipelines create my-pipeline \
  --region=us-east1 \
  --config-from-file=- <<'EOF'
serialPipeline:
  stages:
  - targetId: dev
    profiles: [dev]
  - targetId: staging
    profiles: [staging]
  - targetId: prod
    profiles: [prod]
    strategy:
      canary:
        runtimeConfig:
          cloudRun:
            automaticTrafficControl: true
        canaryDeployment:
          percentages: [25, 50, 75]
          verify: true
EOF

# Create targets
gcloud deploy targets create dev \
  --region=us-east1 \
  --run-location=projects/my-project/locations/us-east1

gcloud deploy targets create prod \
  --region=us-east1 \
  --run-location=projects/my-project/locations/us-east1 \
  --require-approval
```

**`--require-approval` on production targets** — prevents accidental deployments. Someone must explicitly `gcloud deploy rollouts approve` before prod traffic shifts.

---

## Level 3: Advanced Patterns (Advanced)

### Artifact Registry cleanup policy

```bash
# Delete images older than 30 days, keep last 10 tagged versions
gcloud artifacts repositories set-cleanup-policies my-repo \
  --location=us-east1 \
  --policy=- <<'EOF'
- name: delete-old
  action: {type: DELETE}
  condition:
    olderThan: 2592000s
    tagState: ANY
- name: keep-recent
  action: {type: KEEP}
  condition:
    tagState: TAGGED
    newerThan: 2592000s
  mostRecentVersions:
    keepCount: 10
EOF
```

### Build security — provenance and SBOM

```yaml
# In cloudbuild.yaml — generate provenance automatically
options:
  requestedVerifyOption: VERIFIED
  sourceProvenanceHash: ['SHA256']
```

Cloud Build generates SLSA Level 3 provenance for builds. Combined with Binary Authorization, this ensures only verified images deploy to GKE or Cloud Run.

### Vulnerability scanning

```bash
# Enable vulnerability scanning on repository
gcloud artifacts repositories update my-repo \
  --location=us-east1 \
  --enable-vulnerability-scanning

# Check scan results for an image
gcloud artifacts docker images list-vulnerabilities \
  us-east1-docker.pkg.dev/my-project/my-repo/my-api:v1.0 \
  --format='table(vulnerability.effectiveSeverity,vulnerability.shortDescription)'
```

---

## Performance: Make It Fast

- **Parallel build steps** — use `waitFor` to run independent steps concurrently. Test + lint in parallel = 2x faster builds.
- **Docker layer caching** — `--cache-from` pulls the previous image's layers. For incremental changes, this reduces build time from minutes to seconds.
- **Machine type selection** — `E2_HIGHCPU_8` for compilation-heavy builds, `E2_MEDIUM` for simple Docker builds. Don't overpay for test-only steps.
- **Kaniko for rootless builds** — use `gcr.io/kaniko-project/executor` instead of Docker-in-Docker for builds that don't need privileged mode. Faster and more secure.
- **Regional Artifact Registry** — co-locate with Cloud Build and deployment targets. Cross-region pulls add latency to every build and deploy.
- **Cleanup policies** — stale images accumulate storage costs. 30-day delete + keep-10-latest is a sane default.

## Observability: Know It's Working

```bash
# List recent builds
gcloud builds list --limit=10

# Check build details
gcloud builds describe BUILD_ID

# Check Cloud Deploy releases
gcloud deploy releases list --delivery-pipeline=my-pipeline --region=us-east1

# Check rollout status
gcloud deploy rollouts list --release=RELEASE_NAME \
  --delivery-pipeline=my-pipeline --region=us-east1
```

| Alert | Severity |
|-------|----------|
| Build failure on main branch | **HIGH** |
| Build duration >2x baseline | **MEDIUM** |
| Vulnerability scan found CRITICAL | **HIGH** |
| Cloud Deploy rollout failed | **HIGH** |
| Artifact Registry storage >100GB | **INFO** |
| Production approval pending >4h | **MEDIUM** |

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never use the default Cloud Build service account
**You will be tempted to:** Skip `--service-account` because "the default works."
**Why that fails:** The default Cloud Build service account has `roles/editor` on the project — it can create VMs, delete databases, modify IAM. A compromised build step (malicious dependency, supply chain attack) inherits all those permissions. This is the #1 Cloud Build security finding in GCP audits.
**The right way:** Create a dedicated service account per pipeline with only the permissions it needs: `roles/artifactregistry.writer`, `roles/run.developer`, `roles/logging.logWriter`. Reference via `--service-account` in triggers.

### Rule 2: Always use Artifact Registry, never Container Registry
**You will be tempted to:** Push to `gcr.io/project/image` because "the old docs show it" or "it works."
**Why that fails:** Container Registry (gcr.io) is deprecated and will be removed. It stores images in GCS buckets with broad project-level access (anyone with `storage.objects.get` can pull any image). Artifact Registry has repository-level IAM, vulnerability scanning, cleanup policies, and multi-format support.
**The right way:** `us-east1-docker.pkg.dev/project/repo/image`. Create dedicated repositories per team or service. Enable vulnerability scanning. Set cleanup policies.

### Rule 3: Require approval for production deployments
**You will be tempted to:** Auto-deploy to production because "we have good tests" or "staging passed."
**Why that fails:** Tests can't catch everything — config differences between staging and prod, data-dependent bugs, external dependency changes. Auto-deploy to prod means a broken main branch = broken production with zero human review. The cost of a 5-minute approval is trivial vs the cost of a production outage.
**The right way:** `--require-approval` on production Cloud Deploy targets. Auto-deploy to dev and staging. Manual approval gate before prod. Canary rollout (25%→50%→75%→100%) with verification at each step.

### Rule 4: Tag images with commit SHA, not just "latest"
**You will be tempted to:** Push only `:latest` because "we always want the newest."
**Why that fails:** `:latest` is mutable — it points to whatever was pushed last. You can't rollback to a known-good version because `:latest` has been overwritten. Two deployments referencing `:latest` can get different images depending on timing. Post-mortem investigations can't determine which exact code was running.
**The right way:** Tag with `$SHORT_SHA` (commit hash) for traceability. Also tag with `:latest` for convenience, but deployments must reference the SHA tag. `image:abc1234` is immutable and auditable.

### Rule 5: Always include test and lint steps before build — never skip them
**You will be tempted to:** Go straight to Docker build because "the tests pass locally" or "this is just a container rebuild."
**Why that fails:** A pipeline that builds without testing can push and deploy broken code. "Tests pass locally" means nothing — the CI environment has different dependencies, env vars, and race conditions. Skipping tests saves 2 minutes per build but costs hours per production incident. Every shipped container should be proven by automated tests.
**The right way:** Every `cloudbuild.yaml` starts with test + lint steps that run in parallel (`waitFor: ['-']`). The build step `waitFor: ['test', 'lint']` — it only runs if both pass. Use `waitFor` for parallelism: independent steps (test, lint, security scan) run concurrently, build waits for all to complete.
