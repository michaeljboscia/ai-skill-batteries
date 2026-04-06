---
name: mx-aws-bedrock
description: Bedrock model selection (Claude/Nova/Titan), agents/guardrails, Knowledge Bases (RAG chunking/hybrid search/reranking), prompt management/caching, cross-region inference profiles, intelligent prompt routing, cost optimization, and AI-generated anti-patterns
---

# AWS Bedrock — Foundation Models & GenAI for AI Coding Agents

**Load this skill when integrating Bedrock models, building RAG applications, configuring guardrails, or optimizing GenAI costs.**

## When to also load
- `mx-aws-lambda` — Lambda as Bedrock agent action group
- `mx-aws-analytics` — Redshift ML + Bedrock SQL integration
- `mx-aws-security` — Guardrails, VPC endpoints for Bedrock, KMS encryption
- `mx-aws-billing` — Token cost tracking, provisioned throughput pricing

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: Model Selection Decision Tree

| Need | Model | Why |
|------|-------|-----|
| Complex reasoning, long context | **Claude** (Sonnet/Opus) | High accuracy, safety, excellent long-context |
| Fast text, cheapest | **Nova Micro** | Text-only, minimal cost |
| Multimodal (image/video input) | **Nova Lite/Pro** | Low-cost multimodal processing |
| Embeddings (vectors for RAG) | **Titan Text Embeddings** | Optimized for search/retrieval |
| Image generation | **Nova Canvas** | Text-to-image |
| Quick prototyping | **Titan Text Express** | Fast, cheap, good enough for prototypes |

**Start with the smallest model that works.** Nova Micro often suffices for classification, extraction, simple generation.

### Pattern 2: Guardrails on Every Production Application
| BAD | GOOD |
|-----|------|
| Raw model output to users | Guardrails: content filters, denied topics, word filters, PII detection |

Guardrails are non-negotiable for user-facing applications. Configure: content filters (hate, violence, sexual), denied topics, word/phrase filters, PII redaction.

### Pattern 3: Prompt Caching for Repetitive Workloads
| BAD | GOOD |
|-----|------|
| Resending same system prompt on every request | Prompt caching: up to 85% latency reduction + 90% cost reduction |

**GA April 2025.** Cache frequently used prompt prefixes. Static content at beginning of prompt. Exact prefix match required. Supported: Nova (Micro/Lite/Pro) + Claude (3.5 Haiku, 3.7 Sonnet).

### Pattern 4: Structured Prompts with Variables
Use Bedrock Prompt Management: define system instructions + tools + user messages in standardized format. Variables (`{{variable_name}}`) for dynamic content. Version control. Auto-optimization.

### Pattern 5: VPC Endpoints for Bedrock
Keep model invocations on AWS backbone. No internet traversal. Required for sensitive/regulated workloads.

---

## Level 2: RAG & Knowledge Bases (Intermediate)

### Knowledge Base Chunking Strategies

| Strategy | Best For | Trade-off |
|----------|----------|-----------|
| **Fixed-size** | Simple documents | Fast but may split context |
| **Hierarchical** | Structured docs (parent/child tree) | Good for documents with sections |
| **Semantic** | Mixed content | Higher quality but more compute |
| **Custom (Lambda)** | Domain-specific | Full control, most complex |

### Retrieval Optimization

| Feature | Purpose |
|---------|---------|
| **Hybrid search** | Vector (semantic) + keyword (full-text). OpenSearch Serverless, Aurora PgSQL, MongoDB Atlas |
| **Metadata filtering** | Pre-filter by date/category/tags before semantic search |
| **Reranking** | Post-retrieval relevance reordering. Amazon Rerank 1.0 / Cohere Rerank 3.5 |
| **Multi-modal RAG** | Search across text, images, audio, video (GA late 2025) |

### Knowledge Base Evaluation
- Built-in metrics: context relevance, faithfulness, correctness, completeness, harmfulness
- Custom metrics with judge prompts
- RAGAS framework integration for retrieval + generation quality assessment

### Agent Architecture
- Agents orchestrate: model invocation + knowledge base retrieval + action group execution
- Action groups: Lambda functions or API schemas
- Session management: multi-turn conversations with context
- Guardrails apply to agent interactions too

---

## Level 3: Cost Optimization & Cross-Region (Advanced)

### Cross-Region Inference Profiles (CRIS)
- Auto-routes to optimal region during high demand
- **Geographic**: within US/EU/APAC boundaries (data residency compliance)
- **Global**: any commercial region (~10% cost savings)
- No extra data transfer cost. Charges based on source region
- Customer data remains in source region (end-to-end encryption)

