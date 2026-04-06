---
name: mx-supa-queries
description: Use when writing Supabase database queries, PostgREST filters, RPC functions, or optimizing data fetching. Also use when the user mentions 'select', 'filter', 'PostgREST', 'resource embedding', 'N+1', 'RPC', 'plpgsql', 'stored procedure', 'pagination', 'upsert', 'ON CONFLICT', 'batch insert', or any .rpc() call.
---

# Supabase Queries & RPCs — Data Access for AI Coding Agents

**This skill loads for ANY Supabase query work.** It prevents the most common AI failures: N+1 loops instead of resource embedding, SELECT * everywhere, OFFSET pagination on large tables, and plpgsql when SQL suffices.

## When to also load
- Index strategy → `mx-supa-indexes`
- RLS on queried tables → `mx-supa-auth`
- Query plan analysis → `mx-supa-diagnostics`
- Performance optimization → `mx-supa-perf`

---

## Level 1: Patterns That Always Work (Beginner)

### Resource embedding solves N+1 — the #1 pattern

```typescript
// BAD: N+1 loop — 1 query + N queries
const { data: users } = await supabase.from('users').select('id, name')
for (const user of users) {
  const { data: posts } = await supabase
    .from('posts').select('*').eq('user_id', user.id)
  user.posts = posts  // N additional queries!
}

// GOOD: Single query with resource embedding
const { data: users } = await supabase
  .from('users')
  .select('id, name, posts(id, title, created_at)')
// PostgREST generates a single optimized JOIN
```

Embedding supports: many-to-one, one-to-many, many-to-many (via junction table), nested multi-level.

### Never SELECT * — specify columns

```typescript
// BAD: Fetches all columns, defeats index-only scans
const { data } = await supabase.from('users').select('*')

// GOOD: Only the columns you need (20-30% faster)
const { data } = await supabase.from('users').select('id, name, email')
```

### Keyset pagination over OFFSET

```typescript
// BAD: OFFSET scans and discards N rows — O(N) degradation
const { data } = await supabase
  .from('logs').select('*').range(10000, 10049)

// GOOD: Keyset pagination — O(log N), constant speed
const { data } = await supabase
  .from('logs')
  .select('id, message, created_at')
  .gt('id', lastSeenId)
  .order('id', { ascending: true })
  .limit(50)
```

### Always destructure { data, error }

```typescript
// BAD: Ignoring errors
const { data } = await supabase.from('users').select('*')

// GOOD: Handle both paths
const { data, error } = await supabase.from('users').select('id, name')
if (error) {
  console.error('Query failed:', error.message)
  return
}
```

---

## Level 2: Advanced Query Patterns (Intermediate)

### Filter chaining with conditional logic

```typescript
// Dynamic filter building
let query = supabase.from('products').select('id, name, price')

if (category) query = query.eq('category', category)
if (minPrice) query = query.gte('price', minPrice)
if (search) query = query.ilike('name', `%${search}%`)

const { data, error } = await query.order('created_at', { ascending: false })
```

### OR conditions with raw PostgREST syntax

```typescript
// .or() uses PostgREST filter syntax, not method chaining
const { data } = await supabase
  .from('tasks')
  .select('*')
  .or('status.eq.urgent,and(priority.gt.5,assigned_to.eq.me)')
```

### Inner joins with !inner modifier

```typescript
// Default: LEFT JOIN — returns parent even if no matching children
const { data } = await supabase
  .from('users')
  .select('id, name, posts(title)')

// With !inner: INNER JOIN — only returns users WHO HAVE posts matching filter
const { data } = await supabase
  .from('users')
  .select('id, name, posts!inner(title)')
  .eq('posts.status', 'published')
```

### Batch upsert with ON CONFLICT

```typescript
// Batch 500-1000 rows per call (not one at a time)
const { error } = await supabase
  .from('products')
  .upsert(batchOf1000Items, {
    onConflict: 'sku',          // Unique constraint column
    ignoreDuplicates: false      // Update on conflict
  })
```

For >100K rows, use PostgreSQL COPY command directly, not the SDK.

### RPC functions — SQL vs plpgsql decision

