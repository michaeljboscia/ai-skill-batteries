---
name: mx-gcp-data
description: Use when building data pipelines with Dataflow/Apache Beam, running Spark jobs on Dataproc, configuring Pub/Sub messaging, transferring data with Storage Transfer Service, or designing visual ETL with Data Fusion. Also use when the user mentions 'Dataflow', 'Apache Beam', 'Dataproc', 'Spark', 'Pub/Sub', 'topic', 'subscription', 'Pub/Sub Lite', 'Data Fusion', 'CDAP', 'Storage Transfer', 'streaming pipeline', 'batch pipeline', 'dead-letter', 'FlexRS', 'Flex Template', 'gcloud dataflow', 'gcloud dataproc', 'gcloud pubsub', or 'event-driven'.
---

# GCP Data — Dataflow, Dataproc, Pub/Sub & Transfer for AI Coding Agents

**This skill loads when you're building data pipelines, messaging systems, or moving data on GCP.**

## When to also load
- `mx-gcp-bigquery` — Dataflow sinks to BigQuery, BQ Storage Write API
- `mx-gcp-storage` — GCS sources/sinks for pipelines, transfer jobs
- `mx-gcp-serverless` — Cloud Run + Pub/Sub event-driven patterns
- `mx-gcp-security` — **ALWAYS load** — CMEK for Pub/Sub topics, VPC-SC for data perimeters, no public Pub/Sub topics

---

## Level 1: Pub/Sub Messaging (Beginner)

### Create a topic and subscription

```bash
# Create topic
gcloud pubsub topics create order-events

# Create pull subscription with dead-letter
gcloud pubsub topics create order-events-dlq

gcloud pubsub subscriptions create order-processor \
  --topic=order-events \
  --ack-deadline=60 \
  --dead-letter-topic=order-events-dlq \
  --max-delivery-attempts=5 \
  --enable-message-ordering
```

**Key settings:**

| Setting | Default | Production recommendation |
|---------|---------|--------------------------|
| `--ack-deadline` | 10s | Match your processing time + buffer |
| `--dead-letter-topic` | None | **Always configure** — catches poison messages |
| `--max-delivery-attempts` | 5 | 5-10 depending on retry strategy |
| `--message-retention-duration` | 7d | Set on topic for replay capability |
| `--expiration-period` | 31d | `never` for production subscriptions |

### Pub/Sub rules

- **At-least-once delivery** — consumers MUST be idempotent. Duplicate messages WILL happen.
- **Attach subscription before publishing** — messages published to a topic with no subscriptions are lost forever.
- **Process before acknowledging** — premature ack + processing failure = lost message.
- **Tune ack deadline** — default 10s causes redelivery storms if processing takes longer.

### Subscription types

| Type | Use case |
|------|----------|
| Pull | Application-managed consumption, most flexible |
| Push | HTTP endpoint triggered per message (Cloud Run, Functions) |
| BigQuery | Direct write to BQ table, no consumer code needed |
| Cloud Storage | Write messages to GCS as Avro/text files |

---

## Level 2: Dataflow Pipelines (Intermediate)

### Which processing service to use

| Requirement | Service | Why |
|-------------|---------|-----|
| New pipelines, unified batch+streaming | **Dataflow** | Serverless, Apache Beam, auto-scaling |
| Existing Spark/Hadoop code | **Dataproc** | Drop-in managed Spark cluster |
| Spark without cluster management | **Dataproc Serverless** | Serverless Spark, pay-per-use |
| Visual ETL, non-engineers | **Data Fusion** | Drag-and-drop, 150+ connectors |
| Simple GCS-to-GCS transfer | **Storage Transfer Service** | Managed, scheduled, cross-cloud |

### Run a Dataflow batch job

```bash
# Run from a Flex Template (recommended for CI/CD)
gcloud dataflow flex-template run my-etl-job \
  --template-file-gcs-location=gs://my-bucket/templates/etl.json \
  --region=us-east1 \
  --parameters input=gs://my-bucket/input/*.csv,output=my-project:dataset.table \
  --service-account-email=df-etl@my-project.iam.gserviceaccount.com \
  --max-workers=10 \
  --staging-location=gs://my-bucket/staging/

# Run with FlexRS for cost savings (batch only, delayed start)
gcloud dataflow flex-template run my-batch-job \
  --template-file-gcs-location=gs://my-bucket/templates/batch.json \
  --region=us-east1 \
  --flexrs-goal=COST_OPTIMIZED \
  --parameters input=gs://my-bucket/data/
```

