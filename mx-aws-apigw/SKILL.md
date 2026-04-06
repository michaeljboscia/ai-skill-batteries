---
name: mx-aws-apigw
description: API Gateway REST vs HTTP API decision, WebSocket APIs, Lambda authorizers, JWT/Cognito auth, caching, throttling/usage plans, request validation, response streaming, Lambda Function URLs, and AI-generated anti-patterns
---

# AWS API Gateway — REST, HTTP & WebSocket APIs for AI Coding Agents

**Load this skill when building APIs with API Gateway, choosing between REST/HTTP/WebSocket, configuring authorizers, or optimizing API performance.**

## When to also load
- `mx-aws-lambda` — Lambda integration, Powertools, cold starts
- `mx-aws-cdn-lb` — CloudFront in front of API Gateway for edge caching + WAF
- `mx-aws-iam` — IAM authorizers, resource policies
- `mx-aws-orchestration` — Step Functions direct API Gateway integration

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: HTTP API by Default
| BAD | GOOD |
|-----|------|
| REST API for a simple Lambda proxy ($3.50/M requests) | HTTP API ($1/M requests, 70% cheaper, lower latency) |

HTTP API gained WAF support in 2025. Unless you need caching, usage plans, or request validation — start with HTTP API.

### Pattern 2: REST vs HTTP Decision Tree

| Need | Choice | Why |
|------|--------|-----|
| Lowest cost + latency | **HTTP API** | $1/M, 60% lower latency |
| API keys / usage plans / per-client throttle | **REST API** | Native Usage Plans |
| Request body validation (JSON schema) | **REST API** | Built-in validation, rejects with 400 |
| Caching at API layer | **REST API** | Built-in stage-level cache |
| GenAI response streaming | **REST API** | Response streaming (Nov 2025), 15min timeout, >10MB |
| Lowest possible latency, no extras | **Lambda Function URL** | Bypasses API GW entirely |

### Pattern 3: JWT Authorizer for HTTP API
| BAD | GOOD |
|-----|------|
| Lambda authorizer for simple JWT validation on HTTP API | Native JWT authorizer (zero Lambda cost, built-in OIDC/OAuth2) |

HTTP API has native JWT validation. Don't pay for a Lambda authorizer when JWT suffices.

### Pattern 4: CloudFront in Front of API Gateway
Place CloudFront in front of either API type for:
- Edge caching (especially for read-heavy APIs)
- WAF protection (HTTP API gained WAF in 2025, but CloudFront adds depth)
- Global acceleration (reduced latency from edge locations)

### Pattern 5: API Keys Are NOT Authentication
| BAD | GOOD |
|-----|------|
| API Keys for user authentication | API Keys only for throttling/metering (Usage Plans) |

API Keys identify callers for quota management. Use JWT, Cognito, IAM, or Lambda authorizers for actual authentication.

---

## Level 2: Authorizers & Caching (Intermediate)

### Authorizer Decision Tree

| Authorizer | API Type | Use Case |
|------------|----------|----------|
| **JWT** | HTTP API only | OIDC/OAuth2 tokens, no Lambda cost |
| **Cognito User Pool** | REST API | Cognito-integrated apps, access token scopes |
| **Lambda** | Both | Custom auth logic, legacy tokens, multi-source auth |
| **IAM (SigV4)** | Both | Service-to-service, AWS SDK callers |

- **Lambda authorizer**: returns IAM policy. Cache TTL configurable (trade-off: perf vs permission revocation delay)
- **Cognito**: use Access Tokens (not ID tokens) for authorization. Scopes + Groups for fine-grained control
- **IAM + resource policies**: combine for IP/VPC restrictions on service-to-service APIs

### REST API Caching
- Stage-level TTL, custom cache keys, encrypted at rest
- Enable only for **read-heavy endpoints** — caching write endpoints causes stale data
- HTTP API caching: use CloudFront in front (no built-in cache)
- Cache key: include only necessary query/header parameters — extra params = cache fragmentation

### Throttling

| API Type | Throttling Mechanism |
|----------|---------------------|
| **REST** | Usage Plans + API Keys (per-client quotas + rate limits) |
| **HTTP** | API-level or route-level only (no native per-client) |

REST Usage Plans: assign clients to tiers (free/basic/premium) with different rate limits and daily/monthly quotas.

---

## Level 3: WebSocket & Response Streaming (Advanced)

