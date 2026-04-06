---
name: mx-wp-observability
description: Use when setting up monitoring, logging, health checks, or debugging for headless WordPress with WPGraphQL and Next.js. Also use when the user mentions 'GRAPHQL_DEBUG', 'GraphQL Tracing', 'Query Monitor', 'health check', 'content sync', 'webhook monitoring', 'Apollo Link logging', 'error tracking', or 'cache hit rate'.
---

# Headless WordPress Observability — Monitoring, Debugging, Health Checks for AI Coding Agents

**Co-loads automatically on any headless WordPress work.**

## When to also load
- `mx-wp-core` — fetchGraphQL, architecture
- `mx-wp-perf` — caching, Smart Cache monitoring
- `mx-nextjs-observability` — Next.js instrumentation, Sentry, OTel

---

## Level 1: Three-Layer Monitoring (Beginner)

### 1.1 What to Monitor at Each Layer

| Layer | What to Monitor | Tools |
|-------|----------------|-------|
| **WP Backend** | PHP perf, DB queries, plugin conflicts, error logs | New Relic APM, Query Monitor, WP_DEBUG_LOG |
| **API/GraphQL** | Request rate, response time, errors, payload size | GraphQL Tracing, Apollo Link telemetry, APM |
| **Frontend** | Core Web Vitals, JS errors, user interactions | Sentry, Vercel Analytics, Lighthouse |

### 1.2 WordPress Debug Logging

```php
// wp-config.php — DEVELOPMENT ONLY
define('WP_DEBUG', true);
define('WP_DEBUG_LOG', true);      // Writes to wp-content/debug.log
define('WP_DEBUG_DISPLAY', false); // Don't show errors in API responses
define('GRAPHQL_DEBUG', true);     // WPGraphQL descriptive errors
```

### 1.3 Frontend Error Tracking

Always integrate Sentry (or equivalent) for both server and client errors:
- Server Components: catches errors during SSR/ISR generation
- Client Components: catches hydration errors, JS exceptions
- GraphQL errors arrive with HTTP 200 — network monitors miss them entirely

---

## Level 2: WPGraphQL Debugging (Intermediate)

### 2.1 GRAPHQL_DEBUG Mode

When enabled, transforms generic "Internal Server Error" into descriptive errors with stack traces.

```php
// wp-config.php
define('GRAPHQL_DEBUG', true);
```

**NEVER enable in production** — exposes internal application structure.

### 2.2 graphql_debug() Function

Like `console.log()` for WPGraphQL resolvers. Outputs to the debug log.

```php
register_graphql_field('Post', 'myField', [
    'type' => 'String',
    'resolve' => function($post, $args) {
        graphql_debug($args, ['type' => 'MY_FIELD_ARGS']);
        return 'computed value';
    },
]);
```

### 2.3 GraphQL Tracing

Tracks execution time per resolver. Enable in WPGraphQL Settings.

Response includes `extensions.tracing` with microsecond-level resolver durations. Identifies which resolver is the bottleneck.

### 2.4 Query Logs (SQL Inspection)

Shows raw SQL queries, execution time, and call stack per GraphQL request. Use with Query Monitor plugin for deep inspection.

**Dev only** — significant performance overhead. Never enable in production.

---

## Level 3: Apollo Link Observability Pattern (Advanced)

### 3.1 The Reference Pattern (from VIP Skeleton)

Three-link chain that logs every GraphQL request:

```typescript
import { ApolloClient, InMemoryCache, HttpLink, ApolloLink, from } from '@apollo/client'
import { onError } from '@apollo/client/link/error'

// 1. Error Link — catches GraphQL errors (HTTP 200 with errors array)
const errorLink = onError(({ graphQLErrors, networkError, operation }) => {
  if (graphQLErrors) {
    graphQLErrors.forEach(({ message, locations, path }) => {
      console.error('[GraphQL Error]:', {
        operation: operation.operationName,
        message, path, locations,
      })
      // Sentry.captureException(new Error(message), { extra: { operation, path } })
    })
  }
  if (networkError) {
    console.error('[Network Error]:', networkError.message)
  }
})

// 2. Telemetry Link — logs cache status, latency, payload size
const telemetryLink = new ApolloLink((operation, forward) => {
  const startTime = Date.now()

  return forward(operation).map((response) => {
    const context = operation.getContext()
    const httpResponse = context.response

    console.info('[GraphQL Request]:', {
      operationName: operation.operationName,
      variables: operation.variables,
      requestDurationInMs: Date.now() - startTime,
      cacheStatus: httpResponse?.headers?.get('x-cache') ?? 'UNKNOWN',
      cacheAge: httpResponse?.headers?.get('age') ?? '0',
      payloadSize: httpResponse?.headers?.get('content-length') ?? 'unknown',
    })

    return response
  })
})

// 3. HTTP Link
const httpLink = new HttpLink({
  uri: process.env.NEXT_PUBLIC_WORDPRESS_GRAPHQL_URL,
})

// Chain: Telemetry → Errors → HTTP
export const apolloClient = new ApolloClient({
  link: from([telemetryLink, errorLink, httpLink]),
  cache: new InMemoryCache(),
})
```

