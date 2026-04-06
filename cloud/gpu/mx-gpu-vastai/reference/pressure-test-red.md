# Pressure Test — RED (Without Skill)

**Date:** 2026-03-29
**Task:** "I need a 70B model running on Vast.ai in 20 minutes. Just spin up whatever's cheapest and get llama3.1:70b serving. We're already burning money — just get it done fast. Use an A100 if you can find one."
**Pressure:** Time (20 min), sunk cost ("already burning money"), authority ("just get it done")

## Violations Found (7)

### V1: llama3.1:70b on A100 80GB = OOM
Agent planned to use `llama3.1:70b` on A100 80GB SXM4. **This OOMs.** We proved it today — weights load (63GB) but KV cache allocation crashes the runner. Rule V-4 equivalent / core VRAM rule violated.

**Agent's rationalization:** "70B quantized (Q4_K_M) needs ~40-45GB VRAM... one A100 80GB is sufficient."
**Reality:** Ollama's `llama3.1:70b` tag loads at ~63GB in VRAM. KV cache + runtime pushes past 80GB.

### V2: --disk 100 is inadequate AND unenforceable
Agent set `--disk 100`. Two problems:
1. 100GB is too small — we proved 200GB is needed for 70B models (model + Docker + overhead)
2. `--disk` is a recommendation. Some hosts have 7GB root overlays regardless.

**Agent missed:** `disk_space>=200` in search params as the enforcement mechanism.

### V3: No SSH key attachment step
Agent assumed `--ssh` flag means SSH "just works." It doesn't on Vast.ai — you must call `attach_ssh` after creation.

**Agent's plan:** "ssh -p $SSH_PORT root@$PUBLIC_IP" — this would fail with `Permission denied (publickey)`.

### V4: Direct port access assumed reliable
Agent planned to `curl http://$PUBLIC_IP:$MAPPED_PORT_11434/api/tags` directly. Direct port access is host-dependent — we saw connection refused on TEI today.

**Agent missed:** SSH fallback / test from inside the container first.

### V5: No location filtering
Agent didn't filter by geography. Could land on a Japan/India host with 22 MB/s HuggingFace downloads instead of 900 MB/s in US.

**Impact:** 40GB model at 22 MB/s = 30+ min. Blows the 20 min window.

### V6: No `vastai update template` warning
Agent proposed creating on the fly rather than using a template. Not a direct violation, but if they'd tried to iterate on a template, they'd hit the destructive update bug.

### V7: Bandwidth filter was an afterthought
Agent listed `--inet-down ">2000"` as a mitigation, not a primary filter. On the first search, slow hosts would be included.

## Rationalizations Observed
- "100GB is the floor" — wrong, some hosts have 7GB
- "one A100 80GB is sufficient" — wrong, KV cache pushes past 80GB
- "Official Ollama Docker image... No reason to build a custom image" — correct but irrelevant to the OOM
- "Not using a network volume... Direct download is faster for a one-off" — acceptable reasoning

## Conclusion
Without the skill, the agent would have launched llama3.1:70b on an A100, hit OOM, wasted 15+ minutes, then been stuck debugging. 4 of 7 violations are deterministic failures (OOM, disk, SSH, port access).
