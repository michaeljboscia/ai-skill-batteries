---
name: mx-ts-observability
description: Use when setting up logging, tracing, metrics, or monitoring in TypeScript Node.js applications. Also use when the user mentions 'logging', 'Pino', 'pino-http', 'pino-pretty', 'OpenTelemetry', 'OTel', 'tracing', 'metrics', 'Prometheus', 'prom-client', 'Sentry', 'health check', 'liveness', 'readiness', 'structured logging', 'observability', 'event loop lag', 'correlation ID', 'traceId', 'spanId', 'child logger', 'redaction', 'BatchSpanProcessor', 'NodeSDK', 'instrumentation.ts', 'collectDefaultMetrics', '/metrics endpoint', '/healthz', 'breadcrumb', 'how do I know it is working', or any monitoring/alerting setup for Node.js services.
---

# TypeScript Observability — Logging, Tracing & Metrics for AI Coding Agents

**This skill co-loads with mx-ts-core for ANY TypeScript work.** It prevents the most common AI failure: shipping code without logging, never setting up tracing, using `console.log` in production, and declaring work done without knowing if it is healthy.

## When to also load
- Core types/patterns -> `mx-ts-core`
- Async patterns -> `mx-ts-async`
- Node.js runtime -> `mx-ts-node`

---

## Level 1: Structured Logging with Pino (Beginner)

### Why Pino

Pino is the consensus structured logger for Node.js. 30x faster than Winston. Output is JSON by default — machine-readable for Elasticsearch, Loki, Graylog, Datadog. `pino-pretty` is dev-only. Never ship pretty-printing to production.

### Core Setup

```typescript
// src/logger.ts
import pino from "pino";

export const logger = pino({
  level: process.env.LOG_LEVEL ?? "info",
  redact: { paths: ["req.headers.authorization", "password", "ssn", "*.token"], censor: "[REDACTED]" },
  serializers: { err: pino.stdSerializers.err, req: pino.stdSerializers.req, res: pino.stdSerializers.res },
  formatters: { level: (label) => ({ level: label }) }, // String levels for observability tool interop
});
```

### Rule: Log Objects, Not Strings

```typescript
// BAD — unstructured, ungrepable, no context
logger.info("User 123 logged in from 192.168.1.1");
console.log(`Processing order ${orderId}`);

// GOOD — structured, queryable, context-rich
logger.info({ userId: 123, ip: "192.168.1.1", action: "login" }, "User logged in");
logger.info({ orderId, items: order.items.length }, "Processing order");
```

First argument is always a data object. Second argument is the human-readable message. This is backwards from Winston/Bunyan and AI agents get it wrong constantly.

### Child Loggers — Scoped Context

```typescript
// BAD — repeating context in every log call
logger.info({ module: "database", connId: 42 }, "Query started");
logger.info({ module: "database", connId: 42 }, "Query complete");

// GOOD — child logger carries context automatically
const dbLogger = logger.child({ module: "database", connId: 42 });
dbLogger.info("Query started");
dbLogger.info({ rows: 150, durationMs: 23 }, "Query complete");
```

Child loggers inherit parent context. Use them per-module, per-request, per-operation. Zero allocation overhead — Pino handles this efficiently.

### pino-http — Request/Response Middleware

```typescript
import pinoHttp from "pino-http";
import { randomUUID } from "node:crypto";
import { logger } from "./logger.js";

const httpLogger = pinoHttp({
  logger,
  genReqId: (req) => req.headers["x-request-id"] ?? randomUUID(),
  customLogLevel(_req, res, err) {
    if (res.statusCode >= 500 || err) return "error";
    if (res.statusCode >= 400) return "warn";
    return "info";
  },
});

// Express
app.use(httpLogger);

// Every downstream handler gets req.log — a child logger with requestId
app.get("/api/users", (req, res) => {
  req.log.info({ query: req.query }, "Fetching users");
  // ...
});
```

### Log Level Decision Table

| Environment | Level | Why |
|-------------|-------|-----|
| Local dev | `debug` or `trace` | Full visibility |
| CI/Test | `warn` | Reduce noise |
| Staging | `info` | Match prod shape |
| Production | `info` | Baseline. Never `debug` unless actively debugging. |
| Incident | `debug` (temporary) | Change via env var, never code change |

### pino-pretty — Dev Only

```bash
npm install -D pino-pretty
node dist/server.js | pino-pretty --colorize --translateTime
```

**Never** `import pino-pretty` in code. It is a CLI transport piped via stdout. Never in production Dockerfiles.

