---
name: mx-rust-async
description: Use when writing async Rust code with tokio. Covers tokio::spawn, select!, channels (mpsc/oneshot/broadcast/watch), JoinSet, CancellationToken, backpressure, Mutex selection, and concurrent task management. Also use when the user mentions 'tokio', 'async', 'await', 'Future', 'spawn', 'select', 'channel', 'mpsc', 'broadcast', 'JoinSet', 'CancellationToken', 'backpressure', 'concurrent', 'parallel', or 'runtime'.
---

# Rust Async & Concurrency — Tokio Patterns for AI Coding Agents

**Loads when writing any concurrent or async Rust code.** The #1 source of AI failures in async Rust: lifetime issues with `tokio::spawn`, blocking the runtime, deadlocks from wrong Mutex, and unbounded channels causing OOM.

## When to also load
- Language fundamentals → `mx-rust-core`
- Subprocess/PTY management → `mx-rust-systems`
- WebSocket/SSE streaming → `mx-rust-network`

---

## Level 1: Patterns That Always Work (Beginner)

### tokio::spawn and the 'static Bound

`tokio::spawn` requires the future to be `'static` — it cannot borrow data from the caller.

```rust
// BAD — borrows `name` which doesn't live long enough
async fn process(name: &str) {
    tokio::spawn(async {
        println!("{}", name); // ERROR: borrowed data
    });
}

// GOOD — move owned data into the task
async fn process(name: String) {
    let name_clone = name.clone();
    tokio::spawn(async move {
        println!("{}", name_clone);
    });
}

// GOOD — Arc for shared data across multiple tasks
use std::sync::Arc;
async fn process_many(data: Arc<Vec<String>>) {
    for i in 0..3 {
        let data = Arc::clone(&data);
        tokio::spawn(async move {
            println!("Task {}: {:?}", i, data[0]);
        });
    }
}
```

**NEVER add `'static` to a function parameter to fix this.** Always use `async move` + owned data or `Arc`.

### Channel Selection Decision Tree

| Need | Channel | Key Property |
|------|---------|-------------|
| N producers → 1 consumer, ordered queue | `mpsc::channel(cap)` | **Bounded = backpressure** |
| 1 value, single response | `oneshot::channel()` | Request/response pattern |
| N producers → N consumers, all see all msgs | `broadcast::channel(cap)` | Slow receivers get `Lagged` |
| N producers → N consumers, latest value only | `watch::channel(init)` | Config/status updates |

```rust
// MPSC — work queue with backpressure
let (tx, mut rx) = tokio::sync::mpsc::channel::<String>(1024);

// ONESHOT — request/response
let (reply_tx, reply_rx) = tokio::sync::oneshot::channel();
tx.send(Command::GetStatus { reply: reply_tx }).await?;
let status = reply_rx.await?;

// BROADCAST — fan-out to all subscribers
let (tx, _) = tokio::sync::broadcast::channel::<Event>(256);
let mut rx1 = tx.subscribe();
let mut rx2 = tx.subscribe();

// WATCH — only latest value matters
let (tx, rx) = tokio::sync::watch::channel(AppConfig::default());
```

### Mutex Decision: std vs tokio

| Situation | Use | Why |
|-----------|-----|-----|
| Lock held for quick sync ops (HashMap lookup, counter increment) | `std::sync::Mutex` | Faster, lower overhead |
| Lock held across `.await` points (I/O, DB query) | `tokio::sync::Mutex` | Yields to executor instead of blocking thread |

**Golden Rule: NEVER hold `std::sync::Mutex` across an `.await` point.**

```rust
// GOOD — std Mutex for quick data access
let data = Arc::new(std::sync::Mutex::new(HashMap::new()));
{
    let mut map = data.lock().unwrap();
    map.insert("key", "value");
} // Lock dropped BEFORE any .await

// GOOD — tokio Mutex when await is needed inside lock
let conn = Arc::new(tokio::sync::Mutex::new(db_connection));
{
    let mut guard = conn.lock().await;
    guard.execute("INSERT ...").await?; // .await while locked is OK
}
```

---

## Level 2: Task Management (Intermediate)

### JoinSet for Dynamic Task Collections

`JoinSet` manages N spawned tasks with structured cleanup.

```rust
use tokio::task::JoinSet;

let mut set = JoinSet::new();

// Spawn dynamically
for i in 0..10 {
    set.spawn(async move { process_item(i).await });
}

// Await results as they complete (unordered)
while let Some(result) = set.join_next().await {
    match result {
        Ok(val) => println!("Done: {:?}", val),
        Err(e) => eprintln!("Task failed: {:?}", e),
    }
}

// On drop, JoinSet aborts ALL remaining tasks
// For explicit shutdown: set.shutdown().await
```

**Always drain results with `join_next()`** — completed tasks accumulate in memory otherwise.

For tracking without results, use `tokio_util::task::TaskTracker` instead.

### select! for Racing Futures

```rust
use tokio::select;
use tokio::signal;
use tokio::sync::mpsc;

async fn run_loop(mut rx: mpsc::Receiver<Command>) {
    loop {
        select! {
            // biased; // Uncomment to poll in declaration order
            
            Some(cmd) = rx.recv() => {
                handle_command(cmd).await;
            }
            _ = signal::ctrl_c() => {
                println!("Shutting down...");
                break;
            }
        }
    }
}
```

