---
name: mx-gcp-gke
description: Use when creating GKE clusters, managing node pools, configuring Workload Identity, planning pod/service IP ranges, deploying workloads, or optimizing GKE costs. Also use when the user mentions 'gcloud container clusters', 'GKE', 'Autopilot', 'node pool', 'Workload Identity', 'kubectl', 'helm', 'pod CIDR', 'service CIDR', 'private cluster', 'cluster autoscaler', 'HPA', 'VPA', 'readiness probe', 'liveness probe', 'rolling update', 'Spot node pool', 'Binary Authorization', 'Network Policy', or 'Pod Security Admission'.
---

# GKE — Kubernetes Engine for AI Coding Agents

**This skill loads when you're creating or managing GKE clusters and workloads.**

## When to also load
- `mx-gcp-iam` — Workload Identity, service account binding
- `mx-gcp-networking` — VPC, subnets, secondary ranges, Cloud NAT, DNS
- `mx-gcp-security` — **ALWAYS load** — Binary Authorization, CMEK for etcd, VPC-SC for cluster isolation, Shielded GKE Nodes, Secret Manager
- `mx-gcp-compute` — Machine types for node pools

---

## Level 1: Cluster Creation (Beginner)

### Autopilot vs Standard decision

| Factor | Autopilot | Standard |
|--------|-----------|----------|
| Node management | Google manages | You manage |
| Billing | Per pod resource request | Per node VM |
| Security defaults | All enforced (WI, shielded, etc.) | You must enable |
| SSH to nodes | No | Yes |
| Privileged containers | No | Yes |
| GPUs/TPUs | Supported (with limits) | Full control |
| Best for | Most workloads, new projects | Specialized needs, GPU, custom nodes |

```bash
# Autopilot (recommended default)
gcloud container clusters create-auto my-cluster \
  --region=us-east1 \
  --network=my-vpc --subnetwork=gke-subnet

# Standard with Workload Identity
gcloud container clusters create my-cluster \
  --region=us-east1 \
  --num-nodes=3 --machine-type=n2-standard-4 \
  --workload-pool=my-project.svc.id.goog \
  --enable-shielded-nodes \
  --enable-ip-alias \
  --network=my-vpc --subnetwork=gke-subnet \
  --cluster-secondary-range-name=pods \
  --services-secondary-range-name=services \
  --no-enable-basic-auth \
  --enable-network-policy
```

### Workload Identity setup

```bash
# 1. Create Google SA
gcloud iam service-accounts create gke-app-sa \
  --display-name="GKE App Service Account"

# 2. Grant GCP permissions to the Google SA
gcloud projects add-iam-policy-binding my-project \
  --member="serviceAccount:gke-app-sa@my-project.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"

# 3. Bind KSA to GSA
gcloud iam service-accounts add-iam-policy-binding \
  gke-app-sa@my-project.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:my-project.svc.id.goog[my-namespace/my-ksa]"

# 4. Annotate Kubernetes SA
kubectl annotate serviceaccount my-ksa \
  --namespace=my-namespace \
  iam.gke.io/gcp-service-account=gke-app-sa@my-project.iam.gserviceaccount.com
```

---

## Level 2: IP Planning & Node Pools (Intermediate)

### GKE IP ranges (3 required)

| Range | Purpose | Recommended size | Notes |
|-------|---------|------------------|-------|
| Node (primary) | VM IPs | `/20` (4K nodes) | From subnet primary range |
| Pod (secondary) | Pod IPs | `/14` (250K pods) | Default 110 pods/node = /24 per node |
| Service (secondary) | ClusterIP IPs | `/20` (4K services) | Virtual, can reuse across clusters |

```bash
# Create subnet with secondary ranges for GKE
gcloud compute networks subnets create gke-subnet \
  --network=my-vpc --region=us-east1 \
  --range=10.0.0.0/20 \
  --secondary-range=pods=10.4.0.0/14,services=10.8.0.0/20 \
  --enable-private-ip-google-access
```

**Pod IP waste:** Default 110 max-pods-per-node allocates /24 (256 IPs) per node. If your pods use 20-30 per node, set `--max-pods-per-node=32` to allocate /26 (64 IPs) instead.

### Spot node pools

```bash
gcloud container node-pools create batch-spot \
  --cluster=my-cluster --region=us-east1 \
  --machine-type=e2-standard-4 \
  --spot --min-nodes=0 --max-nodes=10 \
  --enable-autoscaling
```

- Auto-taint: `cloud.google.com/gke-spot=true:NoSchedule`
- Pods need toleration + nodeSelector/affinity to schedule on Spot
- `terminationGracePeriodSeconds` ≤ 25 (30s preemption window minus overhead)
- Always keep an on-demand pool for critical services

### Private cluster

```bash
gcloud container clusters create my-cluster \
  --region=us-east1 \
  --enable-private-nodes --enable-private-endpoint \
  --master-ipv4-cidr=172.16.0.0/28 \
  --enable-ip-alias \
  --network=my-vpc --subnetwork=gke-subnet
```

**Private cluster access:** Use IAP tunnel or DNS endpoint. Cloud NAT required for node internet access.

---

## Level 3: Deployments, Probes & Autoscaling (Advanced)

### Resource requests and limits

```yaml
resources:
  requests:
    cpu: "250m"      # Scheduling guarantee
    memory: "512Mi"  # Scheduling guarantee
  limits:
    cpu: "1000m"     # Optional — causes throttling if set
    memory: "512Mi"  # MUST equal requests (GKE recommendation)
```

