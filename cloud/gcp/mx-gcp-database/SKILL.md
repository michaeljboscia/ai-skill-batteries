---
name: mx-gcp-database
description: Use when creating Cloud SQL instances, configuring AlloyDB clusters, designing Spanner databases, managing Firestore collections, or setting up Memorystore Redis/Memcached. Also use when the user mentions 'gcloud sql', 'Cloud SQL', 'AlloyDB', 'Spanner', 'Firestore', 'Memorystore', 'Redis', 'database instance', 'read replica', 'failover', 'connection pooling', 'Auth Proxy', 'cloud-sql-proxy', 'PITR', 'point-in-time recovery', '--availability-type', 'REGIONAL', 'document database', 'NoSQL', or 'in-memory cache'.
---

# GCP Database — Cloud SQL, AlloyDB, Spanner, Firestore & Memorystore for AI Coding Agents

**This skill loads when you're creating or managing GCP database services.**

## When to also load
- `mx-gcp-iam` — Database service accounts, IAM authentication
- `mx-gcp-networking` — Private IP, VPC peering, Private Service Connect
- `mx-gcp-security` — **ALWAYS load** — CMEK encryption, VPC-SC for data perimeters, SSL enforcement, no public IPs on databases

---

## Level 1: Cloud SQL Production Setup (Beginner)

### Create a production Cloud SQL instance

```bash
gcloud sql instances create my-app-db \
  --database-version=POSTGRES_16 \
  --tier=db-custom-4-16384 \
  --region=us-east1 \
  --availability-type=REGIONAL \
  --storage-type=SSD \
  --storage-size=100GB \
  --storage-auto-increase \
  --backup-start-time=03:00 \
  --enable-point-in-time-recovery \
  --maintenance-window-day=SUN \
  --maintenance-window-hour=04 \
  --database-flags=max_connections=500,log_min_duration_statement=1000 \
  --no-assign-ip \
  --network=projects/my-project/global/networks/my-vpc \
  --require-ssl
```

**Mandatory flags for production:**

| Flag | Why |
|------|-----|
| `--availability-type=REGIONAL` | HA with automatic failover (99.95-99.99% SLA) |
| `--no-assign-ip` | Private IP only — no public internet exposure |
| `--require-ssl` | Encrypts all connections in transit |
| `--storage-auto-increase` | Prevents outages from full disk |
| `--backup-start-time` | Enables automated daily backups |
| `--enable-point-in-time-recovery` | Granular restore to any second |

### Cloud SQL Auth Proxy (the right connection method)

```bash
# Run the proxy sidecar (GKE, Cloud Run, or local dev)
cloud-sql-proxy my-project:us-east1:my-app-db \
  --private-ip \
  --auto-iam-authn

# Application connects to localhost:5432 — proxy handles auth + encryption
DATABASE_URL="postgresql://app-user@localhost:5432/mydb"
```

**Connection decision:**

| Environment | Method |
|-------------|--------|
| GKE / Cloud Run | Auth Proxy sidecar + private IP |
| Compute Engine (same VPC) | Private IP directly (proxy optional) |
| Local development | Auth Proxy + public IP (dev only) |
| Serverless (Functions) | Built-in Cloud SQL connector |

### Read replicas

```bash
# Create a read replica
gcloud sql instances create my-app-db-read \
  --master-instance-name=my-app-db \
  --region=us-east1 \
  --tier=db-custom-2-8192 \
  --availability-type=ZONAL

# Cross-region replica for DR
gcloud sql instances create my-app-db-dr \
  --master-instance-name=my-app-db \
  --region=us-west1 \
  --tier=db-custom-4-16384
```

---

## Level 2: Database Service Selection (Intermediate)

### Which GCP database to use

| Requirement | Service | Why |
|-------------|---------|-----|
| Standard RDBMS (MySQL/PG/SQL Server) | **Cloud SQL** | Cheapest managed relational, regional |
| PostgreSQL needing 4x transaction speed | **AlloyDB** | Disaggregated storage, columnar engine |
| HTAP (transactions + analytics same DB) | **AlloyDB** | 100x faster analytics than standard PG |
| Global strong consistency | **Spanner** | Only DB with global ACID + horizontal scale |
| Document/NoSQL with real-time sync | **Firestore** | Serverless, offline support, sub-10ms reads |
| Sub-millisecond caching | **Memorystore Redis** | In-memory, connection to Cloud SQL/Spanner |
| Session store / rate limiting | **Memorystore Redis** | TTL-based expiry, atomic counters |

### AlloyDB cluster creation

