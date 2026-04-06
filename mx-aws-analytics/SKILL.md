---
name: mx-aws-analytics
description: Athena partition projection/Parquet/cost control, Glue crawlers/ETL/Data Catalog, Lake Formation permissions, Redshift Serverless vs Provisioned/data sharing/materialized views/AQUA, QuickSight, and AI-generated anti-patterns
---

# AWS Analytics — Athena, Glue, Redshift for AI Coding Agents

**Load this skill when querying data with Athena, building ETL pipelines with Glue, configuring Redshift data warehouses, or setting up Lake Formation.**

## When to also load
- `mx-aws-storage` — S3 data lake, lifecycle management, Intelligent-Tiering
- `mx-aws-streaming` — Kinesis/MSK → S3 for analytics pipelines
- `mx-aws-iac` — CDK/CloudFormation for Glue jobs, Redshift clusters
- `mx-aws-billing` — Analytics cost management, Redshift RI/SP

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: Parquet Over CSV/JSON
| BAD | GOOD |
|-----|------|
| Querying raw CSV/JSON in S3 | Convert to Parquet (columnar, compressed, 10-100x faster queries) |

Athena charges by data scanned. Parquet is columnar — reads only needed columns. CSV reads entire rows. The conversion pays for itself immediately.

### Pattern 2: Partition Your Data
| BAD | GOOD |
|-----|------|
| `s3://data/events.parquet` (full table scan) | `s3://data/year=2025/month=04/day=05/events.parquet` |

Athena with partition projection: auto-generates partition values from patterns. No crawler needed. Filter on `year`/`month`/`day` = scan only matching partitions.

### Pattern 3: Athena Cost Control
| BAD | GOOD |
|-----|------|
| `SELECT *` on multi-TB tables | `SELECT specific_columns WHERE partition_filter` |

Athena charges **$5/TB scanned**. `SELECT *` on a 10TB table = $50 per query. Select specific columns + filter on partitions = pennies.

### Pattern 4: Glue Data Catalog as Central Metastore
| BAD | GOOD |
|-----|------|
| Per-service schema management | Glue Data Catalog shared by Athena, Redshift Spectrum, EMR, Glue ETL |

Single source of truth for table schemas. Crawlers auto-discover schema changes.

### Pattern 5: Lake Formation for Fine-Grained Access
| BAD | GOOD |
|-----|------|
| S3 bucket policies + IAM for data access | Lake Formation column/row/cell-level permissions |

Lake Formation wraps S3 + Glue with SQL-like GRANT/REVOKE. Column-level security, row-level filtering, tag-based access control.

---

## Level 2: Redshift & Glue Deep (Intermediate)

### Redshift: Serverless vs Provisioned

| Aspect | Serverless | Provisioned |
|--------|-----------|-------------|
| Management | None (auto-scales) | Manual cluster management |
| Billing | RPU-seconds (60s min) | Node-hours (+ RIs up to 70% off) |
| Best for | Spiky/ad-hoc/unpredictable | Steady 24/7 ETL pipelines |
| AQUA | Not available | 10x for scan-heavy queries (RA3 only) |
| Concurrency | Included in RPU pricing | Concurrency Scaling (extra cost beyond free credits) |
| AI scaling | Price-performance slider (2024) | Manual tuning |

### Redshift Data Sharing
- Live, transactionally consistent data across clusters. No data movement
- Cross-account, cross-region. Provisioned ↔ Serverless in any combination
- **Multi-data warehouse WRITES** (GA re:Invent 2024): consumers can write to shared data
- Iceberg tables in data shares. 146x performance improvement (2024 vs 2023)
- Granular permissions: scoped at database + object level. `SHOW GRANTS` for discovery

### Redshift Materialized Views
- Pre-computed query results. Incremental refresh (no full recompute)
- **AutoMV**: ML-based automatic creation + refresh based on workload patterns
- Incremental refresh on shared tables + Iceberg tables + Zero-ETL tables (Dec 2024)
- Use for dashboard workloads requiring low latency

### Redshift ML
- SQL-based model training via SageMaker. No data movement
- **Bedrock integration (Oct 2024)**: LLM tasks directly in SQL (translation, summarization, classification)

