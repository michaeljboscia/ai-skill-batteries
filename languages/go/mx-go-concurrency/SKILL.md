---
name: mx-go-concurrency
description: Go concurrency — goroutine lifecycle, WaitGroup, errgroup, context cancellation, channels (buffered/unbuffered), select, fan-out/fan-in, pipelines, Mutex vs RWMutex vs atomic, sync.Once, sync.Map, race detection, worker pools, structured concurrency.
---

# Go Concurrency — Safe Parallelism for AI Coding Agents

**Load when writing goroutines, channels, sync primitives, or any concurrent Go code.**

## When to also load
- Core Go patterns → `mx-go-core`
- HTTP servers (graceful shutdown) → `mx-go-http`
- Profiling goroutine leaks → `mx-go-perf`
- Distributed tracing across goroutines → `mx-go-observability`
- NATS/Temporal async workflows → `mx-go-services`

---

## Level 1: Goroutine Lifecycle

### Always Track Goroutine Completion

```go
// BAD — fire and forget, goroutine leak
go processItem(item)
// who waits for this? nobody. leak.

// GOOD — WaitGroup tracks completion
var wg sync.WaitGroup
wg.Add(len(items))
for _, item := range items {
    go func() {
        defer wg.Done()
        processItem(item)
    }()
}
wg.Wait()
```

**Go 1.25+:** `wg.Go(func() { processItem(item) })` handles Add/Done automatically.

### Context — Always First Parameter, Always Cancel

```go
// BAD — no cancellation, goroutine runs forever
go func() {
    for {
        doWork()
        time.Sleep(time.Second)
    }
}()

// GOOD — context-aware, exits on cancellation
go func(ctx context.Context) {
    ticker := time.NewTicker(time.Second)
    defer ticker.Stop()
    for {
        select {
        case <-ctx.Done():
            return
        case <-ticker.C:
            doWork()
        }
    }
}(ctx)
```

**Rules:**
- `ctx` is always the first parameter
- `defer cancel()` immediately after creating a context
- Check `ctx.Done()` in every loop and blocking operation
- Never store context in a struct — pass through function calls
- `context.WithTimeout`/`WithDeadline` for all blocking operations

### errgroup — The Right Default for Concurrent Work

```go
// errgroup = WaitGroup + error propagation + context cancellation
g, ctx := errgroup.WithContext(ctx)
g.SetLimit(10)  // bounded concurrency (built-in semaphore)

for _, url := range urls {
    g.Go(func() error {
        return fetch(ctx, url)
    })
}

if err := g.Wait(); err != nil {
    return fmt.Errorf("fetch batch: %w", err)
}
```

**errgroup replaces the manual WaitGroup + error channel + context wiring pattern.** Use it as the default for concurrent work that can fail.

---

## Level 2: Channels and Patterns

### Buffered vs Unbuffered

| Type | Behavior | Use When |
|------|----------|----------|
| Unbuffered `make(chan T)` | Synchronous handoff — both sides block | Signaling, synchronization |
| Buffered `make(chan T, n)` | Async up to buffer size — blocks when full | Work queues, rate limiting |

```go
// Signal channel — unbuffered, notification only
done := make(chan struct{})
go func() {
    doWork()
    close(done)  // signal completion
}()
<-done

// Work queue — buffered
jobs := make(chan Job, 100)
// producer won't block until 100 items queued
```

### Channel Direction in Signatures

```go
// GOOD — direction constrains usage, prevents bugs
func producer(out chan<- int) { ... }   // can only send
func consumer(in <-chan int) { ... }    // can only receive
func bridge(in <-chan int, out chan<- int) { ... }
```

### Select — Multiplexing Channels

```go
select {
case msg := <-msgCh:
    handle(msg)
case err := <-errCh:
    handleError(err)
case <-ctx.Done():
    return ctx.Err()
case <-time.After(5 * time.Second):
    return ErrTimeout
}

// Non-blocking check (default case)
select {
case msg := <-ch:
    handle(msg)
default:
    // channel empty, do something else
}
```

### Fan-Out / Fan-In

```go
func fanOut(ctx context.Context, input <-chan Job, workers int) <-chan Result {
    results := make(chan Result, workers)
    var wg sync.WaitGroup
    wg.Add(workers)

    for range workers {  // Go 1.22+ range over int
        go func() {
            defer wg.Done()
            for job := range input {
                select {
                case <-ctx.Done():
                    return
                case results <- process(job):
                }
            }
        }()
    }

    go func() {
        wg.Wait()
        close(results)
    }()

    return results
}
```

### Pipeline Pattern

```go
// source → transform → sink, connected by channels
func generate(ctx context.Context, nums ...int) <-chan int {
    out := make(chan int)
    go func() {
        defer close(out)
        for _, n := range nums {
            select {
            case out <- n:
            case <-ctx.Done():
                return
            }
        }
    }()
    return out
}

func square(ctx context.Context, in <-chan int) <-chan int {
    out := make(chan int)
    go func() {
        defer close(out)
        for n := range in {
            select {
            case out <- n * n:
            case <-ctx.Done():
                return
            }
        }
    }()
    return out
}

// Usage: pipeline
ctx, cancel := context.WithCancel(context.Background())
defer cancel()
for result := range square(ctx, generate(ctx, 1, 2, 3, 4)) {
    fmt.Println(result)
}
```

---

## Level 3: Sync Primitives

### Mutex vs RWMutex vs Atomic — Decision Tree