**FlexRS** uses preemptible VMs and delayed scheduling for up to 40% cost reduction on batch jobs that aren't time-sensitive.

### Run a Dataflow streaming job

```bash
gcloud dataflow flex-template run my-stream-job \
  --template-file-gcs-location=gs://my-bucket/templates/stream.json \
  --region=us-east1 \
  --parameters inputSubscription=projects/my-project/subscriptions/order-processor \
  --enable-streaming-engine \
  --service-account-email=df-stream@my-project.iam.gserviceaccount.com
```

**Always enable `--enable-streaming-engine`** — moves pipeline state off worker VMs for better scaling and lower cost.

### Dataproc Serverless Spark

```bash
# Submit a PySpark job — no cluster to manage
gcloud dataproc batches submit pyspark gs://my-bucket/jobs/etl.py \
  --region=us-east1 \
  --subnet=projects/my-project/regions/us-east1/subnetworks/my-subnet \
  --service-account=dp-batch@my-project.iam.gserviceaccount.com \
  --properties=spark.executor.memory=4g,spark.executor.cores=2 \
  -- --input=gs://my-bucket/data/ --output=gs://my-bucket/output/
```

---

## Level 3: Advanced Patterns (Advanced)

### Storage Transfer Service (cross-cloud & bulk)

```bash
# Transfer from S3 to GCS (recurring daily)
gcloud transfer jobs create \
  s3://source-bucket gs://destination-bucket \
  --source-creds-file=aws-creds.json \
  --name=s3-to-gcs-daily \
  --schedule-starts=2026-04-05T02:00:00Z \
  --schedule-repeats-every=24h \
  --overwrite-objects-already-existing-in-sink
```

**When to use which transfer method:**

| Data size | Method |
|-----------|--------|
| < 1TB, one-time | `gcloud storage cp` or `rsync` |
| > 1TB or recurring | Storage Transfer Service |
| Cross-cloud (S3/Azure) | Storage Transfer Service |
| > 100TB, offline | Transfer Appliance |

### Dataflow pipeline design patterns

```python
# BAD: no dead-letter handling — one bad record kills the pipeline
records | beam.Map(process_record) | beam.io.WriteToBigQuery(table)

# GOOD: dead-letter queue for failed records
results = records | beam.Map(process_record).with_exception_handling(
    dead_letter=failed_records
)
results.good | beam.io.WriteToBigQuery(table)
results.failed | beam.io.WriteToText('gs://bucket/dlq/')
```

**Pipeline anti-patterns to avoid:**
- **Hot keys** — uneven key distribution bottlenecks GroupByKey. Salt keys with random prefix.
- **Fusion over-optimization** — Dataflow fuses steps. Break fusion with `Reshuffle` when a CPU-intensive step starves downstream.
- **Side inputs for large data** — side inputs fit in memory. Use CoGroupByKey for large joins.
- **Legacy streaming inserts to BQ** — use BigQuery Storage Write API instead (faster, cheaper, exactly-once).

### Pub/Sub to BigQuery (no code)

```bash
# Direct BigQuery subscription — no consumer code needed
gcloud pubsub subscriptions create events-to-bq \
  --topic=order-events \
  --bigquery-table=my-project:dataset.events \
  --use-topic-schema \
  --write-metadata
```

---

## Performance: Make It Fast

- **Dataflow Streaming Engine** — always enable. Moves state management off workers, reduces worker memory, and improves autoscaling response time.
- **FlexRS for batch** — 40% cost reduction by using preemptible VMs and delayed scheduling. Only for jobs where a 6-hour delay is acceptable.
- **Pub/Sub batching** — configure publisher batch settings to group messages. Reduces per-message overhead for high-throughput topics.
- **Dataproc ephemeral clusters** — create cluster → run job → delete cluster. Never leave Dataproc clusters running idle. Dataproc Serverless handles this automatically.
- **Avoid Dataflow hot keys** — monitor for uneven key distribution in GroupByKey. A single hot key can bottleneck the entire pipeline regardless of worker count. Salt with random suffix.
- **BQ Storage Write API** — use instead of legacy streaming inserts for Dataflow→BigQuery. 50% cheaper, exactly-once delivery, higher throughput.

