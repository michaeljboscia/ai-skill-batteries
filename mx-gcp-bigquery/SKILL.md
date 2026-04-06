---
name: mx-gcp-bigquery
description: Use when writing BigQuery queries, creating datasets/tables, managing partitioning/clustering, controlling query costs, or optimizing BigQuery performance. Also use when the user mentions 'bq', 'BigQuery', 'bq query', 'dataset', 'partitioned table', 'clustered table', 'slots', 'on-demand', 'flat-rate', 'editions', 'scheduled query', 'materialized view', 'INFORMATION_SCHEMA', 'DML', 'DDL', 'external table', or 'query cost'.
---

# GCP BigQuery — Data Warehouse for AI Coding Agents

**This skill loads when you're querying, designing, or managing BigQuery resources.**

## When to also load
- `mx-gcp-iam` — Dataset/table-level IAM, authorized views
- `mx-gcp-storage` — External tables on GCS, export patterns
- `mx-gcp-security` — CMEK, column-level security, data masking

---

## Level 1: Queries & Cost Control (Beginner)

### ALWAYS estimate cost before running queries

```bash
# Dry run — shows bytes scanned without executing
bq query --dry_run --use_legacy_sql=false \
  'SELECT * FROM `my-project.my_dataset.large_table`'

# Or with gcloud
bq query --nouse_legacy_sql --dry_run \
  'SELECT col1, col2 FROM `my-project.my_dataset.large_table` WHERE date = "2026-04-01"'
```

**Cost formula:** Bytes scanned x $6.25/TB (on-demand pricing). A `SELECT *` on a 10TB table = $62.50 per query.

### Cost control patterns

```sql
-- BAD: scans entire table
SELECT * FROM `project.dataset.events`;

-- GOOD: select only needed columns (columnar storage = only scanned columns cost money)
SELECT user_id, event_type, timestamp
FROM `project.dataset.events`
WHERE DATE(timestamp) = '2026-04-01';

-- GOOD: use partitioned table filter (eliminates partition scans)
SELECT user_id, event_type
FROM `project.dataset.events`
WHERE _PARTITIONDATE = '2026-04-01';

-- GOOD: LIMIT does NOT reduce cost for scanned data, but reduces output
-- Use WHERE clauses to reduce scanned data instead
```

### Maximum bytes billed (safety net)

```bash
# Set max bytes — query fails if it would exceed this
bq query --maximum_bytes_billed=1000000000 --nouse_legacy_sql \
  'SELECT * FROM `project.dataset.big_table`'
```

Set `--maximum_bytes_billed` on every ad-hoc query. 1GB = 1000000000 bytes.

---

## Level 2: Table Design (Intermediate)

### Partitioning + Clustering

```sql
-- Create partitioned + clustered table
CREATE TABLE `project.dataset.events`
(
  event_id STRING,
  user_id STRING,
  event_type STRING,
  properties JSON,
  timestamp TIMESTAMP
)
PARTITION BY DATE(timestamp)
CLUSTER BY user_id, event_type
OPTIONS(
  require_partition_filter = true,
  partition_expiration_days = 365
);
```

| Feature | What it does | When to use |
|---------|-------------|-------------|
| Partitioning | Divides table into segments by column | Always for time-series data (DATE, TIMESTAMP, INTEGER) |
| Clustering | Sorts data within partitions by columns | Columns frequently in WHERE/JOIN/GROUP BY |
| `require_partition_filter` | Rejects queries without partition filter | **Always enable** — prevents full-table scans |
| `partition_expiration_days` | Auto-deletes old partitions | Data retention compliance |

**Partition limit:** 4,000 partitions per table. For daily partitions = ~11 years.

### Materialized views

```sql
CREATE MATERIALIZED VIEW `project.dataset.daily_summary`
AS
SELECT
  DATE(timestamp) AS day,
  event_type,
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_id) AS unique_users
FROM `project.dataset.events`
GROUP BY day, event_type;
```

BigQuery auto-maintains materialized views and uses them transparently to accelerate queries against the base table.

### Dataset creation

```bash
gcloud alpha bq datasets create my_dataset \
  --location=us-east1 \
  --default-table-expiration=86400 \
  --description="Production analytics"

# Or with bq CLI
bq mk --dataset --location=us-east1 \
  --default_table_expiration=86400 \
  --description="Production analytics" \
  my-project:my_dataset
```

---

## Level 3: Advanced Patterns (Advanced)

### Pricing models

| Model | How it works | Best for |
|-------|-------------|----------|
| On-demand | $6.25/TB scanned | Ad-hoc, variable workloads |
| Standard edition | $0.04/slot-hour (autoscale) | Predictable workloads |
| Enterprise edition | $0.06/slot-hour + governance | Enterprise features |
| Enterprise Plus | $0.10/slot-hour + premium | Max performance |

