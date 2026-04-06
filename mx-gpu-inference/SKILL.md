---
name: mx-gpu-inference
description: Use when selecting, sizing, deploying, or serving AI/ML models on GPUs — including model selection, VRAM calculations, quantization decisions, serving framework choice, model storage, golden image creation, or any self-hosted LLM inference work. Also use when the user mentions 'vLLM', 'Ollama', 'llama.cpp', 'GGUF', 'AWQ', 'GPTQ', 'FP8', 'quantization', 'tensor parallelism', 'model serving', 'self-hosted LLM', 'DeepSeek', 'Llama 4', 'Qwen', 'Gemma', 'golden image', 'model weights', 'KV cache', 'RunPod', 'Vast.ai', 'vast', 'SkyPilot', 'sky launch', 'network volume', 'neocloud', 'GPU cloud', 'spot GPU', 'interruptible', 'FlashBoot', 'cold start', 'GPU pricing', or 'fine-tune'.
---

# GPU Inference Operations Matrix

**Core principle:** GPU inference is a stack of interdependent decisions — model, quantization, framework, storage, and hardware must all be chosen together. Getting any one wrong wastes the entire stack's potential. Calculate before you provision. Verify before you serve.

## Operating Mode

| Mode | When | Claude's Role |
|---|---|---|
| **Build** | Creating inference infrastructure (Packer images, startup scripts, vLLM configs) | Infrastructure engineer — enforce all rules, calculate everything |
| **Execute** | Running inference on existing infra, troubleshooting OOMs | Operator — enforce runtime rules (VRAM math, KV cache, framework config) |
| **Direct** | Advising on model selection, sizing, or architecture decisions | Advisor — apply decision trees, provide calculations, cite benchmarks |

## Routing

Determine which tiers apply based on the task.

| If the task involves... | Load these tiers |
|---|---|
| Choosing a model (which LLM, what size) | `model-selection` |
| Calculating VRAM, RAM, disk, or GPU count | `model-sizing` |
| Choosing or configuring vLLM/Ollama/llama.cpp/TGI | `model-serving` |
| Storing, loading, or caching model weights | `model-storage` |
| Moving model files between clouds, downloading from HuggingFace, file transfer | `model-transfer` |
| Creating golden images, Packer builds, fast-boot VMs | `vm-lifecycle` |
| RunPod GPU work | `multi-cloud` tier here + **invoke `mx-gpu-runpod`** vendor skill |
| Vast.ai GPU work | `multi-cloud` tier here + **invoke `mx-gpu-vastai`** vendor skill |
| GCP GPU work | `multi-cloud` tier here + **invoke `mx-gcp-operations`** |
| SkyPilot cross-cloud | `multi-cloud` tier here + read `reference/multi-cloud-providers.md` |
| Full deployment (end-to-end) | All tiers + appropriate vendor skill |

**Vendor skill architecture:** This core matrix handles universal GPU rules (VRAM math, compute cap, image sizing, model selection). Provider-specific rules live in vendor skills:
- **`mx-gpu-vastai`** — Vast.ai templates, volumes, disk enforcement, port behavior
- **`mx-gpu-runpod`** — RunPod pods, network volumes, GraphQL API, Secure Cloud (rules MC-1, MC-8, MC-10, MC-11 from reference/)
- **`mx-gcp-operations`** — GCP VMs, golden images, spot preemption

**Multi-cloud reference:** SkyPilot job files at `~/gpu-infrastructure/jobs/`, research at `~/gpu-infrastructure/research/`, Vast.ai templates at `~/gpu-infrastructure/vastai-templates.md`.

Read `enforcement.md` for rules. Run `validation.md` checklist before completing any GPU inference operation.