**Critical select! rules:**
- Unmatched branches are **dropped** (cancelled) at their next `.await`
- Cleanup code AFTER an `.await` in a cancelled branch **will NOT run**
- `biased;` polls top-to-bottom (useful for priority shutdown signals)
- In loops, pin reused futures: `tokio::pin!(sleep_future);`

**Cancellation-unsafe in select!:** `Mutex::lock`, `RwLock::read/write`, `Semaphore::acquire`, `Notify::notified` — these lose their queue position when cancelled.

### CancellationToken for Graceful Shutdown

```rust
use tokio_util::sync::CancellationToken;

let token = CancellationToken::new();

// Worker task
let worker_token = token.clone();
tokio::spawn(async move {
    loop {
        select! {
            _ = worker_token.cancelled() => {
                println!("Worker shutting down");
                break;
            }
            _ = do_work() => {}
        }
    }
});

// Trigger shutdown
token.cancel();
```

Child tokens: `token.child_token()` — cancelled when parent is cancelled, but can be cancelled independently.

---

## Level 3: Production Patterns (Advanced)

### Backpressure Architecture

**NEVER use unbounded channels for data streams.** They cause OOM.

```rust
// BAD — no backpressure, memory grows forever
let (tx, rx) = tokio::sync::mpsc::unbounded_channel();

// GOOD — bounded, send().await pauses producer when full
let (tx, rx) = tokio::sync::mpsc::channel(1024);
```

Backpressure strategies when channel is full:
1. `send().await` — block producer (default, usually correct)
2. `try_send()` — non-blocking, returns `TrySendError::Full` → drop, log, or retry
3. Semaphore — limit concurrent access to external resources

```rust
// Fan-out to multiple clients: use try_send to prevent one slow client freezing all
match client_tx.try_send(msg.clone()) {
    Ok(_) => {}
    Err(TrySendError::Full(_)) => {
        tracing::warn!(client_id, "client lagging, dropping message");
    }
    Err(TrySendError::Closed(_)) => {
        dead_clients.push(client_id);
    }
}
```

Start capacity at **512-1024**. Tune via profiling under load.

### Actor Pattern with Tokio Channels

For managing shared mutable state without `Arc<Mutex<T>>`:

```rust
// The actor owns its state exclusively — no locks needed
struct AgentActor {
    state: AgentState,
    rx: mpsc::Receiver<AgentCommand>,
}

enum AgentCommand {
    GetStatus { reply: oneshot::Sender<String> },
    Execute { task: String },
    Shutdown,
}

impl AgentActor {
    async fn run(mut self) {
        while let Some(cmd) = self.rx.recv().await {
            match cmd {
                AgentCommand::GetStatus { reply } => {
                    let _ = reply.send(self.state.status.clone());
                }
                AgentCommand::Execute { task } => {
                    self.state.execute(task).await;
                }
                AgentCommand::Shutdown => break,
            }
        }
    }
}

// The handle is cheaply cloneable — send commands from anywhere
#[derive(Clone)]
struct AgentHandle {
    tx: mpsc::Sender<AgentCommand>,
}
```

### spawn_blocking for CPU Work

**NEVER do CPU-intensive work on tokio worker threads.** It blocks other tasks.

```rust
// BAD — blocks the async runtime
let hash = expensive_hash(&data);

// GOOD — offload to blocking thread pool
let hash = tokio::task::spawn_blocking(move || {
    expensive_hash(&data)
}).await?;
```

`spawn_blocking` tasks **cannot be aborted** once started — they run to completion.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Unbounded Channels for Data Streams

**You will be tempted to:** Use `unbounded_channel()` because "it's simpler."
**Why that fails:** A fast producer (subprocess stdout at GB/s) with a slow consumer (WebSocket at MB/s) will exhaust all memory in minutes.
**The right way:** `mpsc::channel(1024)` with `.send().await` for backpressure.

### Rule 2: No std::sync::Mutex Across .await

**You will be tempted to:** Use `std::sync::Mutex` everywhere because "it's faster."
**Why that fails:** Holding it across `.await` blocks the OS thread, starving all other tokio tasks on that thread. Deadlock in single-threaded tests.
**The right way:** `std::sync::Mutex` for quick sync ops. `tokio::sync::Mutex` if the lock spans `.await`.

### Rule 3: No tokio::spawn Without Considering Cancellation

**You will be tempted to:** `tokio::spawn` a task with `loop { ... }` and no shutdown check.
**Why that fails:** Graceful shutdown hangs because the task never checks for cancellation. The entire daemon gets SIGKILL'd after timeout.
**The right way:** Every long-running task must `select!` on a `CancellationToken` or shutdown signal.

### Rule 4: No Blocking in Async Context

**You will be tempted to:** Call `std::thread::sleep()`, synchronous file I/O, or CPU-heavy computation directly in an async function.
**Why that fails:** Blocks the tokio worker thread. Other tasks starve. Timeouts don't fire.
**The right way:** `tokio::time::sleep()` for delays. `tokio::fs` for file I/O. `spawn_blocking` for CPU work.

### Rule 5: No Ignoring JoinHandle Results

**You will be tempted to:** `tokio::spawn(async { ... });` without awaiting or storing the handle.
**Why that fails:** If the task panics, the panic is silently swallowed. Errors disappear.
**The right way:** Store in a `JoinSet`, or `.await` the handle, or at minimum log with `if let Err(e) = handle.await { error!(...) }`.
