# RunPod Enforcement Rules

Extracted from `mx-gpu-inference` multi-cloud rules + 2026-03-29 session failures. RunPod-specific rules only — universal GPU rules live in the core `mx-gpu-inference` matrix.

---

## Rule RP-1: Network Volume Region Lock

**RunPod pods can ONLY attach network volumes in the SAME data center.**

Our `gtm-models` volume is in **US-TX-3** (ID: `iwnymg3nd3`, 50GB). A pod in US-GA-1 or US-CA-2 CANNOT see it.

**You will be tempted to:** Pick the cheapest GPU anywhere without checking the region.
**Why that fails:** Pod launches, has no volume, downloads from HuggingFace (10-30 min), GPU idles at $0.20+/hr.

**The right way:** When using RunPod directly (not SkyPilot), always specify `dataCenterId: US-TX-3`. Or check GPU availability in TX-3 first:
```bash
curl -s "https://api.runpod.io/graphql" -H "Authorization: Bearer $RUNPOD_API_KEY" -H "Content-Type: application/json" \
  -d '{"query":"{ gpuTypes { id displayName memoryInGb } }"}'
```

---

## Rule RP-2: Use GraphQL, NOT REST API for Pod Creation

**The RunPod REST API (`POST /v1/pods`) silently fails or returns misleading errors. The GraphQL API works instantly.**

This cost 3 hours on 2026-03-29. REST returned "no instances available" while GraphQL showed 42 GPU types with availability.

**You will be tempted to:** Use the REST API because it looks simpler.
**Why that fails:** REST for pod creation is unreliable. It's a known issue.

**The right way — ALWAYS use this GraphQL mutation:**
```bash
curl -s "https://api.runpod.io/graphql" \
  -H "Authorization: Bearer $RUNPOD_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"mutation { podFindAndDeployOnDemand(input: {
    name: \"my-pod\",
    imageName: \"ollama/ollama:latest\",
    gpuTypeId: \"NVIDIA RTX A4000\",
    cloudType: COMMUNITY,
    containerDiskInGb: 20,
    volumeInGb: 20,
    gpuCount: 1,
    ports: \"11434/http,22/tcp\"
  }) { id costPerHr machine { gpuDisplayName dataCenterId } } }"}'
```

**REST API is fine for:** templates, network volumes, listing pods/endpoints. Just NOT pod creation.

**Proxy URL:** `https://{podId}-{port}.proxy.runpod.net` — works without SSH, no public IP needed.

---

## Rule RP-3: Network Volumes Are Secure Cloud Only

**Network volumes ONLY work on Secure Cloud pods, NOT Community Cloud.**

**You will be tempted to:** Grab the cheapest Community Cloud GPU and attach `gtm-models`.
**Why that fails:** Community Cloud pods don't support network volume attachment. The API call succeeds but the volume won't mount.

**The right way:** When you need cached models from the network volume, use Secure Cloud. For one-off work without cached models, Community Cloud is fine.

---

## Rule RP-4: Pod Creation Checklist

**Every RunPod pod creation MUST include:**

1. **SSH key:** `"env": {"PUBLIC_KEY": "<contents of ~/.ssh/id_rsa.pub>"}` — otherwise no SSH access
2. **Light base image:** Use `ollama/ollama:latest` or thin TEI images. NOT 10GB+ fat images.
3. **Network volume (if needed):** `"networkVolumeId": "iwnymg3nd3"` — the MCP `create-pod` tool does NOT support this param, use REST/GraphQL
4. **Datacenter match:** Volume `gtm-models` is in US-TX-3. Pod MUST be in US-TX-3.
5. **Secure Cloud (if using volume):** See RP-3.

---

## Rule RP-5: Thin Docker Images Only

**NEVER bake model weights into Docker images on RunPod. This is MC-12 from the core matrix.**

On 2026-03-29: `michaeljboscia/tei-embedding:v1` (11GB) pulled for 20+ min across 5 pod attempts. None ever started serving.

**You will be tempted to:** "Bake everything in for reproducibility."
**Why that fails:** RunPod first-pulls are slow. 11GB = 20+ min. Network volume + thin image = 5 min.

**The right way:** Image has ONLY the runtime binary. Model weights live on the network volume at `/workspace/models/`. CMD points to the volume path.

Docker images on Docker Hub:
- `michaeljboscia/tei-embedding:v1` — **DO NOT USE** (11GB, fat, model baked in)
- `michaeljboscia/tei-embedding:v2-thin` — OK (4GB, thin, needs network volume)

---

## Rule RP-6: Spot Pods Will Die Without Warning

**RunPod Community Cloud and Interruptible instances can be preempted at any time.**

**You will be tempted to:** Run a 6-hour job on spot without checkpointing.
**Why that fails:** Instance dies at hour 4. All progress lost.

