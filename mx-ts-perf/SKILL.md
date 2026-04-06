---
name: mx-ts-perf
description: Use when writing any TypeScript code. Co-loads with mx-ts-core by default. TypeScript performance — profiling CPU or memory, analyzing bundles, benchmarking, clinic.js, V8 internals, event loop lag, Map vs object, WeakRef, code splitting, deoptimization, hidden classes, inline caching, tree shaking, bundle size, tinybench, max-old-space-size. Also use when the user mentions 'performance', 'slow', 'optimize', 'profile', 'flame graph', 'heap snapshot', or any TypeScript/Node.js performance work.
---

# TypeScript Performance — Profiling & Optimization for AI Coding Agents

**This skill co-loads with mx-ts-core for ANY TypeScript work.** It prevents: guessing instead of profiling, naive algorithms on hot paths, ignoring event loop pressure, dead benchmarks with the archived benchmark.js, and shipping bundles nobody measured.

## When to also load
- Async patterns (streams, concurrency limits) -> `mx-ts-async`
- Node.js runtime (cluster, worker threads, child_process) -> `mx-ts-node`
- Project config (tsconfig, ESM/CJS, bundler) -> `mx-ts-project`
- Core types (strict mode, discriminated unions) -> `mx-ts-core`

---

## Profiling Tool Decision Tree

| Symptom | First Tool | What It Shows |
|---------|-----------|---------------|
| "It's slow" (unknown cause) | `clinic doctor` | Categorizes bottleneck: CPU, I/O, event loop, or memory |
| CPU-bound hot functions | `clinic flame` or `0x` | Flame graph — wider bars = more CPU time |
| Memory growing over time | `clinic heap` | Memory allocation flame graph — identifies leak sources |
| Async operations stalling | `clinic bubbleprof` | Async operation visualization and delays |
| Need interactive debugging | `node --inspect` + Chrome DevTools | Performance tab (CPU), Memory tab (heap snapshots) |
| Production profiling (low overhead) | `clinic doctor` (1-3% CPU) | Safe for short production sessions |

**Always start with `clinic doctor`.** It triages the problem type before you go deep.

---

## Level 1: Profile First (Beginner)

### The Profiling Workflow

Never optimize without evidence. This is the workflow:

```
1. clinic doctor -- node server.js     # Triage: what category?
2. Based on result:
   CPU    -> clinic flame -- node server.js   # Flame graph
   Memory -> clinic heap -- node server.js    # Allocation tracking
   I/O    -> clinic bubbleprof -- node server.js
3. Read the output. Identify the hot function / leak source.
4. Fix the SPECIFIC function. Re-profile to confirm improvement.
```

### Installing Clinic.js

```bash
npm install -g clinic    # Installs doctor, flame, heap, bubbleprof
npx clinic doctor -- node dist/server.js
```

### Reading Flame Graphs

```
Wide bar = function spending lots of CPU time
Narrow bar = function that is fast
Stack grows UP = caller is below, callee is above
Plateau (flat top) = leaf function doing actual work

Reading strategy:
1. Look for the WIDEST bars at the TOP — those are the bottlenecks
2. Follow the stack DOWN to find what called them
3. Ignore narrow spikes — they are fast and irrelevant
4. Color coding: hot (red/orange) = self-time, cool (blue) = mostly calling children
```

### Chrome DevTools Profiling

```bash
# Start with inspector
node --inspect dist/server.js

# Open in Chrome
# Navigate to chrome://inspect -> click "inspect" under your process
# Performance tab -> Record -> reproduce the slow behavior -> Stop
# Memory tab -> Take Heap Snapshot -> reproduce -> Take another -> Compare
```

### Heap Snapshot Comparison (Memory Leaks)

```
1. Take Snapshot A (baseline)
2. Reproduce the suspected leak (run requests, process data)
3. Force GC (click trash can icon in DevTools Memory tab)
4. Take Snapshot B
5. Select "Comparison" view between A and B
6. Sort by "Delta" — objects with growing count are leak candidates
7. Look at "Retainers" to see what is holding the reference
```

---

## Level 2: V8 Internals & Data Structures (Intermediate)

### V8 Compilation Pipeline

