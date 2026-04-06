---
name: mx-supa-auth
description: Use when writing Supabase Row Level Security (RLS) policies, auth flows, JWT handling, or any security-related Supabase work. Also use when the user mentions 'RLS', 'row level security', 'auth.uid()', 'getUser', 'getSession', 'SECURITY DEFINER', 'service_role', 'anon key', 'user_metadata', 'app_metadata', 'JWT', 'policy', 'USING', 'WITH CHECK', or any .sql file containing CREATE POLICY.
---

# Supabase Auth & RLS — Security Patterns for AI Coding Agents

**This skill loads for ANY Supabase security work.** It prevents the most common AI failures: policies that silently return empty sets, bare `auth.uid()` calls that destroy performance, and `getSession()` used for server-side auth decisions.

## When to also load
- Schema/migrations → `mx-supa-schema`
- Edge Functions (Deno) → `mx-supa-edge`
- Client SDK init (anon vs service_role) → `mx-supa-client`
- Query optimization → `mx-supa-queries`
- Monitoring RLS performance → `mx-supa-observability`

---

## Level 1: Patterns That Always Work (Beginner)

### Enable RLS on EVERY public table — no exceptions

```sql
-- BAD: Table exposed to anon key with no protection
CREATE TABLE public.documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id),
  content text
);
-- Anyone with the anon key can SELECT/INSERT/UPDATE/DELETE all rows

-- GOOD: RLS enabled immediately after CREATE TABLE
CREATE TABLE public.documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content text,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
```

If RLS is enabled with NO policies, the default is **deny all** — which is safe.

### Wrap auth.uid() in SELECT — the #1 performance rule

| Pattern | Behavior | Performance on 1M rows |
|---------|----------|----------------------|
| `auth.uid() = user_id` | Evaluated per-row | ~3,000ms |
| `(SELECT auth.uid()) = user_id` | Evaluated once (initPlan cached) | ~15ms |

```sql
-- BAD: Per-row evaluation destroys performance
CREATE POLICY "Users read own" ON public.documents
FOR SELECT TO authenticated
USING (auth.uid() = user_id);

-- GOOD: InitPlan caching — 200x faster
CREATE POLICY "Users read own" ON public.documents
FOR SELECT TO authenticated
USING ((SELECT auth.uid()) = user_id);
```

This applies to ALL auth functions: `auth.uid()`, `auth.jwt()`, `auth.role()`, `auth.email()`.

### Separate policies per CRUD operation

```sql
-- BAD: FOR ALL with single expression
CREATE POLICY "Users manage own" ON public.documents
FOR ALL TO authenticated
USING ((SELECT auth.uid()) = user_id);
-- INSERT has no WITH CHECK — silently fails

-- GOOD: Granular per-operation
CREATE POLICY "Select own" ON public.documents
FOR SELECT TO authenticated
USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Insert own" ON public.documents
FOR INSERT TO authenticated
WITH CHECK ((SELECT auth.uid()) = user_id);

CREATE POLICY "Update own" ON public.documents
FOR UPDATE TO authenticated
USING ((SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) = user_id);

CREATE POLICY "Delete own" ON public.documents
FOR DELETE TO authenticated
USING ((SELECT auth.uid()) = user_id);
```

### Use explicit TO clause — always specify the role

```sql
-- BAD: No TO clause — evaluates for ALL roles including system roles
CREATE POLICY "Public read" ON public.posts
FOR SELECT USING (is_published = true);

-- GOOD: Explicit role targeting
CREATE POLICY "Public read" ON public.posts
FOR SELECT TO anon, authenticated
USING (is_published = true);
```

### getUser() vs getSession() — the authentication decision

| Context | Method | Why |
|---------|--------|-----|
| Server-side auth (API routes, Server Actions) | `supabase.auth.getUser()` | Cryptographically validates JWT with Auth server |
| Server-side JWT claims only | `supabase.auth.getClaims()` | Verifies signature locally, no network call |
| Client UI display (name, avatar) | `supabase.auth.getSession()` | Fast local read, OK for non-sensitive UI |
| NEVER for security decisions | `supabase.auth.getSession()` | Reads unverified data from local storage — spoofable |

---

## Level 2: Advanced RLS Patterns (Intermediate)

### Multi-tenancy via JWT claims

```sql
-- Extract tenant_id from JWT app_metadata (set during user creation)
CREATE POLICY "Tenant isolation" ON public.tenant_resources
FOR ALL TO authenticated
USING (
  tenant_id = ((SELECT auth.jwt()) -> 'app_metadata' ->> 'tenant_id')::uuid
)
WITH CHECK (
  tenant_id = ((SELECT auth.jwt()) -> 'app_metadata' ->> 'tenant_id')::uuid
);
```

**Index the tenant_id column** or this becomes a sequential scan.

### RBAC with SECURITY DEFINER helper functions

```sql
-- Helper function — MUST have search_path = ''
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = (SELECT auth.uid())
    AND role = 'admin'
  );
END;
$$;

-- Policy using the helper
CREATE POLICY "Admins full access" ON public.system_configs
FOR ALL TO authenticated
USING ((SELECT public.is_admin()))
WITH CHECK ((SELECT public.is_admin()));
```

### Storage RLS on storage.objects

