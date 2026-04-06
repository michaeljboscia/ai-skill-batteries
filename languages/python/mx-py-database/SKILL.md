---
name: mx-py-database
description: Python database patterns — SQLAlchemy 2.0, psycopg3, connection pools, migrations, Alembic, raw SQL, async database access. Use when writing any database code in Python.
---

# Python Database Patterns — SQLAlchemy 2.0, psycopg3 & Alembic for AI Coding Agents

**This skill loads for ANY Python database work.** It defines the patterns for async database access, ORM usage, migrations, and raw SQL.

## When to also load
- `mx-py-core` — co-loads for ANY Python work (typing, error handling, module structure)
- `mx-py-async` — when using asyncio patterns beyond basic session usage
- `mx-py-web` — when wiring database sessions into FastAPI `Depends()`
- `mx-py-testing` — when writing test DB fixtures, factory_boy, or test transactions

---

## Level 1: Async Engine, Sessions & Queries (Beginner)

### Engine + Session Factory Setup

One engine, one session factory, per service. Sessions are short-lived and request-scoped.

```python
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker

DATABASE_URL = "postgresql+psycopg://user:pass@localhost:5432/app_db"

engine = create_async_engine(
    DATABASE_URL,
    echo=False,
    pool_size=20,
    max_overflow=10,
    pool_recycle=1800,
    pool_pre_ping=True,
)

async_session = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,   # MANDATORY for async — prevents MissingGreenlet
    autoflush=False,
)
```

**Why `expire_on_commit=False`:** After commit, SQLAlchemy normally expires object state and re-fetches on next attribute access. In async, attribute access cannot `await`, so this triggers `MissingGreenlet`. Setting `expire_on_commit=False` keeps attributes in memory. Refresh explicitly with `await session.refresh(obj)` when needed.

### Typed Model Declarations (Mapped + mapped_column)

```python
import uuid
from datetime import datetime
from typing import Optional
from sqlalchemy import ForeignKey, text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

class Base(DeclarativeBase):
    pass

class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    username: Mapped[str] = mapped_column(unique=True, index=True)
    email: Mapped[Optional[str]]
    created_at: Mapped[datetime] = mapped_column(server_default=text("now()"))

    posts: Mapped[list["Post"]] = relationship(
        back_populates="author", lazy="raise"  # Forces explicit eager loading
    )

class Post(Base):
    __tablename__ = "posts"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    title: Mapped[str]
    content: Mapped[Optional[str]]
    author_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"))

    author: Mapped["User"] = relationship(back_populates="posts", lazy="raise")
```

**Rules:** Use `Mapped[T]` + `mapped_column()` for all columns. Never use legacy `Column()`. Declare `lazy="raise"` on every relationship.

### select() + scalars() Query Style

The legacy `session.query()` API is deprecated. Separate statement construction from execution.

```python
from sqlalchemy import select

async def get_user_by_email(session: AsyncSession, email: str) -> User | None:
    stmt = select(User).where(User.email == email)
    result = await session.execute(stmt)
    return result.scalars().first()

async def list_active_users(session: AsyncSession) -> list[User]:
    stmt = (
        select(User)
        .where(User.username.like("admin%"))
        .order_by(User.created_at.desc())
    )
    result = await session.execute(stmt)
    return list(result.scalars().all())
```

### Session as Context Manager

Always use `async with` to prevent connection leaks:

```python
async def create_user(username: str, email: str) -> User:
    async with async_session() as session:
        async with session.begin():
            user = User(username=username, email=email)
            session.add(user)
        return user  # Safe to access — expire_on_commit=False
```

---

## Level 2: N+1 Prevention, Pooling & Transactions (Intermediate)

### N+1 Prevention: lazy="raise" + Explicit Loading

In async, accessing an unloaded relationship triggers `MissingGreenlet` (fatal). The `lazy="raise"` guardrail makes this fail-fast at development time instead of silently degrading.

#### Eager Loading Decision Table

| Strategy | Use for | Mechanism | When to pick |
|---|---|---|---|
| `selectinload` | One-to-Many, Many-to-Many | Second `SELECT ... WHERE id IN (...)` | **Default for collections** — avoids Cartesian explosion |
| `joinedload` | Many-to-One, One-to-One | `LEFT OUTER JOIN` in primary query | **Default for scalars** — single round-trip |
| `subqueryload` | One-to-Many with OFFSET/LIMIT | Secondary subquery mirroring original | Paginated parent queries with large child sets |
| `lazy="raise"` | All relationships | Raises exception on access | **Set globally** — forces explicit loading everywhere |
| `lazy="select"` | NEVER in async | Implicit synchronous SQL | Causes `MissingGreenlet` — forbidden |

