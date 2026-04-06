---
name: mx-go-data
description: Go database and data — database/sql connection pooling, pgx for PostgreSQL, pgxpool, sqlc code generation, transactions with BeginTx/Commit/Rollback, prepared statements, migrations with golang-migrate and goose, context on all DB ops, SELECT column lists, connection pool tuning.
---

# Go Data — Database Patterns for AI Coding Agents

**Load when working with databases, SQL, migrations, or data persistence in Go.**

## When to also load
- Core Go patterns → `mx-go-core`
- Connection pool monitoring → `mx-go-observability`
- Transaction isolation in concurrent code → `mx-go-concurrency`
- Database benchmarking → `mx-go-perf`

---

## Level 1: Connection Management

### sql.DB Is a Pool, Not a Connection

```go
// BAD — creating db per request destroys pooling
func handleRequest(w http.ResponseWriter, r *http.Request) {
    db, _ := sql.Open("postgres", connStr)  // new pool every request!
    defer db.Close()
    // ...
}

// GOOD — initialize once, share everywhere
var db *sql.DB

func main() {
    var err error
    db, err = sql.Open("postgres", connStr)
    if err != nil {
        log.Fatal(err)
    }
    defer db.Close()

    // Tune the pool
    db.SetMaxOpenConns(25)             // (CPU cores * 2) + 1 as starting point
    db.SetMaxIdleConns(10)             // keep some ready for traffic spikes
    db.SetConnMaxLifetime(5 * time.Minute) // prevent stale, aid load balancing
    db.SetConnMaxIdleTime(1 * time.Minute)

    // Verify connectivity
    if err := db.PingContext(context.Background()); err != nil {
        log.Fatal(err)
    }
}
```

### pgx — Use for PostgreSQL

```go
// pgx is faster than database/sql for Postgres (binary format, native types)
// Use pgxpool for connection pooling

pool, err := pgxpool.New(context.Background(), connStr)
if err != nil {
    return fmt.Errorf("create pool: %w", err)
}
defer pool.Close()

// Configure pool
config, err := pgxpool.ParseConfig(connStr)
if err != nil {
    return fmt.Errorf("parse config: %w", err)
}
config.MaxConns = 25
config.MinConns = 5
config.MaxConnLifetime = 5 * time.Minute

pool, err = pgxpool.NewWithConfig(context.Background(), config)
```

**Decision: pgx vs database/sql:**

| Scenario | Use |
|----------|-----|
| PostgreSQL only | pgx directly (faster, richer types) |
| Multiple databases or DB-agnostic | database/sql with pgx/v5/stdlib driver |
| Need jsonb, arrays, custom types | pgx (native type support) |

### Context on ALL Database Operations

```go
// BAD — no context, query can hang forever
rows, err := db.Query("SELECT * FROM users")

// GOOD — context with timeout
ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
defer cancel()
rows, err := db.QueryContext(ctx, "SELECT id, name, email FROM users WHERE active = $1", true)
```

---

## Level 2: Queries and Transactions

### Always Close Rows

```go
// BAD — rows not closed, connection leaked
rows, err := db.QueryContext(ctx, "SELECT id, name FROM users")
if err != nil { return err }
// forgot rows.Close() — connection leak!

// GOOD — defer close immediately
rows, err := db.QueryContext(ctx, "SELECT id, name FROM users")
if err != nil {
    return fmt.Errorf("query users: %w", err)
}
defer rows.Close()

var users []User
for rows.Next() {
    var u User
    if err := rows.Scan(&u.ID, &u.Name); err != nil {
        return fmt.Errorf("scan user: %w", err)
    }
    users = append(users, u)
}
if err := rows.Err(); err != nil {  // check iteration errors
    return fmt.Errorf("iterate users: %w", err)
}
```

### Transactions — The Safe Pattern

