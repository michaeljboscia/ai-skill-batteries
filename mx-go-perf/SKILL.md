---
name: mx-go-perf
description: Use when writing any Go code. Co-loads with mx-go-core by default. Go performance — pprof CPU/memory/goroutine profiling, flame graphs, escape analysis with gcflags -m, benchmarks with -benchmem, sync.Pool object reuse, slice preallocation, strings.Builder, stack vs heap allocation, GOGC and GOMEMLIMIT tuning, PGO profile-guided optimization. Also use when the user mentions 'performance', 'slow', 'optimize', 'profile', 'pprof', 'benchmark', 'allocation', 'escape analysis', or any Go performance work.
---

# Go Performance — Profiling & Optimization for AI Coding Agents

**This skill co-loads with mx-go-core for ANY Go work.** It prevents: guessing instead of profiling, heap allocations in hot paths, unbounded goroutines, ignoring escape analysis, and shipping code nobody benchmarked.

## When to also load
- Core Go patterns → `mx-go-core`
- Goroutine leak profiling → `mx-go-concurrency`
- Database query optimization → `mx-go-data`
- Production metrics → `mx-go-observability`

---

## Level 1: Profiling with pprof

### Enable pprof for HTTP Services

```go
import _ "net/http/pprof"  // registers /debug/pprof/ handlers

// Serve on a separate port (not the main API)
go func() {
    slog.Info("pprof listening", slog.String("addr", ":6060"))
    if err := http.ListenAndServe(":6060", nil); err != nil {
        slog.Error("pprof server failed", slog.String("error", err.Error()))
    }
}()
```

### Collecting Profiles

```bash
# CPU profile (30 seconds)
go tool pprof http://localhost:6060/debug/pprof/profile?seconds=30

# Heap (memory) profile
go tool pprof http://localhost:6060/debug/pprof/heap

# Goroutine profile (leak detection)
go tool pprof http://localhost:6060/debug/pprof/goroutine

# Mutex contention
go tool pprof http://localhost:6060/debug/pprof/mutex

# Block profile (channel/lock wait times)
go tool pprof http://localhost:6060/debug/pprof/block
```

### Reading pprof Output

```bash
# Interactive mode
go tool pprof profile.pb.gz

# Common commands inside pprof:
# top 20          — top 20 functions by CPU/memory
# list funcName   — annotated source for function
# web             — flame graph in browser
# peek funcName   — callers + callees

# Heap: two views
go tool pprof -inuse_space heap.pb.gz   # current allocations (default)
go tool pprof -alloc_objects heap.pb.gz  # total allocations (find churning)
```

### Programmatic Profiling

```go
import "runtime/pprof"

func profileCPU(filename string) (stop func()) {
    f, err := os.Create(filename)
    if err != nil {
        log.Fatal(err)
    }
    pprof.StartCPUProfile(f)
    return func() {
        pprof.StopCPUProfile()
        f.Close()
    }
}

// Usage:
stop := profileCPU("cpu.prof")
defer stop()
doExpensiveWork()
```

---

## Level 2: Benchmarks and Escape Analysis

### Writing Benchmarks

```go
func BenchmarkJSONMarshal(b *testing.B) {
    data := createTestData()
    b.ResetTimer()  // exclude setup

    for b.Loop() {  // Go 1.24+
        json.Marshal(data)
    }
}

func BenchmarkWithAlloc(b *testing.B) {
    b.ReportAllocs()  // or use -benchmem flag
    for b.Loop() {
        result := make([]byte, 1024)
        _ = result
    }
}
```

```bash
# Run benchmarks
go test -bench=. -benchmem ./...

# Compare before/after
go test -bench=. -count=10 ./... > old.txt
# make changes
go test -bench=. -count=10 ./... > new.txt
benchstat old.txt new.txt
```

### Escape Analysis

```bash
# See what escapes to heap
go build -gcflags="-m" ./...

# More detail
go build -gcflags="-m -m" ./...
```

**Variables escape to heap when:**

| Condition | Example | Fix |
|-----------|---------|-----|
| Returned as pointer | `return &Config{}` | Return by value if small |
| Stored in goroutine | `go func() { use(x) }()` | Accept the escape |
| Assigned to interface | `var w io.Writer = &buf` | Use concrete type if possible |
| Too large for stack | Large arrays/slices | Use pointer (heap is fine) |
| Captured by closure | `f := func() { use(x) }` | Pass as parameter |

### Escape-Avoiding Patterns

```go
// BAD — pointer escapes to heap
func newUser(name string) *User {
    u := User{Name: name}
    return &u  // escapes
}

// GOOD — value return, stays on stack (if caller doesn't take address)
func newUser(name string) User {
    return User{Name: name}
}

// BAD — interface causes escape
func process(w io.Writer) { ... }
var buf bytes.Buffer
process(&buf)  // buf escapes

// GOOD — concrete type when you can
func process(w *bytes.Buffer) { ... }  // no escape if buf is local
```

---

## Level 3: Advanced Optimization

### sync.Pool — Object Reuse

```go
var bufPool = sync.Pool{
    New: func() any {
        return new(bytes.Buffer)
    },
}

func process(data []byte) string {
    buf := bufPool.Get().(*bytes.Buffer)
    defer func() {
        buf.Reset()  // ALWAYS reset before returning to pool
        bufPool.Put(buf)
    }()

    buf.Write(data)
    // process...
    return buf.String()
}
```

**sync.Pool rules:**
- Always provide a `New` function
- Always reset objects before returning to pool
- Pool is cleared on GC — don't rely on persistence
- Don't pool variable-size objects (defeats the purpose)
- Profile first — only use Pool when allocations are a proven bottleneck

