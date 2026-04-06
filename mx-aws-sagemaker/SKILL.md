---
name: mx-aws-sagemaker
description: SageMaker training jobs, distributed training (SMDDP/SMP), Spot instances with checkpointing, managed warm pools, HyperPod tiered checkpointing, inference endpoints, Pipelines MLOps, Model Monitor drift detection, Model Registry, and AI-generated anti-patterns
---

# AWS SageMaker — ML Platform for AI Coding Agents

**Load this skill when training ML models, deploying inference endpoints, building ML pipelines, or implementing MLOps practices.**

## When to also load
- `mx-aws-gpu` — GPU instance selection, ParallelCluster for HPC training
- `mx-aws-bedrock` — when deciding Bedrock (managed models) vs SageMaker (custom models)
- `mx-aws-storage` — S3 for training data/model artifacts, FSx Lustre for high-throughput
- `mx-aws-billing` — SageMaker Savings Plans, Spot cost optimization

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: Spot Instances for Training
| BAD | GOOD |
|-----|------|
| On-Demand for all training jobs | Spot instances (up to 90% savings) + checkpointing |

Spot = massive savings for fault-tolerant training. **Must** checkpoint every 5-30 minutes to S3.

### Pattern 2: Checkpoint Every Training Job
| BAD | GOOD |
|-----|------|
| No checkpointing (lose all progress on interruption) | S3 checkpoints every 5-30 min + resume from last checkpoint |

Non-negotiable for Spot. Critical for any training job >1 hour. For distributed training: manually configure checkpoint file names/paths to prevent overwrites.

### Pattern 3: SageMaker Pipelines for MLOps
| BAD | GOOD |
|-----|------|
| Manual notebook-based training + deployment | SageMaker Pipelines: automated, reproducible, auditable |

Pipeline structure: Data Processing → Training → Evaluation → Model Registry → Deployment. Use `PipelineSession` for lazy loading.

### Pattern 4: Model Registry for Governance
| BAD | GOOD |
|-----|------|
| Models in random S3 buckets | Model Package Groups with metadata, approval workflows, Model Cards |

Version all models. Store training data versions, hyperparameters, metrics. Enforce approval workflow before production deployment.

### Pattern 5: Model Monitor in Production
| BAD | GOOD |
|-----|------|
| Deploy and forget | Model Monitor: continuous data quality, model quality, bias drift detection |

Auto-trigger retraining pipelines on drift detection. Models degrade silently without monitoring.

---

## Level 2: Training Optimization & Endpoints (Intermediate)

### Distributed Training

| Library | Purpose | Scale |
|---------|---------|-------|
| **SMDDP** (Data Parallel) | Same model, distributed data | Moderate scale |
| **SMP v2** (Model Parallel) | Model split across GPUs | Billion+ parameters |
| **HyperPod** | Large-scale with auto-recovery | Foundation model training |

### HyperPod Tiered Checkpointing (Sep 2025 GA)
- **CPU memory tier**: fast recovery checkpoints (seconds to resume)
- **S3 tier**: durable long-term checkpoints
- Integrated with PyTorch DCP (Distributed Checkpoint). Minimal code changes
- Reduces training loss from infrastructure failures

### Managed Warm Pools
- Retain training infrastructure up to **4 weeks** between consecutive jobs
- Eliminates startup latency for active experimentation
- **Default limit is 0** — must request service limit increase
- Best for rapid iteration: hyperparameter tuning, model experimentation

### Inference Endpoints

| Type | Use Case | Scaling |
|------|----------|---------|
| **Real-time** | Low-latency predictions | Auto-scaling on InvocationsPerInstance |
| **Serverless** | Intermittent traffic | Scale to zero, pay per invocation |
| **Async** | Large payloads, long processing | Queue-based, SNS notification on complete |
| **Batch Transform** | Bulk predictions on datasets | One-time, cost-effective batch processing |

### Spot Training Best Practices
- `max_wait` >= 2x `max_run` (allow time for Spot availability)
- Checkpoint every 5-30 min to S3
- Choose instance types with good Spot availability (check Spot Instance Advisor)
- Monitor interruptions and cost savings

---

## Level 3: MLOps & Advanced (Advanced)

