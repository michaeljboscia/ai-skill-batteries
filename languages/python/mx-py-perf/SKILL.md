---
name: mx-py-perf
description: Python performance optimization — profiling, caching, memory optimization, generators, __slots__, data structure selection, uvloop, vectorization, compilation. Use for any Python work.
---

# Python Performance Optimization — Profiling, Caching, Data Structures & Async Tuning for AI Coding Agents

**This skill co-loads with mx-py-core for ANY Python work.** It defines the performance patterns that prevent AI agents from generating slow, memory-wasteful code.

## When to also load
- `mx-py-core` — always loaded alongside this skill (core typing, dataclasses, error handling)
- `mx-py-async` — when writing asyncio code (TaskGroup, Semaphore, structured concurrency)
- `mx-py-data` — when handling Pandas/Polars DataFrames or Pydantic validation
- `mx-py-observability` — when adding logging, tracing, or monitoring

---

## The Mantra

**Profile BEFORE optimizing.** Measure, don't guess. Every optimization starts with a flame graph or profiler output. Anything else is superstition.

**Amdahl's Law.** If a function is 1% of total execution time, making it 10x faster yields 0.9% global speedup. Optimize the tallest bars in the flame graph. Ignore cold paths.

---

## Level 1: Data Structures & Memory (Beginner)

### Data Structure Decision Table

| Use Case | Use | Time Complexity | Anti-Pattern |
|----------|-----|-----------------|--------------|
| Membership test / uniqueness | `set` or `frozenset` | O(1) lookup | `x in list` — O(n) |
| Queue / FIFO | `collections.deque` | O(1) append/popleft | `list.pop(0)` — O(n) shift |
| Counting occurrences | `collections.Counter` | O(n) build, O(1) query | Manual `dict[k] = dict.get(k, 0) + 1` |
| Grouping by key | `collections.defaultdict` | O(1) append | `dict.setdefault()` in loops |
| Maintaining sorted order | `bisect` + `list` | O(log n) search/insert | Append then `sort()` — O(n log n) |
| Priority queue (min/max) | `heapq` | O(log n) push/pop | `min()` over list — O(n) |
| Key-value lookup | `dict` | O(1) average | Scanning list of tuples |

### BAD: list for queue operations
```python
queue = []
queue.append(item)
first = queue.pop(0)  # O(n) — shifts entire array
```

### GOOD: deque for O(1) queue
```python
from collections import deque
queue = deque()
queue.append(item)
first = queue.popleft()  # O(1)
```

### BAD: list for membership testing
```python
seen = []
for item in data:
    if item not in seen:  # O(n) per check → O(n^2) total
        seen.append(item)
```

### GOOD: set for O(1) membership
```python
seen = set()
for item in data:
    if item not in seen:  # O(1) per check
        seen.add(item)
```

### Generators Over Lists

Lists materialize everything in memory. Generators yield lazily — O(1) memory instead of O(n).

```python
# BAD: O(n) memory — entire file in memory
def process_bad(path):
    lines = [line.strip() for line in open(path)]
    return [parse(line) for line in lines]

# GOOD: O(1) memory — streams one line at a time
def process_good(path):
    with open(path) as f:
        for line in f:
            yield parse(line.strip())
```

**Rule of thumb:** If the caller iterates once and doesn't need random access, use a generator. Use `(x for x in items)` generator expressions over `[x for x in items]` list comprehensions when the result is consumed once.

### `slots=True` for High-Volume Objects

Every Python instance carries a `__dict__` (dynamic attribute storage). For millions of instances, this wastes 40-50% memory.

```python
# BAD: __dict__ overhead per instance
class Point:
    def __init__(self, x, y):
        self.x = x
        self.y = y

# GOOD: Fixed-size attribute storage, 40-50% memory savings
from dataclasses import dataclass

@dataclass(slots=True)
class Point:
    x: float
    y: float
```

