---
name: mx-aws-messaging
description: SQS Standard vs FIFO, visibility timeout, DLQ strategies, batch operations, SNS fan-out, EventBridge Pipes, MessageGroupId parallelism, high-throughput FIFO, exactly-once processing, and AI-generated anti-patterns
---

# AWS Messaging — SQS, SNS & EventBridge Pipes for AI Coding Agents

**Load this skill when configuring SQS queues, SNS topics, EventBridge Pipes, or designing async messaging architectures.**

## When to also load
- `mx-aws-orchestration` — EventBridge rules/scheduler, Step Functions integration
- `mx-aws-lambda` — Lambda triggers on SQS/SNS, batch processing
- `mx-aws-dynamodb` — DynamoDB Streams as Pipe source
- `mx-aws-streaming` — when deciding SQS vs Kinesis for event processing

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: Standard vs FIFO Decision
| Need | Choice | Why |
|------|--------|-----|
| Unlimited throughput, order doesn't matter | **Standard** | At-least-once, best-effort order |
| Strict ordering + exactly-once | **FIFO** | 300 TPS (3000 batched, 70K high-throughput) |
| Multiple consumers, fan-out | **SNS → SQS** | SNS distributes to multiple queues |

FIFO queue names must end in `.fifo`. SNS FIFO topics only subscribe to SQS FIFO queues.

### Pattern 2: Always Enable DLQ
| BAD | GOOD |
|-----|------|
| No DLQ (failed messages block queue forever) | DLQ with `maxReceiveCount: 3-5`, longer retention than source |

DLQ retention MUST be longer than source queue retention (otherwise messages expire before you investigate). Monitor DLQ depth — non-zero = processing failures.

### Pattern 3: Visibility Timeout = 6x Processing Time
| BAD | GOOD |
|-----|------|
| Default 30s visibility timeout for everything | `VisibilityTimeout: 6 * averageProcessingTime` |

For Lambda: visibility timeout >= 6x Lambda timeout + MaximumBatchingWindowInSeconds. Too short = duplicate processing. Too long = slow retry on failures.

### Pattern 4: Long Polling Over Short Polling
| BAD | GOOD |
|-----|------|
| Default short polling (immediate return, many empty responses) | `WaitTimeSeconds: 20` (long polling, fewer empty responses, lower cost) |

### Pattern 5: Batch Operations for Cost
| BAD | GOOD |
|-----|------|
| Individual `SendMessage` / `ReceiveMessage` calls | `SendMessageBatch` / `ReceiveMessageBatch` (up to 10 messages) |

1 batch request = 1 API call. 10 individual requests = 10 API calls. 10x cost difference.

---

## Level 2: FIFO Deep & EventBridge Pipes (Intermediate)

### SQS FIFO — MessageGroupId for Parallelism
- **MessageGroupId**: strict ordering WITHIN group, parallel processing ACROSS groups
- Use business identifiers: `customer_id`, `order_id`, `tenant_id`
- **Single MessageGroupId = serial processing (kills parallelism)**
- More unique MessageGroupIds = more parallelism

### FIFO Deduplication
| Method | How It Works | When to Use |
|--------|-------------|-------------|
| Content-based | SHA-256 hash of body | Messages with deterministic content |
| Explicit ID | `MessageDeduplicationId` per message | Messages with timestamps/random data in body |

5-minute deduplication window. Explicit ID takes precedence over content-based. **Don't include timestamps or random data in message body** when using content-based dedup.

### High-Throughput FIFO (70K TPS)
```
DeduplicationScope: messageGroup
FifoThroughputLimit: perMessageGroupId
```
Increases from 300 TPS to **70,000 TPS without batching**. Requires many unique MessageGroupIds for actual parallelism.

### EventBridge Pipes
Source → Filter → Enrich → Target pipeline. No glue code.
- Sources: SQS, DynamoDB Streams, Kinesis, MSK, self-managed Kafka
- Enrichment: Lambda, Step Functions, API Gateway, API destination
- DLQs for failed events — always enable
- Replaces Lambda "glue" functions for simple source-to-target patterns

### SNS Fan-Out
- SNS topic → multiple SQS queues (fan-out pattern)
- **Filter at SNS level** — reduces unnecessary delivery and downstream processing cost
- Message filtering: attribute-based matching before delivery
- FIFO topics only fan out to FIFO queues

