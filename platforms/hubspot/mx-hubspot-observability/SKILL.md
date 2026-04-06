---
name: mx-hubspot-observability
description: "HubSpot API observability, any HubSpot API work — API call logging, error tracking, webhook HMAC verification, sync health monitoring, rate limit header monitoring, retry patterns, error response format, correlationId"
---

# HubSpot Observability — Logging, Errors, Sync Health for AI Coding Agents

**This skill co-loads with mx-hubspot-core for ANY HubSpot API work.**

## When to also load
- `mx-hubspot-core` — SDK setup, error codes (co-default)
- `mx-hubspot-perf` — rate limit management (co-default)
- `mx-hubspot-automation` — webhook HMAC verification

---

## Level 1: Error Handling (Beginner)

### Pattern 1: Error Response Format

All errors return JSON with `message`, `correlationId`, `category`, `errors[]`. The `errors[].context` field shows specifics (missing properties, malformed values). **Always log correlationId** — HubSpot support requires it.

### Pattern 2: Error Code Reference

| Code | Retry? | Action |
|------|--------|--------|
| 400 | No | Fix payload (check errors.context) |
| 401 | No | Token expired/invalid |
| 403 | No | Missing OAuth scopes |
| 404 | No | Wrong endpoint or record ID |
| 409 | No | Duplicate (search first) |
| 429 | Yes | Honor Retry-After header |
| 5xx | Yes | Auto-retry via SDK |

HubSpot expects error rate below 5% of daily volume.

### Pattern 3: Structured Error Logging

Log every error with: timestamp, operation name, correlationId, category, message, context details, status code, truncated payload (first 500 chars).

---

## Level 2: Rate Limit Monitoring (Intermediate)

### Pattern 4: Response Headers to Monitor

| Header | Meaning |
|--------|---------|
| `X-HubSpot-RateLimit-Daily-Remaining` | Calls left today |
| `X-HubSpot-RateLimit-Remaining` | Calls in current burst window |
| `X-HubSpot-RateLimit-Interval-Milliseconds` | Burst window duration |
| `X-HubSpot-RateLimit-Max` | Max per window |

Search API has NO rate-limit headers. Deprecated: `X-HubSpot-RateLimit-Secondly`.

### Pattern 5: 429 Recovery

SDK handles via `numberOfApiCallRetries`. For custom HTTP: respect `Retry-After` header, exponential backoff (200ms * retryNumber for 5xx, 10s for 429 TEN_SECONDLY_ROLLING).

---

## Level 3: Sync Health and Security (Advanced)

### Pattern 6: Sync Health Monitoring

1. Log every API result (success/failure/retry)
2. Track sync delta: source records vs HubSpot records
3. Monitor for drift (records that should exist but don't)
4. Event-driven sync with message queue (SQS/Pub/Sub) for resilience
5. HubSpot built-in Sync Health: syncing/excluded/failing counters

### Pattern 7: Webhook HMAC Verification

Verify X-HubSpot-Signature-v3 using HMAC SHA-256 of (method + uri + body + timestamp) with client secret. Base64 encode. Use crypto.timingSafeEqual for constant-time comparison. Reject timestamps older than 5 minutes. See mx-hubspot-automation Pattern 7 for full code.

### Pattern 8: External Logging Requirements

HubSpot built-in logs are limited: 7-day retention, Super Admin only, exempt requests NOT logged. You MUST implement external logging for: request/response pairs, correlationIds, rate limit header values, sync reconciliation.

---

## Performance: Make It Fast

Lightweight logging: detail on errors, summary on successes. Async error processing via queue.

## Observability: Know It's Working

Key health indicators:
- **Error rate**: below 5% of daily volume
- **429 frequency**: sustained 429s need better throttling
- **Sync delta**: source vs HubSpot record count difference
- **Webhook delivery**: percentage successfully processed
- **Detection speed**: how quickly sync failures are spotted

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never skip correlationId logging
**You will be tempted to:** Log just the message.
**Why that fails:** HubSpot support cannot help without it.
**The right way:** Extract and log correlationId from every error.

### Rule 2: Never skip webhook HMAC verification
**You will be tempted to:** Accept all POSTs to save time.
**Why that fails:** Fake events can corrupt your CRM data.
**The right way:** Verify every signature. Reject invalid/stale requests.

### Rule 3: Never rely solely on HubSpot built-in logs
**You will be tempted to:** Assume HubSpot logs everything.
**Why that fails:** 7-day retention, exempt requests not logged, no alerting.
**The right way:** External structured logging with retention and alerting.

### Rule 4: Never ignore sync drift
**You will be tempted to:** Assume no errors means everything synced.
**Why that fails:** Silent failures (409s, rate drops) cause records to drift.
**The right way:** Periodically reconcile counts. Alert on divergence.
