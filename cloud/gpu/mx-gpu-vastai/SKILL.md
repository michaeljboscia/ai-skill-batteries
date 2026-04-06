---
name: mx-gpu-vastai
description: Use when creating, launching, managing, or troubleshooting Vast.ai GPU instances, templates, or volumes. Also use when the user mentions 'vastai', 'vast.ai', 'vast template', 'vast instance', 'vast offer', 'vast create', or any Vast.ai MCP tool (mcp__vastai__*).
---

# Vast.ai GPU Operations

**Core principle:** Vast.ai is a decentralized GPU marketplace, not enterprise cloud. Hosts are independent machines with varying storage, networking, and reliability. Every assumption from AWS/GCP must be re-validated.

**Prerequisite:** `mx-gpu-inference` fires first for model selection, sizing, and compute cap validation. This skill handles Vast.ai-specific deployment.

## Operating Mode

| Mode | When | Claude's Role |
|---|---|---|
| **Build** | Creating templates, configuring search params | Template engineer |
| **Execute** | Launching instances, monitoring, testing | Operator |
| **Direct** | Advising on Vast.ai architecture decisions | Advisor |

## Quick Reference

- **CLI:** `vastai` (installed via `uv tool install vastai`)
- **Templates:** `~/gpu-infrastructure/vastai-templates.md`
- **Research:** `~/gpu-infrastructure/research/vastai-deployment-strategy.md`
- **Security:** `~/gpu-infrastructure/research/vastai-security-practices.md`

Read `enforcement.md` for rules. Run `validation.md` checklist before claiming deployment is complete.