```bash
# Create AlloyDB cluster (PostgreSQL-compatible, premium performance)
gcloud alloydb clusters create my-alloydb \
  --region=us-east1 \
  --network=projects/my-project/global/networks/my-vpc \
  --automated-backup-enabled \
  --automated-backup-retention-period=14d

# Create primary instance
gcloud alloydb instances create my-alloydb-primary \
  --cluster=my-alloydb \
  --region=us-east1 \
  --instance-type=PRIMARY \
  --cpu-count=4 \
  --database-flags=max_connections=1000

# Create read pool (auto-scaling read replicas)
gcloud alloydb instances create my-alloydb-readers \
  --cluster=my-alloydb \
  --region=us-east1 \
  --instance-type=READ_POOL \
  --cpu-count=4 \
  --read-pool-node-count=2
```

**AlloyDB vs Cloud SQL decision:** If you're already on PostgreSQL and need more performance, AlloyDB is the upgrade path. If you need MySQL or SQL Server, stay on Cloud SQL.

### Firestore setup

```bash
# Create Firestore database (Native mode)
gcloud firestore databases create \
  --location=us-east1 \
  --type=firestore-native

# Create composite index for common query patterns
gcloud firestore indexes composite create \
  --collection-group=orders \
  --field-config=field-path=userId,order=ASCENDING \
  --field-config=field-path=createdAt,order=DESCENDING
```

**Firestore modes:** Native mode (document DB with real-time) vs Datastore mode (legacy, no real-time). New projects should always use Native mode.

### Memorystore Redis

```bash
gcloud redis instances create my-cache \
  --region=us-east1 \
  --tier=standard \
  --size=1 \
  --redis-version=redis_7_2 \
  --connect-mode=PRIVATE_SERVICE_ACCESS \
  --network=projects/my-project/global/networks/my-vpc
```

**Tier decision:** Basic (no replication, dev/test) vs Standard (automatic failover, production). Always Standard for production.

---

## Level 3: Spanner & Advanced Patterns (Advanced)

### Spanner instance creation

```bash
# Create Spanner instance
gcloud spanner instances create my-spanner \
  --config=regional-us-east1 \
  --processing-units=100 \
  --description="Production transactional database"

# Create database
gcloud spanner databases create my-db \
  --instance=my-spanner

# Apply DDL
gcloud spanner databases ddl update my-db \
  --instance=my-spanner \
  --ddl='CREATE TABLE Users (
    UserId STRING(36) NOT NULL,
    Email STRING(255),
    CreatedAt TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true)
  ) PRIMARY KEY (UserId)'
```

**Spanner pricing:** Minimum 100 processing units (~$65/month regional). Multi-region starts at $2,340/month. Use only when you genuinely need global consistency.

### Spanner key design (critical)

```sql
-- BAD: sequential primary key causes hotspots
CREATE TABLE Events (
  EventId INT64 NOT NULL,  -- sequential = all writes hit same split
  Data STRING(MAX)
) PRIMARY KEY (EventId);

-- GOOD: UUID or bit-reversed key distributes writes
CREATE TABLE Events (
  EventId STRING(36) NOT NULL,  -- UUID spreads across splits
  Data STRING(MAX)
) PRIMARY KEY (EventId);

-- GOOD: interleaved tables for parent-child locality
CREATE TABLE Orders (
  OrderId STRING(36) NOT NULL
) PRIMARY KEY (OrderId);

CREATE TABLE OrderItems (
  OrderId STRING(36) NOT NULL,
  ItemId STRING(36) NOT NULL
) PRIMARY KEY (OrderId, ItemId),
  INTERLEAVE IN PARENT Orders ON DELETE CASCADE;
```

### Cloud SQL backups and PITR

```bash
# Create on-demand backup
gcloud sql backups create --instance=my-app-db \
  --description="Pre-migration backup"

# List backups
gcloud sql backups list --instance=my-app-db

# Restore to point in time (creates new instance)
gcloud sql instances clone my-app-db my-app-db-restored \
  --point-in-time='2026-04-04T08:00:00Z'
```

---

## Performance: Make It Fast

- **Connection pooling is mandatory** — Cloud SQL has hard connection limits per tier. Use PgBouncer (PG), ProxySQL (MySQL), or application-level pooling. Without pooling, serverless workloads exhaust connections in seconds.
- **Read replicas for read-heavy workloads** — Route SELECT queries to replicas. A 4-vCPU primary + 2 read replicas handles 3x the read throughput at 1.5x the cost.
- **AlloyDB columnar engine** — Automatically caches frequently accessed columns in memory. Analytical queries run 100x faster without any code changes. Enable with `--database-flags=google_columnar_engine.enabled=on`.
- **Spanner: keep transactions short** — Long transactions hold locks across splits. Batch writes into chunks of 20,000 mutations max per commit.
- **Memorystore for hot paths** — Cache database query results with TTL. A cache hit at 0.5ms vs a DB query at 5ms is a 10x latency reduction on your hot path.
- **Right-size instances** — Monitor CPU/memory utilization. Cloud SQL charges for provisioned resources, not usage. An idle db-custom-8-32768 costs the same as one running at 100%.

