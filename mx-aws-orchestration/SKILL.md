---
name: mx-aws-orchestration
description: Step Functions Standard vs Express, ASL error handling, Distributed Map, JSONata transforms, EventBridge rules/pipes/scheduler, SDK integrations, callback tokens, claim check pattern, and AI-generated anti-patterns
---

# AWS Orchestration — Step Functions & EventBridge for AI Coding Agents

**Load this skill when building workflows with Step Functions, configuring EventBridge rules/pipes, or orchestrating multi-service processes.**

## When to also load
- `mx-aws-lambda` — Lambda integration patterns, direct invoke vs SDK
- `mx-aws-messaging` — SQS/SNS as Step Functions targets, EventBridge Pipes sources
- `mx-aws-containers` — ECS RunTask via EventBridge, Step Functions ECS integration
- `mx-aws-observability` — X-Ray tracing, CloudWatch Logs for Step Functions

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: Standard vs Express Decision
| Need | Choice | Why |
|------|--------|-----|
| Long-running (>5 min) | **Standard** | Up to 1 year execution |
| Exactly-once semantics | **Standard** | Express is at-least-once |
| Human approval / wait for callback | **Standard** | `.waitForTaskToken` exclusive |
| Audit trail / execution history | **Standard** | 90-day history |
| High-volume event processing | **Express** | 100K/sec vs 2K/sec |
| Cost-sensitive + short duration | **Express** | Billed per execution/duration |
| Idempotent tasks | **Express** | Cheaper when duplicates are safe |

**Combine both:** Standard orchestrates Express for high-volume parallel steps.

### Pattern 2: Error Handling — Retry + Catch
```json
"Retry": [
  { "ErrorEquals": ["States.TaskFailed"], "IntervalSeconds": 2, "MaxAttempts": 3, "BackoffRate": 2, "JitterStrategy": "FULL" }
],
"Catch": [
  { "ErrorEquals": ["States.ALL"], "ResultPath": "$.error", "Next": "HandleError" }
]
```
- **Specific errors before `States.ALL`** (top-to-bottom evaluation)
- **`ResultPath: "$.error"`** preserves original input. WITHOUT it, entire input is replaced
- **`TimeoutSeconds`** on every Task state — AI forgets this consistently
- Combine: Retry for transient failures, Catch for permanent/exhausted

### Pattern 3: EventBridge Scheduler Over Cron Rules
| BAD | GOOD |
|-----|------|
| CloudWatch Events scheduled rules (legacy) | EventBridge Scheduler (retry limits, flexible windows, better) |

### Pattern 4: Direct SDK Integrations Over Lambda Glue
| BAD | GOOD |
|-----|------|
| Lambda function that calls DynamoDB PutItem | Direct `DynamoDB:PutItem` SDK integration in Step Functions |

14,000+ API actions across 220+ services. Eliminates "glue" Lambda functions for simple API calls. Use JSONata for data transforms.

---

## Level 2: Distributed Map & JSONata (Intermediate)

### Distributed Map
- Up to 10,000 parallel child workflow executions
- Supports S3 objects, Athena manifests, CSV/JSON/JSONL/Parquet
- **LOAD_AND_FLATTEN**: reads + parses S3 content within single Map state
- S3 Inventory >> `listObjectsV2` for large file counts
- **ItemBatcher**: aggressively batch items to reduce state transitions
- Child type: Express for <5min items, Standard for longer/exactly-once
- **ResultWriter**: export results to S3 (child workflows return compact summaries)
- Error handling: Retry in **child workflows** (not at Map level — Map retry reprocesses ALL items)
- `ToleratedFailurePercentage`: allow partial failures without failing entire run

### JSONata (Nov 2024)
- Advanced data manipulation directly in states — eliminates Lambda for transforms
- Replace complex `ResultSelector`/`ResultPath`/`OutputPath` chains with JSONata expressions
- Intrinsic functions: string formatting, JSON conversion, array manipulation, hash calculations
- **Reduce state transitions** by combining transform + logic steps

### Claim Check Pattern
Store large data in S3, pass ARN pointers between states. **256KB payload limit per state transition** — exceeding this silently truncates data.

---

## Level 3: Callbacks, EventBridge & Cost (Advanced)

