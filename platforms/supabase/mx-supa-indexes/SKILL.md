---
name: mx-supa-indexes
description: Use when creating database indexes, optimizing query performance, or choosing index types in Supabase. Also use when the user mentions 'index', 'CREATE INDEX', 'btree', 'GIN', 'GiST', 'BRIN', 'partial index', 'composite index', 'foreign key index', 'sequential scan', 'Seq Scan', 'missing index', 'pg_stat_user_tables', 'covering index', or 'INCLUDE'.
---

# Supabase Indexes — Index Strategy for AI Coding Agents

**This skill loads for ANY index-related work.** It prevents the most common AI failures: always defaulting to btree (even for JSONB), never indexing foreign keys, ignoring partial indexes, and scrambling composite index column order.

## When to also load
- Query optimization → `mx-supa-queries`
- EXPLAIN ANALYZE reading → `mx-supa-diagnostics`
- RLS policy columns → `mx-supa-auth`
- Schema design → `mx-supa-schema`

---

## Level 1: Patterns That Always Work (Beginner)

### Index type decision tree

| Data / Query Pattern | Index Type | Example |
|---------------------|------------|---------|
| Equality, range, ORDER BY (default) | **B-tree** | `CREATE INDEX idx ON t(col);` |
| JSONB containment (`@>`), array search | **GIN** | `CREATE INDEX idx ON t USING gin(data);` |
| Geospatial (PostGIS), overlapping ranges | **GiST** | `CREATE INDEX idx ON t USING gist(geom);` |
| Very large append-only tables (timestamps) | **BRIN** | `CREATE INDEX idx ON t USING brin(created_at);` |
| Full-text search (`tsvector`) | **GIN** | `CREATE INDEX idx ON t USING gin(search_vec);` |

**When in doubt, B-tree is the default.** Only use GIN/GiST/BRIN when the data type demands it.

### ALWAYS index foreign keys

PostgreSQL does NOT auto-index foreign key columns. Missing FK indexes cause:
- Sequential scans on JOINs
- Table locks during parent DELETE (referential integrity check)

```sql
-- Table creation
CREATE TABLE public.orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id),
  created_at timestamptz DEFAULT now()
);

-- MANDATORY: Index every foreign key
CREATE INDEX idx_orders_user_id ON public.orders(user_id);
CREATE INDEX idx_orders_product_id ON public.orders(product_id);
```

### Index columns used in RLS policies

If your RLS policy filters on `user_id`, that column MUST be indexed or every policy check triggers a sequential scan.

---

## Level 2: Advanced Index Patterns (Intermediate)

### Composite indexes — ESR rule (Equality, Sort, Range)

Column order in a composite index determines effectiveness:
1. **Equality** columns first (`=`, `IS NULL`)
2. **Sort** columns next (`ORDER BY`)
3. **Range** columns last (`>`, `<`, `BETWEEN`)

```sql
-- Query: WHERE user_id = X AND status = Y ORDER BY created_at DESC WHERE amount > Z
-- ESR: equality(user_id, status), sort(created_at), range(amount)
CREATE INDEX idx_orders_composite
ON orders(user_id, status, created_at DESC, amount);
```

A composite index on `(A, B)` also serves queries filtering only on `A`. Don't create a redundant standalone `(A)` index.

### Partial indexes — index only what you query

```sql
-- Soft deletes: only index active records
CREATE INDEX idx_active_users ON users(email) WHERE deleted_at IS NULL;

-- Status queues: only index pending items
CREATE INDEX idx_pending_jobs ON jobs(created_at) WHERE status = 'pending';

-- Conditional uniqueness
CREATE UNIQUE INDEX idx_one_active_sub ON subscriptions(user_id) WHERE status = 'active';
```

Partial indexes are smaller, faster to scan, and have lower write overhead. The query's WHERE clause must match or be more restrictive than the index's WHERE clause.

### Covering indexes with INCLUDE

```sql
-- All queried columns in the index = index-only scan (no heap access)
CREATE INDEX idx_users_covering
ON users(tenant_id, status) INCLUDE (email, last_login);
```

### Expression indexes for function-based lookups

```sql
-- BAD: Index on email, but query uses LOWER(email) — index ignored
SELECT * FROM users WHERE LOWER(email) = 'test@example.com';

-- GOOD: Expression index matches the query function
CREATE INDEX idx_users_lower_email ON users(LOWER(email));
```

---

## Level 3: Index Maintenance (Advanced)

