---
name: mx-aws-networking
description: VPC design, subnets, security groups, NACLs, NAT Gateway, Transit Gateway hub-spoke, PrivateLink, VPC endpoints, Network Firewall, IPv6 dual-stack, VPC Flow Logs, and AI-generated security anti-patterns
---

# AWS Networking — VPC & Connectivity for AI Coding Agents

**Load this skill when designing VPCs, configuring security groups, setting up Transit Gateway, creating VPC endpoints, or deploying Network Firewall.**

## When to also load
- `mx-aws-compute` — EC2 placement groups, ENA networking
- `mx-aws-dns` — Route 53 Resolver, DNS Firewall, private hosted zones
- `mx-aws-iam` — VPC endpoint policies, resource-based policies
- `mx-aws-cdn-lb` — ALB/NLB in VPC, WAF integration
- `mx-aws-security` — GuardDuty VPC flow analysis, KMS for encryption

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: Multi-AZ Private-First Architecture
| BAD | GOOD |
|-----|------|
| Single AZ, everything in public subnets | Multi-AZ, public subnets only for LBs/NAT, everything else private |

**Subnet layout per AZ:** Public (/24) + Private App (/22) + Private Data (/24) + Private TGW (/28). Plan CIDRs for future growth + EKS/PrivateLink IP needs.

### Pattern 2: Gateway Endpoints Are Free — Always Use Them
| BAD | GOOD |
|-----|------|
| S3/DynamoDB traffic through NAT Gateway ($$) | Gateway Endpoints for S3 + DynamoDB ($0 in same region) |

Gateway endpoints for S3 and DynamoDB have **zero cost**. They eliminate NAT Gateway data processing charges. Add them to every VPC.

### Pattern 3: Security Groups per Application Tier
| BAD | GOOD |
|-----|------|
| One SG for all resources, wide-open rules | Separate SGs: `web-sg`, `app-sg`, `db-sg` with SG-to-SG referencing |

SG-to-SG referencing (not hardcoded IPs) for internal communication. **Restrict outbound too** — default allows all outbound, which is an exfiltration risk.

### Pattern 4: NACLs as Defense-in-Depth
Default NACLs allow everything — customize them. NACLs are stateless: explicitly allow return traffic on ephemeral ports (1024-65535). Rule ordering matters (evaluated by number, first match wins).

### Pattern 5: Interface Endpoints for Frequently Called AWS APIs
For high-volume AWS API traffic (SQS, KMS, STS, ECR), Interface Endpoints are often **cheaper than NAT Gateway** and keep traffic on the AWS backbone.

---

## Level 2: Transit Gateway & PrivateLink (Intermediate)

### Transit Gateway Hub-Spoke

| Component | Best Practice |
|-----------|---------------|
| Hosting | Central networking account owns TGW |
| Subnets | Dedicated /28 subnets for TGW attachments (no other resources) |
| Route tables | Disable default association/propagation. Multiple tables for segmentation (prod vs non-prod) |
| Inspection | Inspection VPC pattern with Network Firewall. Enable **Appliance mode** for symmetric routing |
| Shared services | Centralize DNS, logging, security, PrivateLink endpoints in shared VPC |
| Egress | Centralized NAT in single egress VPC (cheaper than per-VPC NAT GWs) |
| Cost | Flexible Cost Allocation (Nov 2025) for granular chargeback |

**VPC Peering** is cheaper than TGW for high-volume cross-region transfers between a few VPCs. TGW wins for many-to-many connectivity.

### PrivateLink
- Keeps traffic on AWS backbone — never traverses internet
- Route 53 Profiles (2025): multi-VPC DNS management (replaces old PHZ sharing pattern)
- Monitor and consolidate endpoints — each has hourly cost
- Use for SaaS integrations, cross-account service exposure

### IPv6 Dual-Stack
- Amazon-provided IPv6 CIDRs, /64 per subnet
- NAT64 + DNS64 for IPv6-to-IPv4 communication
- Egress-only internet gateway for private IPv6 subnets
- TGW Connect: MP-BGP for IPv6 over GRE tunnels (SD-WAN integration)
- IPv4 idle EIP charges increasing — IPv6 adoption reduces costs

---

## Level 3: Network Firewall & Advanced Security (Advanced)

### Network Firewall Architecture

| Mode | Architecture | When to Use |
|------|-------------|-------------|
| **Centralized** | Inspection VPC + Transit Gateway | E-W traffic + egress filtering (most common) |
| **Distributed** | Firewall per VPC | Dedicated inbound access per VPC |
| **Combined** | Centralized for E-W/egress, distributed for ingress | Large enterprise with mixed patterns |

