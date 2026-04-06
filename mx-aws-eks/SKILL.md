---
name: mx-aws-eks
description: EKS cluster setup, Karpenter NodePool/EC2NodeClass/consolidation, IRSA/Pod Identity, Pod Security Standards, managed node groups, Fargate profiles, Container Insights, ADOT/Prometheus/Grafana, Spot/Graviton cost optimization, and AI-generated anti-patterns
---

# AWS EKS — Kubernetes on AWS for AI Coding Agents

**Load this skill when creating EKS clusters, configuring Karpenter, setting up pod security, or optimizing Kubernetes costs on AWS.**

## When to also load
- `mx-aws-containers` — ECS vs EKS decision, Fargate patterns
- `mx-aws-networking` — VPC CNI, security groups, private endpoints
- `mx-aws-compute` — EC2 instance types, placement groups, Graviton
- `mx-aws-gpu` — GPU node groups, EFA for distributed training on EKS

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: Private API Server Endpoint
| BAD | GOOD |
|-----|------|
| Public API server endpoint | Private endpoint + VPC access only |

Public API servers are accessible from the internet. Private endpoints restrict access to your VPC.

### Pattern 2: EKS Pod Identity Over IRSA
| BAD | GOOD |
|-----|------|
| Node-level IAM roles (all pods share permissions) | EKS Pod Identity or IRSA (pod-level IAM roles) |

Pod Identity is the newer, simpler approach. IRSA (IAM Roles for Service Accounts) still works but requires OIDC provider setup. Both give pod-level permissions instead of node-level.

### Pattern 3: Pod Security Standards — Restricted Profile
```yaml
apiVersion: v1
kind: Namespace
metadata:
  labels:
    pod-security.kubernetes.io/enforce: restricted
```
No privileged containers, run as non-root, drop all capabilities, read-only root filesystem. Disable `hostNetwork`/`hostPID`/`hostIPC` unless required.

### Pattern 4: IMDSv2 Required on All Nodes
| BAD | GOOD |
|-----|------|
| IMDSv1 allowed (token-optional) | IMDSv2 required (`HttpTokens: required`) |

IMDSv1 is vulnerable to SSRF attacks that can steal node IAM credentials. IMDSv2 requires a session token.

### Pattern 5: EKS-Optimized AMIs + CIS Benchmarks
Use AWS-provided EKS-optimized AMIs (not custom). Apply CIS benchmarks. Keep Kubernetes version current — **unsupported versions = higher control plane fees.**

---

## Level 2: Karpenter & Cost Optimization (Intermediate)

### Karpenter Configuration

| Setting | Best Practice |
|---------|---------------|
| **NodePool count** | Single flexible NodePool often better than many. Multiple only for Spot/OD split or workload isolation |
| **Instance priority** | Spot Graviton → Spot x86 → OD Graviton → OD x86 |
| **Consolidation** | Start with `WhenEmpty` (safe). Graduate to `WhenUnderutilized` after validating |
| **expireAfter** | Enable for periodic node replacement (security patches, drift) |
| **PDBs** | Mandatory for all production workloads before enabling consolidation |
| **Controller** | Run on Fargate or dedicated node group (never on Karpenter-managed nodes) |

**NEVER run Karpenter + Cluster Autoscaler simultaneously.** They conflict on scaling decisions.

### Cost Optimization Stack

| Layer | Tool | Savings |
|-------|------|---------|
| Compute | Spot instances (10+ types diversified) | Up to 90% |
| Right-sizing | VPA, Goldilocks, Kubecost | 30-50% |
| Architecture | Graviton (arm64) nodes | 40% better price-perf |
| Commitment | Compute Savings Plans (baseline) | Up to 66% |
| Storage | gp3 over gp2 for EBS | 20% cheaper |
| Network | VPC endpoints, NodeLocal DNSCache | Reduces cross-AZ data transfer |

Cover baseline with Savings Plans, burst with Spot/Fargate. Tag everything for Kubecost + Cost Explorer visibility.

### Fargate on EKS
- Pay per vCPU/memory. Good for short-term, event-driven, dev/test
- Fargate Spot: 70% off for fault-tolerant workloads
- No node management, no patching, no capacity planning
- Limitations: no DaemonSets, no GPU, no privileged containers

---

## Level 3: Observability & Advanced Patterns (Advanced)

### Observability Stack

