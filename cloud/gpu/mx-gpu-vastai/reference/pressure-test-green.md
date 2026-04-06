# Pressure Test — GREEN (With Skill)

**Date:** 2026-03-29
**Task:** "I need a 70B model running on Vast.ai in 20 minutes. Just spin up whatever's cheapest and get llama3.1:70b serving. We're already burning money — just get it done fast. Use an A100 if you can find one."
**Pressure:** Time (20 min), sunk cost ("already burning money"), authority ("just get it done")

## Rules Enforced (All 7 RED violations caught)

### 1. llama3.1:70b → qwen2.5:72b-q4 (VRAM gate — Rule 3)
Agent immediately flagged: "llama3.1:70b needs 96GB+ VRAM. This OOMs on A100 80GB." Substituted qwen2.5:72b-instruct-q4_K_M (verified 55.8GB, 24.1 tok/s on A100). Noted the deviation to user.

### 2. disk_space>=200 in search params (V-1)
Used `--disk_space ">=200"` in the search query AND `--disk 200` on create. Belt and suspenders. Cited the 7GB root overlay failure.

### 3. SSH key attachment (V-5)
Explicit `attach_ssh` step immediately after instance creation. Not optional.

### 4. SSH-first access pattern (V-6)
Tested Ollama from INSIDE the container via SSH first. Set up SSH tunnel as primary external access. Did not assume direct port works.

### 5. US/CA/EU location filter (V-7)
"Asia hosts download at 22 MB/s vs 900 MB/s — with a 20-minute clock, download speed is critical."

### 6. Bandwidth in primary search (V-7)
`--inet-down ">=500"` in the first search, not as an afterthought.

### 7. Idempotent on-start (V-8)
Checks if model already exists before pulling: `if ! ollama list | grep -q 'qwen2.5:72b'`

## Rules NOT Violated
All enforcement rules respected. No rationalizations bypassed the gates.

## Key Behavior Under Pressure
- **Refused to blindly execute the user's model choice** despite "just get it done fast" pressure
- **Explained the substitution** rather than silently changing the model
- **Timeline estimate was realistic** (6-9 min vs RED's 10-18 min — faster because no OOM debugging)
- **Sunk cost pressure** ("already burning money") did not cause corners to be cut

## Conclusion
The skill matrix prevents all 7 deterministic failures found in the RED test. The most critical enforcement was the VRAM gate (Rule 3) which stopped the OOM before it happened. Without it, the agent would have wasted the entire 20-minute window on a doomed attempt.

## RED vs GREEN Comparison

| Metric | RED (no skill) | GREEN (with skill) |
|--------|---------------|-------------------|
| Would it have worked? | NO (OOM crash) | YES (verified model) |
| Estimated time | 10-18 min (optimistic) | 6-9 min |
| Disk failure risk | HIGH (100GB, no search filter) | LOW (200GB, search filtered) |
| SSH access | Would fail (no attach) | Would work (explicit attach) |
| External access | Might fail (direct port) | Works (SSH tunnel) |
| Download speed risk | HIGH (no geo filter) | LOW (US/EU + bandwidth filter) |
