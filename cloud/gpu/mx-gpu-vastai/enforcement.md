# Vast.ai Enforcement Rules

Crystallized from 2026-03-29 session: 10 templates built, 6 deployment failures diagnosed, all verified with live inference.

---

## Rule V-0: ASK What Serving Framework Before Launching

**Do NOT default to Ollama. ASK the user: "vLLM or Ollama?" before creating any instance.**

On 2026-03-29: User explicitly said "vLLM serving Qwen 2.5 32B" and Claude launched an Ollama instance anyway. When corrected, Claude launched ANOTHER Ollama instance before finally using vLLM. Two wasted GPU instances + billing + user trust.

**You will be tempted to:** "Ollama is simpler, I'll just use that and they won't mind."
**Why that fails:** The user specified the tool. Overriding the user's explicit choice is not a decision you get to make. Ollama and vLLM have fundamentally different APIs, performance profiles, and multi-model behavior.

**The right way:**
1. If user specifies a framework → use exactly that framework
2. If user doesn't specify → ASK: "vLLM (production, OpenAI-compatible API, tensor parallel) or Ollama (quick test, simple API)?"
3. Never assume. Never substitute.

---

## Rule V-0b: CLI + Direct SSH Only — No MCP for Execution

**Use `vastai` CLI and direct `ssh` via Bash for all instance operations. Do NOT use the Vast.ai MCP SSH tools (`mcp__vastai__ssh_execute_command`, `mcp__vastai__attach_ssh`) for anything that touches a running instance.**

On 2026-03-29: The MCP SSH tool failed repeatedly — rejected calls, auth failures, timeouts, silent drops. Every single time, falling back to `ssh -p <PORT> root@<IP>` via Bash worked immediately. The MCP adds a failure layer between you and the machine.

**MCP is OK for:** `search_offers`, `show_instances`, `search_templates` — read-only queries that don't touch running instances.

**MCP is NOT OK for:** `ssh_execute_command`, `attach_ssh`, anything that requires a live connection to an instance.

**You will be tempted to:** "The MCP tool is more convenient, I'll just use it."
**Why that fails:** It silently fails, returns auth errors on valid keys, and gives you no output when it drops. You sit there blind while the GPU bills.

**The right way:**
```bash
# SSH in
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p <PORT> root@<IP> '<command>'

# Attach SSH key
vastai attach_ssh <INSTANCE_ID>

# Check logs
vastai logs <INSTANCE_ID>
```

---

## Rule V-0c: DO THE VRAM MATH BEFORE LAUNCHING — EVERY TIME

**Calculate total VRAM (weights + vLLM overhead + KV cache) and compare to card size BEFORE creating any instance. If the math is within 10% of the card, go up a tier.**

On 2026-03-29: Launched Qwen 32B AWQ on 3090 (24GB) THREE TIMES. Failed every time. The math shows 23.5GB minimum — impossible on 24GB. If the math had been done once, we'd have gone straight to the A6000 and saved 3 launch cycles + 45 minutes + GPU billing.

**You will be tempted to:** "AWQ is 4-bit, 32B × 0.5 bytes = 16GB, should fit on 24GB easy."
**Why that fails:** That's weight math, not deployment math. vLLM adds 4GB overhead (CUDA context, engine buffers, activation memory, Python). Then KV cache needs 0.5-1GB per 2048 context. Real total = 23.5-24.5GB. That's a coinflip on 24GB — and coinflips lose.

**The right way:**
```
Total VRAM = Model_Weights_In_VRAM + vLLM_Overhead (4GB) + KV_Cache
KV_Cache = 2 × layers × kv_heads × head_dim × 2bytes × context_length

If Total > (Card_VRAM × 0.90): GO UP A TIER. Don't try it.
```

**Quick reference — vLLM minimums (including 4GB overhead + 2048 ctx KV):**
| Model | Weights | Total | Min Card |
|-------|---------|-------|----------|
| 7B FP16 | 14GB | 19GB | 24GB |
| 7B AWQ | 4GB | 9GB | 16GB |
| 32B AWQ | 19.5GB | 24GB | **48GB** (NOT 24GB) |
| 70B AWQ | 42GB | 48GB | **80GB** (NOT 48GB — tight) |
| 72B Q4 (Ollama) | 47GB | 56GB | 80GB |
| 2B FP16 | 5GB | 9.5GB | 16GB |

