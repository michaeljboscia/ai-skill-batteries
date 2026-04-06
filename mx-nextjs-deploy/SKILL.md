---
name: mx-nextjs-deploy
description: "Next.js deployment, Vercel vs self-hosted, Docker standalone output, NEXT_PUBLIC environment variables, Edge vs Node runtime, output modes, multi-stage Dockerfile, next.config.ts, static export, CDN, self-hosted caching Redis, ISR persistence, Sharp image optimization, standalone build"
---

# Next.js Deploy — Vercel, Docker, and Runtime Configuration for AI Coding Agents

**Load this skill when deploying Next.js, configuring Docker, managing environment variables, choosing Edge vs Node runtime, or setting up self-hosted infrastructure.**

## When to also load
- `mx-nextjs-core` — Route structure and configuration
- `mx-nextjs-middleware` — Edge runtime constraints
- `mx-nextjs-perf` — Runtime selection affects performance
- `mx-nextjs-observability` — Self-hosted monitoring setup differs from Vercel

---

## Level 1: Environment Variables and Basic Config (Beginner)

### Pattern 1: NEXT_PUBLIC_ Build-Time Inlining

```tsx
// ❌ BAD — Expecting runtime env vars on the client
// .env
API_URL=https://api.example.com
// Client component: process.env.API_URL → undefined

// ✅ GOOD — NEXT_PUBLIC_ prefix for client-accessible vars
// .env
NEXT_PUBLIC_API_URL=https://api.example.com
// Client component: process.env.NEXT_PUBLIC_API_URL → "https://api.example.com"
```

**Critical limitation**: `NEXT_PUBLIC_*` vars are **inlined at BUILD time**. You cannot change them at runtime with the same Docker image. To use different values per environment:

| Approach | How | When to use |
|----------|-----|------------|
| Rebuild per env | Build with different `.env` | CI/CD pipeline, small teams |
| Runtime API route | `/api/config` endpoint returns env vars | Single Docker image, multiple envs |
| `__NEXT_DATA__` injection | Custom `_document.tsx` injects vars | Advanced, SSR-only |

Server-side vars (`process.env.SECRET_KEY`) are available at runtime — set via `docker run -e` or docker-compose.

### Pattern 2: next.config.ts (TypeScript Config)

```ts
// next.config.ts (TypeScript support stable in Next.js 15)
import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  images: {
    remotePatterns: [
      { protocol: 'https', hostname: 'cdn.example.com' },
    ],
  },
  logging: {
    fetches: { fullUrl: true }, // Show full fetch URLs in dev
  },
  experimental: {
    ppr: true,                  // Partial Prerendering
  },
};

export default nextConfig;
```

### Pattern 3: Output Modes

| Mode | Config | Use Case |
|------|--------|----------|
| Default | (none) | Vercel deployment |
| `standalone` | `output: 'standalone'` | Docker / self-hosted |
| `export` | `output: 'export'` | Static site (no server) |

```ts
// next.config.ts — for Docker deployment
const nextConfig: NextConfig = {
  output: 'standalone',  // Generates minimal .next/standalone (~150-200MB vs >1GB)
};
```

---

## Level 2: Docker and Self-Hosted Deployment (Intermediate)

### Pattern 1: Multi-Stage Dockerfile

```dockerfile
# Stage 1: Dependencies
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN corepack enable pnpm && pnpm install --frozen-lockfile

# Stage 2: Build
FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Build args for NEXT_PUBLIC_ vars (inlined at build time)
ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL

RUN corepack enable pnpm && pnpm build

# Stage 3: Production
FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production

# Sharp for image optimization (required for self-hosted)
RUN apk add --no-cache libc6-compat
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public

EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

CMD ["node", "server.js"]
```

**Key details**:
- `standalone` output creates a self-contained `server.js` — no `node_modules` needed
- `.next/static` and `public/` are NOT included in standalone — copy them manually
- Or serve static assets from a CDN and set `assetPrefix` in next.config.ts