**When to use:** Millions of instances (ORM-like row objects, graph nodes, event records). **When NOT to use:** Singletons, config objects, anything needing dynamic attributes or metaprogramming.

---

## Level 2: Profiling & Caching (Intermediate)

### Profiler Decision Table

| Scenario | Profiler | Why |
|----------|----------|-----|
| **Live production issue** | `py-spy` | Zero code changes, out-of-process, negligible overhead, flame graphs |
| **Data/ML workload** | `scalene` | Separates Python vs native time, tracks GPU + memory, line-level |
| **Memory leak hunting** | `scalene` or `memray` | Line-level allocation tracking, C-level leak detection |
| **Algorithm tuning (local)** | `cProfile` + `snakeviz` | Deterministic — counts every call, return, exception |

**Workflow:**
1. `cProfile` to find hot functions during development
2. `py-spy` flame graph to confirm bottlenecks under real production load
3. `scalene` for data-heavy workloads (separates Python overhead from C/Rust extension time)
4. `memory_profiler` or `tracemalloc` for pinpointing exact lines causing memory growth

```bash
# py-spy: attach to running process, generate flame graph
py-spy record -o profile.svg --pid <PID>

# cProfile: deterministic profiling, save stats
python -m cProfile -o profile.stats script.py

# scalene: line-level CPU + memory + GPU
scalene --cli --reduced-profile script.py

# memory_profiler: line-by-line memory (requires @profile decorator)
python -m memory_profiler script.py
```

### Caching Decision Table

| Need | Use | Pitfall |
|------|-----|---------|
| Pure function memoization (small domain) | `@lru_cache(maxsize=128)` | Unbounded `@cache` leaks memory |
| Time-based expiration | `cachetools.TTLCache(maxsize=1000, ttl=300)` | No TTL = stale data forever |
| Frequency-based eviction | `cachetools.LFUCache` | Rarely needed — LRU covers most cases |
| Per-instance expensive property | `@cached_property` | Only computed once per instance lifecycle |
| Distributed / multi-process | Redis with TTL | Single-process caches don't share across workers |

### BAD: Unbounded cache on dynamic data
```python
import functools

@functools.cache  # No eviction — grows until OOM
def fetch_user(user_id):
    return db.query("SELECT * FROM users WHERE id = ?", user_id)
```

### GOOD: Bounded cache with TTL
```python
from cachetools import cached, TTLCache

@cached(cache=TTLCache(maxsize=1000, ttl=300))
def fetch_user(user_id):
    return db.query("SELECT * FROM users WHERE id = ?", user_id)
```

### Cache Stampede Prevention

When a hot cache key expires under load, hundreds of requests miss simultaneously and slam the database (thundering herd).

**Strategy 1 — Distributed lock (Redis):**
```python
def get_with_lock(key, fetch_fn):
    value = redis.get(key)
    if value:
        return value
    lock = redis.lock(f"{key}_lock", timeout=5)
    if lock.acquire(blocking=False):
        try:
            value = fetch_fn()
            redis.set(key, value, ex=300)
            return value
        finally:
            lock.release()
    else:
        time.sleep(0.05)
        return get_with_lock(key, fetch_fn)
```

**Strategy 2 — Singleflight (asyncio):** Return the same `Future` for concurrent misses on the same key — only one fetch executes.

**Strategy 3 — Staggered TTL:** Add random jitter to TTL values so keys don't expire simultaneously.

**Monitor:** Target 80-90% hit rate. Track eviction rate and memory usage.

---

## Level 3: Async Performance, Vectorization & Compilation (Advanced)

### asyncio Performance Tuning

**uvloop — 2-4x throughput for I/O-heavy workloads:**
```python
import asyncio
import uvloop

# Python 3.11+
with asyncio.Runner(loop_factory=uvloop.new_event_loop) as runner:
    runner.run(main())
```
Built on libuv (same as Node.js). Drop-in replacement. Lower p95/p99 latency, reduced CPU.