### WebSocket API Patterns
- **Connection tracking**: DynamoDB table with connection IDs + TTL for stale cleanup
- `$disconnect` handler may NOT fire on ungraceful disconnects — **TTL is your safety net**
- Handle **410 GoneException** on `PostToConnection` — remove stale IDs from DB
- **Idle timeout**: 10 minutes hard limit. Client-side heartbeats mandatory
- Route selection: `$request.body.action` pattern. Always define `$default` route
- Provisioned concurrency on critical route Lambda handlers

### Response Streaming (REST API, Nov 2025)
- Enables streaming responses from Lambda to clients
- Improves Time-To-First-Byte (TTFB) for GenAI and large payload use cases
- Extends timeout to 15 minutes (vs standard 29-second timeout)
- Supports payloads >10MB
- Critical for LLM integration patterns (streaming token-by-token)

### Lambda Function URLs
- Bypass API Gateway entirely for lowest latency
- No throttling, no validation, no caching — just Lambda
- Use for internal service-to-service, webhook receivers, or latency-critical paths
- IAM auth or no auth only (no JWT/Cognito)

---

## Performance: Make It Fast

### Optimization Checklist
1. **HTTP API over REST** when features allow — 60% lower latency
2. **CloudFront in front** — edge caching reduces origin calls
3. **REST caching** on read-heavy endpoints — reduces Lambda invocations
4. **Provisioned Concurrency** on critical Lambda handlers — zero cold starts
5. **GZIP/Brotli compression** — enable in CloudFront or API response
6. **Response streaming** for GenAI — TTFB improvement, 15min timeout
7. **Lambda Function URLs** for internal/latency-critical — skip API GW overhead

### Latency Reduction
- HTTP API < REST API < REST API with validation/transforms (each layer adds latency)
- Avoid unnecessary request/response transforms in REST — each adds processing time
- Minimize authorizer logic — cache authorization results aggressively
- Use `MessagePack` or `Protocol Buffers` over JSON for high-throughput APIs

---

## Observability: Know It's Working

### What to Monitor

| Signal | Metric | Alert Threshold |
|--------|--------|-----------------|
| Latency | `Latency` (P99) | >2s for synchronous APIs |
| Errors | `4XXError`, `5XXError` | 5XX > 1% of requests |
| Cache | `CacheHitCount` / `CacheMissCount` | Hit rate < 80% = review cache keys |
| Throttle | `Count` vs `ThrottleCount` | Any throttle = capacity issue |
| WebSocket | `ConnectCount`, `MessageCount` | Connection spikes, message drops |

- **X-Ray tracing**: enable for end-to-end visibility (API GW → Lambda → downstream)
- **Access logging**: enable on all stages. JSON format for Logs Insights analysis
- **CloudWatch dashboards**: Latency P50/P90/P99, error rates, cache hit ratio

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No REST API When HTTP API Suffices
**You will be tempted to:** Default to REST API because "it has more features"
**Why that fails:** 3.5x cost premium and higher latency. Most APIs need a Lambda proxy with JWT auth — HTTP API handles this perfectly
**The right way:** Start with HTTP API. Migrate to REST only when you need caching, usage plans, or request validation

### Rule 2: No API Keys for Authentication
**You will be tempted to:** Use API Keys as the primary authentication mechanism
**Why that fails:** API Keys are for identifying callers and enforcing quotas. They're transmitted in plaintext headers, easily shared, and not tied to identity. They are NOT a security mechanism
**The right way:** JWT, Cognito, IAM, or Lambda authorizers for authentication. API Keys only for throttling tiers

### Rule 3: No WebSocket Without Connection Cleanup
**You will be tempted to:** Trust $disconnect to clean up all connections
**Why that fails:** $disconnect doesn't fire on ungraceful disconnects (network drops, client crashes). Stale connection IDs accumulate. PostToConnection fails with 410 but you keep trying
**The right way:** DynamoDB with TTL for connection tracking. Handle 410 GoneException. Client-side heartbeats every 5 minutes

### Rule 4: No Unvalidated Input on REST APIs
**You will be tempted to:** Skip request validation because "Lambda validates anyway"
**Why that fails:** Every invalid request invokes Lambda (you pay for it). REST API validation rejects with 400 BEFORE Lambda runs — free validation
**The right way:** JSON schema request validation on REST API. Validate required parameters, body structure, and data types at the gateway

### Rule 5: No Caching on Write Endpoints
**You will be tempted to:** Enable stage-level caching without considering endpoint types
**Why that fails:** Cached POST/PUT/DELETE responses return stale data. Users think their writes succeeded but see old data
**The right way:** Cache only GET endpoints. Use method-level cache settings, not stage-level blanket caching
