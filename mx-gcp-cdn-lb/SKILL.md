---
name: mx-gcp-cdn-lb
description: Use when configuring Cloud Load Balancing (L4/L7), enabling Cloud CDN, creating Cloud Armor WAF policies, managing SSL certificates, or setting up DDoS protection. Also use when the user mentions 'load balancer', 'url-map', 'backend-service', 'Cloud CDN', 'Cloud Armor', 'WAF', 'DDoS', 'security policy', 'rate limiting', 'SSL certificate', 'managed certificate', 'Certificate Manager', 'HTTPS', 'forwarding-rule', 'target-proxy', 'health check', 'Adaptive Protection', 'cache hit ratio', or 'bot management'.
---

# GCP CDN & Load Balancing — Cloud CDN, Cloud Armor & L4/L7 LB for AI Coding Agents

**This skill loads when you're configuring load balancers, CDN caching, or WAF protection.**

## When to also load
- `mx-gcp-networking` — VPC, firewall rules, NEGs for serverless backends
- `mx-gcp-security` — **ALWAYS load** — Cloud Armor IS security infrastructure, CMEK for SSL certs, VPC-SC
- `mx-gcp-serverless` — Cloud Run behind load balancer patterns

---

## Level 1: HTTPS Load Balancer with CDN (Beginner)

### Full stack: LB + CDN + managed SSL

```bash
# 1. Reserve global IP
gcloud compute addresses create my-app-ip --global

# 2. Create health check
gcloud compute health-checks create http my-app-hc \
  --port=8080 --request-path=/healthz

# 3. Create backend service with CDN enabled
gcloud compute backend-services create my-app-backend \
  --global \
  --protocol=HTTP \
  --port-name=http \
  --health-checks=my-app-hc \
  --enable-cdn \
  --cache-mode=CACHE_ALL_STATIC \
  --default-ttl=3600 \
  --enable-logging --logging-sample-rate=1.0

# 4. Add backend (NEG for Cloud Run, or MIG for VMs)
gcloud compute backend-services add-backend my-app-backend \
  --global \
  --network-endpoint-group=my-run-neg \
  --network-endpoint-group-region=us-east1

# 5. Create URL map
gcloud compute url-maps create my-app-urlmap \
  --default-service=my-app-backend

# 6. Create managed SSL certificate
gcloud compute ssl-certificates create my-app-cert \
  --domains=app.mycompany.com \
  --global

# 7. Create HTTPS target proxy
gcloud compute target-https-proxies create my-app-proxy \
  --ssl-certificates=my-app-cert \
  --url-map=my-app-urlmap

# 8. Create forwarding rule
gcloud compute forwarding-rules create my-app-https \
  --global \
  --address=my-app-ip \
  --target-https-proxy=my-app-proxy \
  --ports=443
```

### Which load balancer type

| Need | Type | Scope |
|------|------|-------|
| Web app / API (HTTP/HTTPS) | Application LB (L7) | Global or Regional |
| TCP/UDP (database, game server) | Network LB (L4) | Regional (passthrough) |
| gRPC or WebSocket | Application LB (L7) | Global |
| Internal microservices | Internal Application LB | Regional |
| SSL offload without HTTP features | SSL Proxy LB | Global |

### SSL certificates

**Use Certificate Manager with DNS authorization** (recommended):
```bash
# Create DNS authorization
gcloud certificate-manager dns-authorizations create my-auth \
  --domain=app.mycompany.com

# Create certificate with DNS auth
gcloud certificate-manager certificates create my-cert \
  --domains=app.mycompany.com \
  --dns-authorizations=my-auth

# Create certificate map and entry
gcloud certificate-manager maps create my-cert-map
gcloud certificate-manager maps entries create my-entry \
  --map=my-cert-map \
  --certificates=my-cert \
  --hostname=app.mycompany.com
```

DNS authorization supports wildcards and works before the LB exists. Google-managed certs are free and auto-renew.

---

## Level 2: Cloud Armor WAF (Intermediate)

### Create a security policy

