---
name: mx-ts-node
description: Use when working with Node.js runtime features, file system operations, streams, process management, or environment configuration. Also use when the user mentions 'fs', 'readFile', 'readFileSync', 'stream', 'backpressure', 'graceful shutdown', 'SIGTERM', 'SIGINT', 'child_process', 'cluster', 'PM2', 'memory leak', 'environment variables', 'dotenv', '__dirname', 'process.cwd', 'worker threads', 'pipeline', 'createReadStream', 'createWriteStream', 'drain', 'process.exit', 'server.close', or 'http-terminator'.
---

# TypeScript Node.js Runtime -- Server Patterns for AI Coding Agents

**This skill loads for Node.js runtime work.** It prevents: sync fs in async contexts, ignoring stream backpressure, missing graceful shutdown, memory leaks from timers/listeners, and unvalidated environment variables.

## When to also load
- Async patterns (Promises, retry, p-limit) -> `mx-ts-async`
- Observability (Sentry, OpenTelemetry) -> `mx-ts-observability`
- Validation (Zod schemas beyond env) -> `mx-ts-validation`
- Build/config (tsconfig, bundlers) -> `mx-ts-project`

---

## Level 1: File System & Streams (Beginner)

### The Sync FS Rule

`readFileSync` blocks the ENTIRE event loop. No requests processed, no timers fire, no I/O completes.

| Context | Sync OK? | Use Instead |
|---------|----------|-------------|
| Startup config, SSL certs | Yes | `readFileSync` is fine here |
| CLI scripts (no server) | Yes | Sync is simpler, no event loop to block |
| Inside request handler | **NEVER** | `fs.promises.readFile` |
| Inside any async function | **NEVER** | `fs.promises.*` API |
| Large files (>10MB) anywhere | **NEVER** | `fs.createReadStream` |

```typescript
// BAD -- blocks event loop in a request handler
app.get('/report', (req, res) => {
  const data = fs.readFileSync('/data/report.csv', 'utf-8'); // ALL requests stall
  res.json(processReport(data));
});

// GOOD -- async, non-blocking
app.get('/report', async (req, res) => {
  const data = await fs.promises.readFile('/data/report.csv', 'utf-8');
  res.json(processReport(data));
});

// BEST -- streaming for large files
app.get('/report', (req, res) => {
  const stream = fs.createReadStream('/data/report.csv');
  stream.pipe(transformStream).pipe(res);
});
```

### File Path Resolution

`fs` resolves relative paths from `process.cwd()`, NOT from the script's directory. This breaks when the server is started from a different directory.

```typescript
// BAD -- breaks if cwd != script directory
const config = fs.readFileSync('./config.json');

// GOOD -- CommonJS: resolve relative to script location
import path from 'node:path';
const config = fs.readFileSync(path.join(__dirname, 'config.json'));

// GOOD -- ESM: resolve relative to module location
import { fileURLToPath } from 'node:url';
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const config = fs.readFileSync(path.join(__dirname, 'config.json'));

// GOOD -- path.resolve for absolute from fragments
const dataDir = path.resolve(process.env.DATA_DIR ?? './data');
```

**Always use `node:` prefix** for built-in modules (`node:fs`, `node:path`, `node:url`). Prevents name collision with npm packages.

### Streams and Backpressure

Streams process data in chunks (16KB default). A 512MB RAM server can handle 10GB files. But ONLY if you handle backpressure.

```typescript
// BAD -- ignores backpressure, memory grows unbounded
const readable = fs.createReadStream('huge.csv');
const writable = fs.createWriteStream('output.csv');

readable.on('data', (chunk) => {
  writable.write(chunk); // return value IGNORED -- buffer fills until OOM
});

// GOOD -- pipe() handles backpressure automatically
readable.pipe(writable);

// BEST -- pipeline() handles errors AND backpressure
import { pipeline } from 'node:stream/promises';

await pipeline(
  fs.createReadStream('huge.csv'),
  transformStream,
  fs.createWriteStream('output.csv')
);
// Automatically destroys all streams on error
```

**Why backpressure matters:** `writable.write()` returns `false` when its internal buffer is full. If you keep writing, Node buffers in memory. For fast reads + slow writes (network, disk), memory grows until the process crashes.

The `pipeline()` API (from `node:stream/promises`) is the correct way to compose streams. It:
- Connects backpressure between all streams
- Destroys all streams if any errors
- Returns a Promise (no callback hell)
- Replaces manual `.pipe()` + error handling

---

