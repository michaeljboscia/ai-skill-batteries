---
name: mx-aws-dynamodb
description: DynamoDB table design, partition key selection, single-table patterns, GSI projections, DAX caching, DynamoDB Streams/CDC, Global Tables, TTL, on-demand vs provisioned capacity, Contributor Insights, and AI-generated anti-patterns
---

# AWS DynamoDB — NoSQL Database for AI Coding Agents

**Load this skill when designing DynamoDB tables, choosing partition keys, configuring GSIs, setting up Streams/CDC, or optimizing DynamoDB costs.**

## When to also load
- `mx-aws-database` — when deciding DynamoDB vs Aurora/RDS
- `mx-aws-lambda` — Lambda triggers on DynamoDB Streams
- `mx-aws-orchestration` — Step Functions direct DynamoDB integration
- `mx-aws-networking` — VPC Gateway Endpoints for DynamoDB (free)

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: Access-Pattern-Driven Key Design
| BAD | GOOD |
|-----|------|
| Design schema first, figure out queries later | List all access patterns first, then design keys to serve them |

DynamoDB is not relational. You cannot add indexes after the fact without cost/complexity. **Design for your queries, not your data model.**

### Pattern 2: High-Cardinality Partition Keys
| BAD | GOOD |
|-----|------|
| `PK: status` (3 values: active/inactive/deleted) | `PK: userId` or `PK: orderId` (millions of unique values) |

Hot partition threshold: >3,000 RCU or >1,000 WCU per partition = throttling. Low-cardinality keys = guaranteed hot partitions.

### Pattern 3: Query Over Scan — Always
| BAD | GOOD |
|-----|------|
| `Scan` with `FilterExpression` (reads entire table) | `Query` on PK + SK (reads only matching items) |

Scan consumes capacity proportional to **table size**, not result size. A scan on a 100GB table costs the same whether it returns 1 item or 1 million.

### Pattern 4: Eventually Consistent Reads by Default
| BAD | GOOD |
|-----|------|
| `ConsistentRead: true` for all reads (2x RCU cost) | Eventually consistent reads (default, half the cost) |

Strongly consistent reads cost **double**. Only use when your application genuinely requires read-after-write consistency.

### Pattern 5: TTL for Automatic Data Expiry
Enable TTL on a timestamp attribute. DynamoDB automatically deletes expired items at no cost. Use for session data, logs, temporary records. Implement tiered TTL based on data importance.

---

## Level 2: GSIs, DAX & Capacity (Intermediate)

### GSI Design

| Projection | Storage | Cost | Use Case |
|------------|---------|------|----------|
| `KEYS_ONLY` | Smallest | Cheapest | When you only need to check existence |
| `INCLUDE` | Medium | Medium | Specific attributes for a query pattern |
| `ALL` | Largest | Most expensive | Full flexibility, highest cost |

- **Lean projections reduce storage + throughput costs.** Design GSIs for specific access patterns
- GSIs have independent throughput — a hot GSI throttles independently of the base table
- Remove unused indexes regularly. Each GSI adds write amplification

### DAX (DynamoDB Accelerator)

| DAX Ideal For | DAX NOT Ideal For |
|---------------|-------------------|
| Read-heavy workloads | Write-heavy workloads |
| Hot key mitigation | Strongly consistent reads (DAX = eventually consistent) |
| Microsecond latency requirements | Large item sizes |

- Start with 3 nodes (multi-AZ). T-type for dev, R-type for production
- Item cache + query cache. Configure TTL per table/operation

### Capacity Modes

| Mode | When to Use | Cost Model |
|------|-------------|------------|
| **On-Demand** | New tables, unpredictable traffic | Pay per request, no planning |
| **Provisioned + Auto Scaling** | Stable, predictable traffic | Target utilization 50-70%, cheaper |

Start with On-Demand for new tables. Switch to Provisioned after analyzing metrics (14+ days). Reserved Capacity: up to 75% savings for 1-3yr commitment on Provisioned.

---

## Level 3: Streams, Global Tables & Single-Table Design (Advanced)

### DynamoDB Streams + CDC
- Stream records: KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES
- Lambda trigger: process changes in near-real-time. Configure error handling (DLQ, bisect-on-error)
- EventBridge Pipes: filter + transform stream events without Lambda glue code
- Use for: event sourcing, cross-service sync, audit trails, materialized views

### Global Tables
- Multi-region, multi-active replication. Sub-second replication lag
- Conflict resolution: last-writer-wins (by timestamp)
- Enable on new tables before writing data (easier than retrofitting)
- All replicas accept reads AND writes — no primary/secondary distinction

### Single-Table Design: When It Works

