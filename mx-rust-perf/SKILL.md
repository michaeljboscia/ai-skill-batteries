---
name: mx-rust-perf
description: Use when writing any Rust code. Co-loads with mx-rust-core by default. Rust performance optimization — profiling, benchmarking, zero-copy patterns, allocation reduction, async runtime tuning, SIMD JSON, SQLite WAL tuning, build speed (sccache mold Cranelift), binary size analysis. Also use when the user mentions 'performance', 'slow', 'optimize', 'profile', 'criterion', 'benchmark', 'allocation', 'flamegraph', or any Rust performance work.
---

# Rust Performance — Making It Fast for AI Coding Agents

**This skill co-loads with mx-rust-core for ANY Rust work.** It prevents: guessing instead of profiling, unnecessary allocations, naive async patterns, ignoring build speed, and shipping code nobody benchmarked.

## When to also load
- `mx-rust-core` — ownership patterns affect performance (Arc vs references)
- `mx-rust-async` — tokio runtime tuning, channel throughput
- `mx-rust-project` — build speed, Docker optimization
- `mx-rust-data` — serde/SQLite performance specifics

---

## Level 1: Allocation & Dispatch (Beginner)

### Prefer Static Dispatch Over Dynamic Dispatch

| Approach | Cost | When |
|----------|------|------|
| Generics `fn foo<T: Trait>(t: T)` | Zero-cost, monomorphized | Default choice |
| `dyn Trait` | Vtable indirection, ~10-20% slower | Heterogeneous collections, plugin APIs |
| `enum` dispatch | Match branch, no heap | Fixed set of variants |

**BAD:** `fn process(items: &[Box<dyn Handler>])` for 3 known handler types.
**GOOD:** `enum Handler { A(TypeA), B(TypeB), C(TypeC) }` — compiler optimizes the match away.

### Avoid Allocation in Hot Paths

| Pattern | Why |
|---------|-----|
| `Vec::with_capacity(n)` | Avoids realloc when size is known |
| `&str` over `String` | Zero allocation for read-only data |
| `Cow<'_, str>` | Borrows usually, allocates only when mutation needed |
| `SmallVec<[T; N]>` | Stack-allocated for small collections, heap fallback |
| `ArrayString` / `ArrayVec` | Fixed-size, zero heap |

### Iterator Chains Over Manual Loops

Iterators often compile to identical assembly via LLVM. They enable `.collect::<Vec<_>>()` with pre-allocated capacity and allow lazy evaluation.

**BAD:**
```rust
let mut results = Vec::new();
for item in items { if item.valid() { results.push(item.transform()); } }
```
**GOOD:**
```rust
let results: Vec<_> = items.iter().filter(|i| i.valid()).map(|i| i.transform()).collect();
```

---

## Level 2: Zero-Copy & Async Tuning (Intermediate)

### Zero-Copy Deserialization with Serde

```rust
#[derive(Deserialize)]
struct Message<'a> {
    #[serde(borrow)]
    name: Cow<'a, str>,  // Borrows from input — no allocation
    id: u64,
}
let msg: Message = serde_json::from_slice(&bytes)?;  // from_slice, NOT from_str
```

For max throughput: `simd-json` (2-5x faster on x86_64 with `target-cpu=native`). Only switch if profiling shows JSON as bottleneck. `sonic-rs` even faster in some benchmarks.

### Zero-Copy Network I/O with `bytes`

| Type | Use |
|------|-----|
| `BytesMut` | Mutable buffer for building frames |
| `Bytes` (via `.freeze()`) | Immutable, ref-counted — clone = atomic increment |
| `Arc<[u8]>` | Zero-copy fan-out to multiple consumers |
| `Cow<'a, [u8]>` | Borrow when possible, clone on write |

### Async Runtime Tuning

```rust
tokio::runtime::Builder::new_multi_thread()
    .worker_threads(num_cpus::get())      // Tune per workload
    .max_blocking_threads(512)            // For spawn_blocking pool
    .max_io_events_per_tick(1024)         // More events per poll cycle
    .build()
```

**Task spawn overhead:** ~64 bytes + bookkeeping. Don't spawn micro-tasks — fewer tasks doing more work beats many tiny tasks.

**Channel throughput:**
- Bounded `mpsc::channel(512)` — start here, tune up
- `try_send` avoids context switch when capacity available
- Batch messages: pack 16-64 items per send
- `JoinSet` > `FuturesUnordered<JoinHandle>` — less overhead, auto-abort on drop

