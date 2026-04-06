---
name: mx-aws-lambda
description: AWS Lambda functions — cold starts, SnapStart, Powertools, layers vs containers, handler patterns, concurrency, ARM64, recursive detection, Lambda@Edge vs CloudFront Functions, cost optimization, and AI-generated anti-patterns
---

# AWS Lambda — Serverless Functions for AI Coding Agents

**Load this skill when writing, reviewing, or debugging AWS Lambda functions, layers, triggers, or serverless APIs.**

## When to also load
- `mx-aws-apigw` — API Gateway triggers (REST vs HTTP API, authorizers, WebSocket)
- `mx-aws-orchestration` — Step Functions integration (direct invoke vs SDK, Express workflows)
- `mx-aws-observability` — CloudWatch, X-Ray, EMF, Application Signals
- `mx-aws-iam` — execution roles, resource policies, least privilege
- `mx-aws-containers` — when deciding Lambda vs Fargate for workload

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: Global Scope for Reusable Objects
| BAD | GOOD |
|-----|------|
| `const client = new DynamoDBClient({})` inside handler | `const client = new DynamoDBClient({})` outside handler at module level |
| Creates new connection every invocation (200ms+ penalty) | Reuses connection across warm invocations |

SDK clients, DB connections, config lookups, and heavy imports go in **global scope**. Only request-specific data goes in the handler.

### Pattern 2: Modular SDK Imports
| BAD | GOOD |
|-----|------|
| `import AWS from 'aws-sdk'` (v2 monolithic, 70MB+) | `import { DynamoDBClient } from '@aws-sdk/client-dynamodb'` (v3 modular) |
| `import boto3; client = boto3.client('s3')` is fine for Python | Python: use `boto3` normally — it's pre-loaded in the runtime |

For Node.js: use **AWS SDK v3 modular imports** + esbuild/webpack with tree-shaking. For Python: `boto3` is fine but lazy-import heavy optional deps.

### Pattern 3: ARM64 Runtime by Default
| BAD | GOOD |
|-----|------|
| `Architectures: [x86_64]` (default, more expensive) | `Architectures: [arm64]` (20% cheaper, often faster) |

ARM64 (Graviton2) is **20% cheaper** and provides better performance for most workloads. Java 11+, Python, Node.js, Go, .NET 6+ all support ARM64. Set it as default unless you have compiled x86-only dependencies.

### Pattern 4: Powertools Initialization
```python
# OUTSIDE handler — global scope
from aws_lambda_powertools import Logger, Tracer, Metrics
logger = Logger(service="payment-service")
tracer = Tracer()
metrics = Metrics()

@logger.inject_lambda_context
@tracer.capture_lambda_handler
@metrics.log_metrics
def handler(event, context):
    # Request-specific logic only
```
Set `POWERTOOLS_SERVICE_NAME` env var for consistent tagging across Logger/Tracer/Metrics.

### Pattern 5: Never Store User Data in Global Scope
Global variables persist between invocations. Storing user sessions, auth tokens, or request-specific data in global scope causes **data leaks between different users' requests**.

---

## Level 2: Cold Start Elimination (Intermediate)

### Decision Tree: Cold Start Strategy

| Scenario | Strategy | Cost |
|----------|----------|------|
| Java/.NET functions | **SnapStart** (free, 90% reduction) | $0 |
| Python/Node.js with VPC | Remove VPC if possible, use VPC endpoints | $0 |
| Predictable steady traffic | **Provisioned Concurrency** on alias (not $LATEST) | $/hr per instance |
| Unpredictable traffic, latency-tolerant | Do nothing — warm starts are fast enough | $0 |
| Need <100ms cold starts | Use **Go or Rust** runtime | $0 |

### SnapStart Deep Dive (Java, Python, .NET)
- **Free** — no additional cost. Up to 90% cold start reduction
- INIT phase billing starts **Aug 2025** — cold start optimization = direct cost savings
- Hooks: `beforeCheckpoint` (download files, preload ML models) + `afterRestore` (reconnect DB, refresh tokens)
- State frozen in snapshot: **randomness, timestamps, connections all need reinit** via afterRestore hook
- Python + .NET support added 2024-2025 (not just Java anymore)

