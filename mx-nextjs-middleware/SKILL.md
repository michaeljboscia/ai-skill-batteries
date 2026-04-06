---
name: mx-nextjs-middleware
description: "Next.js middleware, edge middleware, auth redirects, middleware.ts, NextResponse redirect rewrite, route matcher config, rate limiting, CORS, security headers, CSP nonces, CVE-2025-29927, edge runtime limitations, Data Access Layer, auth patterns, geolocation"
---

# Next.js Middleware — Edge Security and Request Interception for AI Coding Agents

**Load this skill when writing middleware.ts, implementing auth redirects, configuring CORS/security headers, or working with Edge runtime constraints.**

## When to also load
- `mx-nextjs-core` — Route structure middleware protects
- `mx-nextjs-data` — Server Actions need same auth verification
- `mx-nextjs-deploy` — Edge vs Node runtime selection
- `mx-nextjs-observability` — Security event logging

---

## Level 1: Middleware Fundamentals (Beginner)

### Pattern 1: Middleware File Location and Structure
One `middleware.ts` at project root (or `src/middleware.ts`). Runs on EVERY matched request before the route handler.

```tsx
// middleware.ts
import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

export function middleware(request: NextRequest) {
  // Check for auth cookie
  const token = request.cookies.get('session-token');

  if (!token && request.nextUrl.pathname.startsWith('/dashboard')) {
    return NextResponse.redirect(new URL('/login', request.url));
  }

  return NextResponse.next();
}

// ALWAYS configure matcher — without it, middleware runs on ALL routes including static assets
export const config = {
  matcher: ['/((?!api|_next/static|_next/image|favicon.ico).*)'],
};
```

### Pattern 2: Always Configure the Matcher

```tsx
// ❌ BAD — No matcher, runs on every request including static assets
export function middleware(request: NextRequest) { ... }

// ✅ GOOD — Exclude static assets and internal routes
export const config = {
  matcher: [
    // Match all paths except static files and images
    '/((?!api|_next/static|_next/image|favicon.ico).*)',
  ],
};

// Alternative: explicit paths
export const config = {
  matcher: ['/dashboard/:path*', '/admin/:path*', '/api/protected/:path*'],
};
```

Matcher values must be **string constants** — no variables. Analyzed at build time.

### Pattern 3: Redirect vs Rewrite

| Action | Effect | URL changes? | Use when |
|--------|--------|-------------|----------|
| `NextResponse.redirect(url)` | Sends user to new URL | Yes | Auth redirects, moved pages |
| `NextResponse.rewrite(url)` | Serves different content, same URL | No | A/B testing, locale routing |
| `NextResponse.next()` | Continue to route | No | Passthrough with modified headers |

```tsx
// Redirect: user sees /login in browser
return NextResponse.redirect(new URL('/login', request.url));

// Rewrite: user sees /dashboard but gets /dashboard/v2 content
return NextResponse.rewrite(new URL('/dashboard/v2', request.url));

// Passthrough with custom header
const response = NextResponse.next();
response.headers.set('x-custom-header', 'value');
return response;
```

---

## Level 2: Auth Patterns and Security (Intermediate)

### Pattern 1: Defense-in-Depth Auth (Post-CVE-2025-29927)

**CVE-2025-29927** (March 2025): Attackers bypassed middleware auth entirely via the `x-middleware-subrequest` header. Middleware alone is NOT safe for auth.

```
                    ┌─────────────────────────────────────────────┐
                    │            Defense-in-Depth Auth             │
                    ├─────────────────────────────────────────────┤
                    │ Layer 1: Middleware (OPTIMISTIC)              │
                    │   → Cookie exists? Redirect to /login if not │
                    │   → NOT authoritative. Can be bypassed.      │
                    ├─────────────────────────────────────────────┤
                    │ Layer 2: Server Component / Route Handler     │
                    │   → Verify session token is valid            │
                    │   → Check user has permission for this page  │
                    ├─────────────────────────────────────────────┤
                    │ Layer 3: Data Access Layer (AUTHORITATIVE)    │
                    │   → Verify auth INSIDE every DB query/action │
                    │   → This is the final gate. Cannot bypass.   │
                    └─────────────────────────────────────────────┘
```