| Scenario | Use |
|----------|-----|
| Single counter/flag | `atomic.Int64`, `atomic.Bool` |
| Multi-variable critical section | `sync.Mutex` |
| Reads >> writes (>70% reads) | `sync.RWMutex` |
| Writes >30% of operations | `sync.Mutex` (RWMutex overhead not worth it) |
| Write-once-read-many or disjoint keys | `sync.Map` |
| General concurrent map | `map` + `sync.Mutex` (NOT sync.Map) |
| Exactly-once initialization | `sync.Once` |

```go
// Mutex — exclusive lock
type SafeCounter struct {
    mu sync.Mutex
    v  map[string]int
}
func (c *SafeCounter) Inc(key string) {
    c.mu.Lock()
    defer c.mu.Unlock()
    c.v[key]++
}

// RWMutex — multiple readers OR single writer
type Cache struct {
    mu    sync.RWMutex
    items map[string]Item
}
func (c *Cache) Get(key string) (Item, bool) {
    c.mu.RLock()
    defer c.mu.RUnlock()
    item, ok := c.items[key]
    return item, ok
}

// Typed atomics (Go 1.19+)
var counter atomic.Int64
counter.Add(1)
val := counter.Load()

// sync.Once — lazy init
var (
    instance *DB
    once     sync.Once
)
func GetDB() *DB {
    once.Do(func() {
        instance = connectDB()
    })
    return instance
}
```

### Worker Pool (Bounded Concurrency)

```go
func workerPool(ctx context.Context, jobs <-chan Job, results chan<- Result, workers int) {
    var wg sync.WaitGroup
    wg.Add(workers)
    for range workers {
        go func() {
            defer wg.Done()
            for job := range jobs {
                select {
                case <-ctx.Done():
                    return
                case results <- processJob(job):
                }
            }
        }()
    }
    go func() {
        wg.Wait()
        close(results)
    }()
}
```

**Prefer `errgroup.SetLimit(n)` over manual worker pools** — it handles the wiring for you.

---

## Performance: Make It Fast

### Detect Goroutine Leaks Early

```go
// In tests — use goleak
func TestMain(m *testing.M) {
    goleak.VerifyTestMain(m)
}

// In production — monitor goroutine count
go func() {
    ticker := time.NewTicker(30 * time.Second)
    defer ticker.Stop()
    for range ticker.C {
        slog.Info("goroutine count", slog.Int("count", runtime.NumGoroutine()))
    }
}()
```

### Channel vs Mutex Performance

- Mutex: ~nanoseconds per lock/unlock
- Channel: higher overhead (allocation, scheduling, goroutine context switch)
- **Rule:** Mutex for protecting state, channels for passing data. They complement, not replace.

### Race Detector

```bash
# ALWAYS in CI — catches data races
go test -race ./...

# 5-10x memory, 2-20x slower — test only, never production
```

---

## Observability: Know It's Working

### Key Metrics to Track

| Metric | How | Alert Threshold |
|--------|-----|-----------------|
| Goroutine count | `runtime.NumGoroutine()` | Sustained growth = leak |
| errgroup errors | Log on `g.Wait()` error | Any unexpected error |
| Channel backpressure | Monitor buffered channel `len(ch)` | >80% capacity = slow consumer |
| Mutex contention | `pprof` mutex profile | High wait time in profile |

### Context Propagation for Tracing

Always pass the parent `ctx` through goroutines so distributed traces connect parent and child spans. See `mx-go-observability` for full OpenTelemetry integration.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Fire-and-Forget Goroutines
**You will be tempted to:** Write `go doSomething()` without tracking completion.
**Why that fails:** Goroutine leak. The goroutine runs forever or blocks on a channel nobody reads. In production, this accumulates until OOM.
**The right way:** Every goroutine must have a tracked lifecycle — WaitGroup, errgroup, or context cancellation.

### Rule 2: sync.Map Is NOT a General-Purpose Concurrent Map
**You will be tempted to:** Use `sync.Map` for any concurrent map access because "it's in the stdlib."
**Why that fails:** sync.Map is optimized for two specific patterns: (1) write-once-read-many, (2) disjoint key sets across goroutines. For balanced read/write workloads, `map + sync.Mutex` is faster AND type-safe.
**The right way:** Default to `map` + `sync.Mutex`. Only use `sync.Map` when you've profiled and confirmed it helps.

### Rule 3: Close Channels from the Sender Only
**You will be tempted to:** Close a channel from the receiver side to "signal done."
**Why that fails:** Sending to a closed channel panics. If the sender doesn't know the channel is closed, your program crashes.
**The right way:** Only the sender closes the channel. Use a separate `done` channel or context for receiver-to-sender signaling.

### Rule 4: Large Buffer Sizes Mask Bugs
**You will be tempted to:** Set `make(chan T, 10000)` to "avoid blocking."
**Why that fails:** A large buffer hides a slow consumer. The program works in testing (small data), then deadlocks or OOMs in production (large data) when the buffer fills.
**The right way:** Size buffers based on actual throughput requirements. If you need >100, you need backpressure design, not a bigger buffer.

### Rule 5: Atomic Operations Are Not Composable
**You will be tempted to:** Use multiple atomic operations to implement a compound operation "without a lock."
**Why that fails:** Each atomic op is individually atomic, but the combination is not. `if counter.Load() == 0 { counter.Store(1) }` is a race condition.
**The right way:** Use `sync.Mutex` for multi-step operations. Atomics are for single-variable reads/writes only.
