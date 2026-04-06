---
name: mx-supa-schema
description: Use when creating Supabase tables, writing database migrations, altering schema, or managing schema evolution. Also use when the user mentions 'migration', 'ALTER TABLE', 'CREATE TABLE', 'db push', 'db reset', 'db diff', 'schema drift', 'rollback', 'seed.sql', 'supabase migration', 'declarative schema', 'foreign key', 'ON DELETE', 'timestamptz', 'uuid', or any file in supabase/migrations/.
---

# Supabase Schema & Migrations — Database Evolution for AI Coding Agents

**This skill loads for ANY Supabase schema or migration work.** It prevents the most common AI failures: modifying applied migrations, using db reset on production, skipping RLS on new tables, and creating tables with wrong column types.

## When to also load
- RLS policies on new tables → `mx-supa-auth`
- Index strategy for new tables → `mx-supa-indexes`
- Edge Function deployment → `mx-supa-edge`
- Query patterns for new schema → `mx-supa-queries`

---

## Level 1: Patterns That Always Work (Beginner)

### Every table needs these columns and settings

```sql
CREATE TABLE public.documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title text NOT NULL,
  content text,
  created_at timestamptz DEFAULT now()
);

-- MANDATORY: Enable RLS immediately
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;

-- MANDATORY: Index foreign keys (Postgres does NOT auto-index them)
CREATE INDEX idx_documents_user_id ON public.documents(user_id);
```

### Type selection decision tree

| Need | Use | Never Use | Why |
|------|-----|-----------|-----|
| Primary key | `uuid DEFAULT gen_random_uuid()` | `serial` / `bigint` | Prevents enumeration attacks, works with Supabase Auth |
| Timestamps | `timestamptz` | `timestamp` | Stores UTC, prevents timezone bugs in global apps |
| Strings | `text` | `varchar(255)` | Identical performance in Postgres, no arbitrary limit errors |
| JSON data | `jsonb` | `json` | Binary format enables indexing and fast querying |
| Fixed values | `text` + CHECK constraint | Custom ENUM | ENUMs require migrations to add values |

### Naming conventions — snake_case everything

```sql
-- BAD: camelCase requires double-quoting everywhere
CREATE TABLE "userProfiles" ("firstName" text, "lastName" text);

-- GOOD: snake_case works natively with PostgREST
CREATE TABLE user_profiles (first_name text, last_name text);
```

### Foreign key ON DELETE behavior — decide at design time

| Behavior | When to use | Example |
|----------|------------|---------|
| `ON DELETE CASCADE` | Strong ownership — child meaningless without parent | post → comments |
| `ON DELETE SET NULL` | Optional relationship — child survives | department → employees |
| `ON DELETE RESTRICT` | Critical data — prevent accidental deletion | invoice → line_items |

### Migration workflow — the only safe path

```bash
# 1. Create a new migration file
supabase migration new add_documents_table

# 2. Write SQL in supabase/migrations/TIMESTAMP_add_documents_table.sql

# 3. Apply locally
supabase db reset   # Local only — drops and recreates

# 4. Deploy to production
supabase db push    # Appends new migrations only
```

---

## Level 2: Migration Management (Intermediate)

### db push vs db reset — the critical distinction

| Command | What it does | Data impact | Use for |
|---------|-------------|-------------|---------|
| `supabase db push` | Applies PENDING migrations on top of existing DB | Non-destructive | Staging, production |
| `supabase db reset` | DROPS everything, reruns ALL migrations from scratch | DESTROYS all data | Local development ONLY |

**The trap:** `db reset` runs on an empty database. `db push` runs on a live, data-filled database. A migration that works with `db reset` locally may FAIL with `db push` on production if it conflicts with existing data.

### Roll-forward pattern — how to undo mistakes

Supabase has NO `down` command. NO `rollback` command. To undo a deployed migration, create a NEW migration with the inverse SQL.

```sql
-- Migration 20250810_add_faulty_column.sql (the mistake)
ALTER TABLE users ADD COLUMN ssn text;

-- Migration 20250810_revert_faulty_column.sql (the fix — roll forward)
ALTER TABLE users DROP COLUMN IF EXISTS ssn;
```

### Declarative schemas with db diff

```bash
# 1. Define desired state in supabase/schemas/employees.sql
# 2. Run diff to generate migration
supabase db diff -f add_employee_age

# 3. Review generated migration, then push
supabase db push
```

**Limitation:** `db diff` CANNOT handle renames (interprets as DROP + CREATE = data loss), RLS policies, or data migrations. Use imperative migrations for these.

### Idempotent migrations

