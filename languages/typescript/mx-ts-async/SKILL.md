---
name: mx-ts-async
description: Use when writing async/await code, Promise chains, concurrent operations, or handling asynchronous errors. Also use when the user mentions 'async', 'await', 'Promise', 'Promise.all', 'Promise.allSettled', 'AbortController', 'worker threads', 'event loop', 'concurrent', 'parallel', 'waterfall', 'p-limit', 'for-await-of', or 'floating promise'.
---

# TypeScript Async/Promises — Concurrency Patterns for AI Coding Agents

**This skill loads for async/concurrent code.** It prevents: sequential awaits that should be parallel, unhandled promise rejections, forEach+async trap, missing cancellation, and event loop blocking.

## When to also load
- Node.js runtime patterns --> `mx-ts-node`
- Observability/monitoring --> `mx-ts-observability`
- Performance optimization --> `mx-ts-perf`

---

## Level 1: Async Fundamentals (Beginner)

### Waterfall Detection and Parallel Refactoring

The #1 AI mistake in async code: sequential `await` when operations are independent.

```typescript
// BAD — waterfall: each await waits for the previous one (3x latency)
async function loadDashboard(userId: string) {
  const user = await fetchUser(userId);        // 200ms
  const orders = await fetchOrders(userId);    // 300ms
  const prefs = await fetchPreferences(userId); // 100ms
  return { user, orders, prefs };              // Total: 600ms
}

// GOOD — parallel: all three run simultaneously (1x latency)
async function loadDashboard(userId: string) {
  const [user, orders, prefs] = await Promise.all([
    fetchUser(userId),        // 200ms
    fetchOrders(userId),      // 300ms
    fetchPreferences(userId), // 100ms
  ]);
  return { user, orders, prefs }; // Total: 300ms (slowest wins)
}
```

**Detection heuristic:** Two or more consecutive `await` statements where neither uses the result of the previous one. That is a waterfall. Refactor to `Promise.all()`.

**When sequential IS correct:** When call B depends on the result of call A:

```typescript
// This MUST be sequential — token depends on login result
const token = await login(credentials);
const profile = await fetchProfile(token);
```

### The forEach + async Trap

`Array.forEach` does NOT await async callbacks. It fires all callbacks and returns immediately.

```typescript
// BAD — forEach ignores returned promises; errors vanish silently
const userIds = ['u1', 'u2', 'u3'];
userIds.forEach(async (id) => {
  await updateUser(id); // These run concurrently AND unhandled
});
console.log('Done'); // Logs BEFORE any update completes

// GOOD — sequential: use for...of when order matters
for (const id of userIds) {
  await updateUser(id); // Each completes before next starts
}

// GOOD — parallel: use map + Promise.all when order doesn't matter
await Promise.all(userIds.map((id) => updateUser(id)));
```

| Need | Pattern | When |
|------|---------|------|
| Sequential processing | `for...of` with `await` | Order matters, rate-sensitive APIs |
| Parallel processing | `Promise.all(items.map(...))` | Independent operations, speed matters |
| Controlled concurrency | `p-limit` + `map` | API rate limits, resource constraints |
| Never | `forEach` + `async` | Never. Not even once. |

### Forgetting `await` — Operating on Promise Objects

```typescript
// BAD — comparing a Promise object, not the resolved value
async function isAdmin(userId: string): Promise<boolean> {
  const user = fetchUser(userId); // Missing await!
  return user.role === 'admin';   // user is Promise<User>, not User
}

// GOOD
async function isAdmin(userId: string): Promise<boolean> {
  const user = await fetchUser(userId);
  return user.role === 'admin';
}
```

Enable `@typescript-eslint/no-floating-promises` to catch these at lint time.

---

## Level 2: Error Handling & Cancellation (Intermediate)

### Promise.all vs Promise.allSettled Decision Tree