---

## Level 2: OpenTelemetry + Metrics (Intermediate)

### instrumentation.ts — Must Load First

The instrumentation file MUST load before any application code. Node.js v20+ required for `--import` flag.

```typescript
// src/instrumentation.ts
import { NodeSDK } from "@opentelemetry/sdk-node";
import { getNodeAutoInstrumentations } from "@opentelemetry/auto-instrumentations-node";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-proto";
import { BatchSpanProcessor, SimpleSpanProcessor } from "@opentelemetry/sdk-trace-base";
import { Resource } from "@opentelemetry/resources";
import { ATTR_SERVICE_NAME, ATTR_DEPLOYMENT_ENVIRONMENT_NAME } from "@opentelemetry/semantic-conventions";

const isProd = process.env.NODE_ENV === "production";

const exporter = new OTLPTraceExporter({
  url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT ?? "http://localhost:4318/v1/traces",
});

const sdk = new NodeSDK({
  resource: new Resource({
    [ATTR_SERVICE_NAME]: process.env.SERVICE_NAME ?? "my-service",
    [ATTR_DEPLOYMENT_ENVIRONMENT_NAME]: process.env.NODE_ENV ?? "development",
  }),
  // BatchSpanProcessor for prod (buffers + batches), SimpleSpanProcessor for dev (immediate)
  spanProcessor: isProd
    ? new BatchSpanProcessor(exporter)
    : new SimpleSpanProcessor(exporter),
  instrumentations: [
    getNodeAutoInstrumentations({
      // Disable noisy fs instrumentation
      "@opentelemetry/instrumentation-fs": { enabled: false },
    }),
  ],
});

sdk.start();

// Graceful shutdown — flush buffered spans on SIGTERM
process.on("SIGTERM", async () => {
  await sdk.shutdown();
  process.exit(0);
});
```

### Loading instrumentation — The --import Flag

```jsonc
// package.json — instrumentation MUST load before app code
{ "scripts": {
    "start": "node --import ./dist/instrumentation.js dist/server.js",
    "dev": "tsx --import ./src/instrumentation.ts src/server.ts"
} }
```

Without `--import`, auto-instrumentation misses modules imported before `sdk.start()`.

### Custom Spans for Business Logic

```typescript
import { trace, SpanStatusCode } from "@opentelemetry/api";

const tracer = trace.getTracer("order-service");

async function processOrder(orderId: string): Promise<void> {
  await tracer.startActiveSpan("processOrder", async (span) => {
    try {
      span.setAttribute("order.id", orderId);

      // Child spans auto-nest under parent via active context
      const shipping = await tracer.startActiveSpan("calculateShipping", async (child) => {
        const result = await calculateShipping(orderId);
        child.setAttribute("shipping.cost", result.cost);
        child.end();
        return result;
      });

      await chargePayment(orderId, shipping.cost);
      span.setStatus({ code: SpanStatusCode.OK });
    } catch (error) {
      span.recordException(error as Error);
      span.setStatus({ code: SpanStatusCode.ERROR, message: (error as Error).message });
      throw error;
    } finally {
      span.end();
    }
  });
}
```

### Pino + OTel Correlation

Inject `traceId` and `spanId` into every log line so logs are searchable by trace:

```typescript
import { context, trace } from "@opentelemetry/api";
import pino from "pino";

export const logger = pino({
  level: process.env.LOG_LEVEL ?? "info",
  mixin() {
    const span = trace.getSpan(context.active());
    if (span) {
      const { traceId, spanId } = span.spanContext();
      return { traceId, spanId };
    }
    return {};
  },
  redact: {
    paths: ["req.headers.authorization", "password", "*.token"],
    censor: "[REDACTED]",
  },
});
```

Now every log line includes `traceId` and `spanId`, correlating logs to traces in Grafana/Jaeger/Datadog.

### prom-client — Prometheus Metrics

```typescript
// src/metrics.ts
import { Registry, collectDefaultMetrics, Histogram, Counter } from "prom-client";

export const registry = new Registry();

// Default metrics: CPU, memory, event loop lag, GC stats
collectDefaultMetrics({ register: registry });

// Custom metrics
export const httpRequestDuration = new Histogram({
  name: "http_request_duration_seconds",
  help: "Duration of HTTP requests in seconds",
  labelNames: ["method", "route", "status_code"] as const,
  buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
  registers: [registry],
});

export const httpRequestsTotal = new Counter({
  name: "http_requests_total",
  help: "Total HTTP requests",
  labelNames: ["method", "route", "status_code"] as const,
  registers: [registry],
});
```

