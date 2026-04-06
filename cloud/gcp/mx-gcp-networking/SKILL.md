---
name: mx-gcp-networking
description: Use when creating VPCs, subnets, firewall rules, Cloud NAT, VPC peering, Cloud DNS, or any GCP networking configuration. Also use when the user mentions 'gcloud compute networks', 'gcloud compute firewall-rules', 'VPC', 'subnet', 'CIDR', 'firewall', '0.0.0.0/0', 'Cloud NAT', 'Private Google Access', 'VPC peering', 'Cloud DNS', 'private zone', 'forwarding zone', 'network tag', 'source-ranges', 'hierarchical firewall policy', 'Shared VPC', or 'IAP tunnel'.
---

# GCP Networking — VPC, Firewall, NAT & DNS for AI Coding Agents

**This skill loads when you're creating or modifying GCP network infrastructure.**

## When to also load
- `mx-gcp-iam` — IAP configuration, service account firewall targeting
- `mx-gcp-security` — VPC Service Controls
- `mx-gcp-gke` — GKE subnet/pod/service IP planning
- `mx-gcp-compute` — VM network interfaces, external IPs

---

## Level 1: Patterns That Always Work (Beginner)

### Always use custom mode VPCs

```bash
# BAD — auto mode creates subnets in every region with 10.128.0.0/9
gcloud compute networks create my-vpc --subnet-mode=auto

# GOOD — custom mode, you control every subnet
gcloud compute networks create my-vpc --subnet-mode=custom
```

### Delete the default VPC

The default VPC ships with `default-allow-ssh` and `default-allow-rdp` from `0.0.0.0/0`. Delete it.

```bash
# List default firewall rules
gcloud compute firewall-rules list --filter="network=default"

# Delete them all, then the network
gcloud compute firewall-rules delete default-allow-ssh default-allow-rdp default-allow-icmp default-allow-internal --quiet
gcloud compute networks delete default --quiet
```

### Never use 0.0.0.0/0 as a source range

```bash
# BAD — entire internet can reach your VMs
gcloud compute firewall-rules create allow-ssh \
  --network=my-vpc --action=ALLOW --rules=tcp:22 \
  --source-ranges=0.0.0.0/0

# GOOD — specific CIDR (home IP, office, VPN)
gcloud compute firewall-rules create allow-ssh \
  --network=my-vpc --action=ALLOW --rules=tcp:22 \
  --source-ranges=203.0.113.10/32 \
  --target-service-accounts=vm-web-api@my-project.iam.gserviceaccount.com

# BEST — use IAP instead of opening SSH to any IP
gcloud compute firewall-rules create allow-iap-ssh \
  --network=my-vpc --action=ALLOW --rules=tcp:22 \
  --source-ranges=35.235.240.0/20 \
  --target-service-accounts=vm-web-api@my-project.iam.gserviceaccount.com
```

### Subnet sizing guide

| Environment | Subnet size | Usable IPs | Use case |
|-------------|-------------|------------|----------|
| Dev/test | `/24` | 252 | Small workloads |
| Production | `/20` | 4,092 | Standard workloads |
| Enterprise/GKE | `/16` | 65,532 | Large clusters |
| Minimum | `/29` | 4 | Single-purpose |

**GCP reserves 4 IPs per subnet** (network, gateway, second-to-last, broadcast). Subnets can only expand (not shrink), start address is fixed.

```bash
gcloud compute networks subnets create web-subnet \
  --network=my-vpc \
  --region=us-east1 \
  --range=10.0.1.0/24 \
  --enable-private-ip-google-access
```

---

## Level 2: NAT, Private Access & Peering (Intermediate)

### The no-external-IP pattern (Cloud NAT + Private Google Access)

```bash
# 1. Enable Private Google Access on the subnet
gcloud compute networks subnets update web-subnet \
  --region=us-east1 --enable-private-ip-google-access

# 2. Create Cloud Router (required for NAT)
gcloud compute routers create my-router \
  --network=my-vpc --region=us-east1

# 3. Create Cloud NAT with reserved IPs
gcloud compute addresses create nat-ip-1 --region=us-east1
gcloud compute routers nats create my-nat \
  --router=my-router --region=us-east1 \
  --nat-external-ip-pool=nat-ip-1 \
  --nat-custom-subnet-ip-ranges=web-subnet \
  --enable-logging
```

**Result:** VMs have no external IPs, can reach Google APIs (via Private Google Access) and the internet (via Cloud NAT), but can't be reached from the internet.

### Firewall targeting: service accounts > network tags

