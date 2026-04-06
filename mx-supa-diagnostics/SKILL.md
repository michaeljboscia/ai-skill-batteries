---
name: mx-supa-diagnostics
description: Use when debugging slow Supabase queries, reading EXPLAIN ANALYZE output, configuring connection pooling, managing vacuum/bloat, or troubleshooting database performance. Also use when the user mentions 'EXPLAIN ANALYZE', 'Seq Scan', 'Index Scan', 'query plan', 'slow query', 'Supavisor', 'PgBouncer', 'connection pool', 'transaction mode', 'session mode', 'prepared statements', 'vacuum', 'autovacuum', 'dead tuples', 'bloat', 'pg_repack', or 'pg_stat_statements'.
---

# Supabase Diagnostics — Query Plans & Database Health for AI Coding Agents

**This skill loads for ANY database performance debugging.** It prevents the most common AI failures: never checking query plans, ignoring connection pooling mode, never monitoring vacuum status, and assuming dev performance equals production.

## When to also load
- Index strategy → `mx-supa-indexes`
- Query optimization → `mx-supa-queries`
- Performance engineering → `mx-supa-perf`
- Monitoring setup → `mx-supa-observability`

---

## Level 1: Reading EXPLAIN ANALYZE (Beginner)

### How to run it

```sql
-- SQL Editor (use BUFFERS for I/O insight)
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM users WHERE email = 'test@example.com';

-- supabase-js (must enable first)
-- ALTER ROLE authenticator SET pgrst.db_plan_enabled TO 'true';
const { data } = await supabase.from('users').select('*').eq('email', 'test@example.com')
  .explain({ analyze: true, verbose: true, format: 'json' })
```

**Disable explain in production after debugging.**

### What to look for

| Plan Node | Meaning | Action |
|-----------|---------|--------|
| `Seq Scan` on large table with WHERE | Missing index | Create appropriate index |
| `Index Scan` | Index used correctly | Good — verify actual time |
| `Bitmap Index Scan` + `Bitmap Heap Scan` | Moderate selectivity | Normal for multi-row matches |
| High `Rows Removed by Filter` | Reading many rows, discarding most | Missing or wrong index |
| `estimated rows` ≠ `actual rows` (big gap) | Stale statistics | Run `ANALYZE table_name` |

### Cost numbers explained

`cost=0.42..14.50` = startup_cost..total_cost (arbitrary units, not milliseconds)
- **Startup cost**: work before first row returned
- **Total cost**: work to return all rows
- Compare costs between different query approaches, not as absolute values

### BUFFERS output

- `shared hit = 500` → 500 blocks found in cache (fast)
- `shared read = 15000` → 15,000 blocks read from disk (slow)
- High `shared read` = cold cache or table too large for shared_buffers

---

## Level 2: Connection Pooling (Intermediate)

### Supavisor vs PgBouncer

| Feature | Supavisor (default) | PgBouncer (dedicated) |
|---------|--------------------|-----------------------|
| Architecture | Elixir cluster, multi-tenant | Single-threaded, co-located |
| Scaling | Millions of connections | Limited by single thread |
| When to use | Default for all projects | IPv4 required, prepared stmt needs |

### Transaction mode vs Session mode

| Mode | Port | Connection held | Prepared statements | Use for |
|------|------|----------------|--------------------|----|
| Transaction | 6543 | Per-transaction only | **NOT supported** in Supavisor | Serverless, Edge Functions, short-lived |
| Session | 5432 | Entire session | Supported | Long-lived backends, session state |

### Disabling prepared statements per ORM (required for transaction mode)

| ORM | How to disable |
|-----|----------------|
| Prisma | `?pgbouncer=true` in connection string |
| node-postgres (`pg`) | Omit `name` property in query, or `prepare: false` |
| postgres.js / Drizzle | `postgres(url, { prepare: false })` |
| asyncpg (Python) | `statement_cache_size=0` in connect/create_pool |
| psycopg (Python) | `prepare_threshold = None` |

### Decision tree

1. Serverless/Edge environment? → **Transaction mode (6543)** + disable prepared statements
2. Long-lived server with session state? → **Session mode (5432)** or direct connection
3. Using PostgREST via supabase-js? → **No pooling config needed** (HTTP/2 multiplexed)

---

## Level 3: Vacuum & Bloat Management (Advanced)

### Why bloat happens

PostgreSQL MVCC: UPDATE/DELETE creates dead tuples (old row versions). They accumulate until VACUUM reclaims space.

### Monitoring bloat