```python
from sqlalchemy.orm import selectinload, joinedload

async def get_users_with_posts(session: AsyncSession) -> list[User]:
    stmt = (
        select(User)
        .options(
            selectinload(User.posts),         # Collection: use selectinload
            joinedload(User.profile),         # Scalar: use joinedload
        )
        .limit(100)
    )
    result = await session.execute(stmt)
    return list(result.scalars().all())

# Chained loading for nested relationships
stmt = (
    select(User)
    .options(
        selectinload(User.posts).joinedload(Post.tags)
    )
)
```

### Connection Pooling

#### Direct Connection (SQLAlchemy manages pool)

```python
engine = create_async_engine(
    DATABASE_URL,
    pool_size=20,          # Baseline persistent connections per worker
    max_overflow=10,       # Burst connections above pool_size
    pool_recycle=1800,     # Recycle after 30min (prevents firewall timeouts)
    pool_pre_ping=True,    # SELECT 1 before borrowing — mandatory for cloud
)
```

#### Behind PgBouncer (NullPool to prevent double-pooling)

```python
from sqlalchemy.pool import NullPool

engine = create_async_engine(
    "postgresql+psycopg://user:pass@pgbouncer:6432/app_db",
    poolclass=NullPool,    # PgBouncer handles pooling — SQLAlchemy must not
)
```

**Double-pooling is catastrophic.** If SQLAlchemy maintains its own pool behind PgBouncer (transaction mode), you get state leakage, prepared statement failures, and deadlocks. Always `NullPool` behind PgBouncer.

### Transaction Patterns

#### Context manager transactions (primary pattern)

```python
async def transfer_funds(
    session: AsyncSession, from_id: int, to_id: int, amount: float
) -> None:
    async with session.begin():
        await session.execute(
            update(Account).where(Account.id == from_id)
            .values(balance=Account.balance - amount)
        )
        await session.execute(
            update(Account).where(Account.id == to_id)
            .values(balance=Account.balance + amount)
        )
    # Commit on success, rollback on exception — automatic
```

#### Savepoints for partial failure tolerance

```python
async def process_batch(session: AsyncSession, records: list[dict]) -> None:
    async with session.begin():
        for record in records:
            try:
                async with session.begin_nested():  # SAVEPOINT
                    session.add(MyModel(**record))
            except IntegrityError:
                # Savepoint rolled back; outer transaction continues
                log.warning(f"Skipped duplicate: {record}")
```

---

## Level 3: Alembic, psycopg3 Direct & Bulk Operations (Advanced)

### Alembic Migrations

#### Autogenerate workflow

```bash
alembic revision --autogenerate -m "add_verified_column_to_users"
```

**Always review autogenerated migrations.** Autogenerate misses: renames, custom types, check constraints, partial indexes. Every generated script must be manually audited.

#### Data migrations: use `op`, never ORM models

ORM models evolve. Migrations are immutable snapshots. Importing a current model into an old migration breaks when columns change.

```python
from alembic import op
import sqlalchemy as sa

def upgrade():
    op.add_column("users", sa.Column("is_verified", sa.Boolean(), server_default="false"))
    # Data migration with raw SQL — never import User model here
    op.execute("""
        UPDATE users SET is_verified = true
        WHERE email LIKE '%@trusted-domain.com'
    """)

def downgrade():
    op.drop_column("users", "is_verified")
```

#### Multi-head merge

When two branches create migrations from the same base:

```bash
alembic heads                                    # Identify divergence
alembic merge heads -m "merge_user_and_payment"  # Create merge revision
```

Never manually edit `down_revision`. Never edit applied migrations. Fix forward with a new revision.

#### CI stairway test

```python
def test_migrations_stairway(alembic_config):
    """Upgrade/downgrade every revision to prove reversibility."""
    for rev in get_all_revisions(alembic_config):
        alembic.command.upgrade(alembic_config, rev.revision)
        alembic.command.downgrade(alembic_config, rev.down_revision)
        alembic.command.upgrade(alembic_config, rev.revision)
```

### psycopg3 Direct Access

For hot paths where ORM overhead is unacceptable, drop to the raw driver.

#### COPY protocol (10-50x faster than batched INSERT)

```python
async def bulk_ingest_copy(session: AsyncSession, rows: list[tuple]) -> None:
    """Use PostgreSQL COPY for millions of rows."""
    conn = await session.connection()
    raw_conn = await conn.get_raw_connection()

    async with raw_conn.cursor() as cur:
        async with cur.copy(
            "COPY sensor_data (ts, device_id, value) FROM STDIN"
        ) as copy:
            for row in rows:
                await copy.write_row(row)
```

#### Prepared statements

psycopg3 auto-prepares queries after `prepare_threshold` (default 5) executions. Cuts SQL parsing overhead on repeated queries.

```python
# Disable auto-prepare when behind PgBouncer < 1.22
engine = create_async_engine(
    DATABASE_URL,
    connect_args={"prepare_threshold": None},  # PgBouncer compat
)
```

#### AsyncConnectionPool (bypass SQLAlchemy for raw pipelines)

