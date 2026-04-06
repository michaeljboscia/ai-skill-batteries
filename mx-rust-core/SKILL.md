---
name: mx-rust-core
description: Use when writing any Rust code. Covers ownership, borrowing, lifetimes, error handling, traits, generics, module architecture, naming conventions, and tracing/observability. Also use when the user mentions 'borrow checker', 'lifetime', 'ownership', 'Result', 'Option', 'anyhow', 'thiserror', 'trait', 'impl', 'derive', 'enum', 'struct', 'module', 'pub', 'clippy', 'rustfmt', 'tracing', 'OpenTelemetry', or any .rs file operations.
---

# Rust Core — Language Fundamentals for AI Coding Agents

**This skill loads for ANY Rust work.** It contains the rules that prevent the most common AI failures: borrow checker fights, lifetime annotation soup, `.unwrap()` everywhere, and "Frankenstein Rust" that compiles but isn't idiomatic.

## When to also load
- Async/concurrent code → `mx-rust-async`
- Subprocess/PTY/signals → `mx-rust-systems`
- HTTP/WebSocket/SSE → `mx-rust-network`
- JSON/SQLite/serde/config → `mx-rust-data`
- NATS/Temporal/policy engines → `mx-rust-services`
- Testing → `mx-rust-testing`
- Cargo workspace/build/deploy → `mx-rust-project`

---

## Level 1: Patterns That Always Work (Beginner)

### Ownership Decision Tree

| Data Access Need | Pattern | Why |
|-----------------|---------|-----|
| Single owner, isolated scope | `T` (owned value) | Default. Zero-cost. |
| Read-only, single thread | `&T` (immutable borrow) | Zero-cost, multiple readers OK |
| Mutation, single thread | `&mut T` (mutable borrow) | Zero-cost, exclusive access |
| Shared read, multi-thread | `Arc<T>` | Atomic refcount, no lock |
| Shared mutation, multi-thread | `Arc<Mutex<T>>` | "Go-style" — works but has cost |
| Shared read-heavy, multi-thread | `Arc<RwLock<T>>` | Multiple readers, single writer |

### Rule: Clone-Heavy Is OK to Start

When fighting the borrow checker, it is acceptable to `.clone()` data to get code compiling. Then optimize later. `Arc::clone()` is cheap (atomic increment, not data copy). For small data (`String`, `PathBuf`), regular `.clone()` is fine.

**You will be tempted to:** Add lifetime annotations everywhere to avoid cloning.
**Why that fails:** AI-generated lifetime annotations are wrong 60%+ of the time. Wrong lifetimes cause cascading errors that are harder to fix than the original problem.
**The right way:** Clone first. Profile later. Only add lifetimes when the profiler says cloning is a bottleneck.

### Rule: Never `.unwrap()` in Production

```rust
// BAD — panics at runtime
let value = some_option.unwrap();

// GOOD — propagate with ?
let value = some_option.ok_or_else(|| anyhow!("expected value"))?;

// GOOD — pattern match
let value = match some_option {
    Some(v) => v,
    None => return Err(AppError::NotFound("value missing".into())),
};
```

`.unwrap()` is allowed ONLY in:
- Tests (`#[test]` functions)
- Examples/documentation
- After a check that guarantees `Some`/`Ok` (with a comment explaining why)

### Rule: Error Handling Split

| Context | Crate | Pattern |
|---------|-------|---------|
| Libraries / reusable modules | `thiserror` | `#[derive(Error)] pub enum DomainError { ... }` |
| Application / `main.rs` | `anyhow` | `fn main() -> anyhow::Result<()>` |
| Web API handlers | Both | `thiserror` for domain, `anyhow` at boundaries |

```rust
// Library module — callers can match on variants
#[derive(thiserror::Error, Debug)]
pub enum AgentError {
    #[error("agent {0} not found")]
    NotFound(String),
    #[error("agent {0} timed out after {1:?}")]
    Timeout(String, std::time::Duration),
    #[error(transparent)]
    Io(#[from] std::io::Error),
}

// Application boundary — collect and propagate
use anyhow::Context;
fn start_agent(name: &str) -> anyhow::Result<()> {
    let config = load_config(name)
        .context("failed to load agent config")?;  // adds context
    Ok(())
}
```

**NEVER use `anyhow` in a public library API.** Callers cannot match on opaque errors.

---

## Level 2: Architecture Patterns (Intermediate)

### Module Architecture: The Type Firewall

Modules communicate through explicit boundary types. Internal types NEVER cross boundaries.

```rust
// PRIVATE to infrastructure layer
struct DbUserRow { id: i32, username: String, created_at: String }

// PUBLIC domain type — no lifetimes, owns its data
pub struct User { pub id: i32, pub username: String }

// Translation at the boundary
impl From<DbUserRow> for User {
    fn from(row: DbUserRow) -> Self {
        User { id: row.id, username: row.username }
    }
}
```