### /metrics Endpoint

```typescript
import express from "express";
import { registry } from "./metrics.js";

const app = express();

// Metrics endpoint — Prometheus scrapes this
app.get("/metrics", async (_req, res) => {
  res.setHeader("Content-Type", registry.contentType);
  res.send(await registry.metrics());
});
```

### Request Duration Middleware

```typescript
app.use((req, res, next) => {
  const end = httpRequestDuration.startTimer();
  res.on("finish", () => {
    const labels = { method: req.method, route: req.route?.path ?? req.path, status_code: String(res.statusCode) };
    end(labels);
    httpRequestsTotal.inc(labels);
  });
  next();
});
```

---

## Level 3: Production Observability (Advanced)

### Sentry Integration — Error Tracking + Performance

```typescript
// src/sentry.ts — MUST be imported first, before other modules
import * as Sentry from "@sentry/node";

Sentry.init({
  dsn: process.env.SENTRY_DSN, // Never hardcode
  environment: process.env.NODE_ENV,
  tracesSampleRate: process.env.NODE_ENV === "production" ? 0.1 : 1.0,
  // Auto-instruments HTTP, Express, database drivers
  integrations: [
    Sentry.httpIntegration(),
    Sentry.expressIntegration(),
  ],
});
```

### Sentry Breadcrumbs — Trail Before the Crash

```typescript
// BAD — error with zero context
throw new Error("Payment failed");

// GOOD — breadcrumbs build context trail
Sentry.addBreadcrumb({
  category: "payment",
  message: `Attempting charge for order ${orderId}`,
  level: "info",
  data: { orderId, amount, provider: "stripe" },
});

// If this throws, Sentry shows the breadcrumb trail
const result = await stripe.charges.create({ amount });
```

### Sentry Manual Spans

```typescript
// Sentry.startSpan wraps business logic with timing + error capture
const data = await Sentry.startSpan({ name: "enrichAccount", op: "function" }, async (span) => {
  span.setAttribute("account.id", accountId);
  return fetchEnrichmentData(accountId);
});
```

### Source Maps — Required for Readable Stack Traces

```json
// tsconfig.json
{
  "compilerOptions": {
    "sourceMap": true,
    "inlineSources": true
  }
}
```

Upload via CI:
```bash
npx sentry-cli sourcemaps inject ./dist
npx sentry-cli sourcemaps upload ./dist --release $GIT_SHA
```

### Event Loop Lag Monitoring

```typescript
import { monitorEventLoopDelay } from "node:perf_hooks";
import { Gauge } from "prom-client";

const eventLoopLag = new Gauge({ name: "nodejs_event_loop_lag_p99_ms", help: "Event loop lag p99 in ms", registers: [registry] });
const h = monitorEventLoopDelay({ resolution: 20 });
h.enable();

setInterval(() => { eventLoopLag.set(h.percentile(99) / 1e6); h.reset(); }, 5000);
```

**Alert threshold:** > 100ms = main thread blocked. Investigate CPU-bound work or synchronous I/O.

### Kubernetes Health Probes

```typescript
// BAD — liveness checks DB; DB down = restart storm
app.get("/healthz", async (_req, res) => {
  const db = await checkDatabase(); // Pod restarts when DB is down — wrong
  res.json({ status: db ? "ok" : "unhealthy" });
});

// GOOD — two endpoints, two concerns
app.get("/healthz", (_req, res) => {
  res.json({ status: "ok", uptime: process.uptime() }); // Liveness: process alive
});

app.get("/readyz", async (_req, res) => {
  const checks = { database: await checkDatabase(), redis: await checkRedis() };
  const healthy = Object.values(checks).every(Boolean);
  res.status(healthy ? 200 : 503).json({ status: healthy ? "ready" : "degraded", checks });
});
```

| Probe | Path | Checks | Failure means |
|-------|------|--------|---------------|
| **Liveness** | `/healthz` | Process alive, uptime | Restart the pod |
| **Readiness** | `/readyz` | DB, cache, event loop | Remove from load balancer |
| **Startup** | `/healthz` | Same as liveness | App still booting, don't kill yet |

**Critical rule:** Liveness probes must NEVER check external dependencies. If the database goes down, restarting your pod makes it worse — you get a restart storm.

---

## Performance: Make It Fast

### Pino Is Async by Design

