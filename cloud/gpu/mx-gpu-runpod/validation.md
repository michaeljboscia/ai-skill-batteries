# RunPod Validation Checklist

Run AFTER pod creation, BEFORE claiming deployment is complete.

## Pre-Launch Checklist
- [ ] GPU availability checked (not NONE/LOW)
- [ ] Using GraphQL API for pod creation (not REST)
- [ ] Docker image is thin (<5GB) — no baked model weights
- [ ] SSH public key included in env
- [ ] If using network volume: datacenter is US-TX-3
- [ ] If using network volume: cloudType is SECURE (not COMMUNITY)

## Post-Launch Checklist
- [ ] Pod status is RUNNING (not PENDING/THROTTLED)
- [ ] SSH connection works: `ssh root@<ip> -p <port>`
- [ ] Model is available (pulled or loaded from volume)
- [ ] Inference test produced actual output
- [ ] Proxy URL accessible: `https://{podId}-{port}.proxy.runpod.net`

## Teardown Checklist
- [ ] `vastai show instances` / RunPod console shows no running pods
- [ ] No orphaned pods billing in background

## Pressure Test Results (from core matrix)
- **GREEN (2026-03-20):** All 12 rules enforced under time+scale pressure. Cost gate stopped $1,500 weekend spend, recommended $69 alternative.
- **RED (2026-03-20):** Skill self-fired via CSO matching. No RED/GREEN gap — triggers work.
