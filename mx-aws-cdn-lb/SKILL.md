---
name: mx-aws-cdn-lb
description: CloudFront cache policies, Origin Shield, versioned URLs, Lambda@Edge vs CloudFront Functions, ALB vs NLB vs GWLB decision, WAF managed rules/rate limiting/bot control, Shield Advanced, ACM certificate management, and AI-generated anti-patterns
---

# AWS CDN & Load Balancing — CloudFront, ALB, WAF for AI Coding Agents

**Load this skill when configuring CloudFront distributions, choosing load balancers, setting up WAF rules, or optimizing content delivery.**

## When to also load
- `mx-aws-apigw` — CloudFront in front of API Gateway
- `mx-aws-storage` ��� S3 origins, versioned static assets
- `mx-aws-networking` — VPC, security groups for ALB/NLB
- `mx-aws-dns` — Route 53 with CloudFront, health checks for LB failover

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: Versioned URLs Over Invalidation
| BAD | GOOD |
|-----|------|
| `Cache-Control: max-age=300` + frequent invalidation | `main.a3f2b1c9.js` + `Cache-Control: max-age=31536000,immutable` |

Content-hash filenames = year-long TTL, zero invalidation. Invalidation costs money (1000 free paths/month), takes 2-15 min, and is unreliable. Use as escape hatch only.

### Pattern 2: Load Balancer Decision Tree
| Need | Choice | Why |
|------|--------|-----|
| HTTP/HTTPS routing (L7) | **ALB** | Path/host-based routing, WebSocket, gRPC |
| TCP/UDP (L4), extreme throughput | **NLB** | Static IPs, millions of requests/sec |
| Inline security appliances | **GWLB** | Transparent network gateway for firewalls |

### Pattern 3: Enable Compression
| BAD | GOOD |
|-----|------|
| Uncompressed responses from CloudFront | Enable Gzip + Brotli in cache policy |

### Pattern 4: ACM for Free SSL
- DNS validation (standard for automation). Auto-renewal with new keys
- Must be in **us-east-1** for CloudFront distributions
- EventBridge alerts 45/30 days before expiry
- **Never pin certificates** — ACM auto-renews with new keys, pinning breaks renewal

### Pattern 5: WAF on All Internet-Facing Resources
Start with Common Rule Set (OWASP Top 10). Add rate limiting. Add bot control. This takes 15 minutes and blocks 90% of automated attacks.

---

## Level 2: CloudFront & WAF Deep (Intermediate)

### CloudFront Cache Configuration

| Component | Purpose | Key Setting |
|-----------|---------|-------------|
| **Cache policy** | Controls cache key + TTLs | `CachingOptimized` for static, `CachingDisabled` for dynamic |
| **Origin request policy** | What to forward to origin | Only necessary headers/cookies/params |
| **Origin Shield** | Extra caching layer before origin | Enable for high-traffic, live streaming, geo-distributed |

- Customize cache keys judiciously — unnecessary items = cache fragmentation = low hit ratio
- Origin Shield adds 10-50ms latency but consolidates origin requests (especially for multi-region)

### CloudFront Functions vs Lambda@Edge
| Criterion | CloudFront Functions | Lambda@Edge |
|-----------|---------------------|-------------|
| Latency | <1ms (runs at POP) | 30-50ms more (regional edge) |
| Cost | **1/6th** the cost | 6x more expensive |
| Triggers | Viewer request/response only | All 4 (viewer + origin request/response) |
| Network calls | No | Yes |
| Runtime | JavaScript only | Node.js, Python |
| Use case | URL rewrites, headers, basic auth | Complex auth, image resize, API calls |

**Start with CloudFront Functions. Migrate to Lambda@Edge only when you hit limits.**

### WAF Configuration

| Layer | Rule | Priority |
|-------|------|----------|
| 1 | **Rate-based rules** (place EARLY — block before expensive rules) | High |
| 2 | **Managed Rule Groups** (Common Rule Set, Known Bad IPs) | Medium |
| 3 | **Bot Control** (Count mode first, then Block) | Medium |
| 4 | **Custom rules** (virtual patching, app-specific) | Low |
| 5 | **Geo-blocking** (high-risk regions + IP exceptions for partners) | Low |