**TaskGroup over gather (Python 3.11+):**
```python
# BAD: gather leaves orphan tasks on failure
async def fetch_all(urls):
    return await asyncio.gather(*[fetch(u) for u in urls])

# GOOD: TaskGroup auto-cancels all tasks if any fails
async def fetch_all(urls):
    async with asyncio.TaskGroup() as tg:
        tasks = [tg.create_task(fetch(u)) for u in urls]
    return [t.result() for t in tasks]
```

**Semaphore for concurrency control:**
```python
sem = asyncio.Semaphore(10)  # Max 10 concurrent

async def fetch_limited(url):
    async with sem:
        return await httpx.AsyncClient().get(url)
```

**run_in_executor for CPU-bound work:**
```python
import asyncio
from concurrent.futures import ProcessPoolExecutor

async def heavy_compute(data):
    loop = asyncio.get_event_loop()
    # Offload CPU work — never block the event loop
    return await loop.run_in_executor(
        ProcessPoolExecutor(), cpu_bound_fn, data
    )
```

**Critical rules:**
- NEVER `time.sleep()` in async code — use `await asyncio.sleep()`
- ALL I/O must be async (`httpx` not `requests`, `aiofiles` not `open()`)
- CPU-bound work goes to `ThreadPoolExecutor` (light) or `ProcessPoolExecutor` (heavy)
- Use `asyncio.Queue(maxsize=N)` for backpressure

### Vectorization — Polars/Pandas Over Loops

Python loops have massive per-iteration overhead from dynamic type checking. Push iteration into C/Rust.

```python
# BAD: iterrows abandons vectorization — O(n) with enormous overhead
def calc_total_bad(df):
    totals = []
    for _, row in df.iterrows():
        totals.append(row["price"] * row["tax"])
    df["total"] = totals

# GOOD (Pandas): Vectorized column operation
def calc_total_pandas(df):
    df["total"] = df["price"] * df["tax"]
    # For complex expressions, bypass Python entirely:
    # df.eval("total = price * tax", inplace=True)

# BEST (Polars): Lazy evaluation + automatic multi-threading
def calc_total_polars(lf):
    return lf.with_columns(
        (pl.col("price") * pl.col("tax")).alias("total")
    ).collect()
```

**Pandas PyArrow backend:** Use `string[pyarrow]` dtypes for ~50% memory savings and 6-27x faster string operations. Enable Copy-on-Write to prevent invisible deep copies.

**Never use:** `df.iterrows()`, `df.itertuples()`, or `df.apply()` with arbitrary lambdas for math. These abandon vectorization entirely.

### Compilation Overview

When profiling proves pure Python CPU speed is the bottleneck and vectorization is not applicable:

| Compiler | Best For | Speedup | Complexity |
|----------|----------|---------|------------|
| **mypyc** | Already type-hinted CPU-bound logic, tree traversals, parsing | Up to 10x | Low — pure Python syntax, compile via mypyc |
| **Cython** | C-extension authoring, tight numerical loops, interfacing with C libraries | C-parity | Medium — cdef type declarations, .pyx files |
| **Nuitka** | Standalone binary distribution, full-program optimization | 2-5x | Medium — supports 100% Python features, GCC/MSVC backend |

**When compilation is worth it:** Profile shows >50% time in pure Python compute. Algorithm is already optimal. You've exhausted vectorization options.

**When it's NOT worth it:** I/O-bound code (use async instead). Unoptimized algorithm (fix the algorithm first). Prototype phase (premature complexity).

---

## Performance: Profile-Driven Optimization

- **Profile BEFORE optimizing** — always. No exceptions. `py-spy` for production, `scalene` for data/ML, `cProfile` for local dev.
- **Amdahl's Law** — don't optimize cold paths. If it's <1% of execution time, leave it alone.
- **Algorithm first, data structure second, micro-optimization last** — fix O(n^2) before reaching for Cython.
- **tracemalloc** for memory snapshots — compare before/after to find leaks in long-running processes.
- **py-spy flame graphs** for production — zero overhead, attach to running process, no code changes.

