---
name: mx-gcp-observability
description: Use when configuring Cloud Logging, Cloud Monitoring, creating alerting policies, building dashboards, setting up uptime checks, querying logs, or instrumenting applications for GCP observability. Also use when the user mentions 'Cloud Logging', 'Cloud Monitoring', 'gcloud logging', 'gcloud monitoring', 'alerting policy', 'uptime check', 'log sink', 'log router', 'log-based metric', 'notification channel', 'dashboard', 'MQL', 'Cloud Trace', 'Error Reporting', 'Cloud Profiler', 'structured logging', 'log exclusion', 'audit log', or 'SLO'.
---

# GCP Observability — Logging, Monitoring & Alerting for AI Coding Agents

**This skill loads when you're configuring logging, monitoring, alerting, or dashboards on GCP.**

## When to also load
- `mx-gcp-iam` — Audit logs, log access IAM
- `mx-gcp-security` — Data Access logs, SCC integration
- `mx-gcp-billing` — Log storage costs, monitoring quotas

---

## Level 1: Logging & Basic Alerting (Beginner)

### Read logs with gcloud

```bash
# Cloud Run service logs (last hour)
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="my-api"' \
  --project=my-project --freshness=1h --limit=50 --format=json

# GKE container logs
gcloud logging read \
  'resource.type="k8s_container" AND resource.labels.cluster_name="my-cluster" AND resource.labels.namespace_name="production"' \
  --project=my-project --freshness=30m --limit=100

# Error logs only (any service)
gcloud logging read 'severity>=ERROR' \
  --project=my-project --freshness=1h --limit=50

# Structured log field search
gcloud logging read \
  'jsonPayload.userId="user-12345" AND severity>=WARNING' \
  --project=my-project --freshness=24h
```

### Structured logging (the right way)

```json
{"severity":"ERROR","message":"Payment failed","httpRequest":{"requestMethod":"POST","requestUrl":"/api/pay"},"labels":{"service":"payment-api","version":"v2.1"},"jsonPayload":{"userId":"u-123","errorCode":"CARD_DECLINED","traceId":"abc-def"}}
```

**Cloud Logging auto-parses JSON from stdout.** If your app writes JSON to stdout/stderr, Cloud Logging indexes `severity`, `httpRequest`, `labels`, and `jsonPayload` fields automatically. No agent or SDK required for Cloud Run, GKE, or Compute Engine.

### Create an alerting policy

```bash
# Alert on Cloud Run 5xx rate >1%
gcloud monitoring policies create \
  --policy-from-file=- <<'EOF'
displayName: "Cloud Run 5xx Rate >1%"
conditions:
- displayName: "5xx error rate"
  conditionThreshold:
    filter: 'resource.type="cloud_run_revision" AND metric.type="run.googleapis.com/request_count" AND metric.labels.response_code_class="5xx"'
    comparison: COMPARISON_GT
    thresholdValue: 0.01
    duration: 300s
    aggregations:
    - alignmentPeriod: 60s
      perSeriesAligner: ALIGN_RATE
notificationChannels:
- projects/my-project/notificationChannels/CHANNEL_ID
EOF

# Create notification channel (email)
gcloud monitoring channels create \
  --type=email \
  --display-name="Ops Team Email" \
  --channel-labels=email_address=ops@mycompany.com
```

### Uptime checks

```bash
gcloud monitoring uptime create my-api-health \
  --resource-type=uptime-url \
  --monitored-resource='{"host":"api.mycompany.com","project_id":"my-project"}' \
  --http-check-path=/healthz \
  --check-every=60s \
  --timeout=10s \
  --regions=USA,EUROPE,ASIA_PACIFIC
```

---

## Level 2: Log Routing, Sinks & Metrics (Intermediate)

### Log sinks (route logs to storage)