## Level 2: Process Lifecycle (Intermediate)

### Graceful Shutdown

Every production Node.js server MUST handle shutdown signals. Without it, Docker/K8s/PM2 kills the process mid-request.

**The sequence:**
1. Receive SIGTERM/SIGINT
2. Stop accepting new connections
3. Mark health check as unhealthy (503)
4. Drain in-flight requests
5. Close resources (DB, Redis, MQ)
6. Flush log buffers
7. Exit 0
8. Hard timeout kills if cleanup stalls

```typescript
import { createServer, type Server } from 'node:http';

function gracefulShutdown(server: Server, timeout = 30_000): void {
  let isShuttingDown = false;
  const connections = new Set<import('node:net').Socket>();
  server.on('connection', (s) => { connections.add(s); s.on('close', () => connections.delete(s)); });

  async function shutdown(signal: string): Promise<void> {
    if (isShuttingDown) return;
    isShuttingDown = true;
    console.log(`${signal} received. Shutting down...`);

    const forceExit = setTimeout(() => process.exit(1), timeout);
    forceExit.unref(); // Don't keep process alive for this timer

    server.close(); // Stop accepting new connections
    for (const s of connections) {
      if (!(s as any)._httpMessage) s.destroy(); // Kill idle keep-alive
    }
    // Close resources: await db.end(); await redis.quit();
    clearTimeout(forceExit);
    process.exit(0);
  }

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

const server = createServer(handler);
server.listen(3000);
gracefulShutdown(server, 30_000);
```

**Health check must return 503 during shutdown:**

```typescript
// BAD -- health check stays 200 during shutdown, load balancer keeps routing
app.get('/health', (req, res) => res.sendStatus(200));

// GOOD -- reflects actual state
let isShuttingDown = false;
app.get('/health', (req, res) => {
  res.sendStatus(isShuttingDown ? 503 : 200);
});
```

**Platform-specific notes:**

| Platform | Signal | Grace Period | Config |
|----------|--------|-------------|--------|
| Docker | SIGTERM | 10s default | `stop_grace_period: 30s` |
| Kubernetes | SIGTERM | 30s default | `terminationGracePeriodSeconds: 30` |
| PM2 | SIGTERM | 1600ms default (too short!) | `kill_timeout: 10000` |
| systemd | SIGTERM | 90s default | `TimeoutStopSec=30` |

**Also handle `uncaughtException` and `unhandledRejection`** -- attempt graceful shutdown, then `process.exit(1)`. These are last-resort safety nets, not flow control.

### Environment Variable Validation

Never trust `process.env` raw. Validate at startup, fail fast.

```typescript
import { z } from 'zod';
import 'dotenv/config'; // Load .env FIRST

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'staging', 'production']).default('development'),
  PORT: z.preprocess((val) => Number(val), z.number().int().positive()).default(3000),
  DATABASE_URL: z.string().url(),
  REDIS_URL: z.string().url().optional(),
  API_KEY: z.string().min(1),
  LOG_LEVEL: z.enum(['debug', 'info', 'warn', 'error']).default('info'),
});

// Validate and export typed config
const parsed = envSchema.safeParse(process.env);
if (!parsed.success) {
  console.error('Invalid environment variables:');
  console.error(parsed.error.flatten().fieldErrors);
  process.exit(1); // Fail LOUD at startup, not silently at runtime
}

export const env = parsed.data;
// env.PORT is number (not string)
// env.NODE_ENV is 'development' | 'staging' | 'production' (not string)
```

**Rules:**
- Import this config module FIRST, before any application code
- `.env` is NEVER committed to version control. `.env.example` IS committed.
- NEVER log `API_KEY`, `DATABASE_URL`, or any secret -- even in development
- Production: use cloud secret managers (GCP Secret Manager, AWS Secrets Manager), not `.env` files
- Use `z.preprocess` for string-to-number coercion (all env vars are strings)

### Custom Error Hierarchy

```typescript
// BAD -- plain Error, no structure
throw new Error('user not found');

// GOOD -- structured, operational errors with status codes
abstract class AppError extends Error {
  abstract readonly statusCode: number;
  abstract readonly isOperational: boolean; // true = expected, false = bug
}

class NotFoundError extends AppError {
  readonly statusCode = 404;
  readonly isOperational = true;
  constructor(resource: string, id: string) {
    super(`${resource} ${id} not found`);
    this.name = 'NotFoundError';
  }
}

class ValidationError extends AppError {
  readonly statusCode = 400;
  readonly isOperational = true;
  constructor(message: string, public readonly fields: Record<string, string[]>) {
    super(message);
    this.name = 'ValidationError';
  }
}
```