**You will be tempted to:** Make `DbUserRow` pub to save 10 lines of mapping code.
**Why that fails:** A database schema change now breaks the presentation layer. Coupling is viral.
**The right way:** Always map at boundaries. The 10 lines of `From` impl save 100 lines of cascading fixes later.

### Newtype Pattern for Type Safety

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct AgentId(pub u64);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct SessionId(pub u64);

// Compiler prevents mixing these up
pub fn kill_agent(id: AgentId) { /* ... */ }
```

### Trait Design for AI Success

**Prefer associated types over generic parameters:**

```rust
// BAD — AI struggles with inference
trait Storage<T> { fn save(&self, value: T); }

// GOOD — one implementation per type, clear inference
trait Storage {
    type Value;
    fn save(&self, value: Self::Value);
}
```

**Provide default implementations** to reduce what AI must write:

```rust
pub trait HealthCheck {
    fn check(&self) -> bool;
    
    // Default — AI only needs to implement check()
    fn check_with_timeout(&self, _timeout: std::time::Duration) -> bool {
        self.check()
    }
}
```

**NEVER use Higher-Ranked Trait Bounds (HRTBs)** like `for<'a> Trait<'a>`. Refactor to use owned data instead.

---

## Level 3: Advanced Patterns (Expert)

### The Contagious Borrow Problem

Borrowing a child field borrows the parent. This blocks mutation of sibling fields.

```rust
struct App { users: Vec<User>, logs: Vec<String> }

fn process(app: &mut App) {
    // BAD — borrows all of app
    // let user = &app.users[0];
    // app.logs.push(format!("processing {}", user.name)); // ERROR!
    
    // GOOD — destructure to get independent borrows
    let App { users, logs } = app;
    let user = &users[0];
    logs.push(format!("processing {}", user.name)); // OK!
}
```

### Graph-Like Data: Use Handles, Not References

For data structures with cycles or shared ownership, use index/handle patterns instead of references:

```rust
type NodeId = usize;

struct Graph {
    nodes: Vec<Node>,
}

struct Node {
    data: String,
    edges: Vec<NodeId>,  // Indices, not references
}
```

This avoids lifetime hell and works naturally with `serde` serialization.

### Tracing & Observability (Cross-Cutting)

Every Rust project uses the `tracing` crate. Key patterns:

```rust
use tracing::{info, error, instrument};

#[instrument(skip(db_pool))]  // Auto-creates span, skips sensitive args
async fn create_user(name: &str, db_pool: &Pool) -> Result<User> {
    info!(user_name = %name, "creating user");
    
    let user = db_pool.insert_user(name).await
        .map_err(|e| {
            error!(error = %e, "database insert failed");
            e
        })?;
    
    Ok(user)
}
```

Rules:
- Span names = class of operation (low cardinality): `"create_user"`, NOT `"create_user_alice"`
- High-cardinality data = span attributes: `user_name = %name`
- Use `#[instrument]` on public async functions
- Use structured fields (`key = %value`), not string concatenation
- Initialize tracing FIRST in `main()`, before any business logic

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Arc<Mutex<T>> to Fix Borrow Errors

**You will be tempted to:** Wrap data in `Arc<Mutex<T>>` to resolve E0502 (cannot borrow as mutable) or E0597 (does not live long enough).
**Why that fails:** This suppresses the architectural flaw. In hot loops, atomic operations and mutex contention consume up to 78% of CPU time.
**The right way:** Refactor data flow to use message passing (channels) or reduce borrow scope. Only use `Arc<Mutex<T>>` for genuinely shared mutable state (connection pools, config).

### Rule 2: No `'static` Lifetime to Fix tokio::spawn

**You will be tempted to:** Add `'static` to function parameters when `tokio::spawn` complains about lifetimes.
**Why that fails:** Forces callers to provide data that lives forever. Makes the function uncallable with runtime data.
**The right way:** Use `async move` closures and clone/Arc data before spawning. See `mx-rust-async` for exact patterns.

### Rule 3: No Generic Sprawl

**You will be tempted to:** Add 3+ generic type parameters to a trait: `trait Processor<Input, Output, Error>`.
**Why that fails:** Every function touching this trait must declare all 3 bounds. Viral generics pollute the entire codebase.
**The right way:** Use associated types: `trait Processor { type Input; type Output; type Error; }`.

### Rule 4: No Exposed Infrastructure Types

**You will be tempted to:** Make database row structs `pub` and pass them across module boundaries.
**Why that fails:** Couples infrastructure to domain. Schema changes cascade everywhere.
**The right way:** Map at boundaries with `From`/`Into` impls.

### Rule 5: Tests Must Test Behavior, Not Structure

**You will be tempted to:** Write tests that verify the exact JSON shape or struct field count.
**Why that fails:** Any refactor breaks tests even when behavior is unchanged.
**The right way:** Test observable behavior: "given input X, the output satisfies property Y." See `mx-rust-testing`.