| Works When | Fails When |
|------------|-----------|
| Access patterns known and stable | Access patterns evolving rapidly (pre-PMF) |
| Team deeply understands DynamoDB | Team is new to DynamoDB |
| Documentation is robust | High team churn (tribal knowledge) |
| Low team churn | Heavy reporting/analytics needs |

### Single-Table Anti-Patterns
1. **"God Partition Key"**: everything under one key (e.g., `tenantId`) = hot partition even when table metrics look healthy
2. **Item Type Explosion**: starting with 3 types, ending with 30. Debugging = tribal knowledge
3. **Sort Key Gymnastics**: `USER#PROFILE#2024#ACTIVE` — encoding business logic in keys = brittle, unmaintainable, silent bugs on refactor
4. **Over-optimizing for cost too early**: compressing item shapes to save RCUs costs more in developer time and outage risk
5. **Reactive "just add a GSI"**: GSIs added without planning = write amplification + hot GSI partitions

---

## Performance: Make It Fast

### Optimization Checklist
1. **Query, never Scan** — Scan reads the entire table
2. **Batch operations** — `BatchGetItem`/`BatchWriteItem` reduce request count
3. **DAX for read-heavy** — microsecond reads, hot key mitigation
4. **Sparse GSIs** — project only needed attributes, lean = fast + cheap
5. **Write sharding** — random/deterministic suffix on PK for hot partitions
6. **Parallel Scan** — if Scan is unavoidable, use `Segment` + `TotalSegments`
7. **VPC Gateway Endpoint** — free, eliminates NAT Gateway latency for DynamoDB calls

### Item Size Optimization
- Store only necessary attributes. Use appropriate data types
- Large binary data → S3 with DynamoDB holding the S3 key (not the data)
- Compress large attributes before storing

---

## Observability: Know It's Working

### What to Monitor

| Signal | Metric | Alert Threshold |
|--------|--------|-----------------|
| Throttling | `ThrottledRequests` | Any > 0 sustained = investigate |
| Hot keys | **Contributor Insights** | Top-N partition keys by traffic |
| Capacity | `ConsumedReadCapacityUnits`, `ConsumedWriteCapacityUnits` | >80% of provisioned |
| On-demand limits | `ReadMaxOnDemandThroughputThrottleEvents` | Any > 0 |
| System errors | `SystemErrors` | Any > 0 = AWS-side issue |
| Streams lag | Lambda `IteratorAge` on stream trigger | >1min = consumer falling behind |

- **Contributor Insights**: enable on all production tables + GSIs. Identifies hot keys
- **Throttled Keys Mode (Aug 2025)**: new CI mode that monitors ONLY throttled keys — cheaper + more targeted
- **Granular throttle exceptions (Aug 2025)**: more precise error classification
- **Exponential backoff with jitter**: golden rule for retry. Built into AWS SDKs. Don't implement custom retry without jitter

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Scan in Application Code
**You will be tempted to:** Use `Scan` with `FilterExpression` because it feels like a SQL `WHERE` clause
**Why that fails:** FilterExpression is applied AFTER the scan reads data. A scan on 100GB still reads 100GB even if it returns 1 item. You pay for the full read
**The right way:** Design your table/GSI so every access pattern can be served by `Query` or `GetItem`

### Rule 2: No Sequential or Low-Cardinality Partition Keys
**You will be tempted to:** Use `date`, `status`, or auto-incrementing IDs as partition keys
**Why that fails:** All traffic concentrates on a few partitions. Throttling occurs even with excess total capacity
**The right way:** Use business identifiers (userId, orderId) with high cardinality. Write-sharding for known hot keys

### Rule 3: No Strongly Consistent Reads by Default
**You will be tempted to:** Set `ConsistentRead: true` everywhere "for safety"
**Why that fails:** 2x RCU cost. Most applications tolerate eventual consistency (typically <1 second)
**The right way:** Eventually consistent by default. Strongly consistent only for read-after-write scenarios that genuinely require it

### Rule 4: No Single-Table Without Documentation
**You will be tempted to:** Build a single-table design because "Alex DeBrie said so"
**Why that fails:** Without documentation of every access pattern + key schema, the next engineer (or you in 6 months) can't understand the table. Item type explosion + sort key gymnastics make it worse
**The right way:** If you choose single-table, document EVERY access pattern, key schema, and GSI purpose. If your team is new to DynamoDB, use multiple tables

### Rule 5: No On-Demand Forever
**You will be tempted to:** Leave tables on On-Demand permanently because "it's simpler"
**Why that fails:** On-Demand is 6.5x more expensive per RCU/WCU than Provisioned. For stable workloads, you're paying a huge premium for convenience
**The right way:** Start On-Demand. After 14+ days, analyze traffic patterns. Switch to Provisioned + Auto Scaling for stable tables. Reserved Capacity for committed workloads
