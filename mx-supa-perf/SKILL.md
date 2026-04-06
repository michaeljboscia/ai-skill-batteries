---
name: mx-supa-perf
description: Use when optimizing Supabase performance, implementing caching strategies, creating materialized views, batch operations, or tuning database configuration. Also use when the user mentions 'materialized view', 'REFRESH MATERIALIZED VIEW', 'caching', 'Cache-Control', 'React Query', 'stale-while-revalidate', 'batch insert', 'COPY', 'bulk', 'table partitioning', 'Supavisor tuning', 'connection optimization', 'HTTP/2', or 'make it faster'.
---

# Supabase Performance Engineering — Making It Fast for AI Coding Agents

**This skill loads for proactive performance optimization.** Not diagnosing what's slow (that's mx-supa-diagnostics) — this is about making things FAST on purpose: materialized views, caching, batching, connection optimization, and partitioning.

## When to also load
- Index strategy → `mx-supa-indexes`
- Query plan analysis → `mx-supa-diagnostics`
- Query patterns → `mx-supa-queries`
- Monitoring → `mx-supa-observability`

---

## Level 1: Quick Wins (Beginner)

### Use PostgREST client over raw SQL connections

PostgREST uses HTTP/2 multiplexing — multiple requests over one persistent TCP connection. Raw Postgres requires per-request TCP + TLS + auth handshake.

| Connection Method | Avg Latency | Best For |
|------------------|-------------|----------|
| supabase-js (PostgREST) | ~500ms | Most CRUD, serverless |
| Raw SQL via Supavisor (6543) | ~990ms | Complex CTEs, multi-statement transactions |
| Direct Postgres (5432) | ~2000ms+ if misconfigured | Long-lived backends only |

### Batch operations — never insert one row at a time

```typescript
// BAD: 1000 network round-trips
for (const item of items) {
  await supabase.from('products').insert(item)
}

// GOOD: 1 network round-trip
await supabase.from('products').upsert(items, { onConflict: 'sku' })
```

Optimal batch size: **500-1000 rows**. For >100K rows, use PostgreSQL COPY command.

### Keyset pagination (always)

```typescript
// Constant-time retrieval regardless of depth
const { data } = await supabase
  .from('events')
  .select('id, name, created_at')
  .gt('id', lastSeenId)
  .order('id')
  .limit(50)
```

---

## Level 2: Caching & Materialized Views (Intermediate)

### Supabase caching is opt-in — nothing is automatic

Supabase cannot auto-cache because RLS makes every query user-specific. You must build caching explicitly.

| Caching Layer | Tool | Best For |
|--------------|------|----------|
| Client memory | React Query, SWR | Deduplication, stale-while-revalidate |
| HTTP edge | `Cache-Control` headers | Public assets, CDN |
| Server cache | Redis | Expensive computations, rate limiting |
| Database level | Materialized views | Complex aggregations, dashboards |

### HTTP Cache-Control via PostgREST

```typescript
const { data } = await supabase
  .from('public_catalog')
  .select('*')
  .setHeader('Cache-Control', 'public, s-maxage=300, stale-while-revalidate=600')
```

### Materialized views for dashboards

```sql
-- Create in a non-public schema (RLS doesn't work on materialized views)
CREATE SCHEMA analytics;

CREATE MATERIALIZED VIEW analytics.user_engagement AS
SELECT user_id, COUNT(*) as total_sessions, MAX(last_active) as last_seen
FROM public.sessions GROUP BY user_id;

-- Required for CONCURRENTLY refresh
CREATE UNIQUE INDEX idx_engagement_user ON analytics.user_engagement(user_id);

-- Refresh without blocking reads
REFRESH MATERIALIZED VIEW CONCURRENTLY analytics.user_engagement;
```

### RLS workaround for materialized views

Materialized views bypass RLS. Wrap in a SECURITY DEFINER function:

```sql
REVOKE ALL ON analytics.user_engagement FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.get_my_engagement()
RETURNS SETOF analytics.user_engagement
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  RETURN QUERY SELECT * FROM analytics.user_engagement
  WHERE user_id = auth.uid();
END;
$$;
```

### Cache invalidation via Realtime

Subscribe to database changes to invalidate client-side caches in real-time:
```typescript
supabase.channel('cache-invalidation')
  .on('postgres_changes', { event: '*', schema: 'public', table: 'products' }, () => {
    queryClient.invalidateQueries(['products'])
  })
  .subscribe()
```

