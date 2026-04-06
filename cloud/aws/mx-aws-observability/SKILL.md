---
name: mx-aws-observability
description: CloudWatch metrics/alarms/dashboards, Logs Insights queries, X-Ray/ADOT tracing, Application Signals APM, EMF custom metrics, CloudTrail organization trail/Lake/Insights, log retention cost optimization, and AI-generated anti-patterns
---

# AWS Observability — CloudWatch, X-Ray, CloudTrail for AI Coding Agents

**Load this skill when setting up monitoring, configuring tracing, creating alarms, querying logs, or establishing audit trails.**

## When to also load
- `mx-aws-lambda` — Powertools Logger/Tracer/Metrics, EMF
- `mx-aws-eks` — Container Insights, ADOT, Prometheus/Grafana
- `mx-aws-security` — GuardDuty findings, Security Hub integration
- `mx-aws-billing` — CloudWatch cost management, log retention optimization

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: JSON Structured Logs
| BAD | GOOD |
|-----|------|
| `console.log("User " + id + " logged in")` | `{"level":"INFO","userId":"123","action":"login","timestamp":"..."}` |

Structured JSON logs are mandatory for Logs Insights parsing. Use Powertools Logger (Lambda) or any structured logging library.

### Pattern 2: EMF for Custom Metrics
| BAD | GOOD |
|-----|------|
| `PutMetricData` API calls (latency, throttling, cost) | Embedded Metric Format in logs (zero API calls) |

EMF publishes custom metrics by writing specially formatted log lines. Zero latency overhead. No `PutMetricData` throttling. Limits: 100 metrics + 30 dimensions per log line.

### Pattern 3: CloudTrail Organization Trail
| BAD | GOOD |
|-----|------|
| Per-account trails (incomplete, fragmented) | Organization trail: multi-region, all accounts, centralized S3 |

One organization trail captures everything. Store in dedicated logging account S3 bucket. Enable log file integrity validation. KMS encryption at rest.

### Pattern 4: Max 10 Dimensions Per Metric
| BAD | GOOD |
|-----|------|
| 15 dimensions on a metric (CloudWatch cost explosion) | Max 10 dimensions. High-cardinality data → log properties, query with Logs Insights |

Each unique dimension combination creates a separate metric stream. High cardinality = thousands of metric streams = thousands of dollars/month.

### Pattern 5: Alarm on What Matters
Don't alarm on CPU. Alarm on **customer-facing impact**: error rates, latency P99, queue depth, DLQ depth, failed deployments.

---

## Level 2: Tracing & APM (Intermediate)

### Tracing Stack Migration
| Component | Legacy | Modern |
|-----------|--------|--------|
| SDK | X-Ray SDK | **ADOT** (OpenTelemetry) |
| Collection | X-Ray Daemon | **ADOT Collector** |
| Deployment | Manual | Lambda Layer / ECS Sidecar / EKS Managed Add-on |

**X-Ray SDK → maintenance mode by Feb 2026.** Migrate to ADOT (AWS Distro for OpenTelemetry). ADOT is vendor-agnostic — sends to X-Ray, CloudWatch, Prometheus, third-party.

### Application Signals — Automatic APM
- Auto-instruments applications for RED metrics (Requests, Errors, Duration)
- SLO tracking built-in. SLO burn rate alerts via CloudWatch Alarms
- No code changes required — agent-based instrumentation
- Adaptive sampling (Sep 2025): auto-adjusts trace capture rates. More during anomalies, less during normal

### Trace Best Practices
- **Annotations**: searchable business data (user_id, customer_tier). Filterable in X-Ray console
- **Metadata**: contextual debug info. NOT searchable but available per segment
- **Custom subsegments**: instrument expensive operations (DB calls, external APIs)
- Correlate traces with logs: embed X-Ray trace IDs in log output

### Logs Insights Query Optimization
- Start broad → refine. Most expensive queries scan the most data
- Logs Insights charges **by data scanned** — shortest timeframes = lowest cost
- Enable indexing for large datasets. Save common queries
- `filter` early to reduce scanned data. `stats` for aggregation

---

## Level 3: CloudTrail Deep & Advanced Monitoring (Advanced)

### CloudTrail Configuration

| Setting | Best Practice |
|---------|---------------|
| Trail scope | Organization trail, multi-region, all accounts |
| Storage | Centralized logging account S3 bucket |
| Integrity | Log file integrity validation enabled |
| Encryption | KMS CMK at rest. MFA Delete + versioning on bucket |
| Immutability | S3 Object Lock for compliance |
| Data events | Advanced event selectors for pattern-based filtering (high volume, high cost) |
| Management events | All (Read + Write). Include global service events (IAM, STS in us-east-1) |