```go
func transferFunds(ctx context.Context, db *sql.DB, from, to string, amount int) error {
    tx, err := db.BeginTx(ctx, &sql.TxOptions{
        Isolation: sql.LevelSerializable,
    })
    if err != nil {
        return fmt.Errorf("begin tx: %w", err)
    }
    defer tx.Rollback()  // safety net — no-op after Commit

    // ALL operations use tx, NOT db
    _, err = tx.ExecContext(ctx, "UPDATE accounts SET balance = balance - $1 WHERE id = $2", amount, from)
    if err != nil {
        return fmt.Errorf("debit: %w", err)
    }

    _, err = tx.ExecContext(ctx, "UPDATE accounts SET balance = balance + $1 WHERE id = $2", amount, to)
    if err != nil {
        return fmt.Errorf("credit: %w", err)
    }

    if err := tx.Commit(); err != nil {
        return fmt.Errorf("commit: %w", err)
    }
    return nil
}
```

### sqlc — Code Generation from SQL

```sql
-- queries/users.sql
-- name: GetUser :one
SELECT id, name, email, created_at
FROM users
WHERE id = $1;

-- name: ListUsers :many
SELECT id, name, email, created_at
FROM users
WHERE active = true
ORDER BY created_at DESC
LIMIT $1 OFFSET $2;

-- name: CreateUser :one
INSERT INTO users (name, email)
VALUES ($1, $2)
RETURNING id, name, email, created_at;
```

```yaml
# sqlc.yaml
version: "2"
sql:
  - engine: "postgresql"
    queries: "queries/"
    schema: "migrations/"
    gen:
      go:
        package: "db"
        out: "internal/db"
        sql_package: "pgx/v5"
        emit_json_tags: true
```

```go
// Generated code — type-safe, no ORM overhead
queries := db.New(pool)
user, err := queries.GetUser(ctx, userID)
if err != nil {
    return fmt.Errorf("get user %s: %w", userID, err)
}
```

### Explicit Column Lists

```go
// BAD — SELECT * couples to schema, breaks on column changes
rows, err := db.QueryContext(ctx, "SELECT * FROM users")

// GOOD — explicit columns, survives schema evolution
rows, err := db.QueryContext(ctx, "SELECT id, name, email FROM users")
```

---

## Level 3: Migrations

### golang-migrate Pattern

```go
// Embed migrations in binary
//go:embed migrations/*.sql
var migrationsFS embed.FS

func runMigrations(dbURL string) error {
    source, err := iofs.New(migrationsFS, "migrations")
    if err != nil {
        return fmt.Errorf("migration source: %w", err)
    }

    m, err := migrate.NewWithSourceInstance("iofs", source, dbURL)
    if err != nil {
        return fmt.Errorf("create migrator: %w", err)
    }

    if err := m.Up(); err != nil && err != migrate.ErrNoChange {
        return fmt.Errorf("migrate up: %w", err)
    }
    return nil
}
```

### Migration Rules

| Rule | Why |
|------|-----|
| Always write up AND down | Rollback capability |
| Make migrations idempotent | `IF EXISTS`, `IF NOT EXISTS` |
| One logical change per migration | Easier to debug and rollback |
| Never modify applied migrations | Create new ones instead |
| Test down migrations before production | Don't assume they work |
| Don't run migrations on app startup in prod | Separate deployment step |
| Embed in binary with `go:embed` | Simpler deploys |

### Migration Naming

```
migrations/
├── 000001_create_users.up.sql
├── 000001_create_users.down.sql
├── 000002_add_user_email_index.up.sql
├── 000002_add_user_email_index.down.sql
```

---

## Performance: Make It Fast

### Connection Pool Tuning

| Setting | Starting Point | Tune Based On |
|---------|---------------|---------------|
| `MaxOpenConns` | (CPU cores * 2) + 1 | Connection wait time in metrics |
| `MaxIdleConns` | MaxOpenConns / 2 | Idle connection count vs new conn rate |
| `ConnMaxLifetime` | 5 min | Load balancer rotation frequency |
| `ConnMaxIdleTime` | 1 min | Traffic pattern (bursty vs steady) |

### Prepared Statements

