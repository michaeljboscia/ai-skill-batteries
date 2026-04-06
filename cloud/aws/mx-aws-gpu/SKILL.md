---
name: mx-aws-gpu
description: GPU instance selection (P5/P5e/G6/Inf2/Trn1/Trn2), EFA networking for distributed training, ParallelCluster with Slurm, Deep Learning AMIs, Capacity Blocks, FSx Lustre for training data, Neuron SDK for Trainium/Inferentia, and AI-generated anti-patterns
---

# AWS GPU & Accelerated Computing — ML Infrastructure for AI Coding Agents

**Load this skill when provisioning GPU instances, configuring distributed training, deploying inference endpoints, or optimizing ML infrastructure costs.**

## When to also load
- `mx-aws-sagemaker` — SageMaker training/endpoints vs self-managed
- `mx-aws-eks` — GPU node groups, Karpenter for GPU scheduling
- `mx-aws-compute` — Spot instances, placement groups, Graviton for non-GPU tasks
- `mx-aws-storage` — FSx Lustre for training data, S3 for checkpoints

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: GPU Instance Selection Decision Tree

| Workload | Instance | GPU | Why |
|----------|----------|-----|-----|
| LLM training (frontier) | **P5/P5e** | H100/H200 | Highest performance, NVLink, EFA |
| ML training (standard) | **G5** | A10G | Good price-performance for smaller models |
| ML inference (GPU) | **G6** | L4 | Cost-optimized inference |
| ML inference (custom silicon) | **Inf2** | Inferentia2 | Best price-performance for inference |
| ML training (custom silicon) | **Trn1/Trn2** | Trainium1/2 | 50% cheaper than GPU for supported models |

### Pattern 2: EFA Mandatory for Multi-Node Training
| BAD | GOOD |
|-----|------|
| Standard networking for distributed training | EFA (Elastic Fabric Adapter): OS-bypass, low-latency inter-node comm |

EFA provides dedicated network interfaces for GPU-to-GPU communication. Without EFA, multi-node training is bottlenecked by standard TCP networking. **ParallelCluster 3.15+ auto-configures EFA-only NICs.**

### Pattern 3: Placement Groups for Training
| BAD | GOOD |
|-----|------|
| GPU instances across random AZs | Cluster placement group in single AZ |

All training nodes in one AZ, one placement group. Minimizes network latency for collective operations (AllReduce, AllGather).

### Pattern 4: FSx for Lustre for Training Data
| BAD | GOOD |
|-----|------|
| EBS or S3 direct access for training data | FSx for Lustre: sub-ms latency, millions IOPS, S3 integration |

FSx Lustre is the standard for ML training data access. EFA + GPUDirect Storage = up to 1,200 Gbps on P5. S3 integration for lazy loading. SCRATCH_2 for temporary data (cheaper).

### Pattern 5: Deep Learning AMIs
| BAD | GOOD |
|-----|------|
| Custom AMI with manual CUDA/driver installation | AWS DLAMI: pre-installed PyTorch/TensorFlow, CUDA, cuDNN, EFA |

DLAMIs save hours of setup. Amazon Linux + Ubuntu options. Optimized for accelerated compute instances. Use custom bootstrap actions for additional packages (not custom AMIs for every release).

---

## Level 2: ParallelCluster & Trainium (Intermediate)

### ParallelCluster + Slurm Architecture

| Component | Configuration |
|-----------|--------------|
| **Head node** | Sufficient compute + network for orchestration (not GPU) |
| **Compute queues** | GPU instances with EFA. Cluster placement group |
| **Storage** | FSx Lustre (shared training data) + EFS (shared home dirs) |
| **Containers** | Enroot + Pyxis for containerized workloads |
| **Cost** | `MinCount: 0` (pay only when jobs running) + Spot for fault-tolerant |

### Enroot Container Configuration
- `ENROOT_RUNTIME_PATH` + `ENROOT_DATA_PATH`: local storage (fast)
- `ENROOT_CACHE_PATH`: shared storage (EFS/Lustre) for caching
- Include `userId` in cache path to prevent permission issues

### GPU Health Checks
ParallelCluster supports auto-health-checks on compute nodes before job initiation. Terminates unhealthy GPU nodes and provisions replacements. Essential with Capacity Blocks.

### Capacity Blocks for ML
- Reserve GPU instances for specific durations (guaranteed capacity)
- ParallelCluster 3.8+ integration: Slurm launches jobs when reserved capacity activates
- Use for: critical training jobs, deadlines, demo preparations

### Trainium & Inferentia (Neuron SDK)

| Chip | Use Case | Key Advantage |
|------|----------|---------------|
| **Trainium (Trn1/Trn2)** | Training | 50% cheaper than comparable GPU |
| **Inferentia2 (Inf2)** | Inference | Best price-performance for inference |

- **Neuron SDK**: compiler + runtime for Trainium/Inferentia. PyTorch integration via `torch_neuronx`
- Not all model architectures supported — verify compatibility before committing
- NeuronCore Pipeline: model parallelism across NeuronCores on single instance

---

## Level 3: Distributed Training & Inference Patterns (Advanced)

### Distributed Training Strategies