### Callback Pattern (`.waitForTaskToken`)
- Single-use, short-lived tokens. Implement timeouts on the Task state
- Send via request body, not headers (>4KB header truncation risk)
- Use for: human approval, external system integration, async processing

### EventBridge Patterns

| Component | Use Case | Key Setting |
|-----------|----------|-------------|
| **Rules** | React to events, route to targets | Narrow JSON patterns, single target per rule |
| **Pipes** | Source → filter → enrich → target | DLQs for failed events |
| **Scheduler** | Cron/rate-based invocations | Flexible time windows, retry limits |

- Design events: small, immutable, self-contained (include all state for consumers)
- **Idempotency in consumers mandatory** — at-least-once delivery
- Schema Registry for event validation. Cross-account via resource policies

### Cost Optimization
- **Nest Express within Standard** for cost optimization of composite workflows
- Reduce state transitions: combine steps with JSONata/intrinsic functions
- **25,000 event history quota**: start new executions for long-running workflows
- Standard: $0.025/1000 transitions. Express: per request/duration/memory

---

## Performance: Make It Fast

### Optimization Checklist
1. **Express for high-throughput** — 100K/sec vs Standard's 2K/sec
2. **Direct SDK integrations** — skip Lambda for simple API calls
3. **JSONata transforms** — eliminate Lambda for data manipulation
4. **Distributed Map** — millions of items in parallel via child workflows
5. **Batch items aggressively** — ItemBatcher reduces state transitions
6. **Parallel states** — concurrent branches for independent tasks

### Throughput Limits
- Standard: 2,000 state transitions/sec (account level)
- Express: 100,000 state transitions/sec
- Distributed Map: 10,000 concurrent child executions (default)

---

## Observability: Know It's Working

### What to Monitor

| Signal | Tool | What to Watch |
|--------|------|--------------|
| Execution status | CloudWatch Metrics | `ExecutionsFailed`, `ExecutionsTimedOut` |
| Duration | `ExecutionTime` P99 | Drift from baseline = bottleneck |
| Distributed Map | `ApproximateOpenMapRunsCount` | Approaching backlog limit |
| EventBridge | `TriggeredRules`, `FailedInvocations` | Rules not firing, target failures |
| Cost | State transition count | More transitions = higher cost |

- **X-Ray tracing**: enable for end-to-end workflow visibility
- **CloudWatch Logs**: ERROR level for prod, ALL for dev. JSON structured
- Log execution input/output for debugging (but watch for PII)

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Lambda as Orchestrator
**You will be tempted to:** Write a Lambda that calls other Lambdas in sequence
**Why that fails:** You pay for idle wait time, lose retry/error handling, get no visual debugging, and hit 15-min timeout
**The right way:** Step Functions for any multi-step workflow. Lambda for compute, Step Functions for coordination

### Rule 2: No Missing TimeoutSeconds
**You will be tempted to:** Skip `TimeoutSeconds` on Task states because "Lambda has its own timeout"
**Why that fails:** External service calls, `.waitForTaskToken`, and SDK integrations can hang indefinitely. Standard workflows run up to 1 year — that's 1 year of waiting and billing
**The right way:** `TimeoutSeconds` on every Task state. Match to expected duration + buffer

### Rule 3: No Retry at Distributed Map Level
**You will be tempted to:** Add Retry on the Distributed Map state for error handling
**Why that fails:** Map-level retry reprocesses ALL items, including already-succeeded ones. Duplicate work, wasted cost, potential side effects
**The right way:** Retry inside child workflows. Use `ToleratedFailurePercentage` + Redrive for failed items only

### Rule 4: No Large Payloads Between States
**You will be tempted to:** Pass full API responses or data sets between states
**Why that fails:** 256KB limit per state transition. Exceeding it silently truncates data. Even below the limit, large payloads slow execution
**The right way:** Claim Check pattern — store in S3, pass ARN. Use `InputPath`/`OutputPath` to filter. `ResultSelector` to extract only needed fields

### Rule 5: No Polling Loops with Wait States
**You will be tempted to:** Use a Wait state + Lambda check + Choice state loop to poll for completion
**Why that fails:** Each loop iteration = state transitions you're paying for. Polling is wasteful when callbacks exist
**The right way:** `.waitForTaskToken` for external systems. `.sync` for AWS service integrations (waits for completion automatically)