```
Source code
  -> Ignition (interpreter — runs immediately, collects type feedback)
  -> Sparkplug (baseline compiler — faster than interpreter, no optimization)
  -> TurboFan (optimizing compiler — uses type feedback for speculative optimization)
  -> [Deoptimization] (back to Ignition if assumptions wrong)
```

Hot functions get promoted to TurboFan. TurboFan relies on **stable types** to generate fast machine code. When types change, TurboFan deoptimizes back to Ignition — this is expensive and shows up as jank.

### Hidden Classes (Maps in V8)

V8 assigns an internal "hidden class" (called a Map) to every object based on its shape (property names, order, types).

```typescript
// BAD — different property order = different hidden class
const a = { x: 1, y: 2 };
const b = { y: 2, x: 1 };  // Different hidden class than a!

// BAD — adding properties after construction
const obj: Record<string, number> = {};
obj.x = 1;  // Transition to new hidden class
obj.y = 2;  // Transition to ANOTHER hidden class

// GOOD — consistent shape, same property order, all properties upfront
interface Point { x: number; y: number }
function createPoint(x: number, y: number): Point {
  return { x, y };  // Always same hidden class
}
```

**Why this matters:** When V8 sees the same hidden class at a call site repeatedly (monomorphic), it uses an inline cache for near-instant property access. Different hidden classes at the same call site (polymorphic/megamorphic) force slow dictionary lookups.

### Inline Caching States

| State | Hidden Classes Seen | Speed | What Happens |
|-------|-------------------|-------|--------------|
| Monomorphic | 1 | Fastest | Direct memory offset lookup |
| Polymorphic | 2-4 | Slower | Linear search through cache entries |
| Megamorphic | 5+ | Slowest | Full dictionary lookup every time |

```typescript
// BAD — megamorphic: function receives many different shapes
function getArea(shape: any) {
  return shape.width * shape.height;  // Different hidden class per call
}
getArea({ width: 1, height: 2 });
getArea({ width: 1, height: 2, color: "red" });
getArea({ height: 2, width: 1 });  // Different order!

// GOOD — monomorphic: discriminated union, each branch sees one shape
type Shape =
  | { kind: "rect"; width: number; height: number }
  | { kind: "circle"; radius: number };

function getArea(shape: Shape): number {
  switch (shape.kind) {
    case "rect": return shape.width * shape.height;   // One hidden class
    case "circle": return Math.PI * shape.radius ** 2; // One hidden class
  }
}
```

### Detecting Deoptimizations

```bash
# Run with deopt logging
node --trace-deopt dist/server.js 2>&1 | head -50

# Run with more detail on optimization
node --trace-opt --trace-deopt dist/server.js 2>&1 | grep -E "optimized|deoptimized"
```

Common deopt triggers:
- Changing object shape after creation (adding/deleting properties)
- Passing different types to the same function parameter
- `arguments` object (use rest params `...args` instead)
- `try/catch` in hot loops (V8 optimizes these now, but older patterns remain)
- `delete obj.prop` (use `obj.prop = undefined` or `Map` instead)

### Data Structure Decision Tree

| Scenario | Use | Why | NOT |
|----------|-----|-----|-----|
| Frequent add/remove of keys | `Map` | O(1) ops, no hidden class churn, no prototype pollution | Plain object |
| Fixed config/constants | Plain object | Faster initial creation, V8 optimizes well for static shapes | Map |
| Checking membership in a list | `Set` | O(1) `.has()` | `Array.includes()` = O(n) |
| Unique values from an array | `new Set(arr)` | Single pass deduplication | `filter` + `indexOf` = O(n^2) |
| Key-value where keys are objects | `Map` | Objects as keys (reference equality) | Plain object (keys become strings) |
| Cache that should not prevent GC | `WeakMap` / `WeakRef` | Keys/values are garbage-collected when no other reference exists | Map (leaks memory) |
| Counting unique occurrences | `Map<string, number>` | Increment `.get()` + `.set()` | Object with bracket access |

### WeakRef for Self-Cleaning Caches

