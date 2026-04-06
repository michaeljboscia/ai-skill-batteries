# GPU Inference Validation Checklist

Run AFTER planning/configuring any GPU inference operation, BEFORE provisioning or deploying.

## First Pass (Belt) — Self-Check

### Universal Cost Gate (Always Run)
- [ ] Five questions answered: model, quantization, GPU count, hourly cost, runtime, total cost
- [ ] If NEW pattern: user confirmed estimated total cost and kill conditions
- [ ] If pre-approved pattern: matches an entry in the pre-approved list exactly

### model-selection (if choosing a model)
- [ ] Model matches workload type (coding/reasoning/RAG/batch)
- [ ] Smallest viable model chosen first — not defaulting to biggest
- [ ] If MoE: VRAM calculated from TOTAL params, not active params

### model-sizing (if calculating resources)
- [ ] VRAM formula computed: weights + KV cache (at actual concurrency × context length) + 2GB CUDA
- [ ] Quantization chosen by GPU generation (FP8 for Hopper/Ada, AWQ for Ampere, GGUF for CPU)
- [ ] System RAM sized correctly: OS (16-32GB) + mmap buffer + vLLM swap space
- [ ] vLLM `--swap-space` explicitly set (not relying on 4GB default)
- [ ] 10% VRAM headroom left (`gpu_memory_utilization` ≤ 0.90)

### model-serving (if deploying inference)
- [ ] Framework matches use case (vLLM for production, Ollama for local only, llama.cpp for edge)
- [ ] `nvidia-smi topo -m` checked — TP only if NVLink, PP if PCIe
- [ ] `max_model_len` set to business need, not model theoretical max
- [ ] `.safetensors` format used (not legacy .bin/.pt)
- [ ] FP8 KV caching enabled if on Hopper/Ada hardware

### model-storage (if loading or caching models)
- [ ] Models NOT being downloaded on every boot (golden image or Hyperdisk ML or GCS FUSE)
- [ ] Correct disk type for each phase (Local SSD for scratch, Hyperdisk ML for fleet, pd-ssd for checkpoints)
- [ ] No checkpoints on Local SSD (ephemeral — wiped on termination)
- [ ] Not using standard snapshots for model disks (lazy hydration trap)

### vm-lifecycle (if creating VM images)
- [ ] Golden image includes: drivers + framework + model weights + systemd auto-start + observability
- [ ] Packer template sets `on_host_maintenance = "TERMINATE"`
- [ ] Boot-to-serve time verified ≤ 3 minutes

## Second Pass (Suspenders) — Triumvirate

For GPU deployments exceeding $10/hr or involving new (non-pre-approved) patterns:
1. Dispatch this checklist + deployment plan to Gemini AND Codex
2. Majority vote (2/3) on each checklist item
3. Disagreement → surface to user before provisioning
