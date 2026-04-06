# GPU Inference Enforcement

## Universal Gate: Cost Control (ALWAYS FIRES)

### Rule 0: No GPU Spend Without a Plan
Before provisioning ANY GPU resources, answer these five questions. If any answer is "I don't know," STOP and plan first.

1. **What model, at what quantization, on how many of which GPU?** (e.g., "Gemma 3 27B, FP8, 1x L4")
2. **What is the total cost per hour?** (GPU + VM + disk)
3. **What is the expected runtime?** (e.g., "2 hours for 10K samples")
4. **What is the total estimated cost?** (hourly × runtime)
5. **Is this a known, pre-approved deployment pattern?** (exists in deepseek-batch README, prior session log, or documented config)

**If the pattern is NEW (not pre-existing):**
- MUST run through `model-sizing` tier calculations first
- MUST benchmark on 100 samples before scaling
- MUST get user confirmation on estimated total cost
- MUST define success criteria and kill conditions (e.g., "stop after $50 or 4 hours")

**Pre-approved patterns (skip planning, just execute):**
- DeepSeek-R1-32B on 4x T4 spot (deepseek-batch README, ~$0.54/hr)
- [Add more as they're proven]

**You will be tempted to:** "Let me just spin up 8x H100s real quick to try this model."
**Why that fails:** 8x H100 spot = $26.96/hr GPU-only. A 4-hour "let me try" session costs $108+ before you've verified the model even fits. At that rate, "funsies" costs more per day than some people's rent.

**The right way:** Calculate → Confirm → Provision → Monitor → Kill when done. Every GPU minute has a price tag. Say the price tag out loud before starting.

---

## Tier: model-selection

### Rule 1: Match Model Architecture to Workload
Different tasks need different models. Don't default to "the biggest one."

| Workload | Best Models (March 2026) | Why |
|----------|------------------------|-----|
| Coding & agentic | DeepSeek-R1, Mistral Small 4 (6B active), Qwen 3.5 Coder 32B | R1 chain-of-thought for complex logic; Small 4 for fast tool-calling |
| Reasoning & math | DeepSeek-R1, Phi-4-reasoning 14B, Gemma 3 27B | R1 thinks before generating; Phi-4 punches above weight; Gemma 89% MATH |
| General purpose & RAG | Llama 4 Scout (10M context), Gemma 3 27B (128k) | Scout for massive context; Gemma for single-GPU daily driver |
| Batch inference (cost) | DeepSeek-R1-Distill-32B, Gemma 3 27B | Best quality-per-VRAM-dollar |

**You will be tempted to:** "Just run DeepSeek-V3 671B for everything."
**Why that fails:** 671B MoE requires 150-350GB VRAM (4-8x H100). If your workload is batch email scoring, a 32B model at $0.72/hr on spot A100 does the same job at 1/40th the cost.

**The right way:** Start with the smallest model that meets quality requirements. Benchmark on 100 samples before scaling. Move up only if quality is measurably insufficient.

### Rule 2: MoE Models Need Total VRAM, Not Active VRAM
Mixture-of-Experts models (DeepSeek V3, Llama 4 Scout/Maverick, Mistral Small 4) activate only a fraction of parameters per token, but ALL parameters must fit in VRAM.

| Model | Total Params | Active Params | VRAM Needed (4-bit) |
|-------|-------------|---------------|-------------------|
| Mistral Small 4 | 119B | 6B | 64-80 GB |
| Llama 4 Scout | 109B | 17B | 64-80 GB |
| DeepSeek V3 | 671B | 37B | 150-350 GB |

**You will be tempted to:** "Mistral Small 4 only activates 6B params — should fit on a 16GB card."
**Why that fails:** All 119B parameters must be loaded into VRAM. The 6B active figure only determines compute cost and speed, not memory.

---

## Tier: model-sizing

### Rule 3: Calculate VRAM Before Provisioning — Never Guess
Always compute exact VRAM requirements before requesting GPU resources.

**Formula:**
```
Total VRAM = Model_Weights + KV_Cache + CUDA_Overhead (2GB)

Model_Weights = Parameters × Bytes_per_precision
  FP16: 2 bytes | FP8: 1 byte | INT4/AWQ: ~0.6 bytes

KV_Cache_per_token = 2 × Layers × KV_Heads × Head_Dim × KV_Precision_Bytes
Total_KV = KV_per_token × Context_Length × Batch_Size
```

**Quick reference (inference, single user, 4k context):**

| Model Size | FP16 | FP8 | AWQ 4-bit |
|-----------|------|-----|-----------|
| 7B | 14 GB | 8 GB | 4 GB |
| 14B | 28 GB | 16 GB | 8 GB |
| 32B | 64 GB | 36 GB | 18 GB |
| 70B | 140 GB | 70 GB | 35 GB |
| 405B | 810 GB | 405 GB | 200 GB |

**You will be tempted to:** "It's a 70B model and I have 80GB — should fit."
**Why that fails:** 70B at FP8 = 70GB weights + KV cache + CUDA overhead. At 128k context with 4 concurrent users, KV cache alone is 80+ GB. You need 2-4 GPUs, not 1.

**The right way:** Always calculate KV cache for your actual max concurrency and context length. Add 10% headroom. Then pick GPU count.

### Rule 4: Choose Quantization by Hardware Generation
Your GPU's silicon determines the best quantization format.

**Decision tree:**
1. **Hopper/Blackwell (H100, H200, B200)** → **FP8** (native silicon, zero quality loss, just pass `--quantization fp8` in vLLM)
2. **Ada Lovelace (L40S, RTX 4090)** → **FP8** (native support)
3. **Ampere (A100)** → **INT8** (safe) or **AWQ 4-bit** with Marlin kernels (if VRAM constrained)
4. **Turing/older (T4, V100)** → **AWQ/GPTQ 4-bit** or **GGUF** (no FP8 silicon)
5. **CPU / Apple Silicon** → **GGUF** via llama.cpp (always)

**Quality benchmarks:**
- FP8/INT8: <0.1% MMLU drop (indistinguishable from FP16)
- AWQ 4-bit: ~0.4% drop (excellent for production, Marlin kernel eliminates unpacking tax)
- GGUF Q4_K_M: ~0.5% drop (mixed-precision layers preserve quality)

**Key insight:** Models >30B are highly resilient to quantization. A 70B at 4-bit hallucinates less than a 14B at FP16.

### Rule 5: Size System RAM Correctly — The Old 2:1 Ratio Is Dead
With safetensors + mmap, system RAM can be LOWER than GPU VRAM.

**Formula:**
```
System RAM = OS/Framework (16-32 GB)
           + Model Loading Buffer (0 with safetensors mmap, 1.2x model size with legacy .bin)
           + vLLM KV Swap Space (default 4GB is dangerously small!)
```

**Critical:** vLLM's default `--swap-space 4` means only 4GB of CPU RAM for swapping preempted KV caches. A single 128k-context user's KV cache is ~40GB. Set `--swap-space` explicitly to match your actual concurrency needs.

**You will be tempted to:** "The machine has 192GB RAM, that's plenty."
**Why that fails:** If 180GB is sitting idle because vLLM's swap is capped at 4GB, you're paying for RAM the inference engine ignores.

---

## Tier: model-serving

### Rule 6: Choose Serving Framework by Use Case — Not by Familiarity

| Use Case | Framework | Why |
|----------|-----------|-----|
| Production API, multi-user, cloud GPUs | **vLLM** | PagedAttention, native TP, 800+ tok/s at 10+ users, OpenAI-compatible |
| Local dev, prototyping, single-user | **Ollama** | 60-second setup, zero config |
| Edge, CPU, Apple Silicon, offline | **llama.cpp** | GGUF quantization, runs anywhere |
| Long-context RAG with prefix caching | **TGI v3** | 13x faster than vLLM for cached 200k+ prompts (but maintenance mode) |

**You will be tempted to:** "Ollama works great locally, let's deploy it to the cloud GPU."
**Why that fails:** On 2026-03-04, Ollama on 4x T4 was slower than independent small models. Ollama's multi-GPU is layer splitting (sequential), not tensor parallelism (parallel). Under 5+ concurrent users, it plateaus at ~150 tok/s total while vLLM hits 800+.

**The right way for production:**
```bash
vllm serve <model-id> \
  --tensor-parallel-size <num_gpus> \
  --quantization fp8 \
  --gpu-memory-utilization 0.90 \
  --max-model-len <actual_business_need> \
  --swap-space <calculated_from_concurrency>
```

### Rule 7: Verify GPU Topology Before Choosing Parallelism Strategy
Run `nvidia-smi topo -m` BEFORE configuring multi-GPU. The topology determines what works.

| Topology Output | Meaning | Strategy |
|----------------|---------|----------|
| `NV#` (NV12, NV18) | NVLink connected | Tensor Parallelism (TP) — fast |
| `PHB` | Same PCIe switch, no NVLink | Pipeline Parallelism (PP) — acceptable |
| `SYS` | Cross NUMA, no NVLink | Pipeline Parallelism only — TP will crawl |

**You will be tempted to:** "Set `--tensor-parallel-size 4` and let vLLM handle it."
**Why that fails:** If GPUs are PCIe-connected (T4, L4, RTX Pro 6000), TP synchronizes matrices over ~32 GB/s instead of ~900 GB/s NVLink. Token generation speed drops to a crawl. Use PP instead — it splits by layers, dramatically reducing cross-GPU traffic.

### Rule 8: Set Safe Memory and Context Limits
Never max out GPU memory or accept unbounded context lengths.

- `gpu_memory_utilization`: max **0.90** (leave 10% for spikes, LoRA adapters, multi-modal tokens)
- `max_model_len`: set to **actual business need**, not model's theoretical max (128k context = massive KV cache per user)
- Enable **FP8 KV caching** to halve KV cache VRAM with near-zero quality loss — standard practice in 2026
- Always use `.safetensors` format (zero-copy mmap, bypasses CPU serialization)

---

## Tier: model-storage

### Rule 9: Pre-Stage Models — Never Download on Boot
Downloading models during VM startup is an anti-pattern for production.

**Storage tier decision:**
| Tier | Use For | Price/GB/mo |
|------|---------|------------|
| GCS Standard | Active serving models | ~$0.020 |
| GCS Nearline | Previous versions, rollback | ~$0.010 (30-day min) |
| GCS Archive | Compliance retention | ~$0.004 (365-day min) |

**Loading patterns (fastest to slowest):**
1. **Golden Image** (Packer) — model weights baked into disk image. Boot → serve in 1-3 min.
2. **Hyperdisk ML** — hydrate once, attach read-only to 2500 VMs simultaneously. 1.2 TB/s throughput.
3. **GCS FUSE v3** — mount bucket directly, enable `file-cache:enable-parallel-downloads: true` with local SSD cache. 9x faster than default.
4. **GCS download on boot** — slowest. Acceptable for infrequent batch jobs only.

**You will be tempted to:** "Just add `huggingface-cli download` to the startup script."
**Why that fails:** 70B model = 35-140GB download. At GCS throughput, that's 5-20 minutes of GPU idle time. At $3.37/hr per H100, you're burning $0.30-1.00 just waiting for weights. With a golden image, boot-to-serve is 90 seconds.

**The right way for HuggingFace models:**
```bash
# For Packer golden images — download once, bake forever:
huggingface-cli download <model-id> --local-dir /opt/models/<name> --local-dir-use-symlinks False

# For runtime — redirect HF cache to shared storage:
export HF_HOME="/mnt/gcs-model-bucket/huggingface-cache"
```

### Rule 10: Use the Right Disk Type for Each Phase

| Phase | Disk Type | Why |
|-------|-----------|-----|
| Model weights (fleet) | **Hyperdisk ML** | Read-only-many to 2500 nodes, 1.2 TB/s |
| Training scratch | **Local SSD** | 37.4 GB/s, sub-ms latency (but ephemeral!) |
| Boot disk | **Hyperdisk Balanced** | Dynamically adjustable IOPS/throughput |
| Checkpoints | **GCS** or **pd-ssd** | Persistent, survives termination |

**Never** save checkpoints to Local SSD (wiped on termination). **Never** use pd-standard for model loading (7.5K IOPS max).

**The Lazy Hydration Trap:** Standard GCP snapshots hydrate lazily from GCS. A freshly restored disk throttles reads horribly when loading a 50GB model. Use **Custom Images** (optimized for boot) or **Instant Snapshots** (same-zone, immediate performance).

---

## Tier: model-transfer

### Rule FT-1: Never Route Model Files Through Residential Internet
Model weights are 1-200GB. Residential ISP upload throttles to 4-5 MB/s regardless of protocol (SCP, FTP, rsync). A 42GB file takes 2+ hours through residential, 5-10 minutes cloud-internal.

**The rule:** Both endpoints must be in the cloud. Local servers NEVER touch the data path.

**You will be tempted to:** "I'll just SCP the model from my local server to the GPU host."
**Why that fails:** Tested 4+ times across Vast.ai and GCP. 4.7 MB/s ceiling every time, regardless of local LAN speed. WAN TCP windowing and ISP upload shaping are the bottleneck, not the protocol.

### Rule FT-2: Download From Inside the Cloud Region
Spin up a cheap ephemeral VM (e2-medium, ~$0.03/hr) in the same region as your storage bucket. Download there, upload to bucket, kill the VM.

**Pattern:**
```bash
# On ephemeral GCP VM in same region as GCS bucket:
aria2c -x 16 -s 16 -d /tmp -o model.gguf "<huggingface-url>"
gcloud storage cp /tmp/model.gguf gs://your-bucket/
# Then kill the VM
```

**Cost:** $0.02-0.05 per model (VM runtime during download). Compare to 2+ hours of your time fighting residential transfers.

### Rule FT-3: Use aria2c for Multi-Connection Downloads
Single-threaded `curl` or `wget` gets throttled by CDNs (HuggingFace, GitHub LFS). `aria2c -x 16 -s 16` opens 16 parallel connections, saturating available bandwidth.

**Install:** `apt-get install -y aria2` in startup script.

**Never use `curl` with progress bars in GCP startup scripts** — the carriage-return output crashes the startup script runner (`bufio.Scanner: token too long`). Use `curl -s` or `aria2c` instead.

### Rule FT-4: Use FTP/HTTP for Cloud-to-Cloud Model Transfer
Model weights are public artifacts — encryption is pure overhead. For moving models between cloud providers (GCP → RunPod, GCP → Vast.ai):

- **FTP:** Zero encryption overhead, clean TCP retransmit, mature protocol. Ideal for large files on trusted networks.
- **Plain HTTP:** nginx serving a directory, or GCS signed URLs. No server to maintain with signed URLs.
- **Never SCP/SFTP** for cross-cloud model transfer. SSH encryption on a 42GB file = billions of wasted encrypt/decrypt cycles.

**Architecture:**
```
GCS bucket ──(FUSE mount)──> GKE pod          (zero transfer)
GCS bucket ──(signed URL/HTTP)──> RunPod       (plain HTTP, no encryption)
GCS bucket ──(signed URL/HTTP)──> Vast.ai      (plain HTTP, no encryption)
GCS bucket ──(FTP from staging VM)──> anywhere (raw TCP, maximum throughput)
```

### Rule FT-5: GCS Upload — Retry and Fallback
`gcloud storage cp` uses composite parallel uploads for large files, which can 503. Always have retry logic:

```bash
# Primary: gcloud storage cp with retry
gcloud storage cp /tmp/model.gguf gs://bucket/ || \
  # Fallback: gsutil with parallel composite threshold
  gsutil -o GSUtil:parallel_composite_upload_threshold=150M cp /tmp/model.gguf gs://bucket/
```

### Rule FT-6: Ephemeral Download VMs — Spin Up, Transfer, Kill
Download VMs exist for ONE purpose: move data into cloud storage. They must:
1. Use startup script that auto-downloads, auto-uploads, and writes a completion flag
2. Have enough disk (2x model size for download + upload headroom)
3. Be killed immediately after upload completes — every minute is wasted money
4. Use `--no-address` if possible (internal-only, avoids egress charges) — but HuggingFace downloads need external IP

---

## Tier: vm-lifecycle

### Rule 11: Build Golden Images — Stop Cold-Starting
Every GPU VM deployment should boot from a pre-built image with everything installed.

**Golden image must include:**
1. NVIDIA drivers + CUDA toolkit (version-locked)
2. Serving framework (vLLM/Ollama) + Python env
3. Model weights downloaded to `/opt/models/`
4. Systemd service for auto-start inference server
5. Ops Agent + DCGM for GPU metrics (from `mx-gcp-operations` Rule 1)
6. Shutdown script for 30-second preemption window

**Build with Packer:**
```hcl
source "googlecompute" "gpu_base" {
  machine_type        = "g2-standard-4"  # Use cheap GPU for build
  accelerator_type    = "nvidia-l4"
  accelerator_count   = 1
  on_host_maintenance = "TERMINATE"  # MANDATORY for GPU VMs
  disk_size           = 150  # Enough for model weights
  disk_type           = "pd-ssd"
  image_name          = "ai-inference-{{timestamp}}"
  image_family        = "ai-inference"
}
```

**You will be tempted to:** "I'll just update the startup script — Packer is overkill for a one-off."
**Why that fails:** Failure #13 from mx-gcp-operations: the observability golden image was designed, written down, and then NEVER BUILT. Startup scripts are "I'll do it right next time" — Packer images are "it's already done." Boot-to-serve: 90 seconds vs 15-40 minutes.

---

## Cross-References — These Matrices Work Together

### mx-gcp-operations (MUST co-fire for any GPU deployment)
Every GPU inference deployment is also a GCP operation. When `mx-gpu-inference` fires, `mx-gcp-operations` MUST also be loaded for:
- **Rule 1 (No Blind Boxes):** Every GPU VM needs Ops Agent + DCGM v2 GPU metrics + structured logs BEFORE vLLM starts. This is not optional — it's a fail-closed gate.
- **Rule 2 (Multi-Source Verification):** Check quotas via `accelerator-types list` + Cloud Quotas API before provisioning GPU VMs.
- **Rule 3 (Zone Capacity):** Identify 3+ zones across 2+ regions. Use `--region` flag for auto-placement.
- **Rule 5 (Disk IOPS):** GPU VMs are especially vulnerable — model loading from slow disks = expensive GPU idle time. Use Local SSD or Hyperdisk ML.
- **Rule 6 (Spot Preemption):** If using spot GPUs, checkpointing and shutdown scripts are mandatory.

### batch-compute-discipline (fires for batch inference jobs)
If running batch inference (processing N items through a model), also load `batch-compute-discipline` for:
- Per-chunk verification (don't trust silent writes)
- CPU reservation (vCPUs-4 max workers)
- Contention analysis before scaling

### Observability Stack (bake into golden images)
Every GPU golden image should include:
```yaml
# Ops Agent config for GPU VMs (/etc/google-cloud-ops-agent/config.yaml)
metrics:
  receivers:
    dcgm_v2:               # GPU utilization, SM occupancy, NVLink bandwidth
      type: dcgm
      collection_interval: 10s
    hostmetrics:            # CPU, RAM, disk, network
      type: hostmetrics
      collection_interval: 30s
logging:
  receivers:
    inference_logs:
      type: files
      include_paths: ["/var/log/inference/*.log"]
    startup_logs:
      type: systemd_journald
      include_units: [google-startup-scripts.service]
  processors:
    parse_json:
      type: parse_json
      time_key: timestamp
  service:
    pipelines:
      inference: { receivers: [inference_logs], processors: [parse_json] }
      startup: { receivers: [startup_logs] }
```

**Logs MUST flow to Loki** (not just Cloud Logging):
- All inference logs (vLLM stdout, request/response traces) → Grafana Alloy → Loki on your observability server
- GPU metrics (DCGM) → Prometheus → Grafana dashboards
- LLM-specific observability → Langfuse for tracing, Promptfoo for eval

**Every GPU golden image must ship with Grafana Alloy configured to push to your central Loki instance.** Cloud Logging is a backup, not the primary. If it's not in Loki, it doesn't exist for debugging.

**GPU-specific monitoring alerts (set in Cloud Monitoring AND Grafana):**
- GPU utilization < 10% for > 5 min while VM is running → GPU is starving (I/O bottleneck)
- GPU memory > 95% → approaching OOM, reduce batch size or context length
- Heartbeat metric flatlines > 10 min → VM is hung, auto-terminate
- `nvidia-smi` driver mismatch detected on boot → alert and block workload start

**Verify on every boot (add to startup script):**
```bash
# Driver compatibility check
DRIVER_API=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
CUDA_VERSION=$(nvcc --version 2>/dev/null | grep "release" | awk '{print $5}' | tr -d ',')
echo "{\"event\":\"gpu_check\",\"driver\":\"$DRIVER_API\",\"cuda\":\"$CUDA_VERSION\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >> /var/log/inference/startup.log

# Topology check (warn if no NVLink)
nvidia-smi topo -m | grep -q "NV" || echo "{\"event\":\"warning\",\"msg\":\"No NVLink detected — tensor parallelism will be slow\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >> /var/log/inference/startup.log
```
