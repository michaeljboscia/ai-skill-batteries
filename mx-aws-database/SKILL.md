---
name: mx-aws-database
description: RDS PostgreSQL/MySQL, Aurora Serverless v2, Aurora Global Database, ElastiCache Valkey/Redis, DocumentDB, RDS Proxy, DMS migration, blue-green deployments, connection pooling, and AI-generated anti-patterns
---

# AWS Database — RDS, Aurora, ElastiCache for AI Coding Agents

**Load this skill when provisioning relational databases, configuring Aurora, setting up caching layers, or migrating databases.**

## When to also load
- `mx-aws-dynamodb` — when deciding relational vs NoSQL
- `mx-aws-lambda` — RDS Proxy mandatory for Lambda + RDS
- `mx-aws-networking` — VPC placement, security groups, subnets
- `mx-aws-security` — KMS encryption, Secrets Manager for credentials

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: Aurora Over RDS for Production
| BAD | GOOD |
|-----|------|
| RDS PostgreSQL for production workloads | Aurora PostgreSQL (3x throughput, 6-way replication, <30s switchover) |

RDS is fine for dev/small workloads. Aurora is better for production — sub-second failover, up to 15 read replicas, shared storage that scales automatically.

### Pattern 2: RDS Proxy for Connection Pooling
| BAD | GOOD |
|-----|------|
| Direct database connections from Lambda/ECS | RDS Proxy (managed connection pooler, 66% faster failover) |

RDS Proxy is **mandatory** for Lambda + RDS. Lambda creates new connections per invocation — without Proxy, you'll exhaust connection limits in minutes.

### Pattern 3: Graviton Instance Classes
| BAD | GOOD |
|-----|------|
| `db.r6i.xlarge` (x86) | `db.r7g.xlarge` (Graviton3, better price-perf) |

Drop-in replacement. Same engine, same data, better performance, lower cost.

### Pattern 4: Multi-AZ Always
| BAD | GOOD |
|-----|------|
| Single-AZ database (no failover) | Multi-AZ with standby (automatic failover) |

### Pattern 5: Secrets Manager for Credentials
| BAD | GOOD |
|-----|------|
| Hardcoded password in connection string | Secrets Manager + IAM auth via RDS Proxy |

---

## Level 2: Aurora Deep & Caching (Intermediate)

### Aurora Serverless v2
- ACU-based scaling (each ACU = ~2GB memory + CPU). Fine-grained, scales in seconds
- **Min ACU too low = cold start latency.** Keep minimum warm or use scheduled scaling
- Aurora I/O Optimized: flat rate I/O pricing. Better for I/O-heavy workloads (>25% spend on I/O)
- Version 3 = 30% faster than v2

### Aurora Read Replicas
- Shared storage (no data copy). 10-20ms replication lag
- **Tier 0/1 replicas:** match writer instance class — these get promoted on failover
- **Tier 2+ replicas:** scale independently for read capacity
- Up to 15 replicas. Monitor `ReplicaLag` metric

### Aurora Global Database
- Up to 10 secondary regions. Sub-second replication. **<30s switchover** (May 2025)
- Managed failover for DR, switchover for planned maintenance
- Confirm replication lag <2s before failover. Short DNS TTL (<60s)
- Test failover quarterly

### ElastiCache
- **Valkey** = open-source Redis fork (7.2.4 compatible). Drop-in Redis replacement
- ElastiCache Serverless: cluster-mode enabled only. Port 6380 for local AZ reads
- Connection management: long-lived connections, connection pooling, client-side timeouts
- Max 65,000 connections per node but avoid operating at limit (single-threaded)
- Graviton instances (`cache.r7g.*`) for better price-perf

### RDS vs Aurora vs DocumentDB Decision

| Need | Service | Why |
|------|---------|-----|
| Standard PostgreSQL/MySQL, simple | **RDS** | Lower cost, manual failover |
| Production HA, read-heavy | **Aurora** | 3x throughput, auto-failover, 15 replicas |
| MongoDB-compatible | **DocumentDB** | Managed, flexible queries, secondary indexes |
| Massive scale, single-digit ms | **DynamoDB** | Serverless, unlimited scale |
| Migration from on-prem | **DMS** | Schema Conversion Tool + CDC for ongoing replication |