---

## Rule V-0d: max-model-len Must Fit the Actual Prompt

**Calculate your prompt size in tokens BEFORE setting max-model-len. System prompt + user prompt + response headroom.**

On 2026-03-30: vLLM was set to `--max-model-len 2048` (leftover from failed 3090 attempts). The c_suite email prompt was 1,812 tokens. With response room needed, it silently failed — no error, just empty response. The other thread diagnosed it.

**You will be tempted to:** "2048 is plenty for a cold email."
**Why that fails:** System prompts for tiered email generation are 1,600+ tokens alone.

**The right way:** Calculate: `system_prompt_tokens + user_prompt_tokens + max_response_tokens = min context`. Set `--max-model-len` to at least 2x that for safety. On a 48GB card with a 32B AWQ model, 4096 context costs only ~1GB extra KV cache — there's no reason to be stingy.

---

## Rule V-1: disk_space in Search Params — Not Just --disk

**The `--disk` flag is a RECOMMENDATION that hosts can ignore. Some hosts have 7GB root overlays regardless of what you request.**

Put `disk_space>=N` in the template's `search_params` (or `extra_filters`). This FILTERS OUT undersized hosts before you ever land on one.

**You will be tempted to:** "I set `--disk 200`, that should be enough."
**Why that fails:** PRO 6000 S in Michigan had a 7GB root overlay. H100 SXM had the same. Both failed with "no space left on device" at 18-20% model download. Wasted $1.50+ in GPU billing.

**The right way:**
```bash
vastai create template ... \
  --disk_space 200 \
  --search_params "... disk_space>=200 ..."
```
Both flags. Belt AND suspenders. The search param is the gate; the --disk is the request.

**Minimum disk by model tier:**
| Model Size | Minimum disk_space |
|------------|-------------------|
| 7B | 30GB |
| 14-32B | 80GB |
| 70B+ | 200GB |
| Fine-tuning | 250GB+ |

---

## Rule V-2: Volumes Are LOCAL — Not Network Attached

**Vast.ai "volumes" are Docker volumes tied to a PHYSICAL MACHINE. They do NOT follow you to other machines.**

If you destroy an instance and create a new one on a DIFFERENT machine, your volume and all cached models are gone. You must re-download everything.

**You will be tempted to:** "I'll cache the model on the volume and reuse it next time."
**Why that fails:** "Next time" might be on a different machine if the original host is busy. The volume only persists if you stay on the same `machine_id`.

**The right way:**
- Treat volumes as a **warm cache**, not guaranteed storage
- On-start scripts MUST handle fresh downloads gracefully (check if model exists, download if not)
- For critical data: sync to GCS/S3 before destroying
- Use `stop` (not `destroy`) if you plan to resume on the same machine
- Filter by `machine_id` if you want to reuse a specific volume

---

## Rule V-3: Never Use `vastai update template`

**`vastai update template` wipes ALL fields you don't explicitly pass. It is not a PATCH — it's a destructive PUT that nullifies unspecified fields.**

This destroyed two production templates on 2026-03-29. The SSH, runtype, env, onstart, and search_params fields were all reset to null/defaults.

**You will be tempted to:** "I just need to change the disk size, let me update the template."
**Why that fails:** Every other field (image, env, onstart, ssh, search_params) resets to default. Your template becomes a blank shell.

**The right way:** Delete + recreate. Always.
```bash
vastai delete template --template-id <ID>
vastai create template --name "..." --image "..." --env "..." ...
```
Yes, the template ID changes. Update your references.

---

## Rule V-4: Compute Cap Must Match TEI Image Tag

**TEI (text-embeddings-inference) publishes architecture-specific images. The tag number IS the compute capability. Wrong match = instant crash.**

```
Runtime compute cap 86 is not compatible with compile time compute cap 89
```