### CloudTrail Lake
- Managed data lake for events. Long-term retention, immutable, SQL queries
- Lake query federation with Lake Formation for cross-account sharing
- Use for: compliance audits, security investigations, operational analysis

### CloudTrail Insights
- ML-based anomaly detection on API call rates + error rates
- 36-hour baseline learning period
- EventBridge rules on Insights events → SNS/Lambda for alerts/remediation
- Combine with GuardDuty + Security Hub for comprehensive detection

### Athena Query Optimization
- Partition projection on account/region/year/month/day
- Filter on `eventSource` + `eventName` for targeted queries
- Convert to Parquet for frequent query workloads

---

## Performance: Make It Fast

### Cost Optimization
1. **Log retention policies** — 30d for debug, 90d for app logs, 1yr+ for audit (CloudTrail)
2. **Log sampling** — 10% DEBUG in production (Powertools Logger supports this)
3. **EMF over PutMetricData** — zero API calls, no throttling
4. **Logs Insights short timeframes** — charges by data scanned
5. **CloudTrail data events selectively** — high volume, high cost. Use advanced selectors
6. **Metric resolution** — standard (60s) for most. High-resolution (1s) only for scaling metrics

### Dashboard Design
- One dashboard per service/team, not one giant dashboard
- Top row: customer-facing metrics (error rate, latency, availability)
- Second row: resource metrics (CPU, memory, queue depth)
- Bottom row: operational metrics (deployment status, config drift)

---

## Observability: Know It's Working

### Meta-Observability (Monitoring Your Monitoring)

| Signal | What to Watch |
|--------|--------------|
| CloudWatch agent health | Agent heartbeat metrics. Dead agent = blind spot |
| Log delivery | `IncomingLogEvents` per log group. Sudden drop = broken logging |
| Trace sampling | X-Ray sampling rate. Too low = missing important traces |
| CloudTrail delivery | `CloudTrailDeliveryLatency`. Delay = security blind spot |
| Alarm actions | `AlarmActionsEnabled`. Disabled alarm = silent failure |

- **Never disable alarms** — snooze or suppress, but don't disable
- Review alarms monthly: remove noisy unactionable alarms, add missing coverage
- **CloudWatch data protection policies** — auto-detect and mask PII in logs

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Unstructured Logs
**You will be tempted to:** Use `console.log()` or `print()` with string concatenation
**Why that fails:** Unstructured logs can't be parsed by Logs Insights, can't be filtered, can't be alarmed on. They're useless at scale
**The right way:** JSON structured logs with consistent fields: level, service, requestId, timestamp. Use Powertools Logger or equivalent

### Rule 2: No X-Ray SDK for New Projects
**You will be tempted to:** Use X-Ray SDK because tutorials reference it
**Why that fails:** X-Ray SDK enters maintenance mode Feb 2026. No new features. ADOT is the replacement and is vendor-agnostic
**The right way:** ADOT (OpenTelemetry) for all new instrumentation. Lambda Layer / ECS Sidecar / EKS Add-on

### Rule 3: No High-Cardinality Dimensions
**You will be tempted to:** Add `userId`, `requestId`, or `sessionId` as CloudWatch metric dimensions
**Why that fails:** Each unique value creates a separate metric time series. 1M users = 1M time series = CloudWatch bill explosion ($0.30/metric/month × 1M = $300K/month)
**The right way:** Log high-cardinality data as log properties. Query with Logs Insights. Dimensions = low-cardinality only (environment, service, region)

### Rule 4: No CloudTrail Without Log Protection
**You will be tempted to:** Store CloudTrail logs in a standard S3 bucket
**Why that fails:** An attacker who compromises the account can delete/modify CloudTrail logs to cover their tracks
**The right way:** Separate logging account, S3 Object Lock, MFA Delete, versioning, KMS encryption, Block Public Access, access logging on the CloudTrail bucket itself

### Rule 5: No Static Alarm Thresholds Only
**You will be tempted to:** Set fixed thresholds (CPU > 80%, error rate > 5%) and call it done
**Why that fails:** Traffic patterns change. What's normal at 3 AM is abnormal at 3 PM. Static thresholds miss slow degradation and false-alarm on predictable spikes
**The right way:** CloudWatch Anomaly Detection for dynamic baselines. SLO burn rate alerts for customer impact. Static thresholds as safety net, not primary signal