| Question | Yes --> | No --> |
|----------|---------|--------|
| Must ALL succeed for the result to be useful? | `Promise.all` | Next question |
| Need partial results from a batch? | `Promise.allSettled` | Next question |
| Is one failure a fatal error? | `Promise.all` | `Promise.allSettled` |
| Processing user-uploaded files in bulk? | `Promise.allSettled` | Depends |
| Calling redundant replicas for fastest response? | `Promise.race` | -- |

```typescript
// Promise.all — fail-fast. First rejection rejects the whole batch.
try {
  const [users, orders] = await Promise.all([
    fetchUsers(),
    fetchOrders(),
  ]);
} catch (err) {
  // One failed — you don't know which without extra work
}

// Promise.allSettled — waits for ALL, never rejects.
const results = await Promise.allSettled([
  sendEmail(user1),
  sendEmail(user2),
  sendEmail(user3),
]);

const succeeded = results.filter(
  (r): r is PromiseFulfilledResult<string> => r.status === 'fulfilled'
);
const failed = results.filter(
  (r): r is PromiseRejectedResult => r.status === 'rejected'
);

if (failed.length > 0) {
  logger.warn(`${failed.length} emails failed`, {
    reasons: failed.map((f) => f.reason),
  });
}
```

**Rule of thumb:** `Promise.all` for "all-or-nothing" transactions. `Promise.allSettled` for "best-effort" batch operations where partial success is acceptable.

### AbortController — Cancellation and Timeouts

`AbortController` is the standard cancellation API. Use it for HTTP requests, long-running operations, and cleanup on unmount/shutdown.

```typescript
// Basic cancellation
const controller = new AbortController();

const response = await fetch('/api/data', {
  signal: controller.signal,
});

// Cancel from elsewhere
controller.abort();

// Distinguish cancellation from real errors
try {
  const data = await fetchWithSignal(controller.signal);
} catch (err) {
  if (err instanceof Error && err.name === 'AbortError') {
    // Cancellation — not a bug, don't log as error
    return;
  }
  throw err; // Real error — rethrow
}
```

**Timeout pattern** — auto-abort after N milliseconds:

```typescript
async function fetchWithTimeout(
  url: string,
  timeoutMs: number
): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort('Timeout'), timeoutMs);

  try {
    const response = await fetch(url, { signal: controller.signal });
    return response;
  } finally {
    clearTimeout(timeout); // Always clean up the timer
  }
}
```

**Custom abort reasons** — pass context to the error handler:

```typescript
controller.abort('User navigated away');
// In catch: error.name === 'AbortError', signal.reason === 'User navigated away'
```

**Node.js core support:** `fs`, `http`, `stream`, `child_process` all accept `AbortSignal`. Use it everywhere, not just `fetch`.

### No Floating Promises

A floating promise is a promise that is neither `await`ed, `.catch()`ed, nor stored.

```typescript
// BAD — floating promise: if it rejects, you get UnhandledPromiseRejection
sendAnalytics(event);

// GOOD — fire-and-forget with explicit error handling
sendAnalytics(event).catch((err) => {
  logger.warn('Analytics failed', { error: err });
});

// GOOD — void operator signals intentional fire-and-forget (with lint rule)
void sendAnalytics(event).catch(logError);
```

**ESLint config** that catches all floating promises:

```json
{
  "@typescript-eslint/no-floating-promises": "error",
  "@typescript-eslint/no-misused-promises": "error"
}
```

---

## Level 3: Concurrency & Workers (Advanced)

### p-limit for Concurrency Limiting

When you need to process N items but can only run M concurrently (API rate limits, DB connection pools, file descriptor limits).

```typescript
import pLimit from 'p-limit';

const limit = pLimit(5); // Max 5 concurrent operations

const urls: string[] = getUrls(); // Could be 1000+

const results = await Promise.all(
  urls.map((url) => limit(() => fetch(url).then((r) => r.json())))
);
```

**Concurrency limit guidelines:**

| Resource | Suggested Limit | Why |
|----------|----------------|-----|
| External API (no docs) | 5-10 | Avoid rate limiting |
| Database queries | 10-20 | Connection pool size |
| File I/O | 50-100 | OS file descriptor limits |
| CPU-bound (via workers) | `os.cpus().length` | One per core |

