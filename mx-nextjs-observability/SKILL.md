---
name: mx-nextjs-observability
description: "Next.js observability, any Next.js work, OpenTelemetry, instrumentation.ts, structured logging, Pino Winston, error tracking, Sentry Datadog, Core Web Vitals monitoring, onRequestError, tracing spans, health checks, production monitoring, error boundaries"
---

# Next.js Observability — Monitoring and Instrumentation for AI Coding Agents

**This skill co-loads with mx-nextjs-core for ANY Next.js work.** Code without observability ships blind. Every feature should include monitoring from day one.

## When to also load
- `mx-nextjs-core` — Error boundaries per route segment
- `mx-nextjs-middleware` — Security event logging
- `mx-nextjs-deploy` — Self-hosted monitoring differs from Vercel
- `mx-nextjs-perf` — Core Web Vitals tracking

---

## Level 1: instrumentation.ts and Error Tracking (Beginner)

### Pattern 1: The instrumentation.ts File
Stable in Next.js 15 (no longer experimental). Runs once on server start. Place at project root or `src/`.

```tsx
// instrumentation.ts
export async function register() {
  if (process.env.NEXT_RUNTIME === 'nodejs') {
    // Node.js runtime initialization
    const { NodeSDK } = await import('@opentelemetry/sdk-node');
    const { getNodeAutoInstrumentations } = await import(
      '@opentelemetry/auto-instrumentations-node'
    );

    const sdk = new NodeSDK({
      serviceName: 'my-nextjs-app',
      instrumentations: [getNodeAutoInstrumentations()],
    });

    sdk.start();
  }
}
```

**Why the runtime check**: `instrumentation.ts` runs for both Node.js and Edge runtimes. OTel Node SDK only works in Node.js. Guard with `NEXT_RUNTIME`.

### Pattern 2: onRequestError Hook (Next.js 15+)
Captures server-side errors from Server Components, Route Handlers, Middleware, and Server Actions:

```tsx
// instrumentation.ts
import type { Instrumentation } from 'next';

export const onRequestError: Instrumentation.onRequestError = async (
  error,
  request,
  context
) => {
  await fetch('https://logging.example.com/errors', {
    method: 'POST',
    body: JSON.stringify({
      message: error.message,
      stack: error.stack,
      path: request.path,
      method: request.method,
      routerKind: context.routerKind,  // 'Pages' | 'App'
      routeType: context.routeType,    // 'render' | 'route' | 'action' | 'middleware'
      routePath: context.routePath,
      timestamp: new Date().toISOString(),
    }),
    headers: { 'Content-Type': 'application/json' },
  });
};
```

### Pattern 3: Error Boundaries Wired to Monitoring

```tsx
// app/dashboard/error.tsx
'use client';

import { useEffect } from 'react';
import * as Sentry from '@sentry/nextjs';

export default function DashboardError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    // Report to error tracking service
    Sentry.captureException(error);
  }, [error]);

  return (
    <div>
      <h2>Something went wrong</h2>
      <p>Error ID: {error.digest}</p>
      <button onClick={reset}>Try again</button>
    </div>
  );
}
```

Place `error.tsx` at every meaningful route segment — not just root. Each catches errors in its subtree.

### Pattern 4: Replace console.log with Structured Logging

```tsx
// ❌ BAD — console.log in production
console.log('User created:', userId);
// Outputs: "User created: 123" — no structure, no context, not queryable

// ✅ GOOD — Structured logging with Pino
import pino from 'pino';

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  formatters: { level: (label) => ({ level: label }) },
});

logger.info({ userId, action: 'user.created', duration: 45 }, 'User created');
// Outputs: {"level":"info","userId":"123","action":"user.created","duration":45,"msg":"User created"}
```

Structured logs are queryable in Datadog, CloudWatch, Loki. `console.log` is not.

---

## Level 2: OpenTelemetry Tracing (Intermediate)

### Pattern 1: Simplified Setup with @vercel/otel

```tsx
// instrumentation.ts
import { registerOTel } from '@vercel/otel';

export function register() {
  registerOTel({
    serviceName: 'my-nextjs-app',
  });
}
```