```tsx
// middleware.ts — Layer 1: Optimistic redirect only
export function middleware(request: NextRequest) {
  const session = request.cookies.get('session');
  if (!session && request.nextUrl.pathname.startsWith('/dashboard')) {
    return NextResponse.redirect(new URL('/login', request.url));
  }
  return NextResponse.next();
}

// lib/server/auth.ts — Layer 3: Data Access Layer
import 'server-only';
export async function getAuthedUser() {
  const session = await verifySession(); // Validates JWT/session token
  if (!session) throw new Error('Unauthorized');
  return session.user;
}

// Every Server Action, every data query:
export async function getOrders() {
  const user = await getAuthedUser(); // Auth verified at data access
  return db.order.findMany({ where: { userId: user.id } });
}
```

### Pattern 2: Security Headers

```tsx
export function middleware(request: NextRequest) {
  const response = NextResponse.next();

  // Security headers
  response.headers.set('X-Content-Type-Options', 'nosniff');
  response.headers.set('X-Frame-Options', 'DENY');
  response.headers.set('Referrer-Policy', 'strict-origin-when-cross-origin');
  response.headers.set('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');

  return response;
}
```

### Pattern 3: CSP with Nonces

```tsx
import { NextResponse } from 'next/server';

export function middleware(request: NextRequest) {
  const nonce = crypto.randomUUID();

  const csp = [
    `default-src 'self'`,
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'`,
    `style-src 'self' 'nonce-${nonce}'`,
    `img-src 'self' blob: data:`,
    `font-src 'self'`,
    `connect-src 'self'`,
    `frame-ancestors 'none'`,
  ].join('; ');

  const response = NextResponse.next();
  response.headers.set('Content-Security-Policy', csp);
  response.headers.set('x-nonce', nonce); // Pass to components via headers()
  return response;
}
```

### Pattern 4: CORS for API Routes

```tsx
export function middleware(request: NextRequest) {
  if (request.nextUrl.pathname.startsWith('/api/')) {
    // Handle preflight
    if (request.method === 'OPTIONS') {
      return new NextResponse(null, {
        status: 204,
        headers: {
          'Access-Control-Allow-Origin': 'https://trusted-domain.com',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
          'Access-Control-Max-Age': '86400',
        },
      });
    }

    const response = NextResponse.next();
    response.headers.set('Access-Control-Allow-Origin', 'https://trusted-domain.com');
    return response;
  }

  return NextResponse.next();
}
```

---

## Level 3: Edge Runtime and Advanced Patterns (Advanced)

### Pattern 1: Edge Runtime Constraints
Middleware runs on Edge by default. These Node.js APIs are NOT available:

| Unavailable | Use Instead |
|-------------|-------------|
| `fs`, `path` | N/A — no filesystem access |
| `crypto` (Node) | `crypto` (Web Crypto API) |
| `jsonwebtoken` | `jose` (Web Crypto based) |
| `ioredis` | `@upstash/redis` (HTTP-based) |
| `require()` | ES Modules only |
| `eval()`, `new Function()` | Not allowed |
| Any npm package using Node APIs | Check compatibility first |

**Limits**: <5s execution (Vercel), ~1MB bundle size, no CommonJS.

### Pattern 2: Rate Limiting (Production)

```tsx
// middleware.ts — using Upstash Redis for distributed rate limiting
import { Ratelimit } from '@upstash/ratelimit';
import { Redis } from '@upstash/redis';

const ratelimit = new Ratelimit({
  redis: Redis.fromEnv(),
  limiter: Ratelimit.slidingWindow(10, '10 s'), // 10 requests per 10 seconds
});

