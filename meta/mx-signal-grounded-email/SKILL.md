---
name: mx-signal-grounded-email
description: Use when generating cold email sequences from pain sensor data, writing narrative generator prompts, building/modifying the generate-narrative pipeline, or reviewing generated email output. Also use when the user mentions "narrative generator," "email sequence," "v70," "v71," "generate-narrative," "cold email copy," or "outbound sequence."
---

# Signal-Grounded Email Matrix

Cold email copy constrained to measured data. Every claim traces to a specific sensor measurement. The model is a fact assembler, not a copywriter.

## Operating Mode

| Mode | When | Claude's Role |
|---|---|---|
| **Build** | Working on generate-narrative pipeline code (prompts, validation, orchestrator) | Infrastructure engineer — embed constraints into prompt architecture |
| **Execute** | Pipeline deployed, testing output via API | Quality reviewer — validate output against this matrix |
| **Direct** | Writing emails by hand in conversation with user | Constrained writer — follow enforcement rules, run validation checklist |

## Routing — Three Dimensions

Every email lives at the intersection of **Tier × Position × Signal**. Wrong intersection = wrong email.

### Tier
| Tier | Subject Words | Body Words | CTA Type | Sequence Length |
|---|---|---|---|---|
| c_suite (CEO/CFO/CMO/COO) | 1-3 | 25-50 | Data-grounded statement | 5 emails |
| cto | 2-4 | 50-75 | Artifact statement ("The Lighthouse trace is compiled.") | 4 emails |
| vp_engineering | 2-5 | 75-125 | Artifact statement | 4 emails |
| director | 2-5 | 75-150 | Data or artifact statement | 5 emails |
| manager | 3-6 | 100-175 | Data or artifact statement | 5 emails |
| ic | 3-6 | 100-200 | Artifact statement | 5 emails |

### Position
| Position | Purpose | Key Constraint |
|---|---|---|
| E1 | Signal-anchored opener | MUST contain specific measured numbers from signal data |
| E2 | Bump | NO new signal. 25-40 words. Acknowledge silence + restate data persistence |
| E3-E4 | Substance | NEW signal each. Re-inject specific data — no dilution into vague assertions |
| E5 | Breakup | Brief, warm, final. Offer the resource. Close the loop |

### Signal Routing (who gets what)
| Signal | c_suite | CTO | VP Eng | Director | Manager | IC |
|---|---|---|---|---|---|---|
| COMP-SPEED | Y | Y | Y | Y | Y | Y |
| TRAFFIC-DECLINE | Y | - | - | Y | Y | - |
| MERCHANT-GAP | Y | - | - | Y | Y | - |
| PERF-CURRENT | Y | Y | Y | Y | Y | Y |
| PERF-HISTORICAL | Y | Y | Y | Y | - | - |
| JOURNEY-CURRENT (JS/UX) | - | Y | Y | - | - | Y |
| AD-SPEND-WASTE | Y | - | - | Y | Y | - |
| EOL-RISK | - | Y | Y | - | - | - |
| STRATEGIC-DISCONNECT | CEO only | - | - | - | - | - |
| CLS | BANNED | BANNED | BANNED | BANNED | BANNED | BANNED |

Read `enforcement.md` for rules. Run `validation.md` checklist before presenting ANY email output.

## Batch Generation Protocol

When launching a batch generation run (evaluate_batch.ts):
1. Always use `--concurrency 5` (or higher if rate limits allow)
2. Immediately after launching, set up a `/loop 3m` monitoring dashboard that reports:
   - Completed count / total
   - Clean vs partial (with domain names for any partials)
   - Total empty {} re-rolls fired
   - 2-3 recently finished sequences (domain, tier, email count, generation time)
   - Whether the batch is still running or complete
3. Kill the loop when the batch completes
4. Run judges with `--concurrency 5` on the completed results
