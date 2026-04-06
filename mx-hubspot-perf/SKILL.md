---
name: mx-hubspot-perf
description: "HubSpot API performance optimization, any HubSpot API work — rate limiting strategy, batch operations, caching pipelines owners properties, pagination optimization, search API limits, API call budgeting, webhook vs polling"
---

# HubSpot Performance — Rate Limits, Batch, Caching for AI Coding Agents

**This skill co-loads with mx-hubspot-core for ANY HubSpot API work.**

## When to also load
- `mx-hubspot-core` — SDK setup, Bottleneck configuration (co-default)
- `mx-hubspot-observability` — rate limit header monitoring (co-default)

---

## Level 1: Rate Limit Architecture (Beginner)

### Pattern 1: Know Your Limits

| Plan | Burst Limit | Daily Limit |
|------|------------|-------------|
| Free/Starter | 100 req/10sec | 250,000/day |
| Professional | 190 req/10sec | 625,000/day |
| Enterprise | 190 req/10sec | 1,000,000/day |

OAuth apps: 110 req/10sec per app per account. Search API: 5 req/sec (independent, NO rate-limit headers).

### Pattern 2: SDK Throttling via Bottleneck

Configure in `limiterOptions`: `minTime` (ms between requests), `maxConcurrent` (parallel cap). Treat HubSpot as a shared token bucket across parallel processes.

---

## Level 2: Batch and Caching (Intermediate)

### Pattern 3: Batch Everything

| Operation | Individual | Batch | Savings |
|-----------|-----------|-------|---------|
| Create 100 contacts | 100 calls | 1 call | 99% |
| Read 100 deals | 100 calls | 1 call | 99% |
| Associate 500 records | 500 calls | 1 call | 99.8% |

Each batch = 1 rate limit hit. Case studies show 98% request reduction.

### Pattern 4: Cache Static Metadata

| Data | Cache Duration | Why |
|------|---------------|-----|
| Owners list | 4-12 hours | Read-only, changes via HR |
| Pipeline/stage IDs | 4-12 hours | Admin changes rare |
| Property definitions | 4-12 hours | Schema changes infrequent |
| Association type IDs | 24+ hours | Almost never change |

Refresh on schedule or webhook, NOT per transaction.

### Pattern 5: Webhooks Over Polling

Webhooks: 0 API calls, near real-time. Polling: 1,440 calls/day per query, up to 60s delay. Subscribe to specific propertyChange events. Polling OK as backup or behind NAT.

---

## Level 3: Search Optimization (Advanced)

### Pattern 6: Search Efficiency

- Explicit property selection (fewer bytes, faster)
- Object-specific CRUD endpoints beat Search for direct reads
- `IN` operator for multi-value lookups vs multiple searches
- Segment queries under 10,000 cap (see core Pattern 7)
- Consider GraphQL for complex multi-object queries

### Pattern 7: Parallel Process Coordination

1. Centralize rate limiting (shared Redis counter or distributed Bottleneck)
2. Pause lower-priority jobs during peak loads
3. Priority-queue user-facing requests
4. Monitor remaining burst quota per response

---

## Performance: Make It Fast

Key metrics: calls per operation (batch), bytes per call (property selection), latency per call (endpoint choice).

## Observability: Know It's Working

### API Budget Dashboard
Track daily consumption vs limit. Alert at 80%.

### Batch Efficiency Ratio
Target: >50 records per API call for batch operations.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never use individual calls in loops
**You will be tempted to:** Write a for-loop with individual PATCH calls.
**Why that fails:** 100 records = 100 calls = instant rate limiting.
**The right way:** Batch. Always. Chunk into groups of 100.

### Rule 2: Never poll when webhooks are available
**You will be tempted to:** Cron job searching for changes every minute.
**Why that fails:** 1,440 wasted calls/day. Webhooks are free and faster.
**The right way:** Subscribe to webhook events. Poll only as backup.

### Rule 3: Never fetch metadata per transaction
**You will be tempted to:** Call Pipelines API before every deal creation.
**Why that fails:** 1,000 deals = 1,000 unnecessary lookups.
**The right way:** Cache on startup, refresh every few hours.

### Rule 4: Never request all properties
**You will be tempted to:** Omit the properties param.
**Why that fails:** Default returns minimal (not all). Even if all, wastes bandwidth.
**The right way:** Explicitly list only needed properties.