| Method | IAM-governed? | Works with hierarchical policies? | Cross-peering? |
|--------|--------------|----------------------------------|----------------|
| Network tags | No | No | No |
| Service accounts | Yes | Yes | No |
| IAM-governed tags (secure tags) | Yes | Yes | Yes |

```bash
# BAD — network tags (anyone with instance edit can change them)
gcloud compute firewall-rules create allow-http \
  --network=my-vpc --action=ALLOW --rules=tcp:80 \
  --source-ranges=0.0.0.0/0 --target-tags=web-server

# GOOD — service account targeting (IAM-governed)
gcloud compute firewall-rules create allow-http \
  --network=my-vpc --action=ALLOW --rules=tcp:80 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-service-accounts=vm-web-api@my-project.iam.gserviceaccount.com
```

### VPC Peering

```bash
# Peer VPC-A with VPC-B (both directions required)
gcloud compute networks peerings create peer-a-to-b \
  --network=vpc-a \
  --peer-network=vpc-b \
  --peer-project=project-b

gcloud compute networks peerings create peer-b-to-a \
  --network=vpc-b \
  --peer-network=vpc-a \
  --peer-project=project-a
```

**Critical VPC peering rules:**
- **Non-transitive:** A↔B + B↔C does NOT give A↔C
- **Non-overlapping IPs required** — peering fails if subnets overlap
- **Cloud NAT doesn't cross peering boundaries** — each VPC needs its own NAT
- **Firewall rules are per-VPC** — each side must allow traffic from the peer

### Cloud DNS private zones

```bash
# Create private zone (NOTE: dns-name MUST end with a dot)
gcloud dns managed-zones create internal-zone \
  --description="Internal DNS" \
  --dns-name="internal.mycompany.com." \
  --visibility=private \
  --networks=my-vpc

# Add A record via transaction
gcloud dns record-sets transaction start --zone=internal-zone
gcloud dns record-sets transaction add 10.0.1.5 \
  --name="api.internal.mycompany.com." --ttl=300 --type=A --zone=internal-zone
gcloud dns record-sets transaction execute --zone=internal-zone
```

**DNS gotchas:**
- CNAME at zone apex is INVALID (conflicts with SOA/NS records)
- Private zone NXDOMAIN does NOT fall back to public DNS
- Forwarding targets must respond within 4 seconds from `35.199.192.0/19`

---

## Level 3: Hierarchical Policies & Hybrid Networking (Advanced)

### Firewall rule priority system

| Priority | Range | Use for |
|----------|-------|---------|
| 0-999 | Reserved | Emergency overrides |
| 1000 | Default | Standard rules |
| 65534 | Implied | Default deny ingress / allow egress |
| 65535 | Implied | Lowest priority |

Lower number = higher priority. A permissive rule at priority 100 overrides a deny at priority 1000.

### Firewall rule evaluation order

1. **Hierarchical firewall policies** (org → folder → VPC) — `goto_next` passes to next level
2. **VPC network firewall policies** (global → regional)
3. **VPC firewall rules** (legacy, per-network)
4. **Implied rules** (deny all ingress, allow all egress)

### GKE IP planning

GKE clusters need 3 separate IP ranges — undersizing the pod range is the #1 mistake.

```bash
# Create subnet with secondary ranges for GKE
gcloud compute networks subnets create gke-subnet \
  --network=my-vpc --region=us-east1 \
  --range=10.0.0.0/20 \
  --secondary-range=pods=10.4.0.0/14,services=10.8.0.0/20

# ~65K pod IPs, ~4K service IPs, ~4K node IPs
```

| Range | What | Sizing rule |
|-------|------|-------------|
| Node (primary) | VMs running GKE | `/20` for up to ~4K nodes |
| Pod (secondary) | Kubernetes pods | `/14` for 100+ nodes (256 pods/node default) |
| Service (secondary) | ClusterIP services | `/20` is usually sufficient |

### DNS forwarding for hybrid (on-prem ↔ GCP)

```bash
# Inbound: on-prem can resolve GCP private zones
gcloud dns policies create inbound-policy \
  --description="Allow on-prem DNS queries" \
  --networks=my-vpc \
  --enable-inbound-forwarding

# Find the forwarding IPs on-prem should target
gcloud compute addresses list --filter="purpose=DNS_RESOLVER"

# Outbound: GCP forwards specific zones to on-prem DNS
gcloud dns managed-zones create onprem-forward \
  --description="Forward corp.local to on-prem" \
  --dns-name="corp.local." \
  --visibility=private \
  --networks=my-vpc \
  --forwarding-targets="10.1.0.2[private],10.1.0.3[private]"
```