### Detecting missing indexes

```sql
-- Tables with high sequential scan counts (likely missing indexes)
SELECT relname, seq_scan, seq_tup_read, idx_scan
FROM pg_stat_user_tables
WHERE seq_scan > 0
ORDER BY seq_tup_read DESC LIMIT 10;
```

Also use: Supabase Performance Advisor (flags unindexed FKs), EXPLAIN ANALYZE (shows Seq Scan).

### Detecting unused indexes (candidates for removal)

```sql
SELECT schemaname, relname AS table_name,
  indexrelname AS index_name,
  pg_size_pretty(pg_relation_size(indexrelid)) AS size,
  idx_scan
FROM pg_stat_user_indexes
WHERE idx_scan = 0 AND indisunique IS FALSE
ORDER BY pg_relation_size(indexrelid) DESC;
```

Use `DROP INDEX CONCURRENTLY` to avoid table locking during removal.

### Over-indexing warning signs

Each index adds overhead to every INSERT, UPDATE, DELETE. Watch for:
- Write-heavy tables with >10 indexes
- Indexes with `idx_scan = 0` over extended periods
- Redundant prefix indexes (`(A)` when `(A, B)` exists)
- Supabase lint `0009 duplicate index` warnings

### When NOT to index

- Tables under ~1,000 rows (sequential scan is faster)
- Low-cardinality columns with even distribution (e.g., boolean 50/50) — use partial index instead
- Columns only used for INSERT, never filtered/sorted

---

## Performance: Make It Fast

1. **B-tree for scalar, GIN for JSONB/arrays, BRIN for time-series** — match type to data
2. **ESR rule for composite indexes** — equality, sort, range column order
3. **Partial indexes for sparse queries** — soft deletes, status filters, queue patterns
4. **INCLUDE for covering indexes** — enable index-only scans
5. **Expression indexes** — match the function used in WHERE clauses
6. **Run VACUUM and ANALYZE** after large data changes — keeps query planner accurate

## Observability: Know It's Working

1. **EXPLAIN ANALYZE** — verify Index Scan not Seq Scan on filtered queries
2. **Supabase Performance Advisor** — flags unindexed foreign keys
3. **pg_stat_user_tables** — monitor seq_scan vs idx_scan ratios
4. **pg_stat_user_indexes** — detect unused indexes wasting write overhead
5. **Supabase lint 0009** — flags duplicate/redundant indexes
6. **BUFFERS output** — `shared hit` (cached) vs `shared read` (disk) shows I/O efficiency

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No btree for JSONB
**You will be tempted to:** Create a B-tree index on a JSONB column to speed up containment queries.
**Why that fails:** B-tree only supports whole-value equality. `WHERE data @> '{"role":"admin"}'` cannot use a B-tree.
**The right way:** Use GIN: `CREATE INDEX idx ON t USING gin(data);`

### Rule 2: Never Skip Foreign Key Indexes
**You will be tempted to:** Trust that PostgreSQL auto-indexes foreign keys like MySQL does.
**Why that fails:** PostgreSQL absolutely does NOT auto-index FK columns. Every JOIN and every parent DELETE triggers a sequential scan on the child table.
**The right way:** Every `REFERENCES` must have a corresponding `CREATE INDEX` on the FK column.

### Rule 3: Never Ignore Partial Indexes
**You will be tempted to:** Create a full index on a `status` column (low cardinality) to speed up queries for 'pending' items.
**Why that fails:** A full B-tree on a boolean or status column provides minimal selectivity and wastes write overhead on every row change.
**The right way:** `CREATE INDEX idx ON t(created_at) WHERE status = 'pending'` — indexes only the rows you query.

### Rule 4: Never Scramble Composite Column Order
**You will be tempted to:** Put the "most selective" column first in a composite index.
**Why that fails:** Selectivity doesn't matter for equality predicates in B-trees. What matters is: equality first, then sort, then range (ESR rule).
**The right way:** Follow ESR strictly. `WHERE user_id = X ORDER BY created_at` → index `(user_id, created_at)`.

### Rule 5: Never Create Redundant Indexes
**You will be tempted to:** Create `(user_id)` AND `(user_id, created_at)` as separate indexes.
**Why that fails:** The composite `(user_id, created_at)` already serves queries filtering only on `user_id`. The standalone index is pure write overhead.
**The right way:** Only the composite index is needed. Check Supabase lint for `0009 duplicate index` warnings.