```bash
# Create policy with default deny
gcloud compute security-policies create my-waf \
  --description="Production WAF policy"

# Allow known IP ranges (priority 100)
gcloud compute security-policies rules create 100 \
  --security-policy=my-waf \
  --action=allow \
  --src-ip-ranges="203.0.113.0/24,198.51.100.0/24" \
  --description="Allow office and VPN IPs"

# Block known bad actors (priority 200)
gcloud compute security-policies rules create 200 \
  --security-policy=my-waf \
  --action=deny-403 \
  --src-ip-ranges="192.0.2.0/24" \
  --description="Block known malicious range"

# Enable OWASP WAF rules (priority 1000)
gcloud compute security-policies rules create 1000 \
  --security-policy=my-waf \
  --action=deny-403 \
  --expression="evaluatePreconfiguredExpr('sqli-v33-stable')" \
  --description="Block SQL injection"

gcloud compute security-policies rules create 1010 \
  --security-policy=my-waf \
  --action=deny-403 \
  --expression="evaluatePreconfiguredExpr('xss-v33-stable')" \
  --description="Block XSS attacks"

# Rate limit (priority 2000)
gcloud compute security-policies rules create 2000 \
  --security-policy=my-waf \
  --action=throttle \
  --rate-limit-threshold-count=100 \
  --rate-limit-threshold-interval-sec=60 \
  --conform-action=allow \
  --exceed-action=deny-429 \
  --enforce-on-key=IP \
  --description="Rate limit: 100 req/min per IP"

# Enable Adaptive Protection (ML-based DDoS detection)
gcloud compute security-policies update my-waf \
  --enable-layer7-ddos-defense

# Attach to backend service
gcloud compute backend-services update my-app-backend \
  --global \
  --security-policy=my-waf
```

**Rule priority best practices:**
- Leave gaps of 10 between priorities (100, 110, 120...) for future insertion
- Group rules: allow lists (100-199), block lists (200-299), WAF rules (1000-1099), rate limits (2000-2099)
- **Always use preview mode first** — add `--preview` flag, monitor logs, then remove to enforce

### Geo-blocking

```bash
gcloud compute security-policies rules create 300 \
  --security-policy=my-waf \
  --action=deny-403 \
  --expression="origin.region_code == 'CN' || origin.region_code == 'RU'" \
  --description="Geo-block China and Russia"
```

---

## Level 3: CDN Optimization & Advanced Patterns (Advanced)

### CDN cache tuning

```bash
# Update backend for aggressive caching
gcloud compute backend-services update my-app-backend \
  --global \
  --cache-mode=CACHE_ALL_STATIC \
  --default-ttl=86400 \
  --max-ttl=604800 \
  --client-ttl=3600 \
  --negative-caching \
  --custom-response-header="X-Cache-Status: {cdn_cache_status}"
```

**Cache modes:**

| Mode | Behavior |
|------|----------|
| `CACHE_ALL_STATIC` | Auto-cache common static types (JS, CSS, images) even without Cache-Control headers |
| `USE_ORIGIN_HEADERS` | Only cache when origin sends Cache-Control/Expires headers |
| `FORCE_CACHE_ALL` | Cache everything (dangerous for dynamic content) |

**Never cache user-specific content** — responses with `Set-Cookie`, `Authorization`, or personalized data. Use `Cache-Control: private` or `no-store` on these responses.

### URL map with path-based routing

```bash
# Create separate backends for API and static
gcloud compute url-maps add-path-matcher my-app-urlmap \
  --default-service=my-app-backend \
  --path-matcher-name=routes \
  --path-rules="/api/*=my-api-backend,/static/*=my-cdn-bucket-backend"
```

### HTTP-to-HTTPS redirect

```bash
# Create HTTP URL map that redirects everything to HTTPS
gcloud compute url-maps import my-app-http-redirect --source=- <<'EOF'
name: my-app-http-redirect
defaultUrlRedirect:
  httpsRedirect: true
  redirectResponseCode: MOVED_PERMANENTLY_DEFAULT
EOF

gcloud compute target-http-proxies create my-app-http-proxy \
  --url-map=my-app-http-redirect

gcloud compute forwarding-rules create my-app-http \
  --global \
  --address=my-app-ip \
  --target-http-proxy=my-app-http-proxy \
  --ports=80
```

---

## Performance: Make It Fast

- **Premium Tier networking** — traffic enters Google's backbone at the nearest PoP. Standard Tier routes through the public internet. Premium is default and worth the cost for user-facing apps.
- **Enable HTTP/3 and QUIC** — Cloud CDN supports it natively. Reduces connection setup time, especially on mobile/lossy networks.
- **Versioned URLs for cache busting** — use `/app.v2.3.1.js` not `/app.js?v=2.3.1`. Query params can cause cache misses depending on cache key config.
- **Custom cache keys** — exclude query params that don't change content (analytics tags, tracking IDs) from cache keys to increase hit ratio.
- **Co-locate backends with users** — multi-region backend services with global LB. Google routes to the nearest healthy backend automatically.
- **Negative caching** — cache 404/410 responses to prevent origin from being hammered by requests for deleted resources.