**The right way:**
- For inference: use Serverless (managed, no preemption) not spot pods
- For batch: checkpoint every N steps, write results incrementally
- For serving: use `autostop` to avoid forgotten pods billing

---

## Rule RP-7: ALWAYS Check Availability via GraphQL (NOT REST)

**The REST API `/v1/gpu-types` endpoint is BROKEN — it returns 1 GPU type with 0 availability even when 42 types are available. GraphQL is the source of truth.**

On 2026-03-29 we concluded RunPod had "zero GPUs" based on the REST endpoint. This was WRONG. GraphQL showed full inventory. We wasted hours on a false conclusion.

**You will be tempted to:** Trust the REST API response for availability.
**Why that fails:** REST returned `{"error": "path does not exist"}` for `/v1/gpu-types`. We interpreted this as "no GPUs." It was a broken endpoint.

**The right way — ALWAYS use GraphQL:**
```bash
curl -s "https://api.runpod.io/graphql" -H "Authorization: Bearer $RUNPOD_API_KEY" -H "Content-Type: application/json" \
  -d '{"query":"{ gpuTypes { displayName memoryInGb secureCloud communityCloud securePrice communityPrice } }"}' \
  | python3 -c "import json,sys; gpus=json.load(sys.stdin)['data']['gpuTypes']; avail=[g for g in gpus if g.get('secureCloud') or g.get('communityCloud')]; print(f'{len(avail)} GPU types available'); [print(f'  {g[\"displayName\"]:30} {g[\"memoryInGb\"]}GB  cc=\${g.get(\"communityPrice\",0):.2f}  sc=\${g.get(\"securePrice\",0):.2f}') for g in sorted(avail, key=lambda x: x.get('communityPrice',999))[:10]]"
```

---

## Rule RP-8: Minimum Disk Provisioning

**Container disk: 50GB minimum. Volume: 100GB minimum for model work. ALWAYS.**

On 2026-03-29: A100 pod crashed during 19GB model download. Had 20GB container disk + 50GB volume. Ollama OOM'd on disk, pod died, all boot time wasted.

**You will be tempted to:** Use 10-20GB disk to save $0.50/month.
**Why that fails:** Disk OOM kills the pod. You lose the 5-15 min boot time + billing for that time. Rebuilding costs more than the disk.

**The right way:**
- Container disk: **50GB minimum** (OS + Docker layers + temp files)
- Volume: **100GB minimum** for any model work (models are 5-20GB each)
- For 70B+ models: **200GB volume**
- Disk costs $0.10/GB/mo. 100GB = $10/mo. A single wasted pod boot costs more.

---

## Rule RP-9: Community Cloud Has Better Image Caching Than Secure Cloud

**Popular Docker images (Ollama, PyTorch) boot in ~60s on Community Cloud but 8+ min on Secure Cloud.**

On 2026-03-29: `ollama/ollama:latest` (2GB) booted in ~60s on Community Cloud A4000. Same image never booted on Secure Cloud A100 after 8+ minutes.

**Why:** Community Cloud machines are shared by many users. Popular images get cached from prior users' pulls. Secure Cloud machines are dedicated — if nobody has pulled Ollama on that specific A100 before, it's a cold pull from Docker Hub.

**The right way:**
- **First deployment on a GPU type:** Use Community Cloud if possible — better cache hit odds
- **Need Secure Cloud (for network volumes):** Accept 5-15 min first boot. It caches after that.
- **Workaround:** Pull images to Secure Cloud once via a cheap "warm-up" pod, then future boots are fast

---

## Rule RP-10: GraphQL Uses `dockerArgs`, Not `dockerStartCmd`

**The GraphQL `podFindAndDeployOnDemand` mutation uses `dockerArgs` (string) for CMD overrides. NOT `dockerStartCmd` (array, REST only).**

```
WRONG: dockerStartCmd: ["--model", "qwen2.5:7b"]     ← REST API field, fails in GraphQL
RIGHT: dockerArgs: "--model qwen2.5:7b"               ← GraphQL field, space-separated string
```

---

## Rule RP-11: Docker Hub Auth Is Registered

**Registry auth ID: `cmncgax0w003nl20612914l16` (Docker Hub, user `michaeljboscia`)**

This gives RunPod authenticated Docker Hub pulls — higher rate limits and potentially faster pulls. Reference it in templates via `containerRegistryAuthId` when using private images.

---

## Rule RP-12: RunPod Proxy URL Is The Primary Access Method

**Format: `https://{podId}-{port}.proxy.runpod.net`**

This works without SSH, without public IP, without `supportPublicIp`. It's the fastest way to hit a running service.

Examples:
- Ollama: `https://{podId}-11434.proxy.runpod.net`
- vLLM: `https://{podId}-8000.proxy.runpod.net`
- TEI: `https://{podId}-80.proxy.runpod.net`
- Jupyter: `https://{podId}-8888.proxy.runpod.net`