**Deadlock warning:** NEVER call a limited function inside another function using the same limiter.

```typescript
// BAD — deadlock: inner limit() can't acquire while outer holds a slot
const limit = pLimit(2);
await limit(async () => {
  await limit(async () => { /* stuck forever */ });
});
```

### Worker Threads for CPU-Bound Work

The event loop is single-threaded. CPU work blocks everything: HTTP servers stop responding, timers don't fire, other async operations stall.

```typescript
// BAD — blocks event loop for entire computation
app.get('/hash', async (req, res) => {
  const result = expensiveHash(req.body.data); // 2 seconds of CPU
  res.json({ result }); // All other requests wait 2 seconds
});

// GOOD — offload to worker thread
import { Worker } from 'worker_threads';

app.get('/hash', async (req, res) => {
  const result = await runInWorker('./hash-worker.js', req.body.data);
  res.json({ result });
});

function runInWorker(workerPath: string, data: unknown): Promise<string> {
  return new Promise((resolve, reject) => {
    const worker = new Worker(workerPath, { workerData: data });
    worker.on('message', resolve);
    worker.on('error', reject);
    worker.on('exit', (code) => {
      if (code !== 0) reject(new Error(`Worker exited with code ${code}`));
    });
  });
}
```

**Worker pool** — reuse workers instead of spawning per-request:

```typescript
// Use a pool library (workerpool, piscina) for production
import Piscina from 'piscina';

const pool = new Piscina({
  filename: './hash-worker.js',
  maxThreads: 4,
});

const result = await pool.run(data);
```

**TypeScript gotcha:** Worker `.ts` files must be compiled to `.js`. The `Worker` constructor takes a file path string, not an import. Use `tsx` or pre-compile.

### Async Generators and for-await-of

Async generators yield values asynchronously. All Node.js readable streams are async iterables.

```typescript
// Paginated API consumer
async function* fetchAllPages<T>(baseUrl: string): AsyncGenerator<T[]> {
  let page = 1;
  let hasMore = true;

  while (hasMore) {
    const response = await fetch(`${baseUrl}?page=${page}`);
    const data = await response.json();
    yield data.items;
    hasMore = data.hasNextPage;
    page++;
  }
}

// Consuming with for-await-of
for await (const batch of fetchAllPages<User>('/api/users')) {
  await processBatch(batch);
}
```

**Breaking out of `for-await-of` calls `return()` on the generator**, which triggers cleanup. Use `try/finally` in generators for resource cleanup:

```typescript
async function* streamWithCleanup(): AsyncGenerator<Buffer> {
  const conn = await openConnection();
  try {
    for await (const chunk of conn.stream()) {
      yield chunk;
    }
  } finally {
    await conn.close(); // Runs even if consumer breaks out early
  }
}
```

---

## Performance: Make It Fast

### Parallel by Default

Before writing any sequence of `await` statements, ask: **"Does call B depend on the result of call A?"**

- **No** --> `Promise.all([A(), B()])`
- **Yes** --> Sequential is correct
- **Partially** --> Group independent calls, then chain dependent ones

```typescript
// Mixed dependencies: user is independent, but orders need userId
const [user, config] = await Promise.all([
  fetchUser(id),
  fetchConfig(),
]);
// These depend on user result
const orders = await fetchOrders(user.accountId);
```

### setImmediate Chunking for Large Sync Loops

When you must process a large array synchronously (no async I/O), chunk it to avoid blocking the event loop:

```typescript
// BAD — blocks event loop for entire array
function processAll(items: Item[]): void {
  for (const item of items) {
    heavyComputation(item); // 10ms per item x 10000 items = 100 seconds blocked
  }
}

// GOOD — yield to event loop between chunks
async function processAllChunked(items: Item[], chunkSize = 100): Promise<void> {
  for (let i = 0; i < items.length; i += chunkSize) {
    const chunk = items.slice(i, i + chunkSize);
    for (const item of chunk) {
      heavyComputation(item);
    }
    // Yield to event loop — lets timers, I/O, and other tasks run
    await new Promise((resolve) => setImmediate(resolve));
  }
}
```