### Slice Preallocation

```go
// BAD — 0 capacity, grows dynamically (multiple allocations)
var results []Result
for _, item := range items {
    results = append(results, process(item))
}

// GOOD — preallocate to known size
results := make([]Result, 0, len(items))
for _, item := range items {
    results = append(results, process(item))
}

// BEST — direct index when length is known
results := make([]Result, len(items))
for i, item := range items {
    results[i] = process(item)
}
```

### strings.Builder vs Concatenation

```go
// BAD — O(n^2), allocates new string each iteration
s := ""
for _, line := range lines {
    s += line + "\n"
}

// GOOD — O(n), single allocation
var b strings.Builder
b.Grow(estimatedBytes)  // pre-grow if you know approximate size
for _, line := range lines {
    b.WriteString(line)
    b.WriteByte('\n')
}
result := b.String()
```

### GC Tuning

```bash
# GOGC — target heap growth % before GC (default 100)
# Lower = more frequent GC, less memory
# Higher = less frequent GC, more memory
GOGC=50 ./myapp    # GC at 50% growth (memory-constrained)
GOGC=200 ./myapp   # GC at 200% growth (throughput-focused)

# GOMEMLIMIT — hard memory ceiling (Go 1.19+)
GOMEMLIMIT=512MiB ./myapp  # GC gets aggressive near limit

# Combine: set GOMEMLIMIT as safety net, tune GOGC for throughput
GOGC=100 GOMEMLIMIT=1GiB ./myapp
```

**Rule: profile first, tune second.** Don't touch GOGC/GOMEMLIMIT without profiling evidence.

### Profile-Guided Optimization (PGO)

```bash
# Step 1: Collect CPU profile from production
curl -o default.pgo http://prod:6060/debug/pprof/profile?seconds=30

# Step 2: Place in main package directory
cp default.pgo cmd/myapp/default.pgo

# Step 3: Build — Go automatically detects default.pgo
go build ./cmd/myapp  # PGO applied automatically

# Typical improvement: 2-7% CPU reduction
```

---

## Performance: Make It Fast (Meta)

### Optimization Workflow

1. **Write correct code first** — don't optimize prematurely
2. **Benchmark** — `go test -bench=. -benchmem` to establish baseline
3. **Profile** — pprof CPU and heap to find hotspots
4. **Fix the top hotspot** — one change at a time
5. **Re-benchmark** — `benchstat` to confirm improvement
6. **Repeat** from step 3

### Quick Wins Checklist

| Check | Tool | Fix |
|-------|------|-----|
| String concatenation in loops | pprof alloc | strings.Builder |
| Unpreallocated slices | pprof alloc | make([]T, 0, cap) |
| Unnecessary pointer returns | gcflags -m | Return by value |
| Large struct copies | pprof CPU | Pass by pointer |
| Repeated JSON encoding | pprof CPU | Cache or pool encoders |
| Goroutine per-request without limit | goroutine count | errgroup.SetLimit |

---

## Observability: Know It's Working

### Runtime Metrics

```go
// Expose key runtime metrics
go func() {
    ticker := time.NewTicker(30 * time.Second)
    defer ticker.Stop()
    var m runtime.MemStats
    for range ticker.C {
        runtime.ReadMemStats(&m)
        slog.Info("runtime stats",
            slog.Uint64("heap_alloc_mb", m.HeapAlloc/1024/1024),
            slog.Uint64("heap_sys_mb", m.HeapSys/1024/1024),
            slog.Uint64("gc_cycles", uint64(m.NumGC)),
            slog.Int("goroutines", runtime.NumGoroutine()),
        )
    }
}()
```

### Key Metrics to Alert On

| Metric | Warning | Critical |
|--------|---------|----------|
| Heap alloc | >80% GOMEMLIMIT | >95% GOMEMLIMIT |
| GC pause | >10ms p99 | >50ms p99 |
| Goroutine count | Sustained growth | >10K (unless expected) |
| Allocs/op in benchmarks | Regression from baseline | 2x+ regression |

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Profile Before Optimizing
**You will be tempted to:** Optimize based on intuition — "this allocation looks expensive."
**Why that fails:** Developer intuition about performance is wrong ~80% of the time. You'll optimize cold code while the actual bottleneck is in a different function entirely.
**The right way:** pprof first. Optimize only what the profile shows as hot.

### Rule 2: Don't Use sync.Pool Without Profiling Evidence
**You will be tempted to:** Add sync.Pool "for performance" on any frequently allocated object.
**Why that fails:** sync.Pool adds complexity (reset logic, type assertions, potential memory leaks). If allocations aren't the bottleneck, you've added complexity for zero gain. Pool is cleared on GC anyway.
**The right way:** Profile allocations first. Use Pool only when `alloc_objects` shows the specific type as a top contributor.

### Rule 3: Never Tune GOGC/GOMEMLIMIT Without Data
**You will be tempted to:** Set `GOGC=200` because "less GC = faster."
**Why that fails:** Higher GOGC means more memory used between GC cycles. Your container might OOM. Or the larger heap makes GC pauses longer, hurting p99 latency.
**The right way:** Benchmark with default settings. If GC is a proven bottleneck (visible in pprof), tune incrementally with measurement.

### Rule 4: Use benchstat, Not Eyeballing
**You will be tempted to:** Run a benchmark once before and once after and compare numbers.
**Why that fails:** Benchmark results vary between runs (OS scheduling, thermal throttling, background processes). A single run tells you nothing about statistical significance.
**The right way:** `-count=10` for both old and new, then `benchstat old.txt new.txt` for statistical comparison.
