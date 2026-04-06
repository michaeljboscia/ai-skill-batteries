---
name: mx-py-async
description: Python async concurrency — asyncio TaskGroup, gather, Semaphore, Queue, concurrent.futures, threading, multiprocessing, run_in_executor, to_thread. Use when writing async/await code, concurrent operations, background tasks, or mixing sync and async.
---

# Python Async Concurrency — asyncio, Executors & Parallelism for AI Coding Agents

**This skill loads when writing any async Python code, concurrent operations, or mixing sync/async boundaries.**

## When to also load
- `mx-py-core` — foundational typing, error handling, module structure
- `mx-py-perf` — when profiling async hot paths, data structure choices, CPU-bound offloading
- `mx-py-network` — when building HTTP clients/servers with httpx, aiohttp, WebSockets
- `mx-py-observability` — when adding structured logging or tracing to async services

---

## Level 1: Core Async Patterns (Beginner)

### Concurrency Model Decision Table

| Workload | Use | NOT |
|----------|-----|-----|
| Many concurrent I/O operations (HTTP, DB, files) | `asyncio` | threading (GIL contention overhead) |
| Moderate I/O with blocking libraries (requests, psycopg2) | `threading` / `ThreadPoolExecutor` | asyncio alone (blocks event loop) |
| CPU-bound computation (crypto, ML, image processing) | `multiprocessing` / `ProcessPoolExecutor` | threading (GIL prevents parallelism) |
| CPU-bound C extension (NumPy, Pillow) that releases GIL | `threading` | multiprocessing (unnecessary IPC overhead) |
| Mixed I/O + CPU in async app | `asyncio` + `run_in_executor(ProcessPoolExecutor)` | synchronous calls on event loop |

### TaskGroup: The Default (Python 3.11+)

TaskGroup is structured concurrency. All tasks complete or cancel before the block exits. No orphans.

```python
import asyncio

async def fetch(url: str) -> dict:
    async with httpx.AsyncClient() as client:
        resp = await client.get(url)
        return resp.json()

async def fetch_all(urls: list[str]) -> list[dict]:
    tasks: list[asyncio.Task[dict]] = []
    async with asyncio.TaskGroup() as tg:
        for url in urls:
            tasks.append(tg.create_task(fetch(url)))
    return [t.result() for t in tasks]
```

### ExceptionGroup Handling (except*)

When a TaskGroup task fails, all siblings cancel and exceptions wrap in `ExceptionGroup`:

```python
async def process_batch(items: list[str]) -> None:
    try:
        async with asyncio.TaskGroup() as tg:
            for item in items:
                tg.create_task(process(item))
    except* ValueError as eg:
        for e in eg.exceptions:
            logger.error("Validation failure: %s", e)
    except* ConnectionError as eg:
        for e in eg.exceptions:
            logger.error("Network failure: %s", e)
```

### asyncio.run() Is the Only Entry Point

```python
# GOOD: Single entry point
async def main() -> None:
    results = await fetch_all(urls)

if __name__ == "__main__":
    asyncio.run(main())
```

Never call `asyncio.get_event_loop()` or `loop.run_until_complete()` in new code. Both are legacy patterns.

---

## Level 2: Coordination & Sync/Async Boundaries (Intermediate)

### gather vs TaskGroup Decision

| Need | Use |
|------|-----|
| Fail-fast: cancel all on first error (Python 3.11+) | `TaskGroup` |
| Complete all regardless of failures | `gather(*tasks, return_exceptions=True)` |
| Pre-3.11 codebase | `gather` (only option) |
| Dynamic task spawning during iteration | `TaskGroup` (create_task inside loop) |

**Emulating return_exceptions with TaskGroup:**
```python
async def safe_op(item: str) -> str | Exception:
    """Catch inside each task to prevent sibling cancellation."""
    try:
        return await risky_operation(item)
    except Exception as e:
        return e

async def resilient_batch(items: list[str]) -> list[str | Exception]:
    tasks: list[asyncio.Task[str | Exception]] = []
    async with asyncio.TaskGroup() as tg:
        for item in items:
            tasks.append(tg.create_task(safe_op(item)))
    return [t.result() for t in tasks]
```