export async function middleware(request: NextRequest) {
  if (request.nextUrl.pathname.startsWith('/api/')) {
    const ip = request.headers.get('x-forwarded-for') ?? '127.0.0.1';
    const { success, limit, reset, remaining } = await ratelimit.limit(ip);

    if (!success) {
      return new NextResponse('Too Many Requests', {
        status: 429,
        headers: {
          'X-RateLimit-Limit': limit.toString(),
          'X-RateLimit-Remaining': remaining.toString(),
          'X-RateLimit-Reset': reset.toString(),
        },
      });
    }
  }
  return NextResponse.next();
}
```

**Never use in-memory `Map` for rate limiting** — doesn't work across serverless instances.

### Pattern 3: Geolocation-Based Routing

```tsx
export function middleware(request: NextRequest) {
  const country = request.geo?.country ?? 'US';
  const city = request.geo?.city ?? 'unknown';

  if (country === 'DE') {
    return NextResponse.rewrite(new URL('/de' + request.nextUrl.pathname, request.url));
  }

  return NextResponse.next();
}
```

`request.geo` is populated by the Edge runtime. Available on Vercel; may need custom headers on self-hosted.

---

## Performance: Make It Fast

### Perf 1: Keep Middleware Lightweight
Middleware adds latency to EVERY matched request. No heavy computation, no DB queries, no external API calls unless absolutely necessary (rate limiting is the exception).

### Perf 2: Use Matcher to Skip Static Assets
Without a matcher, middleware runs on `_next/static`, images, and favicons — pure waste. Always configure `config.matcher`.

### Perf 3: Avoid External API Calls in Middleware
Each middleware invocation adds the external call's latency to the response. If you must call an API, use edge-compatible HTTP clients with aggressive timeouts.

---

## Observability: Know It's Working

### Obs 1: Log Security Events
Log auth failures, rate limit hits, and blocked requests from middleware to your structured logging pipeline. These are security signals.

### Obs 2: Monitor Middleware Latency
Middleware latency adds directly to TTFB. Track p50/p95/p99 middleware execution time. If >50ms consistently, you're doing too much work.

### Obs 3: Alert on CVE-Pattern Headers
If self-hosting older Next.js versions, monitor for `x-middleware-subrequest` header in access logs — this is the CVE-2025-29927 attack vector. Block it at your reverse proxy.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Use Middleware as Sole Auth Gate
**You will be tempted to:** Check auth only in middleware and trust it for the entire app.
**Why that fails:** CVE-2025-29927 proved middleware auth can be bypassed. Attackers send crafted headers to skip middleware entirely.
**The right way:** Middleware for optimistic redirects. Verify auth again at Server Component level AND at the Data Access Layer.

### Rule 2: Never Use Node.js APIs in Middleware
**You will be tempted to:** Import `jsonwebtoken`, `fs`, or Node `crypto` in middleware.
**Why that fails:** Edge runtime doesn't have Node.js APIs. Builds successfully locally (Node), crashes in production (Edge).
**The right way:** Use `jose` for JWT, Web Crypto API for crypto, HTTP-based clients for Redis.

### Rule 3: Never Skip the Matcher Config
**You will be tempted to:** Omit `export const config = { matcher: [...] }` because it works without it.
**Why that fails:** Middleware runs on EVERY request — including static assets, images, and internal Next.js routes. Pointless computation on every CSS/JS file.
**The right way:** Always exclude `_next/static`, `_next/image`, `favicon.ico` via matcher regex.

### Rule 4: Never Apply Express.js Mental Model
**You will be tempted to:** Chain middleware like Express (`app.use(cors); app.use(auth); app.use(logging)`).
**Why that fails:** Next.js has ONE middleware file. It's a request interceptor/proxy, not a chain of handlers.
**The right way:** Single `middleware.ts` with conditional logic sections based on `request.nextUrl.pathname`.

### Rule 5: Never Do Heavy Computation in Middleware
**You will be tempted to:** Parse JWT payloads, query databases, or call external APIs for every request.
**Why that fails:** Edge runtime has <5s execution limit. Heavy work blocks the response, degrading TTFB for every user.
**The right way:** Middleware checks cookies/headers only. Full verification happens in Server Components or Route Handlers.