```sql
-- Users can upload/read files in their own UUID folder
CREATE POLICY "Users manage own files" ON storage.objects
FOR ALL TO authenticated
USING (
  bucket_id = 'user-files'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
)
WITH CHECK (
  bucket_id = 'user-files'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
);
```

---

## Level 3: Security Hardening (Advanced)

### SECURITY DEFINER — mandatory hardening pattern

Every SECURITY DEFINER function MUST:
1. `SET search_path = ''` — prevents search_path hijacking
2. Fully qualify all objects (`public.table_name`, `auth.users`)
3. Revoke EXECUTE from PUBLIC — grant only to needed roles
4. Validate all inputs — runs as superuser

```sql
CREATE OR REPLACE FUNCTION public.promote_user(target_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Fully qualified table reference
  UPDATE public.user_roles SET role = 'admin'
  WHERE user_id = target_id;
END;
$$;

-- Restrict execution
REVOKE EXECUTE ON FUNCTION public.promote_user FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.promote_user TO authenticated;
```

### RLS bypass via views — the hidden trap

Views created by the postgres user bypass RLS by default. Fix:
```sql
-- For Postgres 15+: make views respect caller's RLS
ALTER VIEW public.my_view SET (security_invoker = true);

-- For older versions: revoke access and use RPC instead
REVOKE SELECT ON public.my_view FROM anon, authenticated;
```

### RLS testing — NEVER test in SQL Editor

The SQL Editor runs as `postgres` superuser → bypasses ALL RLS.

| Testing Method | RLS Enforced? | Use For |
|---------------|---------------|---------|
| SQL Editor (default) | NO | Schema design only |
| SQL Editor + Impersonation dropdown | YES | Quick policy debugging |
| Client SDK with real JWT | YES | Integration tests |
| pgTAP with `SET ROLE` | YES | CI/CD automated tests |
| SET LOCAL "request.jwt.claims" | YES | Manual policy expression testing |

---

## Performance: Make It Fast

1. **Wrap ALL auth functions in SELECT** — `(SELECT auth.uid())`, `(SELECT auth.jwt())` — enables initPlan caching
2. **Index every column used in RLS policies** — especially `user_id`, `tenant_id`, `organization_id`
3. **Mark helper functions as STABLE** — allows PostgreSQL to cache per-transaction
4. **Avoid correlated subqueries in policies** — use SECURITY DEFINER functions instead
5. **Specify roles with TO** — prevents unnecessary policy evaluation for wrong roles
6. **Target < 50ms for RLS-affected queries** — use EXPLAIN ANALYZE to verify

## Observability: Know It's Working

1. **Supabase Performance Advisor** — detects unindexed columns used in RLS
2. **Supabase Security Advisor** — flags mutable search_path, missing RLS, overly permissive policies
3. **EXPLAIN ANALYZE** — compare query plans WITH and WITHOUT RLS to measure policy cost
4. **Realtime RLS reports** — Dashboard shows median RLS execution time for private channel subscriptions
5. **pg_stat_statements** — identify slow queries caused by complex RLS policies
6. **supabase-js .explain({ analyze: true })** — programmatic query plan analysis

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: The Bare auth.uid() Trap
**You will be tempted to:** Write `USING (auth.uid() = user_id)` because it's concise and readable.
**Why that fails:** Without the SELECT wrapper, PostgreSQL evaluates `auth.uid()` for every row scanned. On a 1M row table, this adds 3+ seconds to every query.
**The right way:** Always `USING ((SELECT auth.uid()) = user_id)` — forces initPlan caching, 200x faster.

### Rule 2: The SELECT true Policy
**You will be tempted to:** Write `CREATE POLICY "Public" ON table FOR SELECT USING (true)` to quickly make data visible during development.
**Why that fails:** Without a `TO` clause, this evaluates for all roles including system roles. In production, it exposes all data to anyone with the anon key.
**The right way:** Always specify `TO anon, authenticated` explicitly. Even better: use `visibility = 'public'` column with a proper filter.

### Rule 3: Testing in the SQL Editor
**You will be tempted to:** Debug RLS by running `SELECT * FROM table` in the SQL Editor to see if policies work.
**Why that fails:** The SQL Editor runs as `postgres` superuser with BYPASSRLS. Queries return ALL rows regardless of policies.
**The right way:** Use the Impersonation dropdown in the Dashboard, test via client SDK with real JWTs, or use pgTAP in CI/CD.

### Rule 4: getSession() for Security
**You will be tempted to:** Use `supabase.auth.getSession()` in a server action because it's faster than `getUser()`.
**Why that fails:** `getSession()` reads unverified data from cookies/localStorage. An attacker can forge a JWT in their cookies and impersonate any user.
**The right way:** Use `supabase.auth.getUser()` for all server-side security decisions. Use `getClaims()` if you only need JWT validation without full user data.

### Rule 5: SECURITY DEFINER without search_path
**You will be tempted to:** Write `SECURITY DEFINER` functions without `SET search_path = ''` because the function logic is "simple."
**Why that fails:** A malicious user can create a same-named object in a schema that precedes yours in the search_path, hijacking the function's superuser execution context.
**The right way:** ALWAYS append `SET search_path = ''` and fully qualify all object references (`public.table_name`).
