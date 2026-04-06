---
name: mx-gpu-runpod
description: Use when creating, launching, managing, or troubleshooting RunPod GPU pods, network volumes, serverless endpoints, or templates. Also use when the user mentions 'runpod', 'RunPod', 'runpod pod', 'runpod serverless', 'network volume', 'FlashBoot', 'runpod template', or any RunPod MCP tool (mcp__runpod__*).
---

# RunPod GPU Operations

**Core principle:** RunPod has two APIs (REST and GraphQL) that behave differently, two cloud tiers (Secure and Community) with different capabilities, and network volumes that only work in specific regions. Know which tool to use for which task.

**Prerequisite:** `mx-gpu-inference` fires first for model selection, sizing, and compute cap validation. This skill handles RunPod-specific deployment.

## Operating Mode

| Mode | When | Claude's Role |
|---|---|---|
| **Build** | Creating templates, configuring pods, setting up network volumes | Infrastructure engineer |
| **Execute** | Launching pods, monitoring, testing inference | Operator |
| **Direct** | Advising on RunPod architecture decisions | Advisor |

## Quick Reference

- **Network Volume:** `gtm-models` (ID: `iwnymg3nd3`, US-TX-3, 50GB)
- **Templates:** `n6gmw9so7c` (TEI), `b52zkov0u7` (Ollama)
- **Docker Hub:** `michaeljboscia/tei-embedding:v2-thin` (4GB thin image)
- **Launcher script:** `~/gpu-infrastructure/runpod-launch.sh`

Read `enforcement.md` for rules. Run `validation.md` checklist before claiming deployment is complete.