### Semaphore: Bounding Concurrency

```python
MAX_CONCURRENT = 10

async def bounded_fetch(sem: asyncio.Semaphore, url: str) -> bytes:
    async with sem:
        async with httpx.AsyncClient() as client:
            resp = await client.get(url)
            return resp.content

async def fetch_bounded(urls: list[str]) -> list[bytes]:
    sem = asyncio.BoundedSemaphore(MAX_CONCURRENT)
    tasks: list[asyncio.Task[bytes]] = []
    async with asyncio.TaskGroup() as tg:
        for url in urls:
            tasks.append(tg.create_task(bounded_fetch(sem, url)))
    return [t.result() for t in tasks]
```

Use `BoundedSemaphore` (not `Semaphore`) -- it raises on over-release, catching bugs early.

### Queue: Producer/Consumer with Backpressure

```python
async def producer(queue: asyncio.Queue[str], items: list[str]) -> None:
    for item in items:
        await queue.put(item)  # Blocks when queue is full (backpressure)
    await queue.put(None)      # Sentinel

async def consumer(queue: asyncio.Queue[str | None]) -> None:
    while True:
        item = await queue.get()
        if item is None:
            break
        await process(item)
        queue.task_done()

async def pipeline(items: list[str], concurrency: int = 5) -> None:
    queue: asyncio.Queue[str | None] = asyncio.Queue(maxsize=100)
    async with asyncio.TaskGroup() as tg:
        tg.create_task(producer(queue, items))
        for _ in range(concurrency):
            tg.create_task(consumer(queue))
```

### Mixing Sync and Async: The Executor Bridge

#### Blocking I/O in async code: `asyncio.to_thread`

```python
# GOOD: Offload blocking library to thread pool
import asyncio

def legacy_sync_fetch(url: str) -> str:
    """Uses requests (blocking). Cannot be made async."""
    import requests
    return requests.get(url).text

async def main() -> None:
    # to_thread propagates contextvars automatically (Python 3.9+)
    result = await asyncio.to_thread(legacy_sync_fetch, "https://api.example.com")
```

#### CPU-bound work in async code: ProcessPoolExecutor

```python
import asyncio
from concurrent.futures import ProcessPoolExecutor

def compute_heavy(n: int) -> int:
    """CPU-bound -- must run in separate process to bypass GIL."""
    return sum(i * i for i in range(n))

async def main() -> None:
    loop = asyncio.get_running_loop()
    with ProcessPoolExecutor(max_workers=4) as pool:
        result = await loop.run_in_executor(pool, compute_heavy, 10_000_000)
```

#### Calling async from sync (rare but necessary):

```python
import asyncio

def sync_entry_point() -> str:
    """CLI or legacy framework that cannot be made async."""
    return asyncio.run(async_implementation())
```

Never nest `asyncio.run()` inside a running event loop. Use `asyncio.to_thread` or a dedicated thread with its own loop if truly needed.

### Event: Coordinating Between Tasks

```python
async def waiter(event: asyncio.Event) -> None:
    await event.wait()
    print("Event fired, proceeding")

async def setter(event: asyncio.Event) -> None:
    await asyncio.sleep(1.0)
    event.set()

async def main() -> None:
    event = asyncio.Event()
    async with asyncio.TaskGroup() as tg:
        tg.create_task(waiter(event))
        tg.create_task(setter(event))
```

---

## Level 3: Cancellation, Shutdown & Event Loop Internals (Advanced)

### Cancellation and CancelledError

`CancelledError` is a `BaseException` (Python 3.9+). It propagates through the task tree to enable structured shutdown.

```python
async def cancellable_worker(name: str) -> None:
    try:
        while True:
            await asyncio.sleep(1.0)
            print(f"{name} working")
    except asyncio.CancelledError:
        # Cleanup resources, then RE-RAISE
        print(f"{name} cleaning up")
        raise  # MUST re-raise -- see anti-rationalization Rule 2
```

### Graceful Shutdown Pattern

