---
name: mx-supa-observability
description: Use when setting up Supabase monitoring, configuring Prometheus/Grafana, analyzing database health, or establishing alerting. Also use when the user mentions 'monitoring', 'observability', 'Prometheus', 'Grafana', 'pg_stat_statements', 'metrics', 'alerting', 'dashboard', 'Performance Advisor', 'Security Advisor', 'Index Advisor', 'Logs Explorer', 'cache hit ratio', 'Sentry', or 'how do I know it is working'.
---

# Supabase Observability — Monitoring & Alerting for AI Coding Agents

**This skill loads for ANY monitoring or observability work.** It prevents the most common AI failure: shipping code without any monitoring, never checking query performance, never monitoring connection pools, and declaring work done without knowing if it's healthy.

## When to also load
- Query plan analysis → `mx-supa-diagnostics`
- Index strategy → `mx-supa-indexes`
- Edge Function monitoring → `mx-supa-edge`
- Realtime monitoring → `mx-supa-realtime`

---

## Level 1: Dashboard Built-in Tools (Beginner)

### The four advisors — check these first

| Advisor | What it checks | Where |
|---------|---------------|-------|
| **Performance Advisor** | Unindexed foreign keys, redundant indexes | Dashboard → Database → Advisors |
| **Security Advisor** | Missing RLS, mutable search_path, overly permissive policies | Dashboard → Database → Advisors |
| **Index Advisor** | Recommends indexes for slow queries | Dashboard → Database → Query Performance |
| **Query Performance** | pg_stat_statements — slowest queries by total time | Dashboard → Database → Query Performance |

### pg_stat_statements — already enabled by default

```sql
-- Top 10 slowest queries
SELECT query, calls, total_exec_time, mean_exec_time, max_exec_time
FROM pg_stat_statements
ORDER BY total_exec_time DESC LIMIT 10;

-- High-frequency queries (may indicate N+1)
SELECT query, calls, mean_exec_time
FROM pg_stat_statements
ORDER BY calls DESC LIMIT 10;

-- Reset after deploying fixes
SELECT pg_stat_statements_reset();
```

### Edge Function observability

| Dashboard Tab | Shows |
|--------------|-------|
| **Metrics** | CPU, memory, execution time per function |
| **Invocations** | Request/response data, status codes, duration |
| **Logs** | Platform events, exceptions, console output |

**Log limit:** 100 events per 10 seconds per function. 10,000 chars max per message.

---

## Level 2: Prometheus & Grafana (Intermediate)

### Metrics API endpoint

`https://<project-ref>.supabase.co/customer/v1/privileged/metrics`

- ~200 Prometheus-compatible metrics
- Auth: HTTP Basic with `service_role` username + secret API key as password
- Refresh cadence: 60 seconds

### prometheus.yml configuration

```yaml
scrape_configs:
  - job_name: 'supabase'
    scrape_interval: 60s
    metrics_path: /customer/v1/privileged/metrics
    scheme: https
    basic_auth:
      username: service_role
      password: '<your-secret-api-key>'
    static_configs:
      - targets: ['<project-ref>.supabase.co:443']
        labels:
          project: '<project-ref>'
```

### Grafana dashboard setup

1. Add Prometheus data source → point to your Prometheus server
2. Import dashboard from `supabase/supabase-grafana` GitHub repo (200+ charts)
3. Key panels: CPU, memory, disk I/O, WAL, connections, query performance

### Alerting thresholds

| Metric | Alert When | Why |
|--------|-----------|-----|
| RLS execution time | > 50ms | Complex policies degrading API and Realtime |
| Connection pool saturation | > 80% | Connection starvation causing timeouts |
| Sequential scans (high ratio) | seq_scan >> idx_scan | Missing indexes |
| CPU utilization | > 85% for 5 min | OOM risk, query throttling |
| Disk utilization | > 85% | Full disk = Postgres crash |
| Replication lag | > 5 seconds | Stale Realtime broadcasts, read replica inconsistency |
| Dead tuples (n_dead_tup) | Consistently high | Autovacuum stalled, bloat accumulating |

---

## Level 3: Deep Monitoring (Advanced)

### Realtime monitoring

- **RLS Execution Time reports** — median time to validate private channel subscriptions
- **Connected Clients** — track against plan quotas (Free=200, Pro=500)
- **Message Payload Size** — >256KB payloads should trigger architecture review

### Database health checks

