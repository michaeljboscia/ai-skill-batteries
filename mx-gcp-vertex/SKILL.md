---
name: mx-gcp-vertex
description: Use when deploying models to Vertex AI endpoints, using Gemini API via Vertex, fine-tuning or distilling models, building RAG pipelines, configuring Vector Search, creating AI agents with Agent Builder, or managing custom training jobs. Also use when the user mentions 'Vertex AI', 'gcloud ai', 'Model Garden', 'Gemini API', 'fine-tuning', 'distillation', 'endpoint', 'online prediction', 'batch prediction', 'Vector Search', 'RAG', 'embeddings', 'Feature Store', 'Agent Builder', 'ADK', 'custom training', 'model upload', 'Model Registry', or 'Vertex AI Pipelines'.
---

# GCP Vertex AI — ML Platform & Generative AI for AI Coding Agents

**This skill loads when you're deploying, training, or serving models on Vertex AI.**

## When to also load
- `mx-gcp-iam` — Service accounts for endpoints, Workload Identity
- `mx-gcp-networking` — Private Service Connect for private endpoints
- `mx-gcp-security` — **ALWAYS load for production ML** — CMEK encryption, VPC Service Controls perimeters to prevent data exfiltration from training/prediction workloads
- `mx-gpu-inference` — Self-hosted model serving, VRAM calculations

---

## Level 1: Gemini API & Model Deployment (Beginner)

### Call Gemini via Vertex AI

```bash
# Set project and region
gcloud config set project my-project
gcloud config set ai/region us-central1

# Generate content with Gemini (REST)
curl -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  "https://us-central1-aiplatform.googleapis.com/v1/projects/my-project/locations/us-central1/publishers/google/models/gemini-2.0-flash:generateContent" \
  -d '{"contents":[{"role":"user","parts":[{"text":"Explain Kubernetes in one sentence"}]}]}'
```

**Vertex AI Gemini API vs Google AI Studio:** Vertex AI gives you VPC-SC support, CMEK, private endpoints, IAM authentication, and SLA — use it for production. Google AI Studio is for prototyping only.

### Deploy a model to an endpoint

```bash
# Upload model to Model Registry
gcloud ai models upload \
  --region=us-central1 \
  --display-name=my-classifier-v1 \
  --artifact-uri=gs://my-bucket/models/classifier/ \
  --container-image-uri=us-docker.pkg.dev/vertex-ai/prediction/sklearn-cpu.1-3:latest

# Create endpoint
gcloud ai endpoints create \
  --region=us-central1 \
  --display-name=classifier-endpoint

# Deploy model to endpoint with autoscaling
gcloud ai endpoints deploy-model ENDPOINT_ID \
  --region=us-central1 \
  --model=MODEL_ID \
  --display-name=classifier-v1 \
  --machine-type=n1-standard-4 \
  --min-replica-count=1 \
  --max-replica-count=5 \
  --traffic-split=0=100
```

**Autoscaling settings:**

| Setting | Production | Dev/Test |
|---------|------------|----------|
| `--min-replica-count` | 1+ (no cold starts) | 0 (saves cost) |
| `--max-replica-count` | Based on load test | 1-2 |
| Machine type | Match model size | Smallest viable |

### Traffic splitting for safe rollouts

```bash
# Deploy v2 alongside v1 with 10% canary
gcloud ai endpoints deploy-model ENDPOINT_ID \
  --region=us-central1 \
  --model=MODEL_V2_ID \
  --display-name=classifier-v2 \
  --machine-type=n1-standard-4 \
  --min-replica-count=1 \
  --traffic-split=0=90,DEPLOYED_MODEL_V2_ID=10
```

---

## Level 2: Fine-Tuning, RAG & Vector Search (Intermediate)

### Fine-tune Gemini (supervised)

```python
# Using Vertex AI SDK (Python)
from vertexai.tuning import sft

tuning_job = sft.train(
    source_model="gemini-2.0-flash",
    train_dataset="gs://my-bucket/tuning/train.jsonl",
    validation_dataset="gs://my-bucket/tuning/val.jsonl",
    tuned_model_display_name="my-tuned-gemini",
    epochs=3,
    learning_rate_multiplier=1.0,
)
```