```python
# tracemalloc: compare memory snapshots
import tracemalloc

tracemalloc.start()
snapshot1 = tracemalloc.take_snapshot()

# ... run suspected leaky code ...

snapshot2 = tracemalloc.take_snapshot()
for stat in snapshot2.compare_to(snapshot1, "lineno")[:10]:
    print(stat)
```

---

## Observability: Know What's Slow

- **tracemalloc** — standard library memory allocation tracker. Compare snapshots to find leaks.
- **py-spy flame graphs** — production-safe. Generates SVG flame graphs showing which code paths consume the most time.
- **scalene** — line-level CPU + memory + GPU profiling. Differentiates Python time vs native extension time.
- **Cache hit rate monitoring** — target 80-90%. Below that, the cache is not doing its job.
- **`sys.getsizeof`** — shallow object size. For nested structures, use recursive sizeof or `pympler.asizeof`.

See `mx-py-observability` for structlog, OTel, Sentry, and Prometheus patterns.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Optimizing Without Profiling
**You will be tempted to:** Rewrite a loop in Cython or add caching because "I know this is the bottleneck."
**Why that fails:** Without profiling data, you're guessing. The actual bottleneck is usually somewhere else — often I/O, not CPU. You waste effort optimizing code that doesn't matter while the real problem persists.
**The right way:** Run a profiler first. `py-spy record` for production. `scalene` for data workloads. `cProfile` for local dev. Read the flame graph. Optimize the tallest bar. Nothing else.

### Rule 2: Premature Compilation
**You will be tempted to:** Reach for mypyc, Cython, or Nuitka because "Python is slow."
**Why that fails:** Compilation adds massive CI/CD complexity (build matrices, platform-specific binaries, C compiler dependencies). Most Python performance problems are algorithmic or I/O-bound — compilation doesn't help either. Compiling an O(n^2) algorithm just makes it fail slightly faster.
**The right way:** Fix the algorithm. Use vectorization (Polars/Pandas). Use async for I/O. Only compile when profiling proves pure Python CPU execution is the binding constraint and all other options are exhausted.

### Rule 3: Micro-Optimizing Cold Paths
**You will be tempted to:** Optimize a utility function that runs once at startup because "every millisecond counts."
**Why that fails:** Amdahl's Law. If startup takes 200ms and your optimization saves 50ms there, but the hot loop runs 10,000x per second and you ignored it, you optimized the wrong thing. Cold path improvements have near-zero impact on overall throughput.
**The right way:** Look at the flame graph. The tallest bars are the hot paths. Optimize those. Ignore everything under 1% of total execution time.

### Rule 4: Unbounded Caches in Long-Running Processes
**You will be tempted to:** Use `@functools.cache` (unbounded) or `@lru_cache` without `maxsize` on functions that take dynamic inputs, because "more caching = faster."
**Why that fails:** In a long-running server, unbounded caches grow without limit. Every unique input creates a new cache entry that is never evicted. Memory climbs until the process is OOM-killed. This is a memory leak disguised as an optimization.
**The right way:** Always set `maxsize` on `lru_cache`. Use `cachetools.TTLCache` for time-sensitive data. Monitor cache size and hit rate. Cache only deterministic, pure-function results.

### Rule 5: List for Queue or Membership Operations
**You will be tempted to:** Use a plain `list` for everything because "it's simple and I know the API."
**Why that fails:** `list.pop(0)` is O(n) — it shifts every element. `x in list` is O(n) — it scans the entire array. In loops, these become O(n^2). For 10,000 elements, that's 100 million operations instead of 10,000.
**The right way:** `collections.deque` for FIFO/LIFO. `set` for membership testing. `heapq` for priority queues. `Counter` for counting. `defaultdict` for grouping. The standard library has specialized containers — use them.
