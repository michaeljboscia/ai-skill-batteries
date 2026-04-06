---
name: mx-gcp-serverless
description: Use when deploying Cloud Run services or jobs, writing Cloud Functions, configuring Cloud Scheduler or Cloud Tasks, or any serverless GCP workload. Also use when the user mentions 'gcloud run deploy', 'Cloud Run', 'Cloud Functions', 'gen2', 'Eventarc', 'Cloud Scheduler', 'Cloud Tasks', 'cron job', 'task queue', 'cold start', 'min-instances', 'concurrency', '--set-secrets', 'serverless', 'run jobs', or 'at-least-once delivery'.
---

# GCP Serverless — Cloud Run, Functions, Scheduler & Tasks for AI Coding Agents

**This skill loads when you're deploying or configuring serverless workloads on GCP.**

## When to also load
- `mx-gcp-iam` — Service account for invokers, Workload Identity
- `mx-gcp-security` — **ALWAYS load** — Secret Manager for all credentials, CMEK, ingress restrictions, no secrets in env vars
- `mx-gcp-networking` — VPC connector, Direct VPC egress, Cloud NAT

---

## Level 1: Cloud Run Services (Beginner)

### Deploy a production service

```bash
gcloud run deploy my-api \
  --image=us-east1-docker.pkg.dev/my-project/my-repo/my-api:v1.2.3 \
  --region=us-east1 \
  --service-account=cr-my-api@my-project.iam.gserviceaccount.com \
  --set-secrets=DB_PASS=db-password-prod:3 \
  --min-instances=1 --max-instances=10 \
  --cpu=1 --memory=512Mi \
  --concurrency=80 \
  --cpu-boost \
  --no-allow-unauthenticated
```

**Key flags:**
- `--set-secrets` mounts from Secret Manager (not env vars)
- `--min-instances=1` eliminates cold starts from zero
- `--cpu-boost` temporarily allocates extra CPU during startup (30-50% faster)
- `--no-allow-unauthenticated` requires IAM auth to invoke

### Concurrency tuning

| Workload type | Concurrency | Why |
|--------------|-------------|-----|
| I/O-bound (API proxy, DB queries) | 80-200 | Requests spend time waiting on I/O |
| CPU-bound (image processing) | = vCPUs (1-2) | Each request saturates a core |
| Mixed | 2-4x vCPUs | Balance |

If CPU >70% sustained, reduce concurrency. If memory climbs with concurrency, increase memory or reduce concurrency.

### Secrets — the right way

```bash
# GOOD — mount from Secret Manager
gcloud run deploy my-api \
  --set-secrets=DB_PASS=db-password-prod:3,API_KEY=api-key-prod:latest

# BAD — plain env vars with secret values
gcloud run deploy my-api \
  --set-env-vars=DB_PASS=actual-secret-value
```

**`--set-env-vars` replaces ALL existing env vars.** Use `--update-env-vars` to add/update without wiping others.

---

## Level 2: Cloud Run Jobs & Cloud Functions (Intermediate)

### Cloud Run Jobs (batch/scheduled work)

```bash
# Create a job
gcloud run jobs create nightly-etl \
  --image=us-east1-docker.pkg.dev/my-project/my-repo/etl:v1 \
  --region=us-east1 \
  --tasks=100 --parallelism=10 \
  --task-timeout=30m --max-retries=3 \
  --cpu=2 --memory=2Gi \
  --service-account=cr-etl@my-project.iam.gserviceaccount.com

# Execute manually
gcloud run jobs execute nightly-etl --region=us-east1

# Schedule via Cloud Scheduler
gcloud scheduler jobs create http nightly-etl-trigger \
  --location=us-east1 \
  --schedule="0 2 * * *" \
  --uri="https://us-east1-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/my-project/jobs/nightly-etl:run" \
  --http-method=POST \
  --oauth-service-account-email=scheduler-sa@my-project.iam.gserviceaccount.com
```

**Jobs vs Services decision:**

| Use case | Use |
|----------|-----|
| HTTP API, web app, webhook receiver | **Service** |
| Batch ETL, data migration, report generation | **Job** |
| Scheduled cleanup, nightly aggregation | **Job** + Cloud Scheduler |
| Event-driven processing (Pub/Sub, GCS) | **Service** or **Cloud Function** |

### Cloud Functions v2 (gen2)

```bash
gcloud functions deploy process-upload \
  --gen2 --runtime=nodejs20 \
  --region=us-east1 \
  --trigger-event-filters="type=google.cloud.storage.object.v1.finalized" \
  --trigger-event-filters="bucket=my-upload-bucket" \
  --memory=256Mi --timeout=300s \
  --service-account=cf-processor@my-project.iam.gserviceaccount.com \
  --set-secrets=API_KEY=api-key-prod:latest
```

**Gen2 vs Gen1:** Gen2 is built on Cloud Run. Use gen2 for: concurrency, longer timeouts (60min vs 9min), more memory (32GB), Eventarc triggers. Gen1 is legacy.

---

## Level 3: Cloud Scheduler & Cloud Tasks (Advanced)

### Cloud Scheduler