- Start ALL new rules in **Count mode**. Review logs. Then switch to Block
- Rate limiting: 5-min sliding window. Composite keys (up to 5 params) for per-user/per-IP
- Managed rules auto-update. Scope-down statements for fine-tuning
- **Shield Advanced**: auto L7 DDoS mitigation (ML-based, seconds). Protection groups

---

## Level 3: Advanced Patterns (Advanced)

### Multi-Layer Security
CloudFront WAF + API Gateway throttling + Lambda validation = defense-in-depth. WAF alone is bypassable.

### Cache Key Design
- Include only what varies the response: necessary query strings, Accept-Language, device type
- Exclude: timestamps, request IDs, session tokens (each creates unique cache key = 0% hit rate)
- Monitor `CacheHitCount` / `CacheMissCount` — target >80% hit rate

### Origin Shield for Live Streaming
Single cache point before origin. Collapses duplicate requests from multiple edge locations. Essential for live events with global audience.

---

## Performance: Make It Fast

### Optimization Checklist
1. **Versioned URLs** — year-long TTL, zero invalidation
2. **Gzip + Brotli compression** — enabled in cache policy
3. **Origin Shield** — reduces origin load for high-traffic
4. **CloudFront Functions** — <1ms for URL rewrites/headers (1/6 cost of Lambda@Edge)
5. **Cache key minimization** — only include what varies the response
6. **Rate-based rules early** — block before expensive WAF rules process

### ALB/NLB Performance
- ALB: enable HTTP/2 for multiplexed connections. Cross-zone load balancing (enabled by default)
- NLB: static IPs, consistent hashing. Use for TCP/UDP or when you need fixed IPs
- Connection draining: configure deregistration delay for graceful shutdown

---

## Observability: Know It's Working

### What to Monitor

| Signal | Metric | Alert Threshold |
|--------|--------|-----------------|
| Cache ratio | `CacheHitRate` | <80% = review cache keys |
| Errors | `5xxErrorRate`, `4xxErrorRate` | 5xx > 1% |
| Origin latency | `OriginLatency` P99 | >2s = origin struggling |
| WAF | `BlockedRequests` | Sudden spike = attack or false positive |
| Bot control | WAF labels for bot type | Unusual bot traffic patterns |
| ALB | `TargetResponseTime` P99 | >1s for web apps |

- **CloudFront real-time logs** → Kinesis for low-latency analysis
- **WAF logs**: enable for all web ACLs. Review blocked requests for false positives
- **ALB access logs** to S3 for forensic analysis

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Cache Invalidation as Primary Strategy
**You will be tempted to:** Set short TTLs and invalidate frequently
**Why that fails:** Invalidation takes 2-15 minutes, costs money after 1000 paths/month, and doesn't guarantee all edge locations clear simultaneously
**The right way:** Versioned URLs (content-hash filenames). Change URL = instant new content. Old URLs stay cached (no wasted bandwidth)

### Rule 2: No Lambda@Edge for Simple Tasks
**You will be tempted to:** Use Lambda@Edge for URL rewrites or header manipulation
**Why that fails:** 6x the cost and 30-50ms added latency for tasks that CloudFront Functions handle in <1ms
**The right way:** CloudFront Functions for simple tasks. Lambda@Edge only when you need network calls, multiple triggers, or complex logic

### Rule 3: No WAF Without Count Mode First
**You will be tempted to:** Deploy WAF rules directly in Block mode
**Why that fails:** False positives block legitimate users. Managed rules can be aggressive. You'll learn about the breakage from angry customers, not from testing
**The right way:** Deploy in Count mode. Review logs for 1-2 weeks. Fix false positives. Then switch to Block

### Rule 4: No Allow Rules High in WebACL
**You will be tempted to:** Place Allow rules early in WebACL evaluation order
**Why that fails:** Allow rules short-circuit evaluation. An early Allow rule bypasses all subsequent Block rules. Attackers craft requests that match the Allow rule
**The right way:** Place rate-based/block rules EARLY. Allow rules LATE. Default action = block (explicit allow only)

### Rule 5: No Certificate Pinning with ACM
**You will be tempted to:** Pin ACM certificate fingerprints for "extra security"
**Why that fails:** ACM auto-renews certificates with NEW keys. Pinned fingerprints break on renewal. Your application goes down when the cert rotates
**The right way:** Trust the ACM certificate chain, not individual certificates. If you must pin, pin the CA certificate, not the leaf