### Intelligent Prompt Routing (Jan 2025)
- Auto-routes simple queries to smaller/cheaper models, complex to larger
- Up to **30% cost reduction** without quality loss
- No application code changes needed

### Model Distillation
- Fine-tune smaller "student" models to match larger "teacher" models for specific tasks
- Bedrock-native distillation workflow
- Result: cheaper inference with task-specific accuracy

### Pricing Models

| Model | Best For | Savings |
|-------|----------|---------|
| **On-Demand** | Variable workloads | Pay per token |
| **Batch Inference** | Bulk processing | Up to 50% cheaper |
| **Provisioned Throughput** | Predictable workloads | 40-60% cheaper (1-6 month commit) |

### Cost Levers
1. **Right-size model** — Nova Micro for simple, Claude for complex
2. **Prompt caching** — 90% input token cost reduction
3. **Intelligent routing** — 30% auto-routing savings
4. **Context window management** — trim prompts, summarize history, enforce token caps
5. **Batch inference** — 50% off for non-real-time processing
6. **CRIS Global** — ~10% via cross-region distribution

---

## Performance: Make It Fast

### Optimization Checklist
1. **Prompt caching** — 85% latency reduction for cached prefixes
2. **Smallest sufficient model** — Nova Micro for simple tasks
3. **CRIS** — distributes load, prevents rate limiting
4. **Streaming responses** — use `InvokeModelWithResponseStream` for lower TTFB
5. **Concise prompts** — fewer input tokens = faster + cheaper
6. **Prompt optimization** — Bedrock auto-rewrites for efficiency

### Latency Reduction
- Static content at prompt beginning (caching requirement)
- Use streaming for all user-facing responses
- CRIS prevents regional throttling during peaks
- Provisioned Throughput for guaranteed latency SLAs

---

## Observability: Know It's Working

### What to Monitor

| Signal | Metric | Alert Threshold |
|--------|--------|-----------------|
| Token usage | `InputTokenCount`, `OutputTokenCount` | Budget-based threshold |
| Latency | `InvocationLatency` P99 | >5s for chat applications |
| Errors | `InvocationClientErrors`, `InvocationServerErrors` | >1% error rate |
| Cache | Cache hit rate (API response) | <50% = review prompt structure |
| Throttle | `ThrottledCount` | >0 sustained = enable CRIS |
| Cost | Per-model token costs via inference profiles | Trending above budget |

- **Application inference profiles**: per-workload/tenant cost tracking
- **Cost allocation tags** on Bedrock resources for chargeback
- **CloudWatch Logs** for request/response auditing (careful: don't log sensitive data)
- **Guardrail metrics**: blocked/filtered request rates

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Largest Model by Default
**You will be tempted to:** Use Claude Opus or the latest flagship model for everything
**Why that fails:** 10-50x cost premium over Nova Micro for tasks that don't need the capability. Classification, extraction, and simple generation work fine on smaller models
**The right way:** Start with Nova Micro or Haiku. Test quality. Upgrade only if results are insufficient. Use intelligent prompt routing for automatic selection

### Rule 2: No Production Without Guardrails
**You will be tempted to:** Ship without guardrails because "the model is safe enough"
**Why that fails:** Models hallucinate, generate inappropriate content, and leak PII. One bad response = PR crisis, compliance violation, or data breach
**The right way:** Guardrails on every production endpoint: content filters, denied topics, PII detection. Test with adversarial inputs

### Rule 3: No Repetitive Prompts Without Caching
**You will be tempted to:** Send the same system prompt on every request
**Why that fails:** You're paying full price to reprocess identical context thousands of times per day. 90% waste
**The right way:** Prompt caching. Static system instructions cached. Dynamic user input appended. Monitor cache hit rate

### Rule 4: No Hardcoded Model IDs
**You will be tempted to:** Hardcode `anthropic.claude-3-sonnet-v1` in application code
**Why that fails:** Models get deprecated, new versions launch, pricing changes. Hardcoded IDs require code changes for every model update
**The right way:** Configuration-driven model selection. Environment variables or parameter store. Easy to switch models without code changes

### Rule 5: No RAG Without Evaluation
**You will be tempted to:** Ship a Knowledge Base without measuring retrieval quality
**Why that fails:** Bad chunking, wrong embedding model, or poor search configuration produces irrelevant context. Model generates confident but wrong answers based on bad retrieval
**The right way:** Evaluate with built-in metrics (context relevance, faithfulness). Test with known Q&A pairs. Iterate on chunking strategy + search configuration before production
