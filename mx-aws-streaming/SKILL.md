---
name: mx-aws-streaming
description: Kinesis Data Streams on-demand vs provisioned, Enhanced Fan-Out vs polling, Managed Flink, Kinesis Firehose dynamic partitioning, MSK Serverless vs Provisioned, Lambda stream integration, consumer patterns, and AI-generated anti-patterns
---

# AWS Streaming — Kinesis & MSK for AI Coding Agents

**Load this skill when building real-time data pipelines with Kinesis Data Streams, Firehose, Managed Flink, or MSK (Kafka).**

## When to also load
- `mx-aws-lambda` — Lambda triggers on Kinesis, batch processing, error handling
- `mx-aws-analytics` — Kinesis → S3 → Athena/Redshift for analytics
- `mx-aws-messaging` — when deciding SQS vs Kinesis for event processing
- `mx-aws-observability` — CloudWatch metrics, CloudTrail data plane logging

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: Kinesis vs MSK Decision
| Need | Choice | Why |
|------|--------|-----|
| AWS-native, simpler ops | **Kinesis** | Managed shards/on-demand, native AWS integrations |
| Kafka ecosystem, existing expertise | **MSK** | Kafka API compatibility, Connect ecosystem |
| Zero-admin delivery to S3/Redshift | **Firehose** | Buffer + batch + deliver, no consumer code |

### Pattern 2: On-Demand Mode for New Streams
| BAD | GOOD |
|-----|------|
| Guessing shard count for new streams | On-demand mode (auto-scales, no shard management) |

Switch to Provisioned after analyzing traffic patterns for cost optimization.

### Pattern 3: Enhanced Fan-Out for Multiple Consumers
| Consumer Count | Mode | Why |
|---------------|------|-----|
| 1 consumer | **Standard polling** | Shared 2MB/s, cheaper |
| 2+ consumers | **Enhanced Fan-Out** | Dedicated 2MB/s per consumer, ~70ms latency |

Standard polling: shared 2MB/s per shard, 200ms+ latency. EFO: push-based HTTP/2, dedicated throughput per consumer. Up to 20 EFO consumers (5 default).

### Pattern 4: Firehose Buffer Tuning
| BAD | GOOD |
|-----|------|
| Default buffer (1MB, 60s) for all workloads | Buffer 5-128MB + 60-900s based on downstream needs |

Too small = cost explosion from many small S3 files. Dynamic partitioning routes records to different S3 prefixes without Lambda.

### Pattern 5: Lambda Error Handling on Streams
- `ReportBatchItemFailures` — fail specific records, not entire batch
- `BisectBatchOnError` — split batch to isolate poison messages
- On-failure destination (SQS/SNS) for failed records
- `MaximumRetryAttempts` + `MaximumRecordAgeInSeconds` to prevent infinite retry

---

## Level 2: Managed Flink & Lambda Deep (Intermediate)

### Managed Flink (formerly KDA)
- SQL/Java/Scala on Kinesis or MSK. Complex event processing, windowing, ML inference
- Exactly-once semantics with checkpointing
- New Flink connectors: EFO support, native watermark integration, standardized source metrics
- Use for: complex transformations, multi-source joins, time-windowed aggregations

### Lambda + Kinesis Tuning

| Setting | Range | Guidance |
|---------|-------|----------|
| `BatchSize` | 1-10,000 | Higher = fewer invocations, higher per-invoke cost |
| `MaximumBatchingWindowInSeconds` | 0-300 | Accumulate before invoking. Balance latency vs efficiency |
| `ParallelizationFactor` | 1-10 | Concurrent invocations per shard. Reduces `IteratorAge` |
| Consumer type | Standard or EFO | EFO for lower latency + dedicated throughput |

### MSK Serverless vs Provisioned

| Aspect | Serverless | Provisioned |
|--------|-----------|-------------|
| Management | Zero broker management | Full control over instance types |
| Scaling | Auto-scales | Manual broker/partition sizing |
| Cost | Pay-per-use | Pay per broker-hour |
| Use case | Variable/unpredictable | Predictable high-throughput |
| Latency | Higher | Lower (tunable) |

MSK Producer tuning: `batch.size` + `linger.ms` for throughput. `compression.type: lz4/snappy`. Replication factor 3 (default), `min.insync.replicas: 2`.

---

## Level 3: Advanced Consumer Patterns (Advanced)