### MLOps Architecture
- **Multi-account**: experiment → dev → staging → prod (separate accounts)
- **Security**: private VPC, no public internet, KMS encryption on all data
- **CI/CD**: SageMaker Projects with MLOps templates for automated build/deploy
- **Experiment tracking**: SageMaker Experiments + MLflow for inputs/outputs/metrics
- **Reproducibility**: version data, configs, models, scripts. Model Cards for documentation

### SageMaker Pipelines Best Practices
- `PipelineSession` for lazy resource loading
- **Local mode** for development (smaller datasets, faster iteration)
- Run in private VPC with IAM least privilege
- Integrate with Experiments for automatic tracking
- Standardized environments via SageMaker Projects

### Cost Optimization

| Strategy | Savings | Applies To |
|----------|---------|------------|
| **Spot instances** | Up to 90% | Training |
| **SageMaker Savings Plans** | Up to 64% | Steady-state inference |
| **Serverless endpoints** | Pay per invocation | Intermittent inference |
| **Managed warm pools** | Reduced startup | Rapid experimentation |
| **Right-sizing** | 30-50% | Over-provisioned endpoints |

---

## Performance: Make It Fast

### Training Speed
1. **Distributed training** (SMDDP/SMP) — scale across GPUs/nodes
2. **HyperPod** — auto-recovery from failures, tiered checkpointing
3. **Spot + checkpointing** — cost-effective long training
4. **Warm pools** — eliminate startup latency between experiments
5. **FSx for Lustre** — high-throughput training data access
6. **Right-size instances** — match GPU/memory to model requirements

### Inference Latency
- Auto-scaling: target-tracking on `InvocationsPerInstance`
- Multi-model endpoints: serve multiple models from one endpoint
- Model compilation (SageMaker Neo) for hardware-optimized inference
- Inference Recommender for instance type selection

---

## Observability: Know It's Working

### What to Monitor

| Signal | Metric | Alert Threshold |
|--------|--------|-----------------|
| Training health | `train:loss` convergence | Plateauing = learning rate issue |
| Spot interruption | `SpotInstanceInterruptions` | Check checkpoint recency |
| Endpoint latency | `ModelLatency` P99 | >SLA for real-time |
| Endpoint errors | `Invocation4XXErrors`, `5XXErrors` | >1% error rate |
| Model drift | Model Monitor findings | Any drift = investigate retraining |
| Cost | Per-endpoint/training job cost | Trending above budget |

- **Model Monitor**: schedule daily/weekly quality checks. Auto-alert on drift
- **Training job logs**: CloudWatch for loss curves, GPU utilization
- **Endpoint auto-scaling metrics**: track scaling events and invocation patterns

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Training Without Checkpointing
**You will be tempted to:** Skip checkpointing because "the job will finish"
**Why that fails:** Spot interruptions, infrastructure failures, and bugs all lose hours/days of training progress. Even On-Demand jobs can fail
**The right way:** Checkpoint every 5-30 min to S3. Resume from last checkpoint on restart. Non-negotiable

### Rule 2: No Production Models Without Monitoring
**You will be tempted to:** Deploy a model and move on to the next project
**Why that fails:** Model accuracy degrades silently as data distribution shifts. By the time customers complain, the model has been wrong for weeks
**The right way:** Model Monitor for data quality + model quality + bias drift. Auto-trigger retraining pipelines

### Rule 3: No Notebook-Based Production Training
**You will be tempted to:** Train production models in SageMaker Studio notebooks
**Why that fails:** Not reproducible, not version-controlled, not automated, not auditable. "It worked on my notebook" is the ML equivalent of "it works on my machine"
**The right way:** SageMaker Pipelines. Parameterized, versioned, automated, with approval gates

### Rule 4: No Over-Provisioned Endpoints
**You will be tempted to:** Pick a large instance for inference "just in case"
**Why that fails:** ml.p3.2xlarge at $3.825/hr vs ml.g5.xlarge at $1.006/hr. If the smaller instance handles your load, you're wasting $2,000+/month per endpoint
**The right way:** SageMaker Inference Recommender. Load test different instance types. Auto-scale based on actual utilization

### Rule 5: No Single-Account MLOps
**You will be tempted to:** Train, test, and deploy models in the same AWS account
**Why that fails:** No isolation between experiments and production. Accidental data access. Service limit conflicts. No clear promotion path
**The right way:** Multi-account: experiment/dev → staging → production. Model Registry for cross-account promotion with approval workflows