```sql
-- GOOD: Won't fail if run twice
CREATE TABLE IF NOT EXISTS public.documents (...);
DROP TABLE IF EXISTS public.old_table;
ALTER TABLE public.documents ADD COLUMN IF NOT EXISTS status text;
```

### Transactional wrapping for complex migrations

```sql
BEGIN;
  ALTER TABLE public.orders ADD COLUMN total_amount numeric;
  UPDATE public.orders SET total_amount = quantity * price;
  ALTER TABLE public.orders ALTER COLUMN total_amount SET NOT NULL;
COMMIT;
```

---

## Level 3: Production Operations (Advanced)

### Schema drift prevention

Dashboard changes without migrations = drift. The production DB state diverges from your codebase.

```bash
# If someone changed schema via Dashboard, capture it:
supabase db diff --linked -f capture_dashboard_changes

# Commit the generated migration to version control
git add supabase/migrations/
git commit -m "capture dashboard schema changes"
```

### CI/CD pipeline (the right way)

1. Developer creates migration locally
2. PR opened → GitHub Action runs `supabase db reset` + `supabase test db` on ephemeral instance
3. PR merged → GitHub Action runs `supabase db push` against production

### Fixing hash mismatches

If a migration file was modified after being applied, the CLI detects a hash mismatch:
```
ERROR: The remote database's migration history does not match local files
```

Fix with surgical repair:
```bash
supabase migration repair --status applied <timestamp>
```

**NEVER delete the schema_migrations table or local migration files to "fix" this.**

### Include RLS + indexes in every table migration

```sql
-- One migration file = table + RLS + indexes + policies
CREATE TABLE public.tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title text NOT NULL,
  status text DEFAULT 'pending',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_tasks_user_id ON public.tasks(user_id);
CREATE INDEX idx_tasks_status ON public.tasks(status) WHERE status = 'pending';

CREATE POLICY "Users manage own tasks" ON public.tasks
FOR ALL TO authenticated
USING ((SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) = user_id);
```

---

## Performance: Make It Fast

1. **Include indexes in table creation migrations** — don't add them as afterthoughts
2. **Use `IF NOT EXISTS` / `IF EXISTS`** for idempotent migrations
3. **Wrap complex migrations in transactions** — prevents partial application
4. **Keep migrations small and focused** — one concern per file
5. **Use declarative schemas for simple additions** — `db diff` auto-generates optimal SQL

## Observability: Know It's Working

1. **Check `supabase_migrations.schema_migrations`** — verify migration history
2. **Monitor schema drift** — periodically run `supabase db diff --linked` to detect Dashboard changes
3. **CI/CD validation** — run migrations against ephemeral instance before production
4. **`--dry-run` flag** — preview `db push` changes before executing on production
5. **Version control everything** — migrations in Git, reviewed in PRs

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Modify Applied Migrations
**You will be tempted to:** Edit the original `CREATE TABLE` migration to add a new column, keeping the schema definition "clean."
**Why that fails:** The CLI stores a cryptographic hash of each applied migration. Modifying the file changes the hash, causing a fatal mismatch error on next deployment.
**The right way:** Create a NEW migration with `ALTER TABLE ... ADD COLUMN`.

### Rule 2: Never db reset on Production
**You will be tempted to:** Run `supabase db reset --linked` when production throws a migration conflict, because it "worked locally."
**Why that fails:** `db reset` drops ALL schemas and data. Every user record, every file reference, every auth session — gone.
**The right way:** Use `supabase migration repair` for hash mismatches, or create a fix-forward migration for conflicts.

### Rule 3: Never Skip RLS on New Tables
**You will be tempted to:** Create a table without RLS "for now" to get the API working quickly.
**Why that fails:** The table is immediately exposed via the anon key. Anyone can read, write, and delete all data.
**The right way:** Every `CREATE TABLE` in the `public` schema MUST be followed by `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` in the same migration file.

### Rule 4: Never Use varchar(255)
**You will be tempted to:** Use `varchar(255)` because it's the "standard" from MySQL/Rails tutorials.
**Why that fails:** PostgreSQL has zero performance difference between `text` and `varchar(n)`. The arbitrary limit only causes runtime errors when strings exceed it.
**The right way:** Use `text` for all string columns. Add CHECK constraints only when a strict length limit is a real business requirement.

### Rule 5: Never Use db diff for Renames
**You will be tempted to:** Rename a column in the declarative schema file and run `supabase db diff`.
**Why that fails:** The diff engine interprets a rename as DROP old column + CREATE new column. All data in that column is permanently destroyed.
**The right way:** Write an imperative migration: `ALTER TABLE ... RENAME COLUMN old_name TO new_name`.