### SQLite WAL Performance

```sql
PRAGMA journal_mode = WAL;        -- Concurrent readers during writes
PRAGMA synchronous = NORMAL;      -- Safe in WAL, eliminates most fsync
PRAGMA temp_store = memory;       -- Temp tables in RAM
PRAGMA mmap_size = 268435456;     -- 256MB memory-mapped I/O
```
Batch writes in single transaction. 1000 INSERTs in one TX = one fsync. Individual INSERTs = 1000 fsyncs.

---

## Level 3: Build Speed & Binary Size (Advanced)

### Build Speed Stack

| Tool | Impact | Setup |
|------|--------|-------|
| `mold` linker | 7x faster linking (Linux) | `rustflags = ["-C", "link-arg=-fuse-ld=mold"]` |
| `sccache` | Cache compilation across builds | `RUSTC_WRAPPER=sccache` |
| Cranelift backend | 20-30% faster debug builds | Nightly: `rustup component add rustc-codegen-cranelift-preview` |
| `codegen-units = 4` | Faster parallel codegen (debug) | `[profile.dev]` in Cargo.toml |
| `cargo-nextest` | 60% faster test execution | `cargo install cargo-nextest` |

### Release Binary Optimization

```toml
[profile.release]
opt-level = 3         # Max speed (use "z" for min size)
lto = "fat"           # Whole-program optimization
codegen-units = 1     # Better cross-crate optimization
strip = "symbols"     # Remove symbol tables
panic = "abort"       # No unwinding overhead
```

### Docker Layer Caching

```dockerfile
COPY Cargo.toml Cargo.lock ./
RUN cargo chef cook --release --recipe-path recipe.json  # Cache deps
COPY src/ src/
RUN cargo build --release  # Only this layer rebuilds on code change
```
BuildKit cache mounts for `~/.cargo/registry` and `target/`. Multi-stage: build in `rust:latest`, deploy from `scratch`.

### Binary Size Analysis

`cargo-bloat` identifies which crates/functions bloat the binary. Track in CI across PRs. Combine with `cargo build --timings` HTML report to find slow-compiling crates.

---

## Level 4: Profiling & Benchmarking (Expert)

### Benchmarking with criterion

```rust
use criterion::{criterion_group, criterion_main, Criterion};

fn bench_parser(c: &mut Criterion) {
    let input = include_str!("../testdata/large.json");
    c.bench_function("parse_json", |b| b.iter(|| parse(input)));
}
criterion_group!(benches, bench_parser);
criterion_main!(benches);
```

Tune `noise_threshold` (default 0.01 = 1%) to filter insignificant fluctuations. `black_box()` prevents LLVM from optimizing away benchmark targets.

### Systems-Level Profiling

| Tool | What |
|------|------|
| `cargo flamegraph` | CPU time visualization |
| `tokio-console` | Async task inspection (dev only, requires `tokio_unstable`) |
| `tokio-metrics` | Production runtime metrics (workers, queue depth, poll duration) |
| `DHAT` / `heaptrack` | Heap allocation profiling |
| `perf` / `samply` | Linux sampling profiler |

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Premature Optimization Without Profiling
**You will be tempted to:** Rewrite code to be "faster" based on intuition.
**Why that fails:** Gut feelings about performance are wrong 80% of the time. You optimize the wrong thing.
**The right way:** Profile first (flamegraph, criterion), identify the actual bottleneck, optimize that, benchmark again.

### Rule 2: No unbounded_channel for "Simplicity"
**You will be tempted to:** Use `unbounded_channel()` because bounded requires choosing a capacity.
**Why that fails:** Fast producer + slow consumer = OOM in minutes.
**The right way:** `mpsc::channel(512)` with backpressure. Tune capacity from profiling.

### Rule 3: No General Pool for SQLite Writes
**You will be tempted to:** Use a connection pool for all SQLite operations.
**Why that fails:** Multiple writers contend for SQLite's exclusive write lock → `SQLITE_BUSY` → starvation.
**The right way:** Single writer connection (queued via Mutex) + separate reader pool.

### Rule 4: No Skipping Build Speed Tools
**You will be tempted to:** Accept 5-minute debug builds as normal.
**Why that fails:** Slow builds kill iteration speed. Developer time > CPU time.
**The right way:** mold + sccache + Cranelift for debug builds. Always.
