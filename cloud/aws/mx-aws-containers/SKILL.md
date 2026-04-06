---
name: mx-aws-containers
description: ECS Fargate task definitions, capacity providers, Service Connect, ECS Express Mode, SOCI lazy loading, ECS Exec, Fargate Spot, Copilot, App Runner EOL, container right-sizing, and AI-generated anti-patterns
---

# AWS Containers — ECS & Fargate for AI Coding Agents

**Load this skill when deploying containerized workloads on ECS, configuring Fargate, or choosing between ECS/EKS/App Runner.**

## When to also load
- `mx-aws-eks` — when deciding ECS vs EKS
- `mx-aws-lambda` — when deciding containers vs Lambda for workload
- `mx-aws-cicd` — ECR image management, CodeDeploy for ECS
- `mx-aws-networking` — awsvpc mode, security groups, load balancers
- `mx-aws-compute` — EC2-backed ECS, capacity providers

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: Container Platform Decision Tree
| Need | Choice | Why |
|------|--------|-----|
| Simplest path (new apps) | **ECS Express Mode** | Auto-provisions everything (replaces App Runner) |
| Serverless containers | **Fargate** (ECS or EKS) | No server management, pay per vCPU/memory |
| GPU / custom hardware | **ECS on EC2** | Direct hardware access |
| Kubernetes required | **EKS** (+ Fargate or EC2) | K8s API compatibility |
| Hybrid / on-prem | **ECS Anywhere** | 2025 extension |

**App Runner EOL:** No new customers after April 30, 2026. Use ECS Express Mode instead.

### Pattern 2: Fargate Task Definition Essentials
| Setting | Best Practice |
|---------|---------------|
| Network mode | `awsvpc` (mandatory — each task gets own ENI + private IP) |
| IAM | Task role (not instance profile). Least privilege per task |
| Secrets | Secrets Manager or SSM Parameter Store, never hardcode |
| CPU/Memory | Pre-approved combinations only. Match vCPU to thread pool size |
| Architecture | Graviton (ARM64) for better price-performance |

### Pattern 3: Capacity Provider Strategy
```json
{
  "capacityProviders": ["FARGATE", "FARGATE_SPOT"],
  "defaultCapacityProviderStrategy": [
    { "capacityProvider": "FARGATE", "base": 1, "weight": 1 },
    { "capacityProvider": "FARGATE_SPOT", "weight": 3 }
  ]
}
```
Base = minimum On-Demand tasks. Weight ratio = 1:3 means 25% OD + 75% Spot. Fargate Spot = up to 70% savings.

### Pattern 4: Enable `initProcessEnabled`
```json
"linuxParameters": { "initProcessEnabled": true }
```
Prevents zombie processes. Always enable on Fargate tasks.

### Pattern 5: Service Connect for Service-to-Service
| BAD | GOOD |
|-----|------|
| Manual DNS/service discovery + custom retry logic | Service Connect (auto DNS, retries, outlier detection) |

Service Connect provides simple DNS names within namespace. Automatic retries + outlier detection built in.

---

## Level 2: ECS Express Mode & Performance (Intermediate)

### ECS Express Mode (Nov 2025)
- Provide container image + IAM roles → auto-provisions: cluster, Fargate task def, ALB, auto-scaling, Route 53, ACM, security groups
- Up to 25 services share 1 ALB (host-header routing). Auto-provisions more beyond 25
- Full control retained — all resources in your account, directly modifiable
- IaC support: CloudFormation, CDK, Terraform
- Default canary deployment. Also supports linear + blue/green
- Deployment lifecycle hooks + CloudWatch alarm-triggered rollbacks

### SOCI (Seekable OCI) — Up to 50% Startup Acceleration
- Lazy loading of container images — don't download entire image before starting
- Creates an index for on-demand layer fetching
- zstd compression: up to 27% additional startup reduction
- Use for large images where startup time matters

### Right-Sizing Fargate Tasks
- Start lean, monitor with CloudWatch. **Compute Optimizer** for recommendations (30-70% savings)
- Match vCPU to thread pool size — don't over-allocate
- Graviton on Fargate: significant price-performance improvement
- Pre-approved CPU/memory combinations only (not arbitrary values)

### Ephemeral Storage
- 20GB default (free), configurable up to 200GB
- Encrypted by default (AES-256). KMS CMK optional
- For tasks needing temporary disk (ML inference, data processing)

---