```go
// Prepared statements: security (SQL injection) + performance (plan reuse)
stmt, err := db.PrepareContext(ctx, "SELECT id, name FROM users WHERE email = $1")
if err != nil { return err }
defer stmt.Close()

// Reuse for multiple queries
for _, email := range emails {
    var u User
    if err := stmt.QueryRowContext(ctx, email).Scan(&u.ID, &u.Name); err != nil {
        // handle
    }
}
```

### Batch Operations

```go
// pgx CopyFrom for bulk inserts (orders of magnitude faster than INSERT loops)
rows := [][]any{}
for _, u := range users {
    rows = append(rows, []any{u.Name, u.Email})
}
_, err := pool.CopyFrom(ctx,
    pgx.Identifier{"users"},
    []string{"name", "email"},
    pgx.CopyFromRows(rows),
)
```

---

## Observability: Know It's Working

### Pool Statistics

```go
// Expose pool stats as metrics
go func() {
    ticker := time.NewTicker(15 * time.Second)
    defer ticker.Stop()
    for range ticker.C {
        stats := db.Stats()
        slog.Info("db pool stats",
            slog.Int("open", stats.OpenConnections),
            slog.Int("in_use", stats.InUse),
            slog.Int("idle", stats.Idle),
            slog.Int64("wait_count", stats.WaitCount),
            slog.Duration("wait_duration", stats.WaitDuration),
        )
    }
}()
```

**Alert on:** `WaitCount` increasing rapidly (pool exhaustion), `WaitDuration` > 100ms (connection starvation).

### Query Timing

```go
func queryWithTiming(ctx context.Context, db *sql.DB, query string, args ...any) (*sql.Rows, error) {
    start := time.Now()
    rows, err := db.QueryContext(ctx, query, args...)
    duration := time.Since(start)

    slog.Info("query",
        slog.String("query", query),
        slog.Duration("duration", duration),
        slog.Bool("error", err != nil),
    )

    if duration > 500*time.Millisecond {
        slog.Warn("slow query", slog.String("query", query), slog.Duration("duration", duration))
    }
    return rows, err
}
```

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Use Context on Every DB Call
**You will be tempted to:** Use `db.Query()` instead of `db.QueryContext()` because "it's just a quick query."
**Why that fails:** Without context, a database issue (network partition, lock contention) blocks the goroutine indefinitely. With context timeout, it fails cleanly after N seconds.
**The right way:** Every DB call uses the `Context` variant. Propagate the request context through.

### Rule 2: defer rows.Close() Immediately After Query
**You will be tempted to:** Process rows first and close at the end, or forget to close entirely.
**Why that fails:** If processing panics or returns early, the rows aren't closed. The database connection leaks. After enough leaks, the pool is exhausted and the app hangs.
**The right way:** `defer rows.Close()` on the line immediately after the error check.

### Rule 3: All Operations in a Transaction Use tx, Not db
**You will be tempted to:** Mix `db.ExecContext` and `tx.ExecContext` within a transaction block.
**Why that fails:** `db.ExecContext` runs outside the transaction on a different connection. The operations aren't atomic. Commits and rollbacks don't affect the db calls.
**The right way:** Once you call `BeginTx`, every operation until Commit/Rollback uses the `tx` object.

### Rule 4: Never SELECT *
**You will be tempted to:** Use `SELECT *` because "it's easier and gets everything."
**Why that fails:** Schema coupling. Adding a column to the table breaks Scan() calls. Removing a column breaks Scan() calls. You transfer data you don't need. The query plan can't use covering indexes.
**The right way:** Explicit column lists in every query. sqlc enforces this automatically.

### Rule 5: Never Run Migrations on App Startup in Production
**You will be tempted to:** Add `migrate.Up()` to `main()` for "convenience."
**Why that fails:** Multiple replicas race to run migrations simultaneously. One succeeds, others fail or corrupt state. Migration failures crash the app at startup, causing cascading restarts.
**The right way:** Migrations are a separate deployment step — run once before the app starts, via CI/CD or a dedicated migration job.