```typescript
// BAD — Map cache leaks memory forever
const cache = new Map<string, ExpensiveObject>();

// GOOD — WeakRef cache: entries auto-cleaned when objects are GC'd
const cache = new Map<string, WeakRef<ExpensiveObject>>();

function getCached(key: string): ExpensiveObject {
  const ref = cache.get(key);
  const obj = ref?.deref();
  if (obj) return obj;

  const newObj = computeExpensive(key);
  cache.set(key, new WeakRef(newObj));
  return newObj;
}

// Optional: FinalizationRegistry to clean up stale Map entries
const registry = new FinalizationRegistry<string>((key) => {
  // Only delete if the WeakRef is actually dead
  const ref = cache.get(key);
  if (ref && !ref.deref()) cache.delete(key);
});

function getCachedWithCleanup(key: string): ExpensiveObject {
  const ref = cache.get(key);
  const obj = ref?.deref();
  if (obj) return obj;

  const newObj = computeExpensive(key);
  cache.set(key, new WeakRef(newObj));
  registry.register(newObj, key);  // Clean Map entry when newObj is GC'd
  return newObj;
}
```

**Warning:** `FinalizationRegistry` callbacks are not guaranteed to run (GC timing is unpredictable). Never use them for critical cleanup logic. They are a best-effort optimization to reclaim Map entry slots.

---

## Level 3: Benchmarking & Bundle Analysis (Advanced)

### Benchmarking Tool Selection

| Tool | Best For | Key Feature |
|------|----------|-------------|
| `tinybench` | General benchmarking | Lightweight, statistical output, actively maintained |
| `bench-node` | V8-aware benchmarks | Prevents JIT optimization of benchmark code |
| `mitata` | Speed | Used by Bun/Deno teams, fast iteration |
| `iso-bench` | Isolation | Each benchmark in separate process |

**`benchmark.js` is archived (April 2024). Do not use it.** Any existing code using benchmark.js should be migrated to tinybench.

### tinybench Example

```typescript
import { Bench } from "tinybench";

const bench = new Bench({ warmup: true, iterations: 100 });

bench
  .add("Map lookup", () => {
    const m = new Map([["key", "value"]]);
    const result = m.get("key");
    return result;  // MUST use the result to prevent dead-code elimination
  })
  .add("Object lookup", () => {
    const o = { key: "value" };
    const result = o.key;
    return result;  // MUST use the result
  });

await bench.run();
console.table(bench.table());
```

### Benchmarking Methodology — The Rules

| Rule | Why |
|------|-----|
| **Always return/use benchmark results** | V8 eliminates dead code — if you do not use the result, V8 removes the computation entirely |
| **Warm up: 30-120s before measuring** | TurboFan needs time to optimize hot functions. Cold measurements test the interpreter, not production code |
| **Process isolation per benchmark** | JIT optimizations from one benchmark pollute the next. Use separate `node` processes or `iso-bench` |
| **Run 30+ iterations minimum** | Statistical significance requires samples. Report mean, stddev, and p95 |
| **Minimize environmental noise** | Close other apps, disable CPU frequency scaling if possible, use consistent hardware |
| **Measure the right metric** | ops/sec is not enough. Also capture: latency percentiles (p50/p95/p99), memory RSS, event loop lag, GC pauses |
| **Do not interpolate from microbenchmarks** | A function 2x faster in isolation may be identical in production due to memory access patterns and cache effects |

### V8 JIT Pitfalls in Benchmarks

```typescript
// BAD — V8 may optimize away the entire loop (dead code elimination)
for (let i = 0; i < 1_000_000; i++) {
  fibonacci(30);  // Result unused — V8 can remove this
}

// BAD — V8 inlines and constant-folds known inputs
const result = fibonacci(30);  // Input is constant — V8 pre-computes

// GOOD — use dynamic input and consume the result
const inputs = Array.from({ length: 1000 }, () => Math.floor(Math.random() * 30));
let sink = 0;
for (const n of inputs) {
  sink += fibonacci(n);  // Dynamic input, result accumulated
}
console.log(sink);  // Force V8 to keep the computation
```

### Tree Shaking Rules

Tree shaking removes unused code at build time. It requires ES module syntax and static analysis.