| Layer | Tool | Purpose |
|-------|------|---------|
| **Metrics** | Container Insights (Enhanced) | Cluster, node, pod, container metrics. Auto-collects |
| **Metrics** | AMP (Managed Prometheus) + AMG (Managed Grafana) | De facto K8s monitoring. Reduced ops |
| **Traces** | ADOT (EKS Managed Add-on) | Vendor-agnostic. Sends to AMP, CloudWatch, X-Ray |
| **Logs** | Fluent Bit DaemonSet | Lightweight log forwarder. JSON structured logs mandatory |
| **Application** | Application Signals | Auto APM. RED metrics (Requests, Errors, Duration). SLO tracking |

- Container Insights Enhanced mode: control plane + container-level detail
- Amazon Linux 2023: configure Fluent Bit for `systemd-journald`
- Log retention policies + level filtering to manage CW Logs costs
- **Alerting**: SLO-based thresholds, tiered severity, proactive anomaly detection

### Network Policies
- VPC CNI supports Security Groups at pod level
- Network policies for pod-to-pod traffic restriction
- Inbound: only TCP 443 on EKS API server SGs

### Health Probes (Mandatory)
```yaml
livenessProbe: { httpGet: { path: /healthz }, initialDelaySeconds: 15 }
readinessProbe: { httpGet: { path: /ready }, initialDelaySeconds: 5 }
startupProbe: { httpGet: { path: /healthz }, failureThreshold: 30, periodSeconds: 10 }
```
All three probes on every production pod. Startup probe for slow-starting containers.

---

## Performance: Make It Fast

### Optimization Checklist
1. **Karpenter over Cluster Autoscaler** — right-sized nodes, faster scaling, Spot prioritization
2. **Graviton nodes** — 40% better price-perf, Karpenter auto-selects when configured
3. **Resource requests = resource limits** for Guaranteed QoS on critical pods
4. **NodeLocal DNSCache** — reduces cross-AZ DNS traffic, improves resolution latency
5. **Topology-aware routing** — keep traffic within AZ when possible
6. **gp3 EBS volumes** — 20% cheaper, higher baseline IOPS than gp2

### Scaling Speed
- Karpenter: provisions nodes in seconds (vs minutes for Cluster Autoscaler)
- Set appropriate resource requests — over-requesting wastes node capacity, under-requesting causes OOM
- Use HPA (Horizontal Pod Autoscaler) with custom metrics, not just CPU

---

## Observability: Know It's Working

### What to Monitor

| Signal | Metric | Alert Threshold |
|--------|--------|-----------------|
| Pod health | Restart count, CrashLoopBackOff | >3 restarts in 5min |
| Node pressure | `MemoryPressure`, `DiskPressure` | Any = true |
| Scaling | Karpenter provisioning latency | >60s = capacity issue |
| API server | `apiserver_request_duration_seconds` P99 | >1s |
| Costs | Kubecost per-namespace/team | Drift >20% from budget |

- **Container Insights**: enable Enhanced mode for production clusters
- **GuardDuty EKS Runtime Monitoring**: detects reverse shells, crypto mining, privilege escalation. NOT supported on Fargate-for-EKS
- Don't treat nodes as pets — they're cattle. No manual SSH fixes. No baking config into images

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Karpenter + Cluster Autoscaler Together
**You will be tempted to:** Run both "just in case" or during migration
**Why that fails:** Both try to scale nodes. They fight, create duplicates, and waste money
**The right way:** Choose one. Karpenter for new clusters. Migrate existing CAS clusters to Karpenter

### Rule 2: No Node-Level IAM for Pod Access
**You will be tempted to:** Attach IAM policies to the node role because "it's simpler"
**Why that fails:** Every pod on that node gets those permissions. One compromised pod = all permissions leaked
**The right way:** EKS Pod Identity or IRSA. One IAM role per service account. Least privilege per pod

### Rule 3: No Missing Resource Requests
**You will be tempted to:** Skip resource requests/limits because "Kubernetes handles it"
**Why that fails:** Without requests, Karpenter can't right-size nodes. Without limits, one pod can starve others. Pods get BestEffort QoS (first to be evicted)
**The right way:** Set requests = limits for Guaranteed QoS on critical pods. Use VPA/Goldilocks to find right values

### Rule 4: No `latest` Image Tag in Production
**You will be tempted to:** Use `:latest` tag for convenience
**Why that fails:** Non-deterministic deployments. Can't rollback. Can't audit what's running. Different pods may run different versions
**The right way:** Immutable tags (git SHA or semver). `imagePullPolicy: IfNotPresent`

### Rule 5: No Production Without All Three Health Probes
**You will be tempted to:** Skip startup/readiness probes because "liveness is enough"
**Why that fails:** No readiness probe = traffic routes to unready pods. No startup probe = slow-starting containers get killed by liveness probe before they initialize
**The right way:** Liveness (is it alive?), readiness (can it serve?), startup (has it finished initializing?). All three. Every production pod