## Level 3: ECS Exec, Cost & Advanced Patterns (Advanced)

### ECS Exec — SSH-less Container Access
- Uses SSM Session Manager. Console integration (Sep 2025)
- Audit logging to S3/CloudWatch
- VPC endpoints for SSM required in private subnets
- Restrict with IAM condition keys — not for production routine access

### Cost Optimization

| Strategy | Savings | Use Case |
|----------|---------|----------|
| **Fargate Spot** | Up to 70% | Fault-tolerant workloads |
| **Compute Savings Plans** | 20-50% | Steady-state Fargate usage |
| **Graviton** | ~20% | ARM64-compatible workloads |
| **Right-sizing** | 30-70% | Over-provisioned tasks |
| **Hybrid: Fargate + EC2** | Variable | Fargate for bursty, EC2 + RIs for steady |

### Two-Layer Scaling
1. **Service Auto Scaling**: scales task count based on CPU/memory/custom metrics
2. **Capacity Provider**: scales infrastructure (Fargate auto-handles, EC2 needs ASG config)

`target_capacity` 80-90% (not 100%) for EC2 capacity providers — prevents "insufficient CPU units" errors.

---

## Performance: Make It Fast

### Optimization Checklist
1. **SOCI** — lazy image loading for 50% startup acceleration
2. **zstd compression** — 27% additional startup reduction
3. **Graviton instances** — better price-performance, minimal code changes
4. **Multi-stage Docker builds** — smaller images = faster pulls
5. **Right-size tasks** — Compute Optimizer recommendations
6. **Pre-warmed task pattern** — for sub-5s launch requirements
7. **Service Connect** — built-in retries + outlier detection, no custom code

### Image Optimization
- Multi-stage builds (mandatory). Minimize final image layers
- Use AWS base images when possible (pre-cached on Fargate infrastructure)
- SOCI index for large images. Don't bake unnecessary data into images

---

## Observability: Know It's Working

### What to Monitor

| Signal | Metric | Alert Threshold |
|--------|--------|-----------------|
| CPU | `CPUUtilization` per service | >80% sustained = scale out |
| Memory | `MemoryUtilization` per service | >85% = risk of OOM kill |
| Task health | `RunningTaskCount` vs `DesiredTaskCount` | Mismatch >5min = deployment issue |
| Deployments | `DeploymentCount` | >1 for extended period = stuck rollout |
| Spot | Task termination events | Spike = Spot reclamation |

- **Container Insights**: enable for all production clusters. Enhanced mode for container-level detail
- **X-Ray / ADOT**: distributed tracing across services
- **ECS Exec audit logs**: monitor for unauthorized container access

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No App Runner for New Projects
**You will be tempted to:** Use App Runner because it's simpler and appears in tutorials
**Why that fails:** App Runner is EOL for new customers (April 2026). No new features. Migration debt accumulates
**The right way:** ECS Express Mode provides the same simplicity with full ECS power underneath

### Rule 2: No Arbitrary Task Sizing
**You will be tempted to:** Pick 1 vCPU / 2GB memory because "it seems reasonable"
**Why that fails:** Fargate has pre-approved CPU/memory combinations. Wrong combinations fail silently or waste money. Oversized tasks = paying for unused capacity
**The right way:** Start lean, monitor actual usage, use Compute Optimizer. Match vCPU to application thread count

### Rule 3: No Hardcoded Secrets in Task Definitions
**You will be tempted to:** Put database passwords in environment variables in the task definition
**Why that fails:** Task definitions are visible in console, API, and CloudFormation templates. Plaintext credentials in version control
**The right way:** `secrets` block referencing Secrets Manager or SSM Parameter Store

### Rule 4: No Permissive IAM Task Roles
**You will be tempted to:** Use `s3:*` or `Resource: *` on task roles because "it works"
**Why that fails:** Container compromise = unlimited AWS access. ECS tasks are internet-facing; they're a primary attack surface
**The right way:** Specific actions on specific resources. One task role per service. Regularly audit with IAM Access Analyzer

### Rule 5: No x86 on Fargate Without Justification
**You will be tempted to:** Default to x86 architecture because more examples exist
**Why that fails:** Graviton on Fargate provides significant price-performance improvement with minimal code changes. Most container workloads are architecture-independent
**The right way:** `RuntimePlatform: { CpuArchitecture: ARM64 }` by default. Only x86 if you have compiled x86-only dependencies