| Rule | Details |
|------|---------|
| Use ESM (`import`/`export`) throughout | CommonJS `require()` is not statically analyzable |
| Set `"sideEffects": false` in package.json | Tells bundler all modules are safe to tree-shake |
| Protect files with real side effects | `"sideEffects": ["*.css", "./src/polyfills.ts"]` |
| Avoid barrel exports (`index.ts`) | Re-exporting everything defeats tree shaking. Import directly from source |
| Use `module: "ESNext"` in tsconfig | Preserve ESM syntax for the bundler to analyze |
| Enable production mode in bundler | Tree shaking only activates in production builds |

```typescript
// BAD — barrel import pulls in the ENTIRE module
import { Button } from "./components";  // components/index.ts re-exports everything

// GOOD — direct import, only Button code is included
import { Button } from "./components/Button";
```

### Bundle Analysis Tools

| Tool | What It Shows | Command |
|------|--------------|---------|
| `webpack-bundle-analyzer` | Interactive treemap: parsed, gzipped, original sizes | `npx webpack --profile --json > stats.json && npx webpack-bundle-analyzer stats.json` |
| `source-map-explorer` | Granular source-level size breakdown from source maps | `npx source-map-explorer dist/bundle.js` |
| `vite-bundle-visualizer` | Rollup-based treemap for Vite projects | `npx vite-bundle-visualizer` |
| `bundlephobia.com` | Check npm package size BEFORE installing | Browser: bundlephobia.com/package/lodash |

### Code Splitting

```typescript
// Static import — included in main bundle always
import { HeavyChart } from "./HeavyChart";

// Dynamic import — loaded on demand, creates separate chunk
const HeavyChart = await import("./HeavyChart");

// React lazy loading
const HeavyChart = React.lazy(() => import("./HeavyChart"));
function Dashboard() {
  return (
    <Suspense fallback={<Spinner />}>
      <HeavyChart />
    </Suspense>
  );
}
```

**Split boundaries:** Route-level splitting is the highest impact. Then split large libraries used on specific pages. Do not over-split — each chunk has HTTP overhead.

---

## Performance: Make It Fast

This IS the performance skill. The optimization decision tree:

| Step | Action | Tool |
|------|--------|------|
| 1 | **Measure first** | `clinic doctor` to categorize |
| 2 | **Profile the specific bottleneck** | `clinic flame` (CPU) / `clinic heap` (memory) / Chrome DevTools |
| 3 | **Check data structures on hot paths** | `Map` over object for dynamic keys, `Set` over `Array.includes()` |
| 4 | **Check object shape consistency** | Monomorphic call sites, consistent property order, no runtime `delete` |
| 5 | **Check async pressure** | Event loop lag, uncontrolled parallelism, missing backpressure |
| 6 | **Check bundle size** (client-side) | `webpack-bundle-analyzer`, tree shaking rules, code splitting |
| 7 | **Benchmark the fix** | `tinybench` with proper methodology, compare before/after |
| 8 | **Verify in production-like conditions** | Load test, not microbenchmark |

---

## Observability: Know It's Working

### Event Loop Lag Monitoring

```typescript
import { monitorEventLoopDelay } from "node:perf_hooks";

const h = monitorEventLoopDelay({ resolution: 20 }); // 20ms sampling
h.enable();

setInterval(() => {
  console.log({
    min: h.min / 1e6,    // Convert nanoseconds to ms
    max: h.max / 1e6,
    mean: h.mean / 1e6,
    p99: h.percentile(99) / 1e6,
  });
  h.reset();
}, 5000);
```

**Healthy:** p99 < 50ms. **Warning:** p99 50-100ms. **Critical:** p99 > 100ms — something is blocking the event loop.

### Memory Monitoring

```typescript
// Programmatic memory check
const mem = process.memoryUsage();
console.log({
  heapUsed: `${(mem.heapUsed / 1024 / 1024).toFixed(1)} MB`,
  heapTotal: `${(mem.heapTotal / 1024 / 1024).toFixed(1)} MB`,
  rss: `${(mem.rss / 1024 / 1024).toFixed(1)} MB`,
  external: `${(mem.external / 1024 / 1024).toFixed(1)} MB`,
});

// Increase heap for memory-intensive apps
// node --max-old-space-size=4096 dist/server.js  (4 GB)
```