```bash
# Route audit logs to BigQuery for long-term analysis
gcloud logging sinks create audit-to-bq \
  bigquery.googleapis.com/projects/my-project/datasets/audit_logs \
  --log-filter='logName:"cloudaudit.googleapis.com"' \
  --use-partitioned-tables

# Route all production logs to GCS for cold storage
gcloud logging sinks create prod-to-gcs \
  storage.googleapis.com/my-logs-archive \
  --log-filter='resource.labels.namespace_name="production"'

# Route error logs to Pub/Sub for real-time processing
gcloud logging sinks create errors-to-pubsub \
  pubsub.googleapis.com/projects/my-project/topics/error-alerts \
  --log-filter='severity>=ERROR'
```

**After creating a sink**, grant the sink's service account write access to the destination:
```bash
# Get sink writer identity
gcloud logging sinks describe audit-to-bq --format='get(writerIdentity)'
# Grant access (example for BigQuery)
# bq add-iam-policy-binding --role=roles/bigquery.dataEditor --member=WRITER_IDENTITY
```

### Log exclusions (reduce costs)

```bash
# Exclude debug logs from storage (still queryable for 30 days)
gcloud logging sinks update _Default \
  --add-exclusion=name=exclude-debug,filter='severity="DEBUG"'

# Exclude noisy health check logs
gcloud logging sinks update _Default \
  --add-exclusion=name=exclude-healthchecks,filter='httpRequest.requestUrl="/healthz"'
```

### Log-based metrics

```bash
# Create counter metric for payment failures
gcloud logging metrics create payment_failures \
  --description="Count of payment processing failures" \
  --log-filter='jsonPayload.event="payment_failed"' \
  --metric-descriptor-type=logging.googleapis.com/user/payment_failures
```

Log-based metrics appear in Cloud Monitoring and can trigger alerts. Use for business-level signals that aren't covered by built-in metrics.

---

## Level 3: SLOs, Dashboards & Advanced (Advanced)

### Service Level Objectives (SLOs)

```bash
# Create an SLO: 99.9% availability over 28 days
gcloud monitoring slo create \
  --service=my-api-service \
  --sli='{"requestBased":{"goodTotalRatio":{"goodServiceFilter":"resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_count\" AND metric.labels.response_code_class!=\"5xx\"","totalServiceFilter":"resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_count\""}}}' \
  --goal=0.999 \
  --rolling-period=28d
```

### Custom dashboards

```bash
# Create dashboard from JSON definition
gcloud monitoring dashboards create --config-from-file=dashboard.json
```

**Essential dashboard widgets:**
- Error rate by service (line chart)
- Latency p50/p95/p99 (line chart)
- Request volume (stacked bar)
- Active instances / pod count (line chart)
- Error budget burn rate (scorecard)

### Cloud Trace integration

Cloud Trace is auto-instrumented for:
- Cloud Run (built-in)
- GKE with managed service mesh
- App Engine

For custom services, add OpenTelemetry SDK with the GCP exporter. Propagate `X-Cloud-Trace-Context` header across service calls for distributed tracing.

---

## Performance: Make It Fast

- **Structured JSON logging** — Cloud Logging indexes JSON fields automatically. Use `severity`, `httpRequest`, `labels`, and `jsonPayload` for fast filtered queries. Unstructured text requires regex search (10x slower).
- **Log exclusions for cost** — Debug and health-check logs can be 80% of log volume. Exclude them from the `_Default` sink but they remain queryable for the default retention period.
- **Partitioned BigQuery sinks** — always use `--use-partitioned-tables` for BQ log sinks. Without partitioning, querying a year of logs scans the entire table (expensive and slow).
- **Sampling for high-volume services** — Cloud Logging supports log sampling at the LB level. Set `--logging-sample-rate=0.1` for high-traffic services to reduce volume by 90% while maintaining statistical validity.
- **Alert on symptoms, not causes** — alert on error rate and latency (symptoms users experience), not CPU usage or memory (causes that may or may not affect users). CPU at 90% is fine if latency is normal.

## Observability: Know It's Working