### Provisioned Concurrency Gotchas
- Must target a **specific version or alias**, NOT `$LATEST`
- Costs $/hr per provisioned instance regardless of invocations
- Use Application Auto Scaling to schedule PC (scale up before known peaks, down after)
- Keep-warm EventBridge rule is a poor substitute (unreliable, doesn't guarantee warm instances)

### Memory = CPU = Speed
Increasing memory proportionally increases CPU. A function at 1769MB gets 1 full vCPU. Use **Lambda Power Tuning** tool to find the optimal memory/cost/speed balance — sometimes 2x memory is cheaper because it finishes 3x faster.

---

## Level 3: Production Patterns (Advanced)

### Concurrency Model
| Setting | Purpose | Scope |
|---------|---------|-------|
| **Account limit** | Default 1000 concurrent (request increase for prod) | Account-wide |
| **Reserved concurrency** | Guarantee capacity for critical functions | Per-function |
| **Provisioned concurrency** | Pre-initialized = zero cold starts | Per-alias/version |

- Recursive invocation detection: Lambda auto-detects and stops loops (SQS→Lambda→SQS). Auto-enabled since 2023
- Throttling: 429 errors when hitting concurrency limit. Implement retries with exponential backoff in callers

### Layers vs Container Images

| Criterion | Layers | Container Images |
|-----------|--------|-----------------|
| Max size | 250MB unzipped (5 layers max) | 10GB |
| Custom runtime | Limited | Full control (any OS-level dep) |
| Cold start | Comparable (AWS optimized) | Comparable (AWS optimized) |
| Go/Rust | **Avoid** layers (increases cold starts) | Preferred |
| Sharing deps | Across functions in account | Per-function |

- Layers and container images are **mutually exclusive** — can't mix
- Container: use **multi-stage builds** mandatory. Use **AWS base images** (pre-cached on Lambda infra)
- Container: use **SOCI** (Seekable OCI) index if image is large — lazy loading reduces startup

### Lambda@Edge vs CloudFront Functions

| Criterion | CloudFront Functions | Lambda@Edge |
|-----------|---------------------|-------------|
| Latency | <1ms (runs at POP) | 30-50ms more (regional edge cache) |
| Cost | **1/6th** the cost | 6x more expensive |
| Triggers | Viewer request/response only | All 4 (viewer + origin request/response) |
| Network calls | No | Yes |
| Runtime | JavaScript only | Node.js, Python |
| Use case | URL rewrites, header manipulation, basic auth | Complex auth, image resize, API calls |

**Start with CloudFront Functions. Migrate to Lambda@Edge only when you hit limits.**

---

## Performance: Make It Fast

### Optimization Checklist
1. **ARM64 runtime** — 20% cheaper, often faster
2. **Minimize package size** — tree-shake, exclude dev deps, no full SDK
3. **Right-size memory** — use Power Tuning tool (not guesswork)
4. **SnapStart for Java/.NET/Python** — free 90% cold start reduction
5. **Reuse connections** — SDK clients, DB pools in global scope
6. **Lazy-load** heavy optional dependencies only when needed
7. **Tiered pricing** (May 2025) — first 6B GB-seconds cheaper

### VPC Considerations
VPC adds latency to cold starts (ENI attachment). Avoid VPC unless you must access VPC resources. Use:
- **VPC endpoints** for AWS services (S3, DynamoDB, SQS) instead of NAT Gateway
- **RDS Proxy** for database connections (mandatory for Lambda + RDS)
- Gateway endpoints for S3 + DynamoDB are **FREE** — always use them

---

## Observability: Know It's Working

### What to Instrument
| Signal | Tool | Key Metric |
|--------|------|-----------|
| Logs | Powertools Logger (JSON structured) | Error rate, cold start frequency |
| Traces | Powertools Tracer → X-Ray | Duration by subsegment, external call latency |
| Metrics | Powertools Metrics → EMF → CloudWatch | Invocations, errors, throttles, duration P99 |

- **EMF** (Embedded Metric Format): zero-latency custom metrics. No `PutMetricData` API calls needed
- Max **10 dimensions per metric** to avoid CloudWatch cost explosion
- Log sampling: **10% DEBUG in production** to reduce CW Logs cost
- Annotations = filterable in X-Ray traces. Metadata = debug context. Different purposes
- **Never log PII or credentials** — use CloudWatch data protection policies
- INIT phase monitoring: track `Init Duration` in CloudWatch to measure cold start impact

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No DB Connections Inside Handler
**You will be tempted to:** Create database clients inside the handler for "cleaner code" or "isolation"
**Why that fails:** 200ms+ connection overhead on every invocation. With RDS, you'll exhaust connection limits within minutes under load
**The right way:** Global scope for clients + RDS Proxy for connection pooling

### Rule 2: No gp2, No x86_64 by Default
**You will be tempted to:** Use default architecture (x86_64) and default EBS (gp2) because they "just work"
**Why that fails:** 20% cost premium on x86_64. gp2 is legacy with burst credit cliffs
**The right way:** `Architectures: [arm64]` unless compiled deps require x86. gp3 for any attached storage

### Rule 3: No $LATEST for Provisioned Concurrency
**You will be tempted to:** Set provisioned concurrency on $LATEST because it's simpler
**Why that fails:** Provisioned concurrency requires a published version or alias. $LATEST changes on every deploy, invalidating the PC config
**The right way:** Publish a version, create an alias (e.g., `prod`), set PC on the alias

### Rule 4: No Full SDK Import in Node.js
**You will be tempted to:** `import AWS from 'aws-sdk'` because v2 examples are everywhere in training data
**Why that fails:** 70MB+ bundle, 500ms+ cold start. AWS SDK v2 is in maintenance mode
**The right way:** `import { S3Client } from '@aws-sdk/client-s3'` (v3 modular, tree-shakeable)

### Rule 5: No Secrets in Environment Variables Without Encryption
**You will be tempted to:** Store API keys and passwords as plaintext Lambda environment variables
**Why that fails:** Visible in console, CloudFormation templates, and API responses. Leaked in logs if you dump `process.env`
**The right way:** Use Secrets Manager or SSM Parameter Store (SecureString). Cache the secret in global scope with TTL refresh