| Metric | What It Means |
|--------|--------------|
| `heapUsed` | Actual memory used by JS objects |
| `heapTotal` | Total heap allocated by V8 (includes unused allocated space) |
| `rss` | Resident Set Size — total process memory including native allocations |
| `external` | Memory for C++ objects bound to JS (Buffers, etc.) |

**Leak signal:** `heapUsed` growing monotonically across GC cycles. If it grows and never drops, you have a leak.

### Chunking Long CPU Work

```typescript
// BAD — blocks event loop for entire computation
function processAll(items: string[]): string[] {
  return items.map(expensiveTransform);  // 10,000 items = event loop frozen
}

// GOOD — yield to event loop between chunks
async function processAllChunked(items: string[], chunkSize = 100): Promise<string[]> {
  const results: string[] = [];
  for (let i = 0; i < items.length; i += chunkSize) {
    const chunk = items.slice(i, i + chunkSize);
    results.push(...chunk.map(expensiveTransform));
    await new Promise((resolve) => setImmediate(resolve)); // Yield to event loop
  }
  return results;
}
```

For truly CPU-heavy work (>100ms per operation), use Worker Threads (see `mx-ts-node`).

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Optimization Without Profiling

**You will be tempted to:** Rewrite a function because it "looks slow" or uses a pattern you read is inefficient.
**Why that fails:** Intuition about performance is wrong more often than right. V8 optimizes aggressively — the "slow-looking" code may be fast, and the "optimization" may trigger deoptimization. You waste time fixing the wrong function.
**The right way:** Run `clinic doctor` or attach Chrome DevTools. Profile the actual workload. Optimize ONLY the functions that show up as hot in the flame graph. If it is not in the flame graph, it is not the bottleneck.

### Rule 2: No benchmark.js

**You will be tempted to:** Use `benchmark.js` because it appears in old examples, Stack Overflow answers, and blog posts.
**Why that fails:** benchmark.js was archived in April 2024. It has known issues with V8 JIT interference, no ESM support, and unmaintained dependencies. Results from benchmark.js are unreliable.
**The right way:** Use `tinybench` for general benchmarking, `bench-node` for V8-aware benchmarks, or `mitata` for speed. Always follow the methodology rules: warm up, isolate processes, use results, run 30+ iterations.

### Rule 3: No Bundle Ship Without Measurement

**You will be tempted to:** Ship a frontend build without checking bundle size because "the feature works" and "we use tree shaking."
**Why that fails:** Tree shaking is defeated by barrel exports, side effects, and CommonJS dependencies. A single `import { x } from "lodash"` can add 70KB. You do not know your bundle size until you measure it.
**The right way:** Run `webpack-bundle-analyzer` or `source-map-explorer` on every production build. Set a bundle size budget. Fail the build if it exceeds the budget. Check new dependencies on bundlephobia.com before installing.

### Rule 4: No `Array.includes()` on Hot Paths With Large Arrays

**You will be tempted to:** Use `arr.includes(value)` or `arr.indexOf(value) !== -1` in loops or frequently called functions because it reads cleanly and "the array is not that big."
**Why that fails:** `Array.includes()` is O(n). On an array of 10,000 items called 1,000 times, that is 10 million comparisons. A `Set` does it in 1,000 lookups.
**The right way:** If the array is checked more than once and has more than ~100 elements, convert to a `Set` once and use `set.has(value)`. Same applies to object key checks: use `Map` for dynamic key collections.

### Rule 5: No Ignoring Event Loop Lag

**You will be tempted to:** Skip event loop monitoring because "the server responds fine in development" and "we do not have that much traffic."
**Why that fails:** Event loop lag is invisible until it cascades. A single synchronous JSON parse of a 5MB payload blocks every concurrent request. In development with one user, you never see it. Under production load, tail latency explodes and health checks fail.
**The right way:** Add `monitorEventLoopDelay` from `node:perf_hooks` to every long-running Node.js process. Alert when p99 exceeds 100ms. When it fires, profile with `clinic doctor` to identify the blocking operation. For CPU-heavy work, chunk with `setImmediate` or offload to Worker Threads.
