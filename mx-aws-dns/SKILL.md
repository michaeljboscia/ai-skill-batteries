---
name: mx-aws-dns
description: Route 53 routing policies (failover/weighted/latency/geolocation), health checks, DNSSEC, Resolver endpoints for hybrid DNS, DNS Firewall (domain filtering/DGA detection), query logging, Route 53 Profiles, and AI-generated anti-patterns
---

# AWS DNS — Route 53 & DNS Security for AI Coding Agents

**Load this skill when configuring Route 53 routing, health checks, hybrid DNS resolution, or DNS Firewall protection.**

## When to also load
- `mx-aws-networking` — VPC DNS resolution, private hosted zones
- `mx-aws-cdn-lb` — CloudFront + Route 53 for global distribution
- `mx-aws-security` — DNS Firewall as security layer, GuardDuty DNS findings
- `mx-aws-compute` — health checks for EC2-based services

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: Alias Records Over CNAMEs
| BAD | GOOD |
|-----|------|
| CNAME pointing to ALB/CloudFront DNS name | Alias record pointing to AWS resource |

Alias records are free (no query charges), work at zone apex, and resolve faster. Always use for AWS resources (ALB, CloudFront, S3, API Gateway).

### Pattern 2: Failover Routing with Health Checks
| BAD | GOOD |
|-----|------|
| Simple routing to a single endpoint | Failover routing: primary + secondary with health checks |

Health checks monitor endpoint availability. On failure, Route 53 automatically routes to secondary. Set TTL to 60s for quick failover.

### Pattern 3: Always Include Default Geolocation Record
| BAD | GOOD |
|-----|------|
| Geolocation records for US, EU only | Geolocation records for US, EU + **default** record |

Without a default record, users from unmatched locations get NXDOMAIN (no answer). Always include a default.

### Pattern 4: DNSSEC for Spoofing Protection
Enable DNSSEC signing on hosted zones for critical domains. Protects against DNS cache poisoning and man-in-the-middle attacks.

### Pattern 5: Allow Health Checker IPs in Security Groups
Route 53 health checkers come from published AWS IP ranges. Ensure SGs and NACLs allow inbound traffic from these IPs on health check ports.

---

## Level 2: Advanced Routing & Health Checks (Intermediate)

### Routing Policy Decision Tree

| Scenario | Policy | Key Setting |
|----------|--------|-------------|
| Active-passive DR | **Failover** | Health checks mandatory |
| Global lowest latency | **Latency-based** | Combine with health checks for failover |
| Canary / A/B testing | **Weighted** | Weights 0-255. Start 95/5 |
| Compliance (data residency) | **Geolocation** | Route by country/continent |
| Combined global HA | **Failover + Latency** | Latency within region, failover across |

### Health Check Types

| Type | Use Case | Notes |
|------|----------|-------|
| **Endpoint** | HTTP/HTTPS/TCP to public endpoints | Interval 10s or 30s, configure failure threshold |
| **Calculated** | Composite ("2 of 3 healthy") | Combine multiple child checks for complex HA logic |
| **CloudWatch alarm** | Private/VPC resources | Route 53 can't reach private IPs directly |

### TTL Trade-offs
- **Low TTL (60s):** Fast failover, but higher DNS query cost + load on resolvers
- **High TTL (3600s):** Cheaper, lower query load, but stale caches during incidents
- **Rule of thumb:** 60s for failover records, 300s for stable records, 86400s for immutable records

### Weighted Routing for Deployments
- DNS caching affects distribution accuracy at small scale — lower TTL during canary
- Weight 0 = no traffic (useful for staging endpoints that should be addressable but not routed to)

---

## Level 3: DNS Firewall & Hybrid Resolution (Advanced)

### Route 53 Resolver DNS Firewall
- Domain name filtering at VPC Resolver level. Rule groups associated with VPCs
- **Managed threat feeds**: malware, botnets, phishing domains (AWS-maintained)
- **Query Type Filtering (Jan 2024)**: block specific QTYPE (e.g., TXT records for DNS tunneling)
- **DNS Firewall Advanced (Nov 2024)**: ML-based detection of DNS tunneling + Domain Generation Algorithms (DGAs)
- **Route 53 Global Resolver (Preview Nov 2025)**: internet-reachable anycast DNS resolver extending Firewall to non-VPC clients
- Centralize via Firewall Manager across Organization

