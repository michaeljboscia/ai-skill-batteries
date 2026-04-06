---
name: mx-aws-cicd
description: CodeBuild caching/ARM builds, CodePipeline V2 event-driven, CodeDeploy blue-green/canary, ECR image scanning/lifecycle/pull-through cache/cross-account replication, GitHub Actions OIDC integration, and AI-generated anti-patterns
---

# AWS CI/CD — CodePipeline, CodeBuild, ECR for AI Coding Agents

**Load this skill when building CI/CD pipelines, configuring ECR repositories, setting up deployment strategies, or integrating GitHub Actions with AWS.**

## When to also load
- `mx-aws-containers` — ECS deployment strategies, task definitions
- `mx-aws-lambda` — SAM deploy, Lambda versioning/aliases
- `mx-aws-iac` — CDK Pipelines, CloudFormation deploy actions
- `mx-aws-security` — ECR scanning, Secrets Manager for build secrets

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: CodeBuild Cache for Speed
| BAD | GOOD |
|-----|------|
| No build cache (downloads deps every build) | S3 or local cache (50-80% build time reduction) |

### Pattern 2: Immutable ECR Image Tags
| BAD | GOOD |
|-----|------|
| `image:latest` (mutable, non-deterministic) | `image:abc1234` (git SHA) or `image:v1.2.3` (semver) |

Enable tag immutability on ECR repos. Prevents image overwriting. Critical for rollback capability.

### Pattern 3: CodePipeline V2 (Event-Driven)
| BAD | GOOD |
|-----|------|
| CodePipeline V1 (polling for changes) | CodePipeline V2 (event-driven, parallel actions) |

V2 triggers on push events via EventBridge, not polling. Parallel actions within stages for faster pipelines.

### Pattern 4: Pipeline Structure
```
Source → Build → Test → Deploy (staging) → Approval → Deploy (prod)
```
Never skip the approval gate for production. Automatic rollback on CloudWatch alarm triggers.

### Pattern 5: ECR Lifecycle Policies
| BAD | GOOD |
|-----|------|
| Unlimited images accumulate forever | Lifecycle: keep last 10 tagged, delete untagged after 1 day |

Unbounded ECR storage grows silently. Lifecycle policies auto-clean old/untagged images.

---

## Level 2: ECR Deep & Deployment Strategies (Intermediate)

### ECR Image Scanning
- **Amazon Inspector-powered**: scan on push. Detects OS + language package vulnerabilities
- Set severity thresholds in CI: CRITICAL/HIGH = block deployment
- Continuous monitoring: re-scans against updated vulnerability databases
- Security Hub integration for centralized vulnerability view

### ECR Pull-Through Cache
- Mirror Docker Hub / ECR Public into private registry
- Faster pulls, avoids Docker Hub rate limits/throttling
- **ECR-to-ECR cache (March 2025)**: private registry mirroring between accounts
- Supply chain security: local copy for scanning/review before deployment
- Apply lifecycle policies to cached images (they accumulate)

### ECR Cross-Account Replication
- Native support: registry-level config, filter by repo name prefix
- **Only images pushed AFTER config replicate** — pre-existing images don't
- Repository settings (lifecycle, scan, tag mutability) NOT replicated
- Use **repository creation templates** for defaults on new repos created by replication

### Deployment Strategies

| Strategy | Risk | Speed | Use Case |
|----------|------|-------|----------|
| **Rolling** | Medium | Fast | EC2 fleets, non-critical |
| **Blue/Green** | Low | Moderate | ECS (recommended), critical services |
| **Canary** | Lowest | Slow | Production validation, API changes |
| **All-at-once** | Highest | Fastest | Dev/test only |

CodeDeploy blue/green for ECS: automatic rollback on CloudWatch alarms. Linear/canary for gradual traffic shift.

---

## Level 3: GitHub Actions & Advanced (Advanced)

### GitHub Actions + AWS (OIDC)
| BAD | GOOD |
|-----|------|
| IAM user access keys in GitHub Secrets | OIDC federation (short-lived tokens, no static keys) |

OIDC eliminates long-lived credentials entirely. GitHub Actions assumes an IAM role via OpenID Connect. Official `aws-actions/configure-aws-credentials` action.