---

## Level 3: DLQ Strategies & Advanced Patterns (Advanced)

### DLQ Redrive
- Move messages from DLQ back to source queue (or compatible destination)
- Configurable velocity — don't flood the source queue
- Investigate root cause BEFORE redriving (otherwise they'll fail again)

### Consumer Idempotency
- Standard SQS: at-least-once → consumers MUST be idempotent
- FIFO SQS: exactly-once within deduplication window → consumers SHOULD STILL be idempotent (partial failures, retries after window)
- Implement: idempotency key in DynamoDB with conditional writes

### Heartbeat for Long-Running Processing
For tasks exceeding visibility timeout: call `ChangeMessageVisibility` periodically (heartbeat) to extend the timeout. Prevents re-delivery during long processing.

---

## Performance: Make It Fast

### Optimization Checklist
1. **Batch API** — 10 messages per call, 10x fewer API calls
2. **Long polling** — `WaitTimeSeconds: 20`, reduces empty responses
3. **FIFO high-throughput mode** — 70K TPS with per-MessageGroupId dedup
4. **Multiple MessageGroupIds** — maximize FIFO parallelism
5. **SNS filtering** — filter before delivery, not after consumption
6. **EventBridge Pipes** — skip Lambda glue for simple transformations

### Lambda + SQS Tuning
- `BatchSize`: up to 10,000 records. Higher = fewer invocations
- `MaximumBatchingWindowInSeconds`: up to 300s. Accumulate before invoking
- Report partial batch failures with `ReportBatchItemFailures` (don't fail entire batch)

---

## Observability: Know It's Working

### What to Monitor

| Signal | Metric | Alert Threshold |
|--------|--------|-----------------|
| Queue depth | `ApproximateNumberOfMessagesVisible` | Growing = consumers can't keep up |
| DLQ depth | DLQ `ApproximateNumberOfMessagesVisible` | >0 = processing failures |
| Age | `ApproximateAgeOfOldestMessage` | >processing SLA = falling behind |
| Empty receives | `NumberOfEmptyReceives` | High = short polling waste |
| Throttling | FIFO `ThrottleCount` | >0 = hitting TPS limit |

- **DLQ alarm is the most critical** — non-zero DLQ = data loss risk
- **Message age** tells you if consumers are falling behind
- **CloudWatch Logs** on consumer Lambda for error investigation

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Queue Without DLQ
**You will be tempted to:** Skip DLQ setup because "messages won't fail"
**Why that fails:** Any failure (bad data, downstream outage, bug) causes messages to recycle indefinitely, blocking the queue
**The right way:** DLQ on every queue. `maxReceiveCount: 3-5`. Monitor DLQ depth. Alarm on >0

### Rule 2: No Single MessageGroupId on FIFO
**You will be tempted to:** Use a single MessageGroupId (like `"default"`) for simplicity
**Why that fails:** All messages process serially. 300 TPS max (or 70K but still serial). One slow message blocks everything behind it
**The right way:** Use business entity IDs as MessageGroupId (customer_id, order_id). Each group processes independently

### Rule 3: No Custom Deduplication Logic
**You will be tempted to:** Build application-level deduplication instead of using FIFO's built-in
**Why that fails:** Reinventing what SQS already does. Distributed dedup is hard — your implementation will have edge cases
**The right way:** Use FIFO with `MessageDeduplicationId` or content-based deduplication. Keep messages within the 5-min window deterministic

### Rule 4: No Standard SQS Without Idempotent Consumers
**You will be tempted to:** Process Standard SQS messages assuming exactly-once delivery
**Why that fails:** Standard SQS is at-least-once. You WILL get duplicates. Non-idempotent processing = duplicate charges, double emails, corrupted state
**The right way:** Idempotency key (DynamoDB conditional write, database upsert). Process duplicate = no-op

### Rule 5: No Short Polling in Production
**You will be tempted to:** Leave default short polling because "it works"
**Why that fails:** Short polling returns immediately even with empty queue. You pay for every empty response. High CPU churn on consumers polling empty queues
**The right way:** `WaitTimeSeconds: 20` (long polling). Consumer waits up to 20s for messages. Dramatic cost + CPU reduction