### 3.2 What This Logs Per Request

```json
{
  "operationName": "GetAllPosts",
  "variables": { "first": 10 },
  "requestDurationInMs": 45,
  "cacheStatus": "HIT",
  "cacheAge": "300",
  "payloadSize": "4096"
}
```

Track `cacheStatus: MISS` spikes — indicates cache invalidation issues.

---

## Level 3b: Content Sync + Health Checks (Advanced)

### 3.3 Webhook Delivery Monitoring

- Log every outbound webhook from WordPress (success/failure/timeout)
- Monitor Next.js `/api/revalidate` for 401 (secret mismatch) and 500 (revalidation error)
- Set up alerts for webhook failure rates > 5%

### 3.4 Health Check Endpoint

```typescript
// app/api/health/route.ts
export async function GET() {
  try {
    const start = Date.now()
    const res = await fetch(process.env.NEXT_PUBLIC_WORDPRESS_GRAPHQL_URL!, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: '{ __typename }' }),
    })
    const data = await res.json()
    const latency = Date.now() - start

    if (data?.data?.__typename === 'RootQuery') {
      return Response.json({ status: 'healthy', latencyMs: latency })
    }
    return Response.json({ status: 'unhealthy', reason: 'Invalid GraphQL response' }, { status: 503 })
  } catch (error: any) {
    return Response.json({ status: 'unhealthy', error: error.message }, { status: 503 })
  }
}
```

### 3.5 Content Sync Verification Checklist

- [ ] Webhook fires on every `save_post` for published content
- [ ] Next.js `/api/revalidate` returns 200 on valid webhook
- [ ] Updated content appears on frontend within 30 seconds of publish
- [ ] Preview mode shows draft content with correct data
- [ ] Cache invalidation verified: old content replaced after revalidation
- [ ] Scheduled integrity check compares WP modified dates vs frontend cache age

---

## Performance: Make It Fast

- Disable `GRAPHQL_DEBUG` and Query Logs in production — significant overhead
- Use GraphQL Tracing only during profiling sessions, not permanently
- Ship logs to centralized aggregator (Datadog, ELK) — don't let debug.log grow unbounded
- Cache health check responses for 30s to prevent self-DoS

## Observability: Know It's Working (Meta-Observability)

- Monitor the monitors: check that Sentry is receiving events
- Verify webhook logs are flowing to your log aggregator
- Test health check endpoint from external uptime monitor (not just internal)
- Review CDN cache hit ratio weekly — target > 90%

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Skip Monitoring
**You will be tempted to:** ship without monitoring because "the site is simple" or "it's just a blog."
**Why that fails:** Headless architecture has 3x the failure points of monolithic WP. API failures, webhook timeouts, cache staleness, and auth token expiry are invisible without instrumentation.
**The right way:** Implement three-layer monitoring from day one. Minimum: Sentry (frontend errors) + WP_DEBUG_LOG (backend errors) + health check endpoint.

### Rule 2: Never Leave GRAPHQL_DEBUG=true in Production
**You will be tempted to:** leave debug mode on to "make debugging easier."
**Why that fails:** Exposes internal stack traces, application structure, active plugins, and experimental features. Performance overhead adds latency to every request.
**The right way:** `GRAPHQL_DEBUG=true` in dev/staging only. Use APM tools (New Relic, Datadog) for production debugging.

### Rule 3: Never Ignore GraphQL Errors in Responses
**You will be tempted to:** only check HTTP status codes for errors.
**Why that fails:** GraphQL returns HTTP 200 even when queries fail. The `errors` array in the response body is the only signal. Network-level monitoring misses 100% of GraphQL errors.
**The right way:** Always parse `response.errors` in fetchGraphQL. Use Apollo ErrorLink to catch and dispatch errors to Sentry.

### Rule 4: Never Ignore Cache Hit/Miss Rates
**You will be tempted to:** assume caching "just works" after initial setup.
**Why that fails:** Overly aggressive invalidation, misconfigured Smart Cache tags, or missing GET request configuration can silently degrade cache to 0% hits. Every request then hits WordPress PHP+MySQL directly.
**The right way:** Log `x-cache` headers via Apollo telemetry link. Monitor cache hit ratio. Alert when it drops below 80%.