| GPU Architecture | Compute Cap | TEI Tag |
|-----------------|-------------|---------|
| Turing (T4) | 75 | `75-1.7` |
| Ampere (A4000, 3090, A5000, A6000, A40, A100) | 80-86 | `86-1.7` |
| Ada Lovelace (4060Ti, 4070, 4080, 4090, 6000 Ada) | 89 | `89-1.7` |

**You will be tempted to:** "I'll just use the latest tag, it should work."
**Why that fails:** There IS no universal tag. Each binary is compiled for specific CUDA architectures. It's a hardware constraint, not a config issue.

**The right way:** Create SEPARATE templates per compute cap family. We have:
- `TEI gte-Qwen2 1.5B [Ampere]` (ID 372862, tag `86-1.7`)
- `TEI gte-Qwen2 1.5B [Ada]` (ID 372863, tag `89-1.7`)
- `TEI gte-Qwen2 7B [Ampere 48GB]` (ID 372924, tag `86-1.7`)

Add `compute_cap>=86 compute_cap<89` to Ampere template search params, `compute_cap>=89` for Ada.

---

## Rule V-5: SSH Keys Require Manual Attachment

**SSH keys do NOT auto-propagate to Vast.ai instances. You MUST call `attach_ssh` after every instance creation.**

**You will be tempted to:** "I set my SSH key in my Vast.ai account, it should just work."
**Why that fails:** The key is registered at the account level but not injected into the instance until you explicitly call attach. Without it, `Permission denied (publickey)`.

**The right way:** Immediately after `vastai create instance`:
```bash
# CLI
vastai attach_ssh <INSTANCE_ID>
# Or MCP
mcp__vastai__attach_ssh(instance_id: <ID>)
```

---

## Rule V-6: Direct Port Access Is Host-Dependent

**Some Vast.ai hosts expose mapped ports to the public internet. Others don't. There is no way to predict which.**

On 2026-03-29: Ollama on a P100 in Texas — direct port worked. TEI on an A4000 in Quebec — connection refused on the exact same port mapping pattern.

**You will be tempted to:** "Port 80 is mapped to 43666, I'll curl it directly."
**Why that fails:** The host's firewall or network config may block external access to mapped ports.

**The right way:**
- Always test via SSH first: `ssh -p <SSH_PORT> root@<IP> 'curl localhost:<INTERNAL_PORT>/health'`
- If direct access is needed: test it. If it fails, use SSH port forwarding: `ssh -L 8080:localhost:80 -p <SSH_PORT> root@<IP>`
- For production: bind services to `0.0.0.0` (not `127.0.0.1`) and hope for the best, but have SSH fallback ready

---

## Rule V-7: Location Matters for Model Downloads

**HuggingFace CDN is fastest from US/CA/EU. Asia hosts (Japan, India, Hong Kong) download at 20-50 MB/s vs 100-900 MB/s in US/EU.**

On 2026-03-29: RTX 6000 Ada in Japan downloaded gte-Qwen2-7B at 22 MB/s (estimated 8+ min for 14GB). An A6000 in Kansas did the same at ~100 MB/s.

**You will be tempted to:** "This Japan host is $0.05/hr cheaper, great deal."
**Why that fails:** The $0.05/hr savings costs 10+ min of extra download time, plus you're paying GPU idle during the pull.

**The right way:** Filter offers to US/CA/EU. The search_params already include `inet_down>500` but also visually check the `geolocation` field before launching.

---

## Rule V-8: On-Start Scripts Must Be Idempotent

**On-start scripts run every time the container starts — including restarts and stop/start cycles.**

**You will be tempted to:** "I'll add `apt-get install` and `pip install` to the on-start."
**Why that fails:** Those commands run on EVERY restart, adding 2-5 min to startup even when the packages already exist.

**The right way:** Use conditionals:
```bash
# Ollama pattern (idempotent — pull skips if model exists)
ollama serve & sleep 10 && ollama pull ${OLLAMA_MODEL:-qwen2.5:7b}

# TEI pattern (idempotent — HF cache hits if model already downloaded)
text-embeddings-router --model-id ${TEI_MODEL:-Alibaba-NLP/gte-Qwen2-1.5B-instruct} --port 80 --hostname 0.0.0.0 &
```
Set `HUGGINGFACE_HUB_CACHE=/workspace/models` so TEI checks the volume cache first.