**Slots vs on-demand decision:** If monthly spend >$2K on-demand, evaluate editions. Autoscaling editions = pay for slots used, not provisioned.

### Scheduled queries

```bash
bq query --schedule='every 24 hours' \
  --display_name='daily_aggregation' \
  --destination_table='project:dataset.daily_agg' \
  --replace=true \
  --use_legacy_sql=false \
  'SELECT DATE(timestamp) AS day, COUNT(*) AS cnt FROM `project.dataset.events` GROUP BY 1'
```

### External tables (query GCS directly)

```sql
CREATE EXTERNAL TABLE `project.dataset.gcs_logs`
OPTIONS(
  format = 'PARQUET',
  uris = ['gs://my-bucket/logs/*.parquet']
);
```

External tables: no storage cost but slower queries. Use for infrequent access to GCS data.

---

## Performance: Make It Fast

- **SELECT only needed columns** — columnar storage means unused columns aren't read
- **Partition filter required** — prevents accidental full-table scans
- **Cluster by high-cardinality filter columns** — up to 4 columns
- **Avoid `SELECT *`** — always specify columns
- **Use approximate functions** — `APPROX_COUNT_DISTINCT()` vs `COUNT(DISTINCT)` (much faster)
- **Materialize repeated subqueries** — CTEs are re-executed; use temp tables for large intermediate results
- **Avoid cross-joins** — BigQuery charges for the Cartesian product

## Observability: Know It's Working

```bash
# Check recent query costs
bq ls --jobs --max_results=10 --format=prettyjson | jq '.[].statistics.totalBytesProcessed'

# INFORMATION_SCHEMA for table metadata
SELECT table_name, row_count, size_bytes/1e9 AS size_gb
FROM `project.dataset.INFORMATION_SCHEMA.TABLE_STORAGE`
ORDER BY size_bytes DESC;

# Query cost audit
SELECT user_email, SUM(total_bytes_processed)/1e12 AS tb_scanned
FROM `region-us`.INFORMATION_SCHEMA.JOBS
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY user_email ORDER BY tb_scanned DESC;
```

| Alert | Severity |
|-------|----------|
| Query scanning >1TB | **HIGH** (cost gate) |
| Daily spend >$100 | **HIGH** |
| Query without partition filter on partitioned table | **MEDIUM** |
| Scheduled query failure | **MEDIUM** |

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Always dry-run before executing large queries
**You will be tempted to:** Run `SELECT * FROM big_table` to "see what's in there."
**Why that fails:** BigQuery charges for bytes scanned. A single `SELECT *` on a multi-TB table can cost $50+. There's no undo.
**The right way:** `--dry_run` first. Then `SELECT` only needed columns with `WHERE` filters. Set `--maximum_bytes_billed` as a safety net.

### Rule 2: Always enable require_partition_filter
**You will be tempted to:** Skip `require_partition_filter` because "it's inconvenient for exploratory queries."
**Why that fails:** One missed WHERE clause on a partitioned table scans ALL partitions. On a 2-year daily partitioned table, that's 730x the intended cost.
**The right way:** `OPTIONS(require_partition_filter = true)` on every partitioned table. Forces callers to include partition filter.

### Rule 3: Never use SELECT * in production queries
**You will be tempted to:** Use `SELECT *` because "I need all the columns" or "it's easier."
**Why that fails:** BigQuery is columnar. `SELECT *` reads every column, even if you only use 3 of 50. A 100GB table with 50 columns where you need 3 costs 50x more than necessary.
**The right way:** Explicitly list columns. If you truly need all columns, list them all — at least you've confirmed the intent.

### Rule 4: Set maximum_bytes_billed on every ad-hoc query
**You will be tempted to:** Skip the cost limit because "I know this query is small."
**Why that fails:** You don't know. A missing partition filter, an unexpected join explosion, or a typo in a WHERE clause can turn a $0.01 query into a $50 query. `maximum_bytes_billed` is free insurance.
**The right way:** `--maximum_bytes_billed=10000000000` (10GB = ~$0.06) for exploration. Increase only when you've confirmed the scan size via dry-run.

### Rule 5: Partition time-series tables — always
**You will be tempted to:** Create a flat table because "it's just a few million rows" or "I'll add partitioning later."
**Why that fails:** "A few million rows" becomes a few billion. Adding partitioning to an existing table requires recreating it with a `SELECT INTO` and costs money for the full scan. Starting partitioned is free.
**The right way:** `PARTITION BY DATE(timestamp)` on creation for any table with a time dimension. Cluster by your most common filter columns.