```bash
gcloud scheduler jobs create http daily-report \
  --location=us-east1 \
  --schedule="0 8 * * *" \
  --time-zone="America/New_York" \
  --uri="https://my-api-xxxxx-ue.a.run.app/generate-report" \
  --http-method=POST \
  --oidc-service-account-email=scheduler-sa@my-project.iam.gserviceaccount.com \
  --attempt-deadline=300s \
  --max-retry-attempts=3 \
  --min-backoff=10s --max-backoff=300s
```

### Cloud Tasks

```bash
# Create queue with rate limiting
gcloud tasks queues create email-queue \
  --location=us-east1 \
  --max-dispatches-per-second=10 \
  --max-concurrent-dispatches=5 \
  --max-attempts=5 \
  --min-backoff=10s --max-backoff=300s
```

**Cloud Tasks patterns:**
- **500/50/5 rule:** When scaling >500 TPS, increase by max 50% every 5 minutes
- **Task deduplication:** Provide unique task ID to prevent duplicates
- **Dead letter:** Return 2xx for permanent failures; implement DLQ pattern for exhausted retries
- **Handlers MUST be idempotent** — at-least-once delivery means duplicates happen

---

## Performance: Make It Fast

### Cold start elimination

1. `--min-instances=1` (eliminates scale-from-zero)
2. `--cpu-boost` (extra CPU during startup)
3. Slim images (distroless, multi-stage builds)
4. Lazy-load dependencies (don't import everything at module level)
5. Global variables for connection reuse (DB pools, API clients)
6. Artifact Registry in same region as service

### Cloud Run cost optimization

- **CPU always-allocated** for high-traffic services (connection pools, background tasks between requests)
- **CPU throttled** (default) for low-traffic/bursty services (cheaper — CPU only during request)
- Direct VPC egress instead of Serverless VPC Access connectors (eliminates connector idle costs)
- Co-locate services with their data (same region as DB/GCS)

---

## Observability: Know It's Working

```bash
# Check Cloud Run service logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=my-api" \
  --project=my-project --freshness=1h --limit=50

# Check Cloud Run Job execution status
gcloud run jobs executions list --job=nightly-etl --region=us-east1

# Check Cloud Scheduler job status
gcloud scheduler jobs describe daily-report --location=us-east1
```

### What to alert on

| Event | Severity |
|-------|----------|
| Cloud Run 5xx rate >1% | **HIGH** |
| Cold start latency p99 >5s | **MEDIUM** |
| Cloud Scheduler job failed 3 consecutive times | **HIGH** |
| Cloud Tasks DLQ depth increasing | **HIGH** |
| Cloud Run Job execution failed | **MEDIUM** |
| Instance count at max-instances | **MEDIUM** |

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Use --set-secrets, never --set-env-vars for sensitive data
**You will be tempted to:** Pass API keys via `--set-env-vars=API_KEY=sk_live_xxx` because "it's just one deploy."
**Why that fails:** Env vars are stored in the Cloud Run revision metadata, visible in Console and via `gcloud run services describe`. Anyone with `run.services.get` can read them.
**The right way:** `--set-secrets=API_KEY=secret-name:version` mounts from Secret Manager. The value never appears in revision metadata.

### Rule 2: Always set --min-instances=1 for production services
**You will be tempted to:** Leave min-instances at 0 because "it saves money when there's no traffic."
**Why that fails:** First request after idle period gets a cold start (1-30 seconds depending on image size and language). Users see timeouts. Health checks fail. The cost of 1 idle instance (~$5-15/month) is trivial compared to dropped requests.
**The right way:** `--min-instances=1 --cpu-boost` for any service that receives real traffic. Set min-instances=0 only for dev/test or truly infrequent cron targets.

### Rule 3: Use Cloud Run Jobs for batch — not Services with long timeouts
**You will be tempted to:** Set `--timeout=3600` on a Cloud Run Service and trigger it with Cloud Scheduler because "it's simpler."
**Why that fails:** Services are designed for request-response, not long-running batch. You pay for the full concurrency slot during the entire execution. There's no parallelism, no task indexing, no automatic retries per task.
**The right way:** `gcloud run jobs create` with `--tasks` and `--parallelism`. Jobs support up to 24hr execution, parallel task distribution via `CLOUD_RUN_TASK_INDEX`, per-task retries, and scale-to-zero billing.

### Rule 4: Cloud Tasks handlers must be idempotent
**You will be tempted to:** Write a handler that assumes exactly-once delivery because "the docs say it's a queue."
**Why that fails:** Cloud Tasks guarantees at-least-once delivery. Network retries, timeout retries, and deduplication window expiry all cause duplicate deliveries. A non-idempotent handler (e.g., "charge credit card") will double-charge customers.
**The right way:** Use a deduplication key (task ID or payload hash) and check before processing. Store processing state in a database. Design every handler to be safe to call multiple times.

### Rule 5: Never use --set-env-vars without understanding it replaces ALL vars
**You will be tempted to:** Run `gcloud run deploy --set-env-vars=NEW_VAR=value` to add one variable.
**Why that fails:** `--set-env-vars` is a REPLACE operation — it removes every env var not in the new list. If you had 10 env vars and deploy with `--set-env-vars=NEW_VAR=value`, you now have 1.
**The right way:** Use `--update-env-vars=NEW_VAR=value` to add/update without removing existing vars. Or use YAML config for declarative management.