`@vercel/otel` works on both Vercel and self-hosted. Supports Node.js + Edge runtimes. Automatically captures Next.js spans.

### Pattern 2: Auto-Instrumented Spans
Next.js generates OTel spans automatically for:

| Operation | Span Name | Captured Data |
|-----------|-----------|--------------|
| Page render | `rendering route (app) [path]` | Route path, render duration |
| API route | `executing api route (app) [path]` | HTTP method, status code |
| `fetch()` calls | `fetch [method] [url]` | URL, status, cache hit/miss |
| Middleware | `middleware [path]` | Matched path |
| Server Component render | `resolve sc` | Component render time |
| Server Action | `server action [name]` | Action name, duration |

### Pattern 3: Custom Spans for Data Fetching

```tsx
// lib/server/products.ts
import 'server-only';
import { trace } from '@opentelemetry/api';

const tracer = trace.getTracer('app');

export async function getProductWithRecommendations(productId: string) {
  return tracer.startActiveSpan('products.getWithRecommendations', async (span) => {
    try {
      span.setAttribute('product.id', productId);

      const product = await tracer.startActiveSpan('products.findById', async (childSpan) => {
        const result = await db.product.findUnique({ where: { id: productId } });
        childSpan.setAttribute('product.found', !!result);
        childSpan.end();
        return result;
      });

      const recommendations = await tracer.startActiveSpan('products.recommend', async (childSpan) => {
        const result = await ml.getRecommendations(productId);
        childSpan.setAttribute('recommendations.count', result.length);
        childSpan.end();
        return result;
      });

      return { product, recommendations };
    } catch (error) {
      span.recordException(error as Error);
      span.setStatus({ code: 2, message: (error as Error).message }); // ERROR
      throw error;
    } finally {
      span.end();
    }
  });
}
```

**Naming convention**: `{resource}.{operation}` — e.g., `products.findById`, `orders.create`, `auth.verify`.

### Pattern 4: Correlate Logs with Traces

```tsx
import pino from 'pino';
import { trace, context } from '@opentelemetry/api';

const logger = pino({ /* ... */ });

export function getCorrelatedLogger() {
  const span = trace.getSpan(context.active());
  const spanContext = span?.spanContext();

  return logger.child({
    traceId: spanContext?.traceId,
    spanId: spanContext?.spanId,
  });
}

// Usage in any server function
const log = getCorrelatedLogger();
log.info({ userId }, 'Processing order'); // Includes traceId + spanId
```

Now you can jump from a log line directly to the full distributed trace.

---

## Level 3: Production Monitoring and Vendor Integration (Advanced)

### Pattern 1: Sentry Integration

```tsx
// instrumentation.ts
export async function register() {
  if (process.env.NEXT_RUNTIME === 'nodejs') {
    await import('./sentry.server.config');
  }
}

export const onRequestError = Sentry.captureRequestError;
```

```tsx
// sentry.server.config.ts
import * as Sentry from '@sentry/nextjs';

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  tracesSampleRate: 0.1,         // 10% of transactions
  profilesSampleRate: 0.1,        // 10% of transactions profiled
  environment: process.env.NODE_ENV,
});
```

Sentry uses OTel under the hood. Single SDK covers client, server, and edge. Provides: error tracking, distributed tracing, session replay, performance monitoring.

### Pattern 2: Health Endpoint for Self-Hosted

```tsx
// app/api/health/route.ts
import { NextResponse } from 'next/server';

export async function GET() {
  const health = {
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    memory: process.memoryUsage(),
    checks: {
      database: await checkDatabase(),
      cache: await checkCache(),
    },
  };

  const allHealthy = Object.values(health.checks).every((c) => c === 'ok');

  return NextResponse.json(health, {
    status: allHealthy ? 200 : 503,
  });
}

async function checkDatabase() {
  try {
    await db.$queryRaw`SELECT 1`;
    return 'ok';
  } catch {
    return 'unhealthy';
  }
}

async function checkCache() {
  try {
    await redis.ping();
    return 'ok';
  } catch {
    return 'unhealthy';
  }
}
```

### Pattern 3: Core Web Vitals Monitoring