### Concurrency Limiter Selection

| Scenario | Tool | Install |
|----------|------|---------|
| Limit concurrent async ops | `p-limit` | `npm i p-limit` |
| Queue with priority/timing | `p-queue` | `npm i p-queue` |
| Rate limit (requests/sec) | Custom sliding window | Built-in |
| CPU parallelism | `piscina` / `workerpool` | `npm i piscina` |

---

## Observability: Know It's Working

### Event Loop Lag Monitoring

Detect when the event loop is blocked or lagging:

```typescript
// Quick detection — check event loop responsiveness
let lastCheck = process.hrtime.bigint();

setInterval(() => {
  const now = process.hrtime.bigint();
  const lagMs = Number(now - lastCheck) / 1_000_000 - 1000; // Expected 1000ms
  if (lagMs > 100) {
    logger.warn(`Event loop lag: ${lagMs.toFixed(0)}ms`);
  }
  lastCheck = now;
}, 1000);
```

**Production tools:**

| Tool | What It Does | When |
|------|-------------|------|
| `blocked-at` | Detects blocking with async stack traces | Dev/staging |
| `clinic doctor` | Full event loop health analysis | Profiling sessions |
| Sentry `eventLoopBlockIntegration` | Alerts on event loop stalls in prod | Always-on production |

```typescript
// Sentry event loop blocking detection
import * as Sentry from '@sentry/node';

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  integrations: [
    Sentry.eventLoopBlockIntegration({ threshold: 200 }), // Alert if blocked > 200ms
  ],
});
```

### Unhandled Rejection Safety Net

```typescript
process.on('unhandledRejection', (reason, promise) => {
  logger.error('Unhandled promise rejection', {
    reason: reason instanceof Error ? reason.message : String(reason),
    stack: reason instanceof Error ? reason.stack : undefined,
  });
  Sentry.captureException(reason);
});
```

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Sequential Awaits on Independent Operations

**You will be tempted to:** Write `const a = await X(); const b = await Y();` because "it's easier to read."
**Why that fails:** You just doubled (or tripled) the latency for no reason. Every user waits longer.
**The right way:** `const [a, b] = await Promise.all([X(), Y()])` when X and Y do not depend on each other.

### Rule 2: No forEach with async Callbacks

**You will be tempted to:** Use `items.forEach(async (item) => { await process(item); })` because "it looks clean."
**Why that fails:** `forEach` returns `void`. It does not await anything. All callbacks fire simultaneously and rejections are unhandled. You get silent data corruption.
**The right way:** `for...of` for sequential. `Promise.all(items.map(...))` for parallel.

### Rule 3: No Floating Promises

**You will be tempted to:** Call `sendEmail(user)` without `await` because "it's fire-and-forget."
**Why that fails:** If it rejects, you get `UnhandledPromiseRejection` which crashes Node.js in strict mode. Even in non-strict mode, the error disappears silently.
**The right way:** `await sendEmail(user)` or `sendEmail(user).catch(logError)`. Every promise must have an error handler.

### Rule 4: No CPU Work on the Event Loop

**You will be tempted to:** Run JSON parsing, crypto hashing, or data transformation directly in an async function because "it's just one call."
**Why that fails:** Even 50ms of CPU work blocks all concurrent requests. At 100 RPS, that means 100 requests queued behind your computation.
**The right way:** `worker_threads` for sustained CPU work. `setImmediate` chunking for large loops. If it takes > 10ms, offload it.

### Rule 5: No Promise.all Without Considering Failure Mode

**You will be tempted to:** Default to `Promise.all` everywhere because "it's the parallel one."
**Why that fails:** `Promise.all` is fail-fast. One rejection kills ALL results, even the ones that succeeded. For batch operations (sending emails, processing files), you lose everything because of one bad record.
**The right way:** Ask the decision tree question: "Is partial success acceptable?" If yes, `Promise.allSettled`. If no, `Promise.all` with proper error handling.
