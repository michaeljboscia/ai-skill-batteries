# Vast.ai Validation Checklist

Run AFTER template creation or instance launch, BEFORE claiming deployment is complete.

## Template Creation Checklist
- [ ] `disk_space>=N` is in `search_params` (not just `--disk_space`)
- [ ] TEI templates have correct compute_cap range in search_params
- [ ] `HUGGINGFACE_HUB_CACHE=/workspace/models` set for TEI templates
- [ ] `OLLAMA_MODELS=/workspace/models` set for Ollama templates
- [ ] On-start script is idempotent (safe to run on restarts)
- [ ] `--ssh --direct` flags set
- [ ] `inet_down>500` in search_params (fast download hosts)
- [ ] `reliability>0.95` in search_params

## Instance Launch Checklist
- [ ] `attach_ssh` called immediately after creation
- [ ] Host is in US/CA/EU (not Asia — slow HF downloads)
- [ ] `vastai show instances` confirms status = running
- [ ] `vastai logs <ID>` shows no errors
- [ ] Model pull started (check `/api/tags` for Ollama or onstart.log for TEI)
- [ ] Inference test produced actual output (not empty/error)
- [ ] `vastai destroy instance <ID>` when done (no orphaned billing)

## Post-Destruction Checklist
- [ ] `vastai show instances` returns empty table
- [ ] No instances in "loading" or "running" state