```sql
-- Cache hit ratio (should be > 99%)
SELECT
  sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) as ratio
FROM pg_statio_user_tables;

-- Bloat estimation
-- supabase inspect db bloat (CLI)

-- Tables with most dead tuples
SELECT relname, n_dead_tup, last_autovacuum
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC LIMIT 10;

-- Active replication slots (stalled slots block vacuum)
SELECT slot_name, active, restart_lsn
FROM pg_replication_slots;
```

### Logs Explorer — SQL-queryable cross-service logs

```sql
-- Edge Function errors
SELECT id, timestamp, event_message, r.statusCode
FROM edge_logs
CROSS JOIN UNNEST(metadata) AS m
CROSS JOIN UNNEST(m.req) AS r
WHERE r.statusCode >= 500
ORDER BY timestamp DESC LIMIT 100;
```

### Sentry for Edge Functions

```typescript
import * as Sentry from 'npm:@sentry/deno'

Sentry.init({ dsn: Deno.env.get('SENTRY_DSN'), tracesSampleRate: 1.0 })

Deno.serve(async (req) => {
  try {
    // ... function logic ...
  } catch (error) {
    Sentry.captureException(error)
    return new Response('Error', { status: 500 })
  }
})
```

---

## Performance: Make It Fast

1. **pg_stat_statements** — identify top time-consuming queries, optimize those first
2. **Cache hit ratio > 99%** — if lower, queries are hitting disk, need more RAM or better indexes
3. **Reset pg_stat_statements after optimization** — prevents old data masking improvements
4. **Monitor Supavisor connection utilization** — connection exhaustion kills all clients
5. **Track dead tuple accumulation** — rising counts = autovacuum failing = silent bloat

## Observability: Know It's Working

This IS the observability skill, so here's the complete monitoring checklist:

### Pre-Deployment
- [ ] Performance Advisor: zero unindexed FK warnings
- [ ] Security Advisor: zero mutable search_path warnings
- [ ] All Edge Functions instrumented with Sentry
- [ ] Private channels configured for Realtime
- [ ] EXPLAIN ANALYZE run on critical queries

### Post-Deployment
- [ ] Prometheus scraping `/customer/v1/privileged/metrics` at 60s
- [ ] Grafana dashboard imported and populating
- [ ] Alerting rules configured for CPU, connections, disk, RLS latency
- [ ] Edge Function logs not exceeding 100 events/10s rate limit
- [ ] Realtime Reports showing healthy RLS execution times

### Ongoing
- [ ] Weekly: Check pg_stat_statements for new slow queries
- [ ] Weekly: Run `supabase inspect db bloat`
- [ ] Monthly: Review unused indexes (pg_stat_user_indexes, idx_scan = 0)
- [ ] Monthly: Verify cache hit ratio remains > 99%

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Ship Without Monitoring
**You will be tempted to:** Deploy code and "add monitoring later."
**Why that fails:** Without monitoring, you won't know the database is dying until users report outages. By then, the table is bloated, connections are exhausted, and recovery takes hours.
**The right way:** Every deployment includes Prometheus config, Grafana dashboard, and alerting rules.

### Rule 2: Never Assume Queries Are Fast
**You will be tempted to:** Skip query plan analysis because "it works in dev."
**Why that fails:** Dev has 100 rows. Production has 10 million. A sequential scan at 100 rows = 1ms. At 10M rows = timeout.
**The right way:** Run EXPLAIN ANALYZE on every query that touches production data. Check pg_stat_statements weekly.

### Rule 3: Never Ignore Connection Pool Health
**You will be tempted to:** Assume connection pooling "just works."
**Why that fails:** Serverless scaling + wrong pooling config = connection exhaustion in seconds. One misconfigured Prisma instance without `?pgbouncer=true` can bring down the entire database.
**The right way:** Monitor Supavisor connection utilization. Alert at 80% capacity.

### Rule 4: Never Skip Security Advisor
**You will be tempted to:** Ignore Security Advisor warnings because "the RLS policies work."
**Why that fails:** A mutable search_path on a SECURITY DEFINER function = privilege escalation vulnerability. Missing RLS on a table = full data exposure.
**The right way:** Zero Security Advisor warnings before production deployment. Non-negotiable.

### Rule 5: Never Defer Bloat Monitoring
**You will be tempted to:** Trust autovacuum to handle everything automatically.
**Why that fails:** Long-running transactions, stuck locks, and inactive replication slots silently stall autovacuum. Dead tuples accumulate, bloating tables and degrading every query.
**The right way:** Check `supabase inspect db bloat` weekly. Monitor `n_dead_tup` counts. Tune autovacuum scale_factor for high-write tables.