### GitHub Actions ECR Workflow
```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::${{ACCOUNT}}:role/github-actions
    aws-region: us-east-1
- uses: aws-actions/amazon-ecr-login@v2
- run: docker build -t $ECR_REGISTRY/$ECR_REPO:$GITHUB_SHA .
- run: docker push $ECR_REGISTRY/$ECR_REPO:$GITHUB_SHA
```

### CodeBuild ARM Builds
Use ARM compute types for compatible workloads — cheaper than x86. Multi-arch builds with `docker buildx` for Graviton deployments.

### Build Reports
CodeBuild integrates test reports + code coverage directly into build output. No external tool needed for basic CI metrics.

---

## Performance: Make It Fast

### Pipeline Speed
1. **Build cache** (S3/local) — 50-80% build time reduction
2. **ARM build instances** — cheaper for compatible workloads
3. **Parallel pipeline actions** — V2 supports parallel within stages
4. **Multi-stage Docker builds** — smaller images, faster push/pull
5. **Pull-through cache** — avoid Docker Hub latency/rate limits
6. **ECR in same region** — minimize pull latency for ECS/EKS

### Image Size Optimization
- Multi-stage builds: build deps in stage 1, copy artifacts to minimal runtime in stage 2
- Alpine/distroless base images where possible
- `.dockerignore` for build context minimization
- SOCI index for large images (lazy loading on Fargate)

---

## Observability: Know It's Working

### What to Monitor

| Signal | Metric | Alert Threshold |
|--------|--------|-----------------|
| Build success | CodeBuild `SucceededBuilds` vs `FailedBuilds` | Failure rate > 20% |
| Build duration | CodeBuild `Duration` | Trending up = cache miss or dep bloat |
| Pipeline health | CodePipeline `PipelineExecutionSucceeded` | Any failure = investigate |
| Image vulns | ECR scan findings | CRITICAL/HIGH = block deploy |
| Deployment | CodeDeploy `Healthy` vs `Unhealthy` | Any unhealthy during deploy = rollback |

- **CodePipeline notifications**: SNS on failure/success for each stage
- **ECR scan findings → Security Hub**: centralized vulnerability tracking
- **Build logs**: CloudWatch Logs for debugging failed builds

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Long-Lived Access Keys for CI/CD
**You will be tempted to:** Create IAM user credentials and store in GitHub Secrets
**Why that fails:** Static keys don't expire, can't be automatically rotated, and are the #1 cause of credential leaks in CI/CD
**The right way:** OIDC federation for GitHub Actions. IAM roles for CodeBuild. No static credentials anywhere in the pipeline

### Rule 2: No Mutable Image Tags
**You will be tempted to:** Use `:latest` or `:staging` tags that get overwritten
**Why that fails:** Can't rollback (the tag now points to the broken version). Can't audit what's running. Race conditions in deployments
**The right way:** Immutable tags (git SHA or semver). Enable tag immutability on ECR. `:latest` is for local dev only

### Rule 3: No Deployment Without Automatic Rollback
**You will be tempted to:** Deploy to production without configuring rollback triggers
**Why that fails:** Bad deploys require manual intervention. At 3 AM on Saturday, no one is watching. Error rates climb for hours
**The right way:** CloudWatch alarm triggers on CodeDeploy. Auto-rollback on error rate spike, latency increase, or health check failures

### Rule 4: No ECR Without Lifecycle Policies
**You will be tempted to:** Let images accumulate because "storage is cheap"
**Why that fails:** ECR charges per GB. 100 images × 2GB = 200GB = ~$20/month per repo. Multiply by repos. Plus: old vulnerable images remain pullable
**The right way:** Lifecycle: keep last N tagged images. Delete untagged after 1 day. Delete old tagged after 90 days

### Rule 5: No Direct Docker Hub Pulls in Production
**You will be tempted to:** Pull base images directly from Docker Hub in CI/CD and production
**Why that fails:** Docker Hub rate limits (100 pulls/6hr anonymous, 200 authenticated). CI/CD at scale hits limits. Docker Hub outage = your pipeline stops
**The right way:** ECR pull-through cache. Local copy of all base images. Scanned before use. No external dependency in critical path