### Hybrid DNS Architecture

| Component | Direction | Purpose |
|-----------|-----------|---------|
| **Inbound endpoints** | On-prem → VPC | Resolve AWS private DNS from on-prem |
| **Outbound endpoints** | VPC → On-prem | Resolve corporate domains from VPC |
| **Conditional forwarding** | Domain-specific | Route `corp.example.com` to on-prem resolvers |

- **Resolver Endpoints Delegation (Aug 2025)**: delegate subdomain authority between on-prem and Route 53 without self-managed DNS
- **Route 53 Profiles**: shareable config (private hosted zones + Resolver rules + DNS Firewall rules) across VPCs/accounts

### Query Logging
- Resolver Query Logging to CloudWatch Logs / S3 / Kinesis Firehose
- Logs include: query name, type, response code, source IP, VPC ID, firewall action, rule group
- CloudWatch Contributor Insights + Anomaly Detection on DNS logs for unusual patterns

---

## Performance: Make It Fast

### Optimization Checklist
1. **Alias records** — free, faster resolution than CNAMEs
2. **Appropriate TTLs** — 60s for failover, 300s for stable, long for immutable
3. **Latency-based routing** — automatically routes to lowest-latency region
4. **Consolidate hosted zones** — fewer zones = less management overhead + cost
5. **Health check intervals** — 30s default, 10s fast (higher cost) only when needed

### DNS Resolution Path
VPC .2 address → Private Hosted Zones → Internal domains → Forwarding rules → Public authority. DNS Firewall rules applied at each step. Ensure all DNS goes through Route 53 Resolver (custom DHCP DNS bypasses Firewall).

---

## Observability: Know It's Working

### What to Monitor

| Signal | Tool | What to Watch |
|--------|------|--------------|
| Health checks | Route 53 console + CloudWatch | `HealthCheckStatus` = 0 (unhealthy) |
| DNS queries | Resolver Query Logging | Unusual domains, volume spikes |
| Firewall | DNS Firewall alert logs | Blocked/alerted domains, DGA detections |
| Failover | Route 53 metrics | Failover events, active/passive switches |
| Cost | DNS query counts | High query volume from low TTLs |

- **CloudWatch alarms** on health check status — immediate notification on failover triggers
- **DNS Firewall logs**: monitor blocked queries for both threat detection and false positive tuning
- **Query logging + Anomaly Detection**: identify DNS exfiltration attempts

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Latency Routing Without Health Checks
**You will be tempted to:** Use latency-based routing alone for global distribution
**Why that fails:** Latency routing uses historical data, not real-time health. An endpoint can be down but still receive traffic because it had the lowest latency historically
**The right way:** Always pair latency-based routing with health checks for automatic failover

### Rule 2: No Custom DHCP DNS Without Resolver Forwarding
**You will be tempted to:** Set custom DNS servers in VPC DHCP options for corporate DNS
**Why that fails:** DNS Firewall only works on queries that pass through Route 53 Resolver. Custom DHCP DNS bypasses the Resolver entirely — no firewall protection
**The right way:** Use Route 53 Resolver outbound endpoints with conditional forwarding rules to on-prem DNS

### Rule 3: No High TTL on Failover Records
**You will be tempted to:** Use high TTLs everywhere to reduce DNS costs
**Why that fails:** High TTL on failover records = stale caches during outages. Users continue hitting dead endpoints for hours
**The right way:** 60s TTL on failover records. 300s for stable records. 86400s only for truly immutable records

### Rule 4: No DNS Firewall Without Managed Threat Feeds
**You will be tempted to:** Create only custom domain lists for DNS Firewall
**Why that fails:** Manual lists go stale immediately. New threat domains appear hourly. You can't keep up
**The right way:** Enable AWS managed threat intelligence rule groups (malware, botnets, phishing) + DNS Firewall Advanced for DGA detection. Add custom lists for your specific block/allow needs

### Rule 5: No Geolocation Without Default Record
**You will be tempted to:** Create geolocation records only for your target regions
**Why that fails:** Users from unmatched locations (VPN users, new markets, edge cases) get no DNS response — complete outage for them
**The right way:** Always include a default geolocation record as fallback