### Pattern 2: Vercel-Specific Features That Don't Work Self-Hosted

| Feature | Vercel | Self-Hosted | Workaround |
|---------|--------|-------------|------------|
| ISR cache persistence | Managed | Filesystem (ephemeral) | Redis cache handler |
| Image Optimization | Built-in | Needs Sharp installed | `RUN apk add --no-cache libc6-compat` |
| Edge Functions | Global CDN | Not available | Use Node.js runtime |
| Analytics | Built-in dashboard | Not available | Datadog, Grafana, custom |
| Data Cache | Distributed | Filesystem (single node) | Redis cache handler |
| Preview Deployments | Per-PR URLs | Not available | Custom CI/CD setup |
| `request.geo` | Populated | Empty | Reverse proxy headers |

### Pattern 3: Redis Cache for Self-Hosted ISR

```ts
// next.config.ts
const nextConfig: NextConfig = {
  cacheHandler: require.resolve('./cache-handler.mjs'),
  cacheMaxMemorySize: 0, // Disable in-memory cache, use Redis only
};
```

```js
// cache-handler.mjs
import { createClient } from 'redis';

const client = createClient({ url: process.env.REDIS_URL });
await client.connect();

export default class CacheHandler {
  async get(key) {
    const data = await client.get(key);
    return data ? JSON.parse(data) : null;
  }

  async set(key, data, ctx) {
    const ttl = ctx.revalidate || 3600;
    await client.set(key, JSON.stringify(data), { EX: ttl });
  }

  async revalidateTag(tags) {
    // Implement tag-based invalidation with Redis sets
    for (const tag of tags) {
      const keys = await client.sMembers(`tag:${tag}`);
      for (const key of keys) {
        await client.del(key);
      }
    }
  }
}
```

Without this, ISR pages go stale permanently on multi-instance deployments (each instance has its own filesystem cache).

---

## Level 3: Edge vs Node Runtime and Advanced Config (Advanced)

### Pattern 1: Edge vs Node Runtime Decision

| Criteria | Edge Runtime | Node.js Runtime |
|----------|-------------|-----------------|
| Cold start | Near-zero (V8 isolates) | Higher (full Node.js) |
| Latency | Low (global distribution) | Higher (origin server) |
| Bundle limit | ~1-4MB | Unlimited |
| Execution limit | <5s (Vercel) | Configurable |
| Node.js APIs | **Not available** | Full access |
| npm packages | Web API compatible only | All packages |
| File system | **Not available** | Full access |
| Database access | HTTP-based clients only | Any ORM/driver |
| **Best for** | Middleware, lightweight functions | Server Components, Route Handlers, Server Actions |

```tsx
// Force a specific runtime per route segment
// app/api/lightweight/route.ts
export const runtime = 'edge';

// app/api/heavy-processing/route.ts
export const runtime = 'nodejs'; // default
```

**Default recommendation**: Use Node.js runtime for everything except middleware. Edge is for request interception, not business logic.

### Pattern 2: Environment Variable Strategy for Multi-Environment Docker

```tsx
// app/api/config/route.ts — Runtime client config endpoint
import { NextResponse } from 'next/server';

export async function GET() {
  return NextResponse.json({
    apiUrl: process.env.API_URL,           // Server-side var, set at runtime
    featureFlags: process.env.FEATURE_FLAGS,
    environment: process.env.NODE_ENV,
  });
}
```

```tsx
// hooks/useConfig.ts (client component)
'use client';
import useSWR from 'swr';

export function useConfig() {
  const { data } = useSWR('/api/config', (url) => fetch(url).then(r => r.json()));
  return data;
}
```

This lets you run ONE Docker image across staging/production — only environment variables change.

### Pattern 3: Static Export for CDN-Only Hosting

```ts
// next.config.ts
const nextConfig: NextConfig = {
  output: 'export',  // Generates static HTML in /out directory
};
```