| Need | Use | Why |
|------|-----|-----|
| Simple SELECT with params | `LANGUAGE SQL` | Inlineable by query planner — faster |
| Conditional logic, loops | `LANGUAGE plpgsql` | Procedural control flow |
| Error handling (EXCEPTION) | `LANGUAGE plpgsql` | Only plpgsql has EXCEPTION blocks |
| Dynamic SQL (EXECUTE) | `LANGUAGE plpgsql` | Only plpgsql supports dynamic queries |

```sql
-- GOOD: SQL function — inlineable, faster for simple reads
CREATE FUNCTION public.get_user_posts(uid uuid)
RETURNS SETOF public.posts
LANGUAGE SQL STABLE
AS $$
  SELECT * FROM public.posts WHERE user_id = uid ORDER BY created_at DESC;
$$;

-- GOOD: plpgsql — only when you need control flow
CREATE FUNCTION public.transfer_funds(from_id uuid, to_id uuid, amount numeric)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive';
  END IF;
  UPDATE accounts SET balance = balance - amount WHERE id = from_id;
  UPDATE accounts SET balance = balance + amount WHERE id = to_id;
END;
$$;
```

---

## Level 3: Query Optimization (Advanced)

### EXISTS over IN for subqueries

```sql
-- BAD: IN materializes entire subquery result
SELECT name FROM customers WHERE id IN (SELECT customer_id FROM orders);

-- GOOD: EXISTS stops at first match
SELECT name FROM customers c
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.id);
```

### Avoid correlated subqueries — use JOINs

```sql
-- BAD: Correlated subquery executes per row
SELECT u.name,
  (SELECT MAX(created_at) FROM logins l WHERE l.user_id = u.id)
FROM users u;

-- GOOD: JOIN with GROUP BY
SELECT u.name, MAX(l.created_at) as last_login
FROM users u LEFT JOIN logins l ON u.id = l.user_id
GROUP BY u.name;
```

### SECURITY DEFINER for RPC functions

```sql
CREATE FUNCTION public.admin_action(target_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.user_roles SET role = 'admin' WHERE user_id = target_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_action FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_action TO authenticated;
```

---

## Performance: Make It Fast

1. **Resource embedding** — one query instead of N+1 loops
2. **Specify columns** — enables index-only scans, reduces payload
3. **Keyset pagination** — O(log N) vs O(N) for OFFSET
4. **Batch upserts** — 500-1000 rows per call, wrapped in transaction
5. **SQL functions over plpgsql** — inlineable by query planner for simple reads
6. **COPY for bulk imports** — bypasses query planner for >100K rows
7. **Keep DB statistics fresh** — run ANALYZE after large data changes

## Observability: Know It's Working

1. **EXPLAIN ANALYZE** — verify query plans use indexes, not sequential scans
2. **supabase-js .explain({ analyze: true })** — programmatic plan analysis
3. **pg_stat_statements** — identify slowest and most frequent queries
4. **Monitor high-call-count queries** — may indicate N+1 patterns in app code
5. **Check `Rows Removed by Filter`** in EXPLAIN output — high count = missing index

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No N+1 Loops
**You will be tempted to:** Fetch a list of IDs, then loop through them fetching related data one by one.
**Why that fails:** Each iteration is a network round-trip + query parse + plan + execute. 100 users × 1 query each = 100 queries instead of 1.
**The right way:** `.select('*, related_table(columns)')` — PostgREST handles the JOIN.

### Rule 2: No SELECT *
**You will be tempted to:** Use `.select('*')` because it's quick and you're "not sure which columns you need yet."
**Why that fails:** Fetches all columns including large text/jsonb fields, prevents index-only scans, wastes bandwidth.
**The right way:** Explicitly list required columns: `.select('id, name, email')`.

### Rule 3: No OFFSET on Large Tables
**You will be tempted to:** Use `.range(page * 50, (page + 1) * 50)` because it maps to page numbers.
**Why that fails:** PostgreSQL must scan, sort, and discard all rows before the offset. Page 200 of 50-row pages = scan 10,000 rows to return 50.
**The right way:** Keyset pagination with `.gt('id', lastId).order('id').limit(50)`.

### Rule 4: No plpgsql for Simple Reads
**You will be tempted to:** Default to `LANGUAGE plpgsql` because it "looks like a real function."
**Why that fails:** plpgsql cannot be inlined by the query planner. It creates an optimization barrier that prevents index pushdown.
**The right way:** Use `LANGUAGE SQL STABLE` for read-only functions. Only use plpgsql when you need IF/LOOP/EXCEPTION.