```python
from psycopg_pool import AsyncConnectionPool

pool = AsyncConnectionPool(
    "postgresql://user:pass@localhost:5432/app_db",
    min_size=5,
    max_size=20,
    open=False,
)
await pool.open()

async with pool.connection() as conn:
    async with conn.cursor() as cur:
        await cur.execute("SELECT count(*) FROM events WHERE ts > %s", (cutoff,))
        count = (await cur.fetchone())[0]

await pool.close()
```

### Bulk Operations (ORM layer)

#### Bulk insert with Core DML

```python
from sqlalchemy import insert

async def bulk_create_users(session: AsyncSession, data: list[dict]) -> None:
    stmt = insert(User)
    await session.execute(stmt, data)  # Optimized executemany via psycopg3
```

#### Upsert with ON CONFLICT

```python
from sqlalchemy.dialects.postgresql import insert as pg_insert

async def upsert_user(session: AsyncSession, user_data: dict) -> User:
    stmt = pg_insert(User).values(**user_data)
    upsert = stmt.on_conflict_do_update(
        index_elements=["email"],
        set_={
            "username": stmt.excluded.username,
            "updated_at": text("now()"),
        },
    ).returning(User)
    result = await session.execute(upsert)
    return result.scalar_one()
```

---

## Performance: Make It Fast

- **NullPool behind PgBouncer** — eliminates double-pooling deadlocks
- **COPY protocol** for bulk ingestion (10-50x faster than batched INSERT)
- **`selectinload`** over lazy loading — predictable query count, no N+1
- **Core `insert()` with list of dicts** — bypasses ORM object instantiation overhead for bulk writes
- **`pool_recycle=1800`** — prevents stale connections from firewall/DB timeouts
- **Prepared statements** — psycopg3 auto-prepares hot queries, cutting parse overhead
- **`slots=True`** on ORM-adjacent dataclasses for high-volume result transformation

See `mx-py-perf` for profiling workflows and full optimization decision table.

---

## Observability: Know It's Working

- **`pool_pre_ping=True`** — dead connections recycled silently before use (mandatory for cloud)
- **Slow query detection** — enable `echo=True` in development, or hook `before_cursor_execute` event for production query logging with timing
- **Alembic CI stairway test** — proves every migration is reversible; catches broken downgrades before production
- **`lazy="raise"`** — turns silent N+1 degradation into immediate, debuggable exceptions
- **Connection pool monitoring** — `engine.pool.status()` exposes checked-out/overflow counts; alert on saturation

See `mx-py-observability` for structlog, OTel, and Sentry integration patterns.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No 1.x Query Syntax
**You will be tempted to:** Write `session.query(User).filter(...)` because it looks simpler or because training data is full of it.
**Why that fails:** The 1.x API is synchronous-only, poorly typed, and incompatible with `AsyncSession`. It will not raise errors immediately — it will fail at runtime in async contexts with cryptic backtraces.
**The right way:** `select(User).where(...)` + `await session.execute(stmt)` + `result.scalars()`. Every time.

### Rule 2: No Sharing AsyncSession Across Tasks
**You will be tempted to:** Pass a single session to multiple concurrent coroutines because "it's just a database handle."
**Why that fails:** `AsyncSession` is NOT concurrency-safe. Concurrent access corrupts the Identity Map, causes deadlocks, and produces data loss. The session holds mutable internal state that assumes single-threaded access.
**The right way:** One session per request/task. Use FastAPI `Depends()` or create a fresh session from the factory in each `asyncio.Task`.

### Rule 3: No f-string SQL
**You will be tempted to:** Write `f"SELECT * FROM users WHERE id = '{user_id}'"` because parameterized queries feel verbose.
**Why that fails:** SQL injection. Also defeats PostgreSQL's prepared statement caching and plan reuse. This is not a style preference — it is a security vulnerability.
**The right way:** `text("SELECT * FROM users WHERE id = :id")` with `{"id": user_id}`, or use the ORM query builder.

### Rule 4: No Implicit Lazy Loading in Async
**You will be tempted to:** Skip `lazy="raise"` because "I'll just remember to use eager loading."
**Why that fails:** You will forget. A teammate will forget. The app will crash with `MissingGreenlet` in production when an unloaded relationship is accessed outside a session context. Silent N+1 queries will saturate your connection pool under load.
**The right way:** Set `lazy="raise"` on every relationship at the model level. Use `selectinload`/`joinedload` explicitly in every query that needs related data.

### Rule 5: No Editing Applied Migrations
**You will be tempted to:** Fix a typo or bug in an already-applied Alembic migration instead of creating a new one.
**Why that fails:** Rewriting an applied migration corrupts the DAG for every other developer and environment. `alembic upgrade head` will silently skip the "already applied" revision, leaving the fix unapplied. In teams, this causes irreversible schema drift.
**The right way:** Create a new migration that corrects the issue. Use `alembic merge heads` for branch conflicts. Never touch `down_revision` on applied scripts.