```python
import asyncio
import signal

async def graceful_shutdown(tasks: list[asyncio.Task]) -> None:
    for task in tasks:
        task.cancel()
    results = await asyncio.gather(*tasks, return_exceptions=True)
    for r in results:
        if isinstance(r, Exception) and not isinstance(r, asyncio.CancelledError):
            logger.error("Task failed during shutdown: %s", r)

async def main() -> None:
    loop = asyncio.get_running_loop()
    shutdown_event = asyncio.Event()

    def _signal_handler() -> None:
        shutdown_event.set()

    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, _signal_handler)

    workers = [asyncio.create_task(worker(i)) for i in range(4)]
    await shutdown_event.wait()
    await graceful_shutdown(workers)
```

### Timeout Patterns

```python
# Single operation timeout
async def fetch_with_timeout(url: str) -> bytes:
    try:
        async with asyncio.timeout(5.0):  # Python 3.11+
            return await do_fetch(url)
    except TimeoutError:
        logger.warning("Fetch timed out: %s", url)
        raise

# Legacy (pre-3.11)
result = await asyncio.wait_for(do_fetch(url), timeout=5.0)
```

Prefer `asyncio.timeout()` context manager (3.11+) over `wait_for` -- it integrates with structured concurrency and is cancellation-safe.

### Event Loop Policy Deprecation (Python 3.14+)

```python
# BAD: Deprecated in 3.14, removed in 3.16
import uvloop
asyncio.set_event_loop_policy(uvloop.EventLoopPolicy())
asyncio.run(main())

# GOOD: Use loop_factory parameter
import uvloop
asyncio.run(main(), loop_factory=uvloop.new_event_loop)

# Or with Runner for more control
async def main() -> None: ...

with asyncio.Runner(loop_factory=uvloop.new_event_loop) as runner:
    runner.run(main())
```

### Nested TaskGroup Propagation

Inner TaskGroup exceptions propagate to outer TaskGroup, triggering cascading cancellation:

```python
async def outer() -> None:
    async with asyncio.TaskGroup() as outer_tg:
        outer_tg.create_task(safe_work())
        # Inner group failure cancels outer group's remaining tasks
        async with asyncio.TaskGroup() as inner_tg:
            inner_tg.create_task(risky_work())
```

---

## Performance: Make It Fast

- **uvloop** gives 2-4x throughput over the default event loop. Use `loop_factory=uvloop.new_event_loop` in `asyncio.run()`. Lower p95/p99 latency, reduced CPU.
- **TaskGroup over gather** for structured concurrency. gather with `return_exceptions=True` still runs all tasks even after failures -- wasted work.
- **Backpressure via `asyncio.Queue(maxsize=N)`** prevents memory exhaustion from unbounded producers. Without maxsize, a fast producer fills RAM.
- **Semaphore for rate limiting** -- `BoundedSemaphore(N)` caps concurrent operations. Essential for API rate limits and DB connection pools.
- **Batch `await` calls** -- each `await` is a context switch. Group small sequential awaits when ordering doesn't matter.
- **`asyncio.to_thread`** over manual `run_in_executor(None, ...)` -- cleaner API, automatic contextvars propagation.
- **`ProcessPoolExecutor`** for CPU-bound -- thread pool does NOT bypass the GIL. If computation takes >1ms, use a process pool.

---

## Observability: Know It's Working

### Debug Mode

Enable during development to catch common async bugs:

```python
# Detects: unawaited coroutines, slow callbacks (>100ms), blocking calls
asyncio.run(main(), debug=True)

# Or via environment variable
# PYTHONASYNCIODEBUG=1 python app.py
```

### Slow Callback Detection

The event loop logs warnings when a callback takes longer than the slow callback threshold (default 100ms in debug mode). Customize:

```python
loop = asyncio.get_running_loop()
loop.slow_callback_duration = 0.05  # Warn at 50ms
```

### Task Monitoring

```python
# Count active tasks (detect leaks)
active = len(asyncio.all_tasks())
logger.info("Active async tasks: %d", active)

# Name tasks for debugging
task = asyncio.create_task(fetch(url), name=f"fetch-{url}")
# Shows in tracebacks and asyncio.all_tasks()
```

### Structured Logging in Async Context