### Glue ETL Best Practices
- Use Glue 4.0+ (Spark 3.3+) for performance improvements
- Auto-scaling workers. DPU right-sizing based on job complexity
- Glue bookmarks for incremental processing (don't reprocess already-processed data)
- Job monitoring: CloudWatch metrics for DPU utilization, job duration, data volume

---

## Level 3: Advanced Analytics Patterns (Advanced)

### Athena Optimization
- Partition projection: auto-generates partition values without `MSCK REPAIR TABLE`
- Workgroup-based query cost limits: prevent runaway queries
- Federated queries: query DynamoDB, RDS, Redshift directly from Athena via connectors
- CTAS (Create Table As Select) for materializing query results

### Redshift Cost Optimization
**Serverless:**
- Set base RPU low (32). AI-driven scaling handles peaks
- Usage limits (RPUs/day) to prevent surprise bills
- Efficient queries: `EXPLAIN` for query plans, avoid full table scans

**Provisioned:**
- Right-size: Elastic Resize for immediate, Resize Scheduler for daily/weekly
- RIs for stable workloads (up to 70% savings). Pause/resume for intermittent
- WLM (Workload Management) + QMR (Query Monitoring Rules) for runaway query protection
- Redshift Spectrum for cold data in S3 (pay by scan, not by storage)

---

## Performance: Make It Fast

### Optimization Checklist
1. **Parquet format** — 10-100x faster Athena queries vs CSV/JSON
2. **Partition projection** — auto-partitioning without crawlers
3. **Column-specific SELECT** — Athena charges by data scanned
4. **Redshift AutoMV** — auto-creates materialized views for common queries
5. **AQUA** (Provisioned RA3) — 10x for scan-heavy queries
6. **Glue bookmarks** — incremental processing, don't re-read old data

### Data Format Impact on Athena Cost
| Format | ~Size (1TB raw) | Athena Scan Cost |
|--------|-----------------|-------------------|
| CSV | 1TB | $5.00/query |
| JSON | 1.2TB | $6.00/query |
| Parquet (compressed) | 100GB | $0.50/query |
| Parquet + partition filter | 10GB | $0.05/query |

---

## Observability: Know It's Working

### What to Monitor

| Signal | Metric | Alert Threshold |
|--------|--------|-----------------|
| Athena cost | Bytes scanned per query | >1TB = review query optimization |
| Glue job health | `glue.driver.aggregate.elapsedTime` | Duration trending up = data growth issue |
| Redshift queues | `WLMQueueWaitTime` | >30s = add concurrency or optimize queries |
| Data freshness | Custom metric: latest partition timestamp | >SLA = pipeline delay |
| Glue crawlers | Crawler success/failure | Failure = schema drift undetected |

- **Athena workgroup metrics**: per-team query cost tracking and limits
- **Redshift Performance Insights**: query-level wait analysis
- **Glue job metrics**: DPU utilization (low = over-provisioned, high = under-provisioned)

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No SELECT * on Large Datasets in Athena
**You will be tempted to:** Use `SELECT *` for exploration or because "the table isn't that big"
**Why that fails:** Athena scans all columns regardless of what you need. Columnar format benefits are negated. Cost = $5/TB scanned
**The right way:** Select only needed columns. Always filter on partitions. Set workgroup byte limits

### Rule 2: No CSV/JSON for Repeated Analytics Queries
**You will be tempted to:** Query raw CSV/JSON because "conversion takes effort"
**Why that fails:** 10-100x more expensive per query. 10-100x slower. The first Parquet conversion pays for itself after 2-3 queries
**The right way:** Convert to Parquet. Use Glue ETL or Athena CTAS. Once and done

### Rule 3: No Redshift Provisioned for Spiky Workloads
**You will be tempted to:** Use Provisioned Redshift because "it's what we know"
**Why that fails:** Paying for idle cluster during off-peak. Concurrency Scaling adds surprise costs. Serverless auto-scales to zero
**The right way:** Serverless for spiky/ad-hoc. Provisioned for 24/7 steady-state with RIs

### Rule 4: No Glue Jobs Without Bookmarks
**You will be tempted to:** Process all data on every Glue job run
**Why that fails:** Reprocesses data you've already handled. Costs scale linearly with total data volume instead of new data volume
**The right way:** Enable Glue bookmarks for incremental processing. Track what's been processed

### Rule 5: No Data Lake Without Lake Formation
**You will be tempted to:** Use S3 bucket policies + IAM for data access control
**Why that fails:** Bucket policies don't support column-level or row-level security. IAM policies for data access become unmanageable at scale. No audit trail of who queried what
**The right way:** Lake Formation: SQL-like GRANT/REVOKE, column/row/cell-level permissions, tag-based access control, centralized audit