## Observability: Know It's Working

```bash
# Check Dataflow job status
gcloud dataflow jobs list --region=us-east1 --status=active

# Check Dataflow job details
gcloud dataflow jobs describe JOB_ID --region=us-east1

# Check Pub/Sub subscription backlog
gcloud pubsub subscriptions describe order-processor \
  --format="get(numUndeliveredMessages)"

# Check Dataproc batch status
gcloud dataproc batches list --region=us-east1
```

**Key Pub/Sub metrics to alert on:**
- `subscription/num_undelivered_messages` — backlog growing = consumers can't keep up
- `subscription/oldest_unacked_message_age` — age growing = processing stalled
- `subscription/dead_letter_message_count` — poison messages accumulating

| Alert | Severity |
|-------|----------|
| Pub/Sub backlog >10K messages for 15min | **HIGH** |
| Oldest unacked message >1 hour | **HIGH** |
| Dataflow job system lag >5 minutes | **HIGH** |
| Dataflow worker CPU >90% sustained | **MEDIUM** |
| Dead-letter queue depth increasing | **HIGH** |
| Dataproc batch job failed | **MEDIUM** |
| Storage Transfer job failed | **MEDIUM** |

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Always configure dead-letter topics on Pub/Sub subscriptions
**You will be tempted to:** Skip `--dead-letter-topic` because "our messages are clean" or "we'll handle errors in the consumer."
**Why that fails:** One malformed message that can't be parsed causes infinite redelivery. The consumer crashes, restarts, pulls the same message, crashes again. This blocks ALL messages behind it. The subscription backlog grows until you manually ack or seek past the bad message — at 3 AM.
**The right way:** `--dead-letter-topic` + `--max-delivery-attempts=5` on every subscription. Monitor the DLQ. A message in the DLQ is a bug to fix, not a message to lose.

### Rule 2: Pub/Sub consumers must be idempotent
**You will be tempted to:** Assume exactly-once delivery because "Pub/Sub is a managed service."
**Why that fails:** Pub/Sub guarantees at-least-once, not exactly-once. Network retries, ack deadline expiry, and rebalancing ALL cause duplicate delivery. A non-idempotent consumer (e.g., "increment counter", "charge credit card") will double-process.
**The right way:** Deduplication key (message ID or business key) + check-before-process pattern. Store processed IDs in a fast cache (Memorystore) with TTL matching the message retention period.

### Rule 3: Never leave Dataproc clusters running idle
**You will be tempted to:** Keep a Dataproc cluster running because "the next job runs in 2 hours" or "it takes 5 minutes to start."
**Why that fails:** Dataproc charges per VM-minute. A 10-node n2-standard-4 cluster costs ~$2/hour idle. Over a weekend that's $96 wasted. Over a month of "we'll delete it later" that's $1,440. Cluster start time is 60-90 seconds for Dataproc Serverless.
**The right way:** Ephemeral clusters: create → run → delete. Or use Dataproc Serverless which auto-provisions and auto-deletes. Schedule with Cloud Scheduler if recurring.

### Rule 4: Use Flex Templates, not Classic Templates for Dataflow
**You will be tempted to:** Use Classic Templates because "the documentation example uses them" or "it's simpler."
**Why that fails:** Classic Templates require pre-staging the pipeline at template creation time, can't use runtime parameters for complex logic, and have limited dependency management. Flex Templates package your pipeline as a Docker image with full dependency control.
**The right way:** `gcloud dataflow flex-template build` to create, `gcloud dataflow flex-template run` to execute. Flex Templates integrate with CI/CD, support arbitrary runtime parameters, and handle custom dependencies via Docker.

### Rule 5: Always enable Streaming Engine for Dataflow streaming jobs
**You will be tempted to:** Skip `--enable-streaming-engine` because "the default works fine" or "I don't know what it does."
**Why that fails:** Without Streaming Engine, pipeline state (windows, timers, counters) is stored on worker VMs. This means workers need more memory, autoscaling is slower (state must be redistributed), and worker preemption causes state loss and reprocessing. Streaming Engine moves state to a managed backend.
**The right way:** `--enable-streaming-engine` on every streaming Dataflow job. There's no cost penalty — it's the same pricing. Also enable Runner V2 for improved performance.