### Kinesis Data Plane Logging (May 2024)
CloudTrail now captures `GetRecords`, `PutRecord`, `PutRecords`, `SubscribeToShard`. First-time auditability of data plane operations.

### Consumer Scaling
- More shards = more parallelism (each shard is independent processing unit)
- Lambda auto-scales to match shard count. ParallelizationFactor multiplies concurrency
- Flink: KPU (Kinesis Processing Unit) scaling. Monitor `MillisBehindLatest`

### MSK Connect
- Managed Kafka Connect for source/sink connectors
- Auto-scales. Pre-built connectors for S3, DynamoDB, Elasticsearch, etc.
- Use for CDC (Change Data Capture) pipelines without custom consumer code

---

## Performance: Make It Fast

### Optimization Checklist
1. **EFO for multi-consumer** — dedicated 2MB/s per consumer
2. **ParallelizationFactor** on Lambda — 10x concurrency per shard
3. **On-demand mode** — auto-scales without shard management
4. **Batch aggressively** — Lambda BatchSize up to 10K
5. **Firehose buffer right-sizing** — larger buffers = fewer, bigger files
6. **MSK compression** — lz4/snappy for producer throughput

### Key Latency Numbers
- Standard polling: 200ms (1000ms with multiple consumers)
- Enhanced Fan-Out: ~70ms
- Firehose: buffer interval (60-900s) — not real-time
- Lambda integration: adds batch window + cold start overhead

---

## Observability: Know It's Working

### What to Monitor

| Signal | Metric | Alert Threshold |
|--------|--------|-----------------|
| Consumer lag | `GetRecords.IteratorAgeMilliseconds` | >1min = falling behind |
| Flink lag | `MillisBehindLatest` | >1hr = investigate |
| Write throttle | `WriteProvisionedThroughputExceeded` | >0 = producer throttled |
| Read throttle | `ReadProvisionedThroughputExceeded` | >0 = consumer contention |
| MSK lag | `ConsumerLag`, `UnderReplicatedPartitions` | Lag growing, under-replicated > 0 |

- **Enhanced monitoring** (shard-level, 1-min granularity): enable for production. Extra cost but pinpoints failing consumers/hot shards
- **`IteratorAgeMilliseconds`** is your single most important metric — it tells you how far behind consumers are

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Standard Polling with Multiple Consumers
**You will be tempted to:** Use standard polling for all consumers to save cost
**Why that fails:** All consumers share 2MB/s per shard. With 3 consumers, each effectively gets 0.67MB/s. Latency degrades to 1000ms+. IteratorAge climbs
**The right way:** Enhanced Fan-Out for 2+ consumers. Each gets dedicated 2MB/s

### Rule 2: No Over-Provisioned Shards
**You will be tempted to:** Set a high shard count "just in case"
**Why that fails:** Shards cost $0.015/hr each. 100 unnecessary shards = $1,080/month wasted
**The right way:** On-demand mode for unpredictable traffic. Provisioned with auto-scaling for predictable. Monitor `IncomingBytes/Records` vs capacity

### Rule 3: No Lambda Without Error Handling on Streams
**You will be tempted to:** Skip `BisectBatchOnError` and `MaximumRetryAttempts` because "messages won't fail"
**Why that fails:** One poison message blocks the entire shard. Lambda retries forever. IteratorAge climbs. All records behind the poison message are stuck
**The right way:** `BisectBatchOnError: true`, `MaximumRetryAttempts: 3`, on-failure destination (SQS DLQ), `ReportBatchItemFailures`

### Rule 4: No Small Firehose Buffers
**You will be tempted to:** Set 1MB/60s buffer for "real-time" delivery to S3
**Why that fails:** Thousands of tiny files in S3. Athena queries become expensive (per-file overhead). Downstream processing slows. S3 request costs increase
**The right way:** Buffer 5-128MB. Use dynamic partitioning for routing. If you need real-time, use Kinesis Data Streams directly, not Firehose

### Rule 5: No MSK Serverless for Ultra-Low-Latency
**You will be tempted to:** Use MSK Serverless because it's simpler to manage
**Why that fails:** Serverless adds management overhead latency. For ultra-low-latency or high-throughput workloads, Provisioned with tuned brokers is significantly faster
**The right way:** Serverless for variable/unpredictable workloads. Provisioned for latency-sensitive + high-throughput production