| Strategy | When | Scale |
|----------|------|-------|
| **Data Parallel** | Same model fits in one GPU | Multiple nodes, each has full model |
| **Model Parallel** | Model too large for one GPU | Model split across GPUs/nodes |
| **Pipeline Parallel** | Very deep models | Model layers split by pipeline stage |
| **Expert Parallel** | MoE models | Experts distributed across GPUs |

### Distributed Training Checklist
1. EFA enabled on all compute nodes
2. Cluster placement group in single AZ
3. FSx Lustre for data + checkpoints
4. Checkpoint every 5-30 minutes
5. Unique checkpoint paths per rank (prevent overwrites)
6. NCCL environment variables tuned for instance type
7. GPU health checks before job start

### Distributed Inference Options

| Approach | Best For |
|----------|----------|
| **SageMaker endpoints** | Managed, auto-scaling, multi-model |
| **EKS + DLCs** | Kubernetes-native, custom serving |
| **ParallelCluster** | Batch/HPC inference, research |
| **vLLM containers** | LLM serving on EC2/ECS/EKS |
| **Lambda** | Lightweight models only |

- vLLM + EFA for multi-node LLM inference
- FSx Lustre for fast model loading across inference nodes

---

## Performance: Make It Fast

### Training Performance
1. **EFA + placement groups** — mandatory for multi-node. Without EFA, GPU utilization drops to 30-50%
2. **FSx Lustre** — data loading shouldn't be the bottleneck
3. **Right-size instances** — match GPU memory to model size. Over-provisioning wastes $/GPU-hour
4. **Mixed precision training** — FP16/BF16 for 2x throughput (most frameworks support natively)
5. **Gradient accumulation** — simulate larger batch sizes without more GPU memory
6. **NCCL tuning** — instance-specific environment variables for collective operations

### Inference Performance
- **Inferentia2** for best price-performance on supported models
- **Model compilation** (Neuron, TensorRT) for hardware-optimized inference
- **Batching** — dynamic batching for throughput optimization
- **Quantization** — INT8/FP8 for reduced memory + faster inference

---

## Observability: Know It's Working

### What to Monitor

| Signal | Metric | Alert Threshold |
|--------|--------|-----------------|
| GPU utilization | `nvidia-smi` / DCGM metrics | <50% sustained = bottleneck elsewhere |
| GPU memory | `gpu_memory_used` | >90% = risk of OOM |
| Training loss | Custom metric per epoch | Plateauing = learning rate/architecture issue |
| Checkpoint health | Checkpoint write latency | >5min = storage bottleneck |
| EFA throughput | Network bytes in/out | Below expected bandwidth = EFA misconfiguration |
| Spot interruption | Instance termination notices | Any = verify checkpoint recency |

- **NVIDIA DCGM** (Data Center GPU Manager): detailed GPU metrics beyond `nvidia-smi`
- **Neuron Monitor**: Trainium/Inferentia metrics (NeuronCore utilization, memory)
- **Slurm accounting**: per-job resource usage, queue wait times, fairshare

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Multi-Node Training Without EFA
**You will be tempted to:** Use standard networking for distributed training "to simplify setup"
**Why that fails:** GPU utilization drops to 30-50% without EFA. Network becomes the bottleneck for collective operations. Training takes 2-3x longer, costing MORE than the EFA setup effort
**The right way:** EFA enabled on all compute nodes. Cluster placement group. ParallelCluster auto-configures EFA-only NICs (3.15+)

### Rule 2: No EBS for Shared Training Data
**You will be tempted to:** Use EBS volumes because they're familiar
**Why that fails:** EBS is per-instance. Can't share across nodes. Limited throughput for large-scale data loading. Becomes the training bottleneck
**The right way:** FSx for Lustre for shared training data (sub-ms latency, millions IOPS). S3 for checkpoint persistence. SCRATCH_2 for temporary data

### Rule 3: No Custom AMIs for Every Update
**You will be tempted to:** Build custom AMIs with your framework + CUDA versions
**Why that fails:** AMI builds take 30+ minutes. Every CUDA update = new AMI. Version management nightmare. Falls out of date with security patches
**The right way:** AWS DLAMIs as base. Custom bootstrap actions for additional packages. Container-based workloads (Enroot) for maximum reproducibility

### Rule 4: No Trainium Without Compatibility Check
**You will be tempted to:** Use Trainium because it's 50% cheaper than GPU
**Why that fails:** Not all model architectures are supported by Neuron SDK. Custom operators may need reimplementation. Debugging on custom silicon is harder
**The right way:** Verify model compatibility with Neuron SDK before committing. Test on Trn1 instance. Benchmark against GPU equivalent. Trainium excels for supported architectures

### Rule 5: No GPU Training Without Checkpointing
**You will be tempted to:** Skip checkpointing for "short" training runs
**Why that fails:** GPU instance hours are expensive ($3-100+/hr). One interruption (Spot, hardware failure, bug) = all progress lost. "Short" training runs become long when debugging
**The right way:** Checkpoint to S3 every 5-30 minutes. Resume from checkpoint on restart. Tiered checkpointing (CPU memory + S3) for fastest recovery on HyperPod