**Limitations of static export**: No Server Components (SSR), no ISR, no middleware, no API routes, no Image Optimization, no `revalidate`. Use only for truly static marketing sites.

### Pattern 4: Vercel Environment Variables

```
Vercel Dashboard → Project Settings → Environment Variables

Production:     DATABASE_URL = postgres://prod...
Preview:        DATABASE_URL = postgres://preview...
Development:    DATABASE_URL = postgres://dev...
```

**Limits**: 64KB total per deployment (Node), 5KB per individual variable (Edge).

---

## Performance: Make It Fast

### Perf 1: standalone Output Reduces Image Size 5-10x
Default `node_modules` can be >1GB. `output: 'standalone'` produces ~150-200MB. Essential for container deployments.

### Perf 2: Serve Static Assets from CDN
Set `assetPrefix: 'https://cdn.example.com'` in next.config.ts to serve `.next/static/` from a CDN. Reduces origin server load.

### Perf 3: Sharp for Image Optimization
Self-hosted deployments MUST install Sharp. Without it, image optimization falls back to slower alternatives or fails entirely:
```dockerfile
RUN apk add --no-cache libc6-compat
# Sharp auto-detected by Next.js when available
```

---

## Observability: Know It's Working

### Obs 1: Health Check Endpoint
Self-hosted deployments need `/api/health` that checks database connectivity, cache availability, and process health. Load balancers and container orchestrators depend on this.

### Obs 2: Monitor ISR Cache on Self-Hosted
Filesystem cache is ephemeral in Docker. Monitor cache hit rates. If ISR pages never regenerate, your cache handler is misconfigured.

### Obs 3: Track Cold Starts
Edge functions have near-zero cold starts. Node.js functions on serverless platforms have 1-5s cold starts. Monitor p99 latency to detect cold start impact.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Assume Vercel Features Work Everywhere
**You will be tempted to:** Use `request.geo`, ISR, or Edge Functions and assume they work on any host.
**Why that fails:** These are Vercel-managed features. Self-hosted: `request.geo` is empty, ISR cache is ephemeral, Edge Functions don't exist.
**The right way:** Check the Vercel vs Self-Hosted table above. Implement workarounds (Redis cache, reverse proxy headers) for self-hosted.

### Rule 2: Never Expect NEXT_PUBLIC_ to Change at Runtime
**You will be tempted to:** Set `NEXT_PUBLIC_API_URL` at `docker run` time and expect it to work.
**Why that fails:** `NEXT_PUBLIC_*` vars are string-replaced into the JS bundle at build time. The Docker image has the build-time value baked in.
**The right way:** For multi-env Docker: use a `/api/config` runtime endpoint for client config, or rebuild per environment.

### Rule 3: Never Forget to Copy Static Assets in Dockerfile
**You will be tempted to:** Use `standalone` output and wonder why CSS/images are missing.
**Why that fails:** `standalone` only produces `server.js` and its dependencies. `.next/static/` and `public/` are excluded.
**The right way:** `COPY --from=builder /app/.next/static ./.next/static` and `COPY --from=builder /app/public ./public` in your Dockerfile.

### Rule 4: Never Use Edge Runtime for Heavy Logic
**You will be tempted to:** Set `runtime = 'edge'` for API routes that query databases or process data.
**Why that fails:** Edge runtime has no Node.js APIs, <5s execution, 1-4MB bundle limit. Most ORMs and npm packages fail silently or crash.
**The right way:** Use Edge only for middleware and lightweight request transformation. Use Node.js runtime for Server Components, Route Handlers, and Server Actions.

### Rule 5: Never Skip Sharp on Self-Hosted
**You will be tempted to:** Deploy without Sharp and assume `next/image` works.
**Why that fails:** Without Sharp, image optimization either falls back to slower alternatives (squoosh, now deprecated) or fails entirely. Images serve unoptimized.
**The right way:** Install Sharp in your Docker image. Alpine Linux: `apk add --no-cache libc6-compat`. Debian: Sharp installs automatically via npm.