Pino writes to stdout and processes through worker-thread transports. **Never** use synchronous file writes or network transports in the hot path. Stdout + external log collector (Fluentd, Vector, Filebeat) is the production pattern. Use `pino.transport()` for file destinations in high-throughput services.

### Sampling Strategy Table

| Signal | Dev | Staging | Production |
|--------|-----|---------|------------|
| Logs | All (`debug`) | All (`info`) | All (`info`) |
| Traces | 100% | 100% | 1-10% (`tracesSampleRate`) |
| Metrics | 15s interval | 15s interval | 15s interval |
| Sentry errors | 100% | 100% | 100% (errors always captured) |
| Sentry perf | 100% | 100% | 10% (`tracesSampleRate: 0.1`) |

### collectDefaultMetrics — Free Monitoring

`collectDefaultMetrics()` gives you CPU usage, memory (RSS/heap), event loop lag, active handles, and GC statistics at zero development cost. There is no reason not to enable it.

---

## Observability: Know It Is Working

This IS the observability skill. Every service you ship must pass this checklist before it is done:

### Production Readiness Checklist

| Check | How to verify |
|-------|---------------|
| Structured logging with Pino | `curl localhost:3000/any-route \| jq .` shows JSON logs with requestId |
| Log redaction active | Auth headers, passwords, tokens appear as `[REDACTED]` |
| Child loggers per module | Logs include `module` field for filtering |
| OTel instrumentation loads first | `--import` flag in start script |
| Traces appear in collector | Check Jaeger/Tempo/Datadog for service traces |
| Pino + OTel correlated | Log lines include `traceId` and `spanId` |
| `/metrics` endpoint returns data | `curl localhost:3000/metrics` returns Prometheus format |
| Default metrics collecting | CPU, memory, event loop lag in `/metrics` output |
| Custom business metrics | Request duration histogram, error counters present |
| `/healthz` returns 200 | Does NOT check external dependencies |
| `/readyz` checks dependencies | Returns 503 when DB/cache down |
| Event loop lag monitored | p99 gauge in `/metrics`, alert at >100ms |
| Sentry DSN configured (if used) | `SENTRY_DSN` env var set, test error appears in dashboard |
| Source maps uploaded (if Sentry) | Stack traces show original TypeScript, not compiled JS |
| Graceful shutdown flushes spans | `sdk.shutdown()` on SIGTERM |

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No console.log in Production Code

**You will be tempted to:** Use `console.log` or `console.error` for "quick" logging during development and leave it in.
**Why that fails:** `console.log` is unstructured, has no levels, no redaction, no correlation IDs, and cannot be queried. It is invisible to every observability tool.
**The right way:** Import the Pino logger from `src/logger.ts`. Use `logger.info()`, `logger.error()`, etc. Even in one-off scripts.

### Rule 2: No Skipping Instrumentation Setup

**You will be tempted to:** Ship the service without `instrumentation.ts` because "we will add tracing later."
**Why that fails:** Later never comes. Without tracing, debugging production issues means reading logs and guessing. A 10-minute setup saves hours of incident response.
**The right way:** Create `instrumentation.ts` + add `--import` flag when you create the project. It is part of scaffolding, not a feature.

### Rule 3: No Dependency Checks in Liveness Probes

**You will be tempted to:** Have `/healthz` check the database, Redis, or external APIs to give a "complete" health picture.
**Why that fails:** When the database goes down, Kubernetes restarts every pod simultaneously (restart storm). The database is still down, so they restart again. Your entire service fleet is now crash-looping.
**The right way:** Liveness = process alive. Readiness = dependencies healthy. Two separate endpoints, two separate concerns.

### Rule 4: No Unredacted Sensitive Data in Logs

**You will be tempted to:** Log the full request object including headers and body for "debugging purposes."
**Why that fails:** Authorization tokens, API keys, passwords, and PII end up in log storage. This is a compliance violation (GDPR, SOC2) and a security incident waiting to happen.
**The right way:** Configure `redact` paths in Pino. Use custom serializers that strip sensitive fields. Log only what you need to diagnose issues.

### Rule 5: No Metrics Without Labels

**You will be tempted to:** Create a single `http_requests_total` counter without labels because it is simpler.
**Why that fails:** A counter that only goes up tells you nothing. You cannot distinguish GET from POST, 200 from 500, `/api/users` from `/api/orders`. It is a vanity metric.
**The right way:** Always include `method`, `route`, and `status_code` labels on HTTP metrics. Use a bounded set — never use unbounded labels like `userId` (cardinality explosion).