## Observability: Know It's Working

```bash
# Check CDN cache hit ratio
gcloud logging read \
  'resource.type="http_load_balancer" AND httpRequest.cacheHit=true' \
  --project=my-project --freshness=1h --limit=10

# Check Cloud Armor blocked requests
gcloud logging read \
  'resource.type="http_load_balancer" AND jsonPayload.enforcedSecurityPolicy.outcome="DENY"' \
  --project=my-project --freshness=1h --limit=20

# List security policies
gcloud compute security-policies list

# Describe specific policy with rules
gcloud compute security-policies describe my-waf
```

| Alert | Severity |
|-------|----------|
| CDN cache hit ratio <50% | **MEDIUM** (investigate cache config) |
| Cloud Armor blocking >1000 req/min | **HIGH** (active attack or false positive) |
| 5xx error rate >1% on LB | **HIGH** |
| SSL certificate expiring <14 days | **CRITICAL** |
| Adaptive Protection alert triggered | **HIGH** |
| Backend health check failing | **CRITICAL** |

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Always attach Cloud Armor to internet-facing load balancers
**You will be tempted to:** Skip Cloud Armor because "we don't have enemies" or "it costs extra."
**Why that fails:** Every internet-facing service gets attacked. Bot scraping, credential stuffing, and volumetric DDoS are automated and indiscriminate. Without Cloud Armor, your only protection is Google's built-in L3/L4 DDoS absorption — which doesn't stop application-layer attacks (SQL injection, XSS, slow-loris).
**The right way:** Create a Cloud Armor policy with at minimum: OWASP WAF rules (sqli + xss), rate limiting per IP, and Adaptive Protection enabled. Attach to every backend service behind a global LB.

### Rule 2: Always use preview mode before enforcing Cloud Armor rules
**You will be tempted to:** Deploy rules directly to production because "the rule is simple" or "I tested locally."
**Why that fails:** WAF rules have false positives. An overly aggressive SQLi rule can block legitimate form submissions containing SQL-like syntax (e.g., "O'Brien" triggers apostrophe detection). A geo-block rule can block VPN users. You won't know until real traffic hits it.
**The right way:** Every new rule starts with `--preview` flag. Monitor Cloud Logging for 24-48 hours. Check for false positives. Then remove `--preview` to enforce. This applies to OWASP rules, rate limits, and geo-blocks equally.

### Rule 3: Use Certificate Manager with DNS authorization, not legacy managed certs
**You will be tempted to:** Use `gcloud compute ssl-certificates create --domains=...` because "it's simpler."
**Why that fails:** Legacy managed certs require the LB to be running and serving traffic for HTTP-01 validation. You can't pre-provision certs, can't use wildcards, and if DNS changes break validation, the cert silently fails to renew. Certificate Manager with DNS authorization validates via DNS TXT records — works before the LB exists, supports wildcards, and doesn't depend on HTTP reachability.
**The right way:** `gcloud certificate-manager` with `dns-authorizations`. Create the cert → set up DNS CNAME → cert provisions automatically. Use certificate maps to attach to LB proxies.

### Rule 4: Never use FORCE_CACHE_ALL on dynamic backends
**You will be tempted to:** Set `--cache-mode=FORCE_CACHE_ALL` because "we want maximum cache hit ratio."
**Why that fails:** FORCE_CACHE_ALL caches EVERYTHING, including responses with `Set-Cookie` headers, personalized content, authenticated API responses, and CSRF tokens. User A sees User B's dashboard. Session tokens leak across users. This is a security incident, not just a performance bug.
**The right way:** `CACHE_ALL_STATIC` for mixed backends (auto-detects static content types). `USE_ORIGIN_HEADERS` when your app sets explicit Cache-Control headers. Set `Cache-Control: private, no-store` on all authenticated/personalized responses from your origin.

### Rule 5: Leave priority gaps when creating Cloud Armor rules
**You will be tempted to:** Use consecutive priorities (1, 2, 3) because "it's cleaner."
**Why that fails:** Cloud Armor evaluates rules from lowest to highest priority. If you use consecutive numbers and need to insert a rule between 2 and 3, you must renumber everything. In a production incident (active DDoS), you need to insert a block rule IMMEDIATELY — not restructure your entire policy first.
**The right way:** Priorities in blocks of 10: allow-lists at 100-199, block-lists at 200-299, WAF rules at 1000-1099, rate limits at 2000-2099. This gives you 9 insertion points in every block.