```bash
# Check current log volume by resource type
gcloud logging read '' --project=my-project \
  --format='table(resource.type)' --limit=1000 | sort | uniq -c | sort -rn

# List alerting policies
gcloud monitoring policies list --project=my-project

# List notification channels
gcloud monitoring channels list --project=my-project

# Check uptime check results
gcloud monitoring uptime list --project=my-project
```

| Alert | Severity |
|-------|----------|
| Uptime check failing | **CRITICAL** |
| Error rate >1% for 5min | **HIGH** |
| Latency p99 >5s for 10min | **HIGH** |
| Error budget burn >10x normal rate | **HIGH** |
| Log volume spike >3x baseline | **MEDIUM** (investigate + potential cost) |
| Alerting policy with no notification channel | **INFO** (silent alert) |

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Always use structured JSON logging, not plaintext
**You will be tempted to:** Use `console.log("Error: " + message)` or `log.Println("failed to process")` because "it's simpler."
**Why that fails:** Plaintext logs can't be filtered by field, can't be indexed, and require regex to search. Finding "all payment errors for user X in the last hour" requires scanning every log line. With structured JSON, it's a single filter: `jsonPayload.userId="X" AND jsonPayload.event="payment_error"`.
**The right way:** Log JSON to stdout with `severity`, `message`, and a `jsonPayload` containing business context (userID, requestID, traceID). Cloud Logging parses it automatically.

### Rule 2: Always create a notification channel before creating alerting policies
**You will be tempted to:** Create an alerting policy without a notification channel because "I'll add it later" or "I'll check the Console."
**Why that fails:** An alert without a notification channel fires silently. It appears in the Cloud Monitoring Console but nobody sees it. Alerts exist to wake people up, not to populate a dashboard. "I'll add it later" means "the next outage at 3 AM goes unnoticed."
**The right way:** Create notification channel FIRST (email, Slack, PagerDuty). Reference the channel ID in every alerting policy. Verify alerts fire by triggering a test condition.

### Rule 3: Always route audit logs to a long-term sink
**You will be tempted to:** Rely on the default 30-day log retention because "we don't need logs that old."
**Why that fails:** Compliance investigations, security incidents, and post-mortems often need logs from months ago. Admin Activity audit logs are retained for 400 days by default, but Data Access logs are only 30 days. When you discover a compromised service account, you need to trace its actions over the entire compromise window — which is often >30 days.
**The right way:** Create a log sink to BigQuery (for querying) or GCS (for archive) with `logName:"cloudaudit.googleapis.com"` filter. Use `--use-partitioned-tables` for BigQuery. Set retention to match compliance requirements (typically 1-7 years).

### Rule 4: Use log exclusions to control cost, not by reducing log volume at source
**You will be tempted to:** Reduce logging in application code to save on Cloud Logging costs ("change INFO to WARN only").
**Why that fails:** Reducing log level at the source means the data is gone forever. When a production incident happens and you need INFO-level context, it doesn't exist. Log exclusions in Cloud Logging route logs away from storage but keep them queryable for the default retention period. You get cost savings without losing debuggability.
**The right way:** Log generously at the application level (INFO for key events, DEBUG for troubleshooting). Use `gcloud logging sinks update _Default --add-exclusion` to exclude high-volume, low-value patterns (health checks, debug) from long-term storage.

### Rule 5: Alert on symptoms (error rate, latency), not causes (CPU, memory)
**You will be tempted to:** Create alerts for "CPU >80%" or "memory >90%" because "that means something is wrong."
**Why that fails:** A service at 90% CPU with 50ms p99 latency is fine — it's efficiently utilized. A service at 30% CPU with 5s p99 latency has a real problem (likely I/O or lock contention). CPU and memory alerts create noise without actionable signal. Error rate and latency alerts directly measure what users experience.
**The right way:** Primary alerts: error rate >1%, latency p99 >target, uptime check failure. Secondary alerts: error budget burn rate >10x normal. Informational only: CPU, memory, disk (useful for capacity planning, not for incident response).