### Stateless vs Stateful Rules
- **Stateless**: per-packet, no context. Fast filtering for known-bad IPs, simple protocol blocking. First-match priority
- **Stateful**: traffic flow context, DPI, IPS (Suricata-compatible). Auto-allows return traffic. Layer 7 inspection
- **Best practice**: forward ALL traffic to stateful by default. Minimal stateless rules. Use **Strict** rule ordering
- AWS managed threat intelligence rule groups (botnets, malware, exploits) — enable all
- Set `$HOME_NET` to include all VPC CIDRs for centralized deployments

### Firewall Logging
- Enable **both** flow logs (all traffic) + alert logs (DROP/ALERT/REJECT)
- Destinations: S3, CloudWatch, Firehose
- 30-90 day retention for flow, longer for alert
- CloudWatch alarms on high-severity alerts

### Firewall Manager
Centralized DNS Firewall + Network Firewall policy management across all accounts/VPCs in Organizations.

---

## Performance: Make It Fast

### Optimization Checklist
1. **Gateway Endpoints** for S3/DynamoDB — zero cost, eliminates NAT bottleneck
2. **Centralized NAT** in egress VPC — one NAT GW serves all VPCs via TGW (vs per-VPC NAT)
3. **PrivateLink** for high-volume AWS API calls — lower latency than internet path
4. **VPC Peering** for high-bandwidth cross-region — cheaper and faster than TGW for point-to-point
5. **Appliance mode** on TGW for firewall VPCs — mandatory for symmetric routing (asymmetric = dropped traffic)
6. **Per-AZ firewall endpoints** — avoid cross-AZ traffic for inspection

### NAT Gateway Cost Control
NAT GW charges: hourly + per-GB data processing. Biggest cost traps:
- S3/DynamoDB traffic going through NAT instead of Gateway Endpoints
- Cross-AZ NAT traffic (use one NAT per AZ or centralized egress)
- Interface Endpoints often cheaper for high-volume API traffic

---

## Observability: Know It's Working

### What to Monitor

| Signal | Tool | Key Metric |
|--------|------|-----------|
| Traffic patterns | VPC Flow Logs → CloudWatch/S3 | Rejected flows, unexpected ports |
| TGW traffic | TGW Flow Logs → CloudWatch/S3 | Cross-account traffic volume, routing anomalies |
| Firewall | Network Firewall alert logs | DROP/ALERT events, high-severity rule matches |
| Endpoints | CloudWatch metrics per endpoint | `ActiveConnections`, `BytesProcessed` |
| NAT | `NATGateway` metrics | `ErrorPortAllocation` (= exhausted), `BytesOutToDestination` |

- **VPC Flow Logs**: enable on all VPCs. Use v5 format for metadata enrichment
- **TGW Flow Logs**: enable for cross-account visibility
- `ErrorPortAllocation` on NAT Gateway = port exhaustion. Fix: add more NAT GWs or reduce connection count

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No 0.0.0.0/0 on Any Security Group
**You will be tempted to:** Open SSH (22), RDP (3389), or app ports to `0.0.0.0/0` for "development"
**Why that fails:** Bots scan the entire internet in minutes. Compromised within hours
**The right way:** Specific CIDRs only. Use Session Manager for SSH-less access. SG-to-SG for internal

### Rule 2: No Single-AZ Architectures
**You will be tempted to:** Deploy to one AZ because it's simpler and cheaper
**Why that fails:** AZ failure = total outage. AWS designs for AZ independence
**The right way:** Multi-AZ for all tiers. NAT Gateway per AZ. Subnets in 2+ AZs minimum

### Rule 3: No NAT Gateway for S3/DynamoDB Traffic
**You will be tempted to:** Skip Gateway Endpoints because "NAT already works"
**Why that fails:** NAT charges $0.045/GB for data processing. S3 Gateway Endpoint is free. At scale this is thousands/month
**The right way:** Gateway Endpoints for S3 + DynamoDB in every VPC. Interface Endpoints for other high-volume AWS APIs

### Rule 4: No Asymmetric Routing Through Firewalls
**You will be tempted to:** Skip Appliance mode on TGW because it's "just a checkbox"
**Why that fails:** Without Appliance mode, return traffic may route through a different firewall endpoint than the request. Stateful inspection breaks. Traffic gets dropped silently
**The right way:** Enable Appliance mode on TGW attachments for any VPC running stateful firewalls

### Rule 5: No Default NACLs in Production
**You will be tempted to:** Leave NACLs at default (allow all) since SGs "handle security"
**Why that fails:** SG misconfiguration is the #1 cloud security issue. NACLs are your safety net
**The right way:** Customize NACLs per subnet tier. Deny known-bad ports. Allow only required traffic + ephemeral return ports