### Result Type for Business Logic

Reserve `throw` for truly unexpected bugs. Use `Result` for expected failures:

```typescript
type Result<T, E = Error> =
  | { success: true; data: T }
  | { success: false; error: E };

function ok<T>(data: T): Result<T, never> {
  return { success: true, data };
}

function err<E>(error: E): Result<never, E> {
  return { success: false, error };
}

// Usage -- failure is explicit in the return type
async function findUser(id: string): Promise<Result<User, NotFoundError>> {
  const row = await db.query('SELECT * FROM users WHERE id = $1', [id]);
  if (!row) return err(new NotFoundError('user', id));
  return ok(mapToUser(row));
}

// Caller MUST handle both cases -- TypeScript enforces it
const result = await findUser('123');
if (!result.success) {
  return res.status(result.error.statusCode).json({ error: result.error.message });
}
const user = result.data; // TypeScript knows this is User
```

---

## Level 3: Production Patterns (Advanced)

### Memory Leak Sources and Prevention

| Leak Source | How It Happens | Prevention |
|-------------|----------------|------------|
| Forgotten timers | `setInterval` never cleared | Store ref, clear in shutdown |
| Stale event listeners | `.on()` without `.off()` | `AbortSignal`, `once()`, cleanup in `finally` |
| Global caches | Unbounded `Map`/`Set` | LRU eviction (`lru-cache` package), `WeakRef` |
| Closures over large data | Callback holds reference to large object | Null references after use, extract needed fields |
| Unreleased streams | Readable created but never consumed | Always `.destroy()` unused streams |

```typescript
// BAD -- interval leaks if connection closes
ws.on('message', () => {
  setInterval(() => sendHeartbeat(ws), 5000); // Never cleared!
});

// GOOD -- clear on disconnect
ws.on('message', () => {
  const heartbeat = setInterval(() => sendHeartbeat(ws), 5000);
  ws.on('close', () => clearInterval(heartbeat));
});

// BAD -- listener accumulates on every request
app.get('/stream', (req, res) => {
  eventBus.on('update', (data) => res.write(data)); // Never removed!
});

// GOOD -- use AbortSignal for automatic cleanup
app.get('/stream', (req, res) => {
  const controller = new AbortController();
  eventBus.on('update', (data) => res.write(data), { signal: controller.signal });
  req.on('close', () => controller.abort());
});
```

**Monitor with `process.memoryUsage()`** on a 30s interval. Watch `heapUsed` -- steady growth without GC drops = leak.

### child_process Decision Tree

| Need | Use | Why |
|------|-----|-----|
| Simple command, small output | `execFile()` | Buffered, no shell, safe |
| Long-running process, streaming output | `spawn()` | Streams stdout/stderr, no buffer limit |
| Shell features (pipes, globs, &&) | `exec()` | Spawns shell -- **NEVER with user input** |
| New Node.js worker with IPC | `fork()` | Built-in `process.send()`/`process.on('message')` |
| CPU-heavy in same process | `worker_threads` | Shared memory, no serialization overhead |

```typescript
import { spawn, execFile } from 'node:child_process';

// BAD -- shell injection risk
import { exec } from 'node:child_process';
exec(`grep ${userInput} /var/log/app.log`); // userInput = "; rm -rf /"

// GOOD -- no shell, arguments are separate
const child = spawn('grep', [userInput, '/var/log/app.log']);

// GOOD -- execFile for simple buffered results (no shell)
execFile('git', ['log', '--oneline', '-10'], (err, stdout) => {
  if (err) throw err;
  console.log(stdout);
});
```

### Cluster Mode and PM2

Node.js is single-threaded. Use PM2 for multi-core utilization instead of manual cluster code:

```javascript
// ecosystem.config.js
module.exports = {
  apps: [{
    name: 'api',
    script: './dist/server.js',   // Compiled JS, NOT .ts
    instances: 'max',             // One per CPU core
    exec_mode: 'cluster',
    kill_timeout: 10_000,         // 10s grace (default 1600ms is too short)
    wait_ready: true,             // Wait for process.send('ready')
    listen_timeout: 10_000,
    env_production: {
      NODE_ENV: 'production',
    },
  }],
};
```

**PM2 + TypeScript:** Always compile to JS first. Running `ts-node` under PM2 cluster mode causes issues. Use `tsc && pm2 start dist/server.js`.