---

## Level 3: Migration & Advanced (Advanced)

### Blue-Green Deployments
- RDS/Aurora support managed blue-green for zero-downtime upgrades
- Create green environment → test → switch traffic → drop blue
- Use for major version upgrades, instance class changes, parameter group changes

### DMS (Database Migration Service)
- Schema Conversion Tool for heterogeneous migrations (Oracle → PostgreSQL)
- CDC (Change Data Capture) for ongoing replication during migration
- Test migrations in a staging environment first — always

### Connection Architecture
```
Application → RDS Proxy → Aurora Writer (primary)
                       → Aurora Reader (replicas)
```
RDS Proxy handles: connection pooling, IAM auth, Secrets Manager rotation, 66% faster failover.

---

## Performance: Make It Fast

### Optimization Checklist
1. **Aurora over RDS** for production — 3x throughput, auto-replication
2. **RDS Proxy** — eliminates connection overhead, faster failover
3. **Graviton instances** — `db.r7g.*` for better price-perf
4. **I/O Optimized** — flat I/O pricing when I/O costs >25% of total
5. **Read replicas** — offload reads, keep Tier 0/1 same size as writer
6. **ElastiCache** — cache hot queries, reduce database load
7. **Connection pooling** — RDS Proxy or PgBouncer for non-Lambda workloads

### Query Performance
- Enable Performance Insights (free for 7-day retention) for query analysis
- Identify top SQL by wait events, not just execution time
- Use `pg_stat_statements` / `slow_query_log` for query profiling

---

## Observability: Know It's Working

### What to Monitor

| Signal | Metric | Alert Threshold |
|--------|--------|-----------------|
| Connection exhaustion | `DatabaseConnections` | >80% of max_connections |
| Replication lag | `AuroraReplicaLag` | >1s for read-after-write consistency |
| CPU | `CPUUtilization` | >80% sustained |
| Freeable memory | `FreeableMemory` | <10% of total |
| I/O throughput | `ReadIOPS`, `WriteIOPS` | Approaching provisioned IOPS limit |
| Failover | `EngineUptime` reset | Any = failover occurred, investigate |
| Proxy | `DatabaseConnectionsCurrentlyBorrowed` | >80% of max |

- **Performance Insights**: enable on all production databases. Free 7-day retention
- **Enhanced Monitoring**: OS-level metrics at 1-second granularity
- **RDS Event Subscriptions**: SNS notifications for failover, maintenance, configuration changes

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Direct Connections from Lambda
**You will be tempted to:** Connect Lambda directly to RDS/Aurora because "RDS Proxy is extra complexity"
**Why that fails:** Lambda creates new connections per invocation. At 100 concurrent invocations, that's 100 new DB connections. Connection limits exhaust in minutes. Silent failures
**The right way:** RDS Proxy. Always. Non-negotiable for Lambda + relational DB

### Rule 2: No Single-AZ Production Databases
**You will be tempted to:** Use Single-AZ because it's cheaper
**Why that fails:** AZ failure = database down = application down. No automatic failover
**The right way:** Multi-AZ for all production databases. The hourly cost difference is trivial vs outage cost

### Rule 3: No RDS When Aurora Fits
**You will be tempted to:** Use RDS PostgreSQL for production because "it's standard PostgreSQL"
**Why that fails:** RDS has manual failover (minutes), limited read replicas, and lower throughput. Aurora is still PostgreSQL-compatible but with 3x throughput and automatic failover
**The right way:** RDS for dev/test/small workloads. Aurora for anything production or HA-required

### Rule 4: No Hardcoded Database Credentials
**You will be tempted to:** Put the database password in environment variables or config files
**Why that fails:** Credentials in env vars are visible in console, API responses, and logs. Static passwords don't rotate
**The right way:** Secrets Manager with automatic rotation. IAM authentication via RDS Proxy for Lambda

### Rule 5: No Mismatched Failover Replicas
**You will be tempted to:** Use smaller instance classes for read replicas to save cost
**Why that fails:** Tier 0/1 replicas get promoted on failover. If they're smaller than the writer, your database immediately degrades under write load after failover
**The right way:** Tier 0/1 replicas match writer instance class. Use Tier 2+ for read scaling with independent sizing
