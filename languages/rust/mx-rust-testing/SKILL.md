---
name: mx-rust-testing
description: Use when writing tests for Rust code. Covers tokio::test patterns, property testing with proptest, integration testing with testcontainers, Miri for unsafe verification, criterion benchmarking, rstest fixtures and parameterized tests, and insta snapshot testing. Also use when the user mentions 'test', 'tokio::test', 'proptest', 'property test', 'testcontainers', 'Docker test', 'miri', 'unsafe test', 'criterion', 'benchmark', 'rstest', 'fixture', 'parameterized', 'insta', 'snapshot', or 'approval test'.
---

# Rust Testing — Comprehensive Testing Patterns for AI Coding Agents

**Loads when writing any tests.** Covers the full testing spectrum: unit, integration, property, snapshot, benchmark, and unsafe verification.

## When to also load
- Async patterns → `mx-rust-async`
- Core rules (behavior over structure) → `mx-rust-core`

---

## Testing Tool Decision Tree

| Scenario | Tool | Why |
|----------|------|-----|
| Async logic with timeouts/delays | `tokio::test(start_paused = true)` | Deterministic time, no real sleeps |
| Checking Future poll states | `tokio-test` macros | `assert_ready!`, `assert_pending!` |
| Generating extensive input permutations | `proptest` + `test-strategy` | Auto-shrinking to minimal failing case |
| State machine transitions | proptest Action Strategy | Random operation sequences |
| Real database integration | `testcontainers` | Ephemeral Docker containers |
| Unsafe memory verification | `cargo +nightly miri test` | Detects UB, aliasing violations |
| Performance regression detection | `criterion` | Statistical analysis + baselines |
| Parameterized test cases | `rstest` | `#[fixture]` + `#[case]` + matrix |
| Large output validation | `insta` | Snapshot testing with interactive review |

---

## Level 1: Async Testing (Beginner)

### tokio::test Configuration

```rust
// Default: single-threaded (fastest, good for most tests)
#[tokio::test]
async fn test_basic() { assert!(true); }

// Multi-threaded: for testing concurrent work-stealing
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn test_concurrent() { /* ... */ }

// Paused time: instant deterministic time travel
#[tokio::test(start_paused = true)]
async fn test_timeout() {
    let start = tokio::time::Instant::now();
    tokio::time::sleep(Duration::from_secs(3600)).await; // Instant!
    assert!(start.elapsed() >= Duration::from_secs(3600));
}
```

`start_paused` requires `current_thread` runtime and `test-util` feature.

### rstest Fixtures and Parameterized Tests

```rust
use rstest::{fixture, rstest};

#[fixture]
fn db_pool() -> TestPool { TestPool::new() }

#[rstest]
#[case("alice", true)]
#[case("bob", true)]
#[case("", false)]  // Empty name should fail
fn test_create_user(db_pool: TestPool, #[case] name: &str, #[case] expected: bool) {
    let result = db_pool.create_user(name);
    assert_eq!(result.is_ok(), expected);
}

// Matrix test: all combinations of role x active status
#[rstest]
async fn test_auth(
    #[values("admin", "user", "guest")] role: &str,
    #[values(true, false)] active: bool,
) {
    let result = check_auth(role, active).await;
    assert!(result.is_finished());
}
```

---

## Level 2: Property & Integration (Intermediate)

### proptest for Invariant Testing

```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn test_roundtrip_serialization(input in "\\PC{1,100}") {
        // Property: serialize then deserialize = original
        let serialized = serde_json::to_string(&input).unwrap();
        let deserialized: String = serde_json::from_str(&serialized).unwrap();
        assert_eq!(input, deserialized);
    }
}
```

For async proptest, use `test-strategy`:
```rust
#[proptest(async = "tokio")]
async fn test_async_property(#[strategy(1..100u32)] n: u32) {
    let result = async_process(n).await;
    assert!(result > 0);
}
```

### testcontainers for Real Database Tests

```rust
use testcontainers::{runners::AsyncRunner, GenericImage};

#[tokio::test]
async fn test_with_postgres() {
    let container = GenericImage::new("postgres", "16")
        .with_env_var("POSTGRES_PASSWORD", "test")
        .start().await.unwrap();
    
    let port = container.get_host_port_ipv4(5432).await.unwrap();
    let pool = connect_db(&format!("postgres://postgres:test@localhost:{}/postgres", port)).await;
    
    sqlx::migrate!().run(&pool).await.unwrap();
    
    // Test against real Postgres — no mocks!
    let count: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM users")
        .fetch_one(&pool).await.unwrap();
    assert_eq!(count.0, 0);
}
// Container auto-removed on drop
```

**Transactional teardown** (faster than restarting container):
```rust
let tx = pool.begin().await?;
// ... test operations on tx ...
tx.rollback().await?;  // Clean slate, no container restart
```

---

## Level 3: Benchmarks, Miri & Snapshots (Advanced)

### criterion for Performance Regression

```rust
use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn bench_parser(c: &mut Criterion) {
    let rt = tokio::runtime::Runtime::new().unwrap();
    
    c.bench_function("parse_json_payload", |b| {
        b.to_async(&rt).iter(|| async {
            parse_payload(black_box(SAMPLE_DATA)).await
        })
    });
}

criterion_group!(benches, bench_parser);
criterion_main!(benches);
```

Regression detection: `cargo bench --save-baseline main` then `cargo bench --baseline main`.

**`black_box` prevents LLVM from optimizing away the benchmark target.**

### Miri for Unsafe Code

```bash
rustup component add miri --toolchain nightly
cargo +nightly miri test
```

Miri detects: OOB access, use-after-free, data races, invalid enum discriminants, Stacked/Tree Borrows violations, memory leaks.

**Limitations:** Cannot execute FFI/C code. Only tests executed paths. Significantly slower than native. Use `#[cfg(not(miri))]` to skip FFI-dependent tests.

### insta Snapshot Testing

```rust
use insta::assert_json_snapshot;

#[test]
fn test_api_response() {
    let response = generate_report();
    assert_json_snapshot!(response);
    // First run: creates .snap file
    // Subsequent runs: compares against snapshot
    // Review changes: cargo insta review
}

// Inline snapshot (stored in source file)
use insta::assert_snapshot;
#[test]
fn test_error_format() {
    assert_snapshot!(format_error(404), @"Not Found: resource does not exist");
}
```

**Redact volatile fields** (timestamps, UUIDs):
```rust
insta::with_settings!({redactions => {
    "[].id" => "[REDACTED]",
    "[].created_at" => "[TIMESTAMP]",
}}, {
    assert_json_snapshot!(response);
});
```

**Don't over-rely on snapshots.** They test "what the output was" not "what it should be." Use semantic assertions for core logic.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Tests Must Test Behavior, Not Structure
**You will be tempted to:** Assert exact JSON field counts or struct layouts.
**The right way:** Test observable properties: "input X produces output satisfying property Y."

### Rule 2: No Mocking Databases in Integration Tests
**You will be tempted to:** Mock the DB layer because "testcontainers is slow."
**The right way:** Testcontainers with session-scoped shared containers + transactional rollback.

### Rule 3: No Real-Time Sleeps in Async Tests
**You will be tempted to:** `tokio::time::sleep(Duration::from_secs(5)).await` to wait for something.
**The right way:** `start_paused = true` for deterministic time. Or await the actual event.

### Rule 4: No Blindly Accepting Snapshot Changes
**You will be tempted to:** `cargo insta test --accept` to pass CI quickly.
**The right way:** `cargo insta review` — inspect every diff. Regressions hide in accepted snapshots.