**PM2 in Docker:** Use `pm2-runtime` (not `pm2 start`). `pm2-runtime` keeps the process in foreground so Docker can track it.

---

## Performance: Make It Fast

| Pattern | When | Improvement |
|---------|------|-------------|
| `createReadStream` over `readFile` | Files > 10MB | Constant memory vs linear growth |
| `pipeline()` over `.pipe()` | Any stream composition | Auto error handling + cleanup |
| Cluster mode / PM2 `instances: max` | CPU-bound work | Linear scaling with cores |
| `worker_threads` | CPU-heavy in request path | Offload without IPC serialization |
| `Buffer.allocUnsafe()` | Known-size buffers you fill immediately | Skip zero-fill (measurable in tight loops) |
| Streaming JSON (`JSONStream`, `stream-json`) | Parsing large JSON | Avoid `JSON.parse` on 100MB+ strings |

---

## Observability: Know It's Working

### Health Probes

```typescript
app.get('/healthz', (req, res) => {
  // Liveness: am I running?
  res.sendStatus(isShuttingDown ? 503 : 200);
});

app.get('/readyz', async (req, res) => {
  // Readiness: can I handle traffic?
  try {
    await db.query('SELECT 1');        // DB alive?
    await redis.ping();                // Cache alive?
    res.sendStatus(isShuttingDown ? 503 : 200);
  } catch {
    res.sendStatus(503);
  }
});
```

### Key Metrics to Expose

| Metric | Source | Why |
|--------|--------|-----|
| `heapUsed` / `rss` | `process.memoryUsage()` | Detect memory leaks |
| Event loop lag | `perf_hooks` or `prom-client` | Detect blocking operations |
| Active handles/requests | `process._getActiveHandles().length` | Detect resource leaks |
| Uptime | `process.uptime()` | Detect silent restarts |

Use `pm2 monit` for real-time CPU/memory per worker, `pm2 logs` for aggregated cluster logs.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Sync FS in Async Contexts

**You will be tempted to:** Use `readFileSync` in a request handler because "the file is small" or "it's just one read."
**Why that fails:** Under 100 concurrent requests, even a 1ms sync read blocks ALL of them sequentially. At scale, "small" files cause P99 latency spikes that are invisible in dev but catastrophic in production.
**The right way:** `fs.promises.readFile` for small files, `fs.createReadStream` for large ones. Sync is ONLY for startup code.

### Rule 2: No Ignoring Stream Backpressure

**You will be tempted to:** Call `writable.write(chunk)` in a loop without checking the return value because "the writes are fast enough."
**Why that fails:** Fast producer + slow consumer = unbounded memory growth. The process OOMs under load. This is the #1 cause of Node.js memory crashes in data pipelines.
**The right way:** Use `pipeline()` from `node:stream/promises`. It handles backpressure, error propagation, and cleanup automatically. Never manually wire `.on('data')` + `.write()`.

### Rule 3: No Skipping Graceful Shutdown

**You will be tempted to:** Skip shutdown handling because "Docker will just restart it" or "it's a dev server."
**Why that fails:** Without graceful shutdown, in-flight requests get 502s, database connections leak, and data corruption occurs on write-heavy services. K8s sends SIGTERM 30s before SIGKILL -- that 30s is yours to use.
**The right way:** Implement the full shutdown sequence: stop accepting, drain connections, close resources, hard timeout. Use `http-terminator` for robust keep-alive connection handling.

### Rule 4: No Raw process.env Access

**You will be tempted to:** Read `process.env.PORT` directly because "I'll validate it later."
**Why that fails:** `process.env.PORT` is `string | undefined`. Using it without validation causes runtime type errors deep in the call stack. "Later" never comes. One missing env var in production = 3am incident.
**The right way:** Zod schema at startup, export typed `env` object. All code imports from the config module. Fail at boot, not at 2am.

### Rule 5: No Fire-and-Forget Timers and Listeners

**You will be tempted to:** Call `setInterval` or `emitter.on()` without storing a cleanup reference because "the connection will close eventually."
**Why that fails:** Each reconnection/request adds another listener. After 1000 connections, there are 1000 orphaned intervals or listeners. Memory grows linearly until OOM. Node.js warns at 11 listeners but most code ignores the warning.
**The right way:** Store every timer/listener reference. Clean up in `finally`, `close`, or `AbortSignal`. Use `emitter.once()` when you only need one event. Set `emitter.setMaxListeners()` only when you genuinely need many -- never to silence the warning.