**Fine-tuning data format** (JSONL, one per line):
```json
{"systemInstruction":"You are a support agent.","contents":[{"role":"user","parts":[{"text":"How do I reset?"}]},{"role":"model","parts":[{"text":"Go to Settings > Reset..."}]}]}
```

**Tuning decision tree:**

| Need | Approach |
|------|----------|
| Adjust tone/format only | Prompt engineering (no tuning) |
| Domain-specific behavior | Supervised fine-tuning (SFT) |
| Smaller model, same quality | Distillation (teacher→student) |
| Align with preferences | Reinforcement learning (RLHF) |

### Vertex AI Vector Search (for RAG)

```bash
# Create index from embeddings
gcloud ai indexes create \
  --region=us-central1 \
  --display-name=doc-embeddings \
  --metadata-file=index_metadata.json

# Create index endpoint
gcloud ai index-endpoints create \
  --region=us-central1 \
  --display-name=search-endpoint \
  --network=projects/my-project/global/networks/my-vpc

# Deploy index to endpoint
gcloud ai index-endpoints deploy-index INDEX_ENDPOINT_ID \
  --region=us-central1 \
  --index=INDEX_ID \
  --deployed-index-id=doc-search-v1 \
  --display-name=doc-search \
  --machine-type=e2-standard-16 \
  --min-replica-count=1
```

### RAG best practices

- **Chunk strategically** — not fixed-size. Use semantic boundaries (paragraphs, sections). Overlap chunks by 10-20% to preserve context at boundaries.
- **Hybrid search** — combine dense vector search with sparse keyword search. Tune the `alpha` parameter to balance semantic vs lexical matching.
- **Rerank** — use Vertex AI Reranker after initial retrieval. Fixes "lost in the middle" where relevant docs rank poorly.
- **Retrieve 3-5 docs** — start small and increase only if quality suffers. Over-retrieval dilutes signal.

---

## Level 3: Custom Training & Pipelines (Advanced)

### Custom training job

```bash
# Submit custom training job with GPU
gcloud ai custom-jobs create \
  --region=us-central1 \
  --display-name=train-detector-v3 \
  --worker-pool-spec=machine-type=n1-standard-8,accelerator-type=NVIDIA_TESLA_T4,accelerator-count=1,replica-count=1,container-image-uri=us-docker.pkg.dev/my-project/ml/trainer:v3 \
  --service-account=ml-training@my-project.iam.gserviceaccount.com \
  --args=--epochs=50,--batch-size=32,--output=gs://my-bucket/models/detector-v3/
```

**Custom training rules:**
- **Containerize everything** — use prebuilt containers for standard frameworks or custom Docker images for specialized deps
- **Co-locate data and compute** — same region for training jobs and GCS buckets
- **Set job timeouts** — prevents runaway training from burning budget
- **Use preemptible for experiments** — up to 70% cheaper, acceptable for non-critical training runs

### Vertex AI Pipelines

```bash
# Compile and run a pipeline
gcloud ai pipelines run \
  --region=us-central1 \
  --display-name=weekly-retrain \
  --template-uri=gs://my-bucket/pipelines/retrain.json \
  --service-account=ml-pipeline@my-project.iam.gserviceaccount.com
```

Pipelines orchestrate: data prep → training → evaluation → model registration → deployment. Use the Kubeflow Pipelines SDK v2 to define pipeline components in Python.

---

## Performance: Make It Fast

- **min-replica-count=1 for production endpoints** — eliminates cold starts. A cold start on a large model can take 2-5 minutes. The cost of 1 idle replica (~$50-100/month) is trivial vs user-facing latency spikes.
- **Dedicated endpoints for large models** — standard endpoints share infrastructure. Dedicated endpoints give production isolation, streaming inference, and larger payload support.
- **Batch predictions for non-real-time** — batch prediction is 50-80% cheaper than online prediction for bulk inference jobs. Use for nightly scoring, data enrichment, and model evaluation.
- **Right-size GPU for training** — start with T4 for experiments, scale to A100/H100 for production training. Monitor GPU utilization — if <50%, you're overpaying.
- **Cache embeddings** — generating embeddings is the most expensive part of RAG. Cache computed embeddings and only regenerate for new/modified documents.
- **Distillation for serving cost** — a distilled Flash model serves at 10-50x lower cost than a Pro model with comparable quality for narrow tasks.