```bash
# Supabase CLI
supabase inspect db bloat
supabase inspect db vacuum-stats
```

```sql
-- Check last vacuum times
SELECT relname, last_vacuum, last_autovacuum, n_dead_tup
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC LIMIT 10;
```

### Autovacuum tuning for high-write tables

Default: triggers after 20% of rows are dead. For a 10M row table = 2M dead rows before cleanup.

```sql
-- Lower threshold for large, high-churn tables
ALTER TABLE massive_events SET (autovacuum_vacuum_scale_factor = 0.05);
-- Now triggers at 5% = 500K dead rows
```

### When autovacuum stalls

| Cause | How to detect | Fix |
|-------|--------------|-----|
| Long-running transactions | `SELECT * FROM pg_stat_activity WHERE state = 'idle in transaction'` | Kill idle transactions, set `idle_in_transaction_session_timeout` |
| Stuck locks | `SELECT * FROM pg_locks WHERE NOT granted` | Investigate and resolve lock contention |
| Inactive replication slots | `SELECT * FROM pg_replication_slots WHERE active = false` | `SELECT pg_drop_replication_slot('slot_name')` |

### VACUUM options

| Tool | Locks table? | Reclaims disk space? | Use when |
|------|-------------|---------------------|----------|
| `VACUUM` | No (concurrent) | No (marks reusable) | Regular maintenance |
| `VACUUM FULL` | YES (exclusive lock) | YES (rewrites table) | Off-peak only, severe bloat |
| `pg_repack` | No (online) | YES (atomic swap) | **Production zero-downtime bloat removal** |

```bash
# pg_repack on Supabase (requires -k flag, no superuser)
pg_repack -k -h db.pooler.supabase.com -d postgres -t public.bloated_table
```

### pg_stat_statements for slow query identification

```sql
-- Top 10 slowest queries by total time
SELECT query, calls, total_exec_time, mean_exec_time
FROM pg_stat_statements
ORDER BY total_exec_time DESC LIMIT 10;

-- Reset after deploying fixes (otherwise old stats mask improvements)
SELECT pg_stat_statements_reset();
```

---

## Performance: Make It Fast

1. **EXPLAIN ANALYZE every slow query** — don't guess, measure
2. **Use transaction mode for serverless** — disable prepared statements per ORM
3. **Monitor and tune autovacuum** — lower scale_factor for large write-heavy tables
4. **Use pg_repack for production bloat** — zero-downtime table compaction
5. **Keep statistics fresh** — run ANALYZE after bulk operations
6. **Set `random_page_cost = 1.1`** for SSD storage — encourages index scans

## Observability: Know It's Working

1. **pg_stat_statements** — top slow queries by total time and call count
2. **pg_stat_user_tables** — dead tuple counts, last vacuum timestamps
3. **supabase inspect db bloat** — CLI tool for bloat estimation
4. **Supabase Performance Advisor** — flags unindexed FKs
5. **BUFFERS output** — cache hit ratio per query
6. **auto_explain** — log plans for nested function queries

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Skip Query Plans
**You will be tempted to:** Assume a query is fast because it "works in dev."
**Why that fails:** A query returning in 5ms on 100 rows will timeout on 10M rows if it's doing a sequential scan.
**The right way:** Run EXPLAIN ANALYZE on every query that touches production data. Look for Seq Scan on large tables.

### Rule 2: Never Ignore Connection Pooling
**You will be tempted to:** Use default ORM settings without configuring the pooler.
**Why that fails:** Prisma with prepared statements + Supavisor transaction mode = `prepared statement does not exist` errors.
**The right way:** Check the deployment environment. Serverless = transaction mode + disable prepared statements. Always.

### Rule 3: Never Assume Vacuum Is Fine
**You will be tempted to:** Ignore dead tuples because "autovacuum handles it."
**Why that fails:** Autovacuum can stall on long-running transactions, stuck locks, or inactive replication slots. Dead tuples accumulate, bloating tables and degrading all queries.
**The right way:** Periodically check `supabase inspect db bloat` and `n_dead_tup` counts. Tune autovacuum for high-write tables.

### Rule 4: Never VACUUM FULL in Production Hours
**You will be tempted to:** Run `VACUUM FULL` to reclaim space during business hours.
**Why that fails:** VACUUM FULL takes an exclusive lock — the table is completely unavailable for reads AND writes until it finishes.
**The right way:** Use `pg_repack` for zero-downtime bloat removal. Reserve VACUUM FULL for scheduled maintenance windows.