**GKE rule:** Set memory requests = memory limits to avoid OOMKill under pressure. CPU limits are optional — they cause throttling.

### Probes — the right way

```yaml
# Liveness: is the process alive? (restarts if failing)
livenessProbe:
  httpGet:
    path: /healthz    # Internal check ONLY — no external deps
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 3

# Readiness: can it serve traffic? (removes from LB if failing)  
readinessProbe:
  httpGet:
    path: /ready       # Can check critical deps here
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
  failureThreshold: 3
  successThreshold: 2   # Must pass 2x before receiving traffic
```

**Probe rules:**
- Liveness checks process health ONLY — never check DB/Redis (causes cascading restarts)
- Readiness checks if app can serve — can check critical deps
- `initialDelaySeconds` > app startup time (prevents CrashLoopBackOff)

### Zero-downtime rolling update

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0    # Never reduce capacity
      maxSurge: 1           # Add 1 new pod at a time
  template:
    spec:
      terminationGracePeriodSeconds: 30
      containers:
      - name: app
        lifecycle:
          preStop:
            exec:
              command: ["sleep", "5"]  # Allow LB deregistration
```

### Autoscaling stack

| Layer | What it scales | Metric | Avoid |
|-------|---------------|--------|-------|
| HPA | Pod count | CPU, custom metrics | Don't use same metric as VPA |
| VPA | Pod requests/limits | Historical usage | Not for JVM; start in recommendation mode |
| CA | Node count | Pending pods | Set optimize-utilization profile |
| NAP | Node pool creation | Pending pod requirements | — |

```bash
# Enable VPA on existing cluster
gcloud container clusters update my-cluster \
  --region=us-east1 --enable-vertical-pod-autoscaling

# Enable NAP
gcloud container clusters update my-cluster \
  --region=us-east1 --enable-autoprovisioning \
  --min-cpu=1 --max-cpu=100 --min-memory=1 --max-memory=400
```

---

## Performance: Make It Fast

- **Pod startup:** Use distroless/slim images. Avoid downloading at startup. Preload via init containers.
- **Scheduling:** Set `topologySpreadConstraints` to distribute pods across zones (reduces cross-zone latency).
- **Bin packing:** Use `optimize-utilization` autoscaler profile to reduce idle nodes (~20% savings).
- **Image pull:** Use Artifact Registry in same region. Enable image streaming for large images.

---

## Observability: Know It's Working

```bash
# Check cluster health
gcloud container clusters describe my-cluster --region=us-east1 --format="yaml(status)"

# Check node pool autoscaling events
kubectl get events --sort-by=.metadata.creationTimestamp | grep -i scale

# Check pod resource usage vs requests
kubectl top pods --all-namespaces --sort-by=cpu
```

### What to alert on

| Event | Severity |
|-------|----------|
| Pending pods (CA can't find capacity) | **HIGH** |
| OOMKilled pods | **HIGH** |
| CrashLoopBackOff | **HIGH** |
| Node not ready | **MEDIUM** |
| Spot node preemption rate >20% | **MEDIUM** |
| VPA recommending >2x current request | **INFO** |

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Use Autopilot unless you have a specific reason not to
**You will be tempted to:** Create a Standard cluster because "I want more control" or "that's what the tutorial showed."
**Why that fails:** Standard clusters require you to manage node upgrades, security patches, node pool sizing, and Workload Identity setup — all of which Autopilot handles automatically. You pay for idle node capacity. Most workloads don't need privileged containers or SSH.
**The right way:** Start with Autopilot. Switch to Standard only if you need GPUs, privileged containers, DaemonSets, or custom node configurations.

### Rule 2: Never skip Workload Identity
**You will be tempted to:** Mount a SA key JSON file as a Kubernetes secret because "it's simpler."
**Why that fails:** SA key files are long-lived credentials that can be stolen, copied, and used from anywhere. They don't rotate automatically and create a persistent security risk.
**The right way:** Enable Workload Identity (`--workload-pool`), bind KSA to GSA, and use the annotation. Zero keys, short-lived tokens, IAM-governed.

### Rule 3: Never deploy without resource requests
**You will be tempted to:** Omit `resources.requests` because "I don't know what to set."
**Why that fails:** Pods without requests are BestEffort QoS — first to be evicted. The scheduler can't make good decisions. VPA and HPA can't function. Cost attribution is impossible.
**The right way:** Set requests based on actual usage (use VPA in recommendation mode for 1 week first). Set memory limits = requests. CPU limits optional.

### Rule 4: Liveness probes must not check external dependencies
**You will be tempted to:** Add a database ping to your liveness probe because "the app is useless without the DB."
**Why that fails:** If the DB has a brief hiccup, ALL pods restart simultaneously. The restart storm makes the DB problem worse. This is the #1 cause of cascading failures in K8s.
**The right way:** Liveness checks the process only (`/healthz` returns 200 if the process is running). Readiness checks if the app can serve (`/ready` can check critical deps). If DB is down, pods stop receiving traffic but don't restart.

### Rule 5: Plan pod CIDR generously — you can't shrink it
**You will be tempted to:** Use a /20 for pod CIDR because "we only have 10 pods."
**Why that fails:** GKE allocates a /24 per node by default (110 max pods). With a /20 pod CIDR, you can only have 16 nodes before exhausting IPs. Expanding pod CIDR later requires careful migration.
**The right way:** Use /14 for pods (250K IPs). IP space is free inside GCP. Use non-RFC 1918 ranges (100.64.0.0/10) to avoid conflicts with other networks. Set `--max-pods-per-node` to match actual usage.