**Hybrid DNS requires:** Cloud Router must advertise `35.199.192.0/19` to on-prem.

---

## Performance: Make It Fast

### Cloud NAT port allocation

- Default: 64 ports per VM — causes connection drops under load
- Monitor `OUT_OF_RESOURCES` drops in Cloud NAT metrics
- Increase with `--min-ports-per-vm=1024` or higher for high-connection workloads
- Use reserved static IPs for stable egress (whitelisting by external services)

### Subnet expansion (not recreation)

```bash
# Expand a subnet (can only go larger, never smaller)
gcloud compute networks subnets expand-ip-range web-subnet \
  --region=us-east1 --prefix-length=20
```

Plan for growth — leave gaps in your IP numbering. Expanding is easy, shrinking is impossible.

### Firewall rule limits

- Max 500 firewall rules per VPC network (soft limit, can request increase)
- Use firewall policies to group rules and reduce count
- Firewall rules with logging enabled have a small per-packet cost — enable selectively on critical rules

---

## Observability: Know It's Working

### Audit open firewall rules

```bash
# Find all rules allowing 0.0.0.0/0
gcloud compute firewall-rules list \
  --filter="sourceRanges=0.0.0.0/0 AND direction=INGRESS" \
  --format="table(name,network,allowed,sourceRanges,targetTags,targetServiceAccounts)"

# Find rules with logging disabled
gcloud compute firewall-rules list \
  --filter="logConfig.enable=false" \
  --format="table(name,network)"
```

### VPC Flow Logs

Enable on subnets to capture network flow data (source/dest IP, port, protocol, bytes).

```bash
gcloud compute networks subnets update web-subnet \
  --region=us-east1 --enable-flow-logs \
  --logging-flow-sampling=0.5 --logging-metadata=include-all
```

### Cloud NAT monitoring

- Watch `nat/port_usage` metric — alert at >80% utilization
- Watch `nat/dropped_sent_packets_count` — any drops = capacity issue
- Check `gcloud compute routers get-nat-mapping-info my-router --region=us-east1`

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No 0.0.0.0/0 source ranges — ever
**You will be tempted to:** Use `--source-ranges=0.0.0.0/0` because "it's just for testing" or "I'll restrict it later."
**Why that fails:** "Later" never comes. Every port scan on the internet will find your VM within hours. Your `infrastructure.md` already says to delete these on sight.
**The right way:** Use specific CIDRs. For SSH/RDP, use IAP (`35.235.240.0/20`). For HTTP, use load balancer health check ranges (`130.211.0.0/22`, `35.191.0.0/16`).

### Rule 2: Never use auto mode VPCs
**You will be tempted to:** Use `--subnet-mode=auto` because "it's simpler" and "I don't know what subnets I need yet."
**Why that fails:** Auto mode creates a `/20` subnet in every single region (35+ subnets), using `10.128.0.0/9` — half the `10.0.0.0/8` space. This makes VPC peering nearly impossible due to overlaps and wastes massive IP space.
**The right way:** Custom mode VPC. Create subnets only in regions you use, with planned CIDR ranges that don't overlap with other VPCs or on-prem.

### Rule 3: Target firewall rules to service accounts, not tags
**You will be tempted to:** Use `--target-tags=web-server` because it's simpler to type.
**Why that fails:** Network tags are NOT IAM-governed. Any user with `compute.instances.setTags` can add a tag to a VM and bypass your firewall rules. Tags also don't work with hierarchical policies.
**The right way:** Use `--target-service-accounts=SA_EMAIL`. This ties firewall targeting to IAM, is auditable, and works with hierarchical policies.

### Rule 4: DNS names must end with a trailing dot
**You will be tempted to:** Write `--dns-name="internal.mycompany.com"` (no trailing dot).
**Why that fails:** Cloud DNS treats names without trailing dots as relative, which can cause zone creation to fail or records to resolve incorrectly.
**The right way:** Always use `--dns-name="internal.mycompany.com."` with the trailing dot. This is a fully qualified domain name (FQDN).

### Rule 5: Plan IP ranges for VPC peering before creating subnets
**You will be tempted to:** Pick convenient CIDR ranges like `10.0.0.0/16` for every VPC.
**Why that fails:** VPC peering requires non-overlapping IP ranges. If two VPCs both use `10.0.0.0/16`, they can never be peered. Changing subnet CIDRs requires deleting and recreating — destroying all VMs in the subnet.
**The right way:** Maintain an IP allocation plan. Use different `/16` blocks per VPC (e.g., `10.0.0.0/16`, `10.1.0.0/16`, `10.2.0.0/16`). Document allocations before creating subnets.