```tsx
// app/components/WebVitals.tsx
'use client';
import { useReportWebVitals } from 'next/web-vitals';

export function WebVitals() {
  useReportWebVitals((metric) => {
    const body = {
      name: metric.name,       // CLS, FID, FCP, LCP, TTFB, INP
      value: metric.value,
      rating: metric.rating,   // 'good' | 'needs-improvement' | 'poor'
      delta: metric.delta,
      id: metric.id,
      navigationType: metric.navigationType,
    };

    // Batch and send to analytics endpoint
    if (navigator.sendBeacon) {
      navigator.sendBeacon('/api/vitals', JSON.stringify(body));
    }
  });

  return null;
}
```

**Thresholds to alert on:**

| Metric | Good | Needs Improvement | Poor |
|--------|------|-------------------|------|
| LCP | ≤2.5s | ≤4s | >4s |
| CLS | ≤0.1 | ≤0.25 | >0.25 |
| INP | ≤200ms | ≤500ms | >500ms |
| TTFB | ≤800ms | ≤1.8s | >1.8s |

---

## Performance: Make It Fast

### Perf 1: Use BatchLogRecordProcessor
In production, always batch log exports. Per-log network calls kill throughput:

```tsx
import { BatchLogRecordProcessor } from '@opentelemetry/sdk-logs';
// NOT SimpleLogRecordProcessor (sends per-log)
```

### Perf 2: Sample Traces in Production
100% trace sampling overwhelms backends and increases costs. Use `tracesSampleRate: 0.1` (10%) for normal traffic. Use head-based sampling with higher rates for error paths.

### Perf 3: Async Error Reporting
Never `await` error reporting calls in the critical path. Use `fire-and-forget` with `void fetch(...)` or `navigator.sendBeacon` to avoid blocking user-facing responses.

---

## Observability: Know It's Working (Meta)

### Obs 1: Monitor ISR Failures (Silent by Default)
ISR regeneration failures are silent — stale content keeps serving. Log inside your data fetching functions and alert on repeated failures. Self-hosted ISR is especially vulnerable.

### Obs 2: Track Middleware Latency
Middleware runs on every matched request. Monitor p50/p95/p99. If middleware adds >50ms consistently, it's doing too much.

### Obs 3: Monitor Server Action Error Rates
Server Actions that fail silently (returning error objects instead of throwing) won't trigger error boundaries. Track action-level success/failure rates in your metrics.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Use console.log in Production
**You will be tempted to:** `console.log('User:', user.id)` for debugging.
**Why that fails:** Unstructured text is not queryable, not searchable, not correlated with traces. In serverless, logs may be lost between invocations.
**The right way:** Use Pino or Winston for structured JSON logging. Correlate with OpenTelemetry trace IDs.

### Rule 2: Never Skip instrumentation.ts
**You will be tempted to:** Scatter tracing setup across individual files.
**Why that fails:** OTel SDK must initialize once, before any other code runs. Multiple initializations cause duplicate spans or dropped traces.
**The right way:** All OTel/monitoring setup in `instrumentation.ts`. It runs once on server start, guaranteed.

### Rule 3: Never Wire error.tsx Without Reporting
**You will be tempted to:** Create `error.tsx` with just a "Something went wrong" message and a reset button.
**Why that fails:** Errors happen in production with no one watching. The error boundary catches it, but nobody knows.
**The right way:** Always call your error tracking service (Sentry, Datadog, custom) in a `useEffect` inside `error.tsx`.

### Rule 4: Never Expose Internal Errors to Users
**You will be tempted to:** Show `error.message` directly in the UI.
**Why that fails:** Database errors, stack traces, and internal paths leak implementation details. Security risk + confusing UX.
**The right way:** Show generic message + `error.digest` (a hash). Log the full error server-side. The digest lets support correlate user reports with server logs.

### Rule 5: Never Forget Runtime Guard in instrumentation.ts
**You will be tempted to:** Import `@opentelemetry/sdk-node` at the top level of instrumentation.ts.
**Why that fails:** Edge runtime can't load Node.js OTel SDK. The middleware/edge functions crash on deployment.
**The right way:** Check `process.env.NEXT_RUNTIME === 'nodejs'` before importing Node-specific OTel packages.