## Observability: Know It's Working

```bash
# Cloud SQL instance status and metrics
gcloud sql instances describe my-app-db \
  --format="table(state,settings.tier,settings.dataDiskSizeGb,settings.availabilityType)"

# List recent operations (failovers, restarts, patches)
gcloud sql operations list --instance=my-app-db --limit=10

# Check replication lag on read replicas
gcloud sql instances describe my-app-db-read \
  --format="get(replicaConfiguration.mysqlReplicaConfiguration)"

# Spanner instance utilization
gcloud spanner instances describe my-spanner \
  --format="table(processingUnits,state)"
```

**Enable Query Insights** for Cloud SQL — surfaces slow queries, lock contention, and connection patterns in the Console without any application changes.

| Alert | Severity |
|-------|----------|
| Cloud SQL CPU >80% sustained for 15min | **HIGH** |
| Replication lag >30 seconds | **HIGH** |
| Storage utilization >80% | **HIGH** |
| Connection count >80% of max_connections | **MEDIUM** |
| Failover event detected | **MEDIUM** |
| Spanner processing unit utilization >65% | **HIGH** |
| Backup failure | **CRITICAL** |

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never assign a public IP to production database instances
**You will be tempted to:** Use `--assign-ip` (the default) because "it's easier to connect from my laptop" or "we'll add firewall rules."
**Why that fails:** A public IP exposes your database to the internet. Even with authorized networks, a single misconfigured CIDR (like `0.0.0.0/0`) makes the database world-accessible. Cloud SQL public IPs are a top finding in GCP security audits.
**The right way:** `--no-assign-ip` + private IP + Cloud SQL Auth Proxy. For local dev, run the Auth Proxy locally — it tunnels through IAM, no public IP needed.

### Rule 2: Always enable automated backups AND point-in-time recovery
**You will be tempted to:** Skip backups because "it's just a dev database" or "we'll set it up later."
**Why that fails:** Backups are NOT enabled by default. Without `--backup-start-time`, you have zero recovery options. A dropped table, a bad migration, or a compromised credential means total data loss. PITR lets you restore to any second; without it, your best recovery point is the last daily backup (up to 24 hours of data loss).
**The right way:** `--backup-start-time=03:00 --enable-point-in-time-recovery` on every instance, including dev. Set `--backup-retain-days` to at least 7.

### Rule 3: Always use REGIONAL availability for production
**You will be tempted to:** Leave the default `--availability-type=ZONAL` because "it's cheaper" or "we don't need HA yet."
**Why that fails:** ZONAL means a single zone failure takes your database offline for the duration of the outage — which can be hours. There's no automatic failover. The cost difference between ZONAL and REGIONAL is roughly 2x, but the cost of a multi-hour production outage dwarfs the monthly savings.
**The right way:** `--availability-type=REGIONAL` for anything that serves production traffic. ZONAL is acceptable only for dev/test instances.

### Rule 4: Never use sequential keys as Spanner primary keys
**You will be tempted to:** Use auto-incrementing integers or timestamps as primary keys because "that's how we do it in PostgreSQL."
**Why that fails:** Spanner distributes data across splits by key range. Sequential keys (1, 2, 3... or timestamps) cause all writes to hit the same split, creating a hotspot. At scale, this bottlenecks throughput to a single server regardless of how many processing units you provision.
**The right way:** UUID v4, bit-reversed sequences, or application-generated hashes as primary keys. For time-series, prefix with a shard key: `ShardId/Timestamp` where ShardId is hash(entity) % N.

### Rule 5: Use connection pooling — never direct connections from serverless
**You will be tempted to:** Connect directly to Cloud SQL from Cloud Run or Cloud Functions because "it works in dev."
**Why that fails:** Serverless platforms can scale to hundreds of instances in seconds. Each instance opening a direct connection exhausts Cloud SQL's `max_connections` limit (varies by tier, ~500 for a 4-vCPU instance). Once exhausted, ALL connections fail — not just new ones. This is the #1 Cloud SQL production incident pattern.
**The right way:** Cloud SQL Auth Proxy with connection pooling, or application-level pooling (PgBouncer, database/sql pool in Go, SQLAlchemy pool in Python). Set pool size per instance to `max_connections / expected_max_instances`.