---

## Level 3: Bulk Operations & Partitioning (Advanced)

### PostgreSQL COPY for massive imports

```bash
# Direct COPY for CSV files (fastest possible insertion)
psql "postgresql://postgres:password@db.project.supabase.co:5432/postgres" \
  -c "\COPY public.events FROM 'events.csv' WITH CSV HEADER"
```

### Temporary optimizations for bulk loads

```sql
-- Before bulk load:
DROP INDEX IF EXISTS idx_events_created; -- Rebuild after is faster
ALTER TABLE events SET (autovacuum_enabled = false); -- Prevent mid-load vacuum

-- After bulk load:
CREATE INDEX idx_events_created ON events(created_at);
ALTER TABLE events SET (autovacuum_enabled = true);
ANALYZE events; -- Update statistics immediately
```

### Table partitioning for very large tables

```sql
-- Partition by month for time-series data
CREATE TABLE events (
  id uuid DEFAULT gen_random_uuid(),
  data jsonb,
  created_at timestamptz DEFAULT now()
) PARTITION BY RANGE (created_at);

CREATE TABLE events_2026_01 PARTITION OF events
  FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE events_2026_02 PARTITION OF events
  FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
```

Benefits: partition pruning (query planner skips irrelevant months), instant data expiration (`DROP TABLE events_2025_01`), parallel maintenance.

### BRIN indexes for time-series

```sql
-- 10-100x smaller than B-tree, perfect for append-only timestamp data
CREATE INDEX idx_events_brin ON events USING brin(created_at)
  WITH (pages_per_range = 128);
```

---

## Performance: Make It Fast

1. **PostgREST over raw SQL** — HTTP/2 multiplexing eliminates connection overhead
2. **Batch 500-1000 rows** per upsert, COPY for >100K rows
3. **Materialized views** for dashboard aggregations (refresh concurrently)
4. **Multi-layer caching** — React Query + Cache-Control + CDN + Redis
5. **Keyset pagination** — constant-time regardless of page depth
6. **BRIN indexes** for time-series data — microscopic storage footprint
7. **Table partitioning** for billion-row tables — enables partition pruning

## Observability: Know It's Working

1. **Cache hit ratio** — `shared hit / (shared hit + shared read)` from EXPLAIN BUFFERS
2. **pg_stat_statements** — track query performance before/after optimizations
3. **Monitor materialized view staleness** — track last refresh time
4. **Supabase Storage CDN** — check `cf-cache-status` header for HIT/MISS
5. **Connection pool utilization** — monitor Supavisor saturation

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No One-Row-at-a-Time Inserts
**You will be tempted to:** Loop through an array calling `.insert()` for each item.
**Why that fails:** Each call = network round-trip + parse + plan + WAL write. 1000 items = 30 seconds vs 0.3 seconds batched.
**The right way:** `.upsert(arrayOf1000)` or COPY for bulk.

### Rule 2: No Materialized Views Without RLS Workaround
**You will be tempted to:** Create a materialized view in the public schema and assume RLS protects it.
**Why that fails:** Materialized views bypass RLS entirely. All data is visible to any role.
**The right way:** Put MV in a private schema, revoke public access, wrap in SECURITY DEFINER function.

### Rule 3: No OFFSET Pagination
**You will be tempted to:** Use `.range(page*50, (page+1)*50)` because it maps to UI page numbers.
**Why that fails:** PostgreSQL scans and discards all rows before the offset. Page 200 = scan 10,000 rows.
**The right way:** Keyset pagination with `.gt('id', lastId).limit(50)`.

### Rule 4: No Assuming Caching Is Automatic
**You will be tempted to:** Assume Supabase caches repeated queries automatically.
**Why that fails:** RLS makes every query user-specific. Caching user A's data for user B = security breach.
**The right way:** Explicitly implement Cache-Control headers, React Query SWR, or Redis.

### Rule 5: No Ignoring Connection Architecture
**You will be tempted to:** Use raw Postgres connections in serverless functions because "it's more flexible."
**Why that fails:** Each Lambda/Edge invocation opens a new TCP connection, exhausting max_connections in seconds.
**The right way:** Use supabase-js (PostgREST/HTTP/2) or Supavisor transaction mode (port 6543).