## Observability: Know It's Working

```bash
# List deployed models on endpoint
gcloud ai endpoints describe ENDPOINT_ID \
  --region=us-central1 \
  --format="table(deployedModels.id,deployedModels.displayName,deployedModels.dedicatedResources)"

# Check custom training job status
gcloud ai custom-jobs describe JOB_ID --region=us-central1

# List tuning jobs
gcloud ai tuning-jobs list --region=us-central1

# Check model in registry
gcloud ai models list --region=us-central1
```

**Enable Vertex AI Data Access logs** from day one — export to BigQuery for audit trails.

| Alert | Severity |
|-------|----------|
| Endpoint error rate >1% | **HIGH** |
| Prediction latency p99 >5s | **HIGH** |
| Endpoint at max replicas | **MEDIUM** |
| Training job failed | **MEDIUM** |
| Tuning job failed | **MEDIUM** |
| Vector Search index >24h stale | **MEDIUM** |
| GPU utilization <20% sustained | **INFO** (over-provisioned) |

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Always set min-replica-count=1 for production endpoints
**You will be tempted to:** Leave min-replica-count at 0 because "it saves money when there's no traffic."
**Why that fails:** Model loading on cold start takes 30 seconds to 5 minutes depending on model size. The first user request after idle period times out. Health checks fail. Load balancers mark the endpoint as unhealthy. The cost of 1 idle replica is negligible compared to production reliability.
**The right way:** `--min-replica-count=1` for any endpoint serving real users. Use min=0 only for dev/test endpoints or batch-only models.

### Rule 2: Use Vertex AI Gemini API for production, not Google AI Studio API
**You will be tempted to:** Use the Google AI Studio API key (generativelanguage.googleapis.com) in production because "it works and the code is simpler."
**Why that fails:** The AI Studio API doesn't support VPC Service Controls, CMEK, private endpoints, or enterprise SLA. Your data traverses the public internet. IAM cannot restrict access. Audit logs are limited. You cannot use Private Service Connect to keep traffic on Google's network.
**The right way:** `us-central1-aiplatform.googleapis.com` with IAM authentication via service account. Use AI Studio only for prototyping and prompt development.

### Rule 3: Never assign public IPs to Vertex AI Workbench notebooks
**You will be tempted to:** Keep the default public IP on notebooks because "I need to install packages."
**Why that fails:** A public IP exposes your ML notebook (with service account credentials, data access, and model artifacts) to the internet. Notebooks are high-value targets — they often have broad IAM permissions and access to training data.
**The right way:** Private IP + Cloud NAT for outbound package installation. Enable Secure Boot, vTPM, and integrity monitoring. Disable root access. Use a dedicated service account with minimal permissions.

### Rule 4: Start with prompt engineering before fine-tuning
**You will be tempted to:** Fine-tune immediately because "our use case is unique" or "we need domain expertise."
**Why that fails:** Fine-tuning costs $2-50+ per training run, takes hours, and creates a model version you must maintain. 80% of "unique" use cases can be solved with system instructions, few-shot examples, and structured output constraints. Fine-tuning is irreversible investment — you can't un-learn bad training data.
**The right way:** (1) Prompt engineering with system instructions → (2) Few-shot examples in context → (3) Grounding with RAG → (4) Fine-tune only if 1-3 fail. Document what you tried and why it wasn't sufficient before starting a tuning job.

### Rule 5: Use traffic splitting for model deployments — never swap 100% at once
**You will be tempted to:** Deploy v2 with `--traffic-split=0=100` because "we tested it locally" or "the eval metrics look good."
**Why that fails:** Offline metrics don't capture production edge cases, latency under load, or integration issues. A full traffic swap means 100% of users hit the new model simultaneously. If v2 has a subtle regression (e.g., hallucination on a rare input class), every user is affected.
**The right way:** Deploy v2 at 5-10% traffic → monitor error rate, latency, and business metrics for 24-48 hours → increase to 50% → full rollover. Use Vertex AI model monitoring to detect prediction drift automatically.