```python
import contextvars

request_id: contextvars.ContextVar[str] = contextvars.ContextVar("request_id")

async def handle_request(req_id: str) -> None:
    request_id.set(req_id)
    # to_thread automatically propagates this context var
    await asyncio.to_thread(sync_helper)
```

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Blocking the Event Loop

**You will be tempted to:** Call `time.sleep()`, `requests.get()`, `open().read()`, or any synchronous I/O directly in an async function because "it's just one quick call."

**Why that fails:** The event loop is single-threaded. ONE blocking call freezes ALL concurrent tasks. A 200ms `requests.get()` in a server handling 1000 connections stalls every one of them.

**The right way:** Use `await asyncio.sleep()`, `httpx.AsyncClient`, `aiofiles.open()`. For unavoidable sync code, wrap in `asyncio.to_thread()` or `run_in_executor()`.

### BAD:
```python
async def get_data(url: str) -> str:
    import requests
    return requests.get(url).text  # Blocks entire event loop
```

### GOOD:
```python
async def get_data(url: str) -> str:
    async with httpx.AsyncClient() as client:
        resp = await client.get(url)
        return resp.text
```

---

### Rule 2: Swallowing CancelledError

**You will be tempted to:** Catch `CancelledError` (or bare `except Exception`) and suppress it to "keep the task alive" or "handle it gracefully."

**Why that fails:** `CancelledError` is the mechanism TaskGroup and shutdown use to propagate cancellation. Swallowing it creates zombie tasks that ignore cancel requests, leading to deadlocks on shutdown and resource leaks.

**The right way:** Catch `CancelledError` ONLY for cleanup, then **always re-raise**.

### BAD:
```python
async def worker() -> None:
    try:
        await do_work()
    except asyncio.CancelledError:
        logger.info("Cancelled, continuing anyway")
        # Swallowed -- task becomes unkillable zombie
```

### GOOD:
```python
async def worker() -> None:
    try:
        await do_work()
    except asyncio.CancelledError:
        await cleanup_resources()
        raise  # Always re-raise
```

---

### Rule 3: Unbounded Task Creation

**You will be tempted to:** Spawn `create_task()` in a loop over thousands of items because "async handles concurrency."

**Why that fails:** Each task consumes memory and scheduler time. 100K tasks hammering an API simultaneously causes OOM, rate-limit bans, and connection pool exhaustion. "Async" is not "infinite."

**The right way:** Use `asyncio.BoundedSemaphore(N)` to cap concurrency, or `asyncio.Queue(maxsize=N)` for producer/consumer patterns.

### BAD:
```python
async def fetch_all(urls: list[str]) -> None:
    async with asyncio.TaskGroup() as tg:
        for url in urls:  # 50,000 URLs = 50,000 simultaneous connections
            tg.create_task(fetch(url))
```

### GOOD:
```python
async def fetch_all(urls: list[str], max_concurrent: int = 50) -> None:
    sem = asyncio.BoundedSemaphore(max_concurrent)
    async with asyncio.TaskGroup() as tg:
        for url in urls:
            tg.create_task(bounded_fetch(sem, url))
```

---

### Rule 4: Using gather When TaskGroup Is Available

**You will be tempted to:** Use `asyncio.gather()` because it returns results directly and "feels simpler."

**Why that fails:** gather without `return_exceptions=True` raises the first exception but leaves other tasks running as orphans. Even with `return_exceptions=True`, failed tasks keep executing -- wasting resources. gather provides no structured lifecycle guarantees.

**The right way:** Use `TaskGroup` on Python 3.11+. Access results via `task.result()` after the block. Use gather ONLY when you need `return_exceptions=True` semantics (all tasks must complete regardless of failures).

---

### Rule 5: Mixing Sync and Async Without Isolation

**You will be tempted to:** Call `asyncio.run()` from inside async code, or use `loop.run_until_complete()` in a thread that shares the event loop.

**Why that fails:** `asyncio.run()` creates a new event loop -- calling it inside a running loop raises `RuntimeError`. `run_until_complete()` on a shared loop from another thread is not thread-safe and causes race conditions.

**The right way:** Async-to-sync bridge: `asyncio.run()` at the top-level entry point ONLY. Sync-to-async bridge inside async: `asyncio.to_thread()` for blocking sync calls. Never nest event loops.
