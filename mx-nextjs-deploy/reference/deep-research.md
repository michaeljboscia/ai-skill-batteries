# Next.js Deployment Architecture: A Comprehensive Technical Reference for Vercel and Self-Hosted Docker Environments

*   **Key Points:**
    *   It seems highly likely that Vercel provides the most frictionless deployment path for Next.js, abstracting critical infrastructure like globally distributed Incremental Static Regeneration (ISR) and Edge caching.
    *   Research indicates that self-hosting Next.js via Docker requires resolving complex distributed state problems, including the "split-brain" cache scenario and Image Optimization resource management.
    *   The `output: 'standalone'` configuration is definitively essential for self-hosted containerization, significantly reducing Docker image sizes by stripping unused dependencies.
    *   Evidence suggests that `NEXT_PUBLIC_` environment variables present a fundamental limitation in "build once, deploy anywhere" Docker pipelines due to forced build-time inlining.
    *   The transition from Webpack to Turbopack in Next.js configuration fundamentally alters build pipelines, requiring specific adaptations in `next.config.ts`.

### Executive Summary
This technical reference provides an exhaustive examination of Next.js deployment paradigms, strictly contrasting the managed Vercel ecosystem with self-hosted Docker environments. As Next.js evolves to support advanced features like React Server Components (RSCs), Partial Prerendering (PPR), and Incremental Static Regeneration (ISR), the underlying infrastructure required to support these features has grown increasingly complex. This document synthesizes current architectural patterns, focusing on standalone output configurations, environment variable limitations, runtime differences (Edge vs. Node.js), distributed caching solutions, and strict anti-rationalization rules designed to prevent common architectural fallacies.

### Context and Scope
Next.js applications can be deployed in multiple environments, but the architectural requirements vary drastically. While Vercel handles global Content Delivery Network (CDN) propagation, Edge function distribution, and durable storage automatically, self-hosted environments require developers to implement custom Redis cache handlers, manage Server Action encryption keys, and configure robust reverse proxies. This guide covers versions up to Next.js 15/16, encompassing recent shifts like Turbopack adoption and strict caching semantics.

### Methodological Limitations
The data presented relies on documented framework behaviors up to Next.js 16 [cite: 1, 2]. Framework features are subject to iteration; experimental APIs (such as specific Turbopack loader features or plural `cacheHandlers`) may evolve. Where performance metrics are provided (e.g., cold start latencies, image size reductions), these represent standard benchmarks that may fluctuate based on underlying physical hardware and specific implementation details.

---

## 1. Next.js Configuration: `next.config.ts`, Turbopack, and Output Modes

The foundation of any Next.js deployment is its configuration file. With recent updates, Next.js natively supports TypeScript configurations (`next.config.ts`), providing strict typing via the `NextConfig` interface [cite: 3, 4]. Furthermore, the transition from Webpack to Turbopack—written in Rust—marks a significant shift in how applications are bundled for development and production [cite: 1, 5].

### 1.1 `next.config.ts` and TypeScript Integration
Utilizing TypeScript for configuration ensures type safety and better integration with IDE autocompletion. The configuration object governs rendering behavior, build output, caching strategies, and experimental flags.

```typescript
// next.config.ts
import type { NextConfig } from 'next';
import crypto from 'crypto';

const nextConfig: NextConfig = {
  // Enables minimal output for Docker containerization
  output: 'standalone',

  // Compresses build output for reduced image size
  outputStyle: 'compressed',

  // Useful for environments like Cloud Run or Kubernetes behind an ingress
  poweredByHeader: false,

  // Modern Turbopack configuration
  turbopack: {
    rules: {
      '*.svg': {
        loaders: ['@svgr/webpack'],
        as: '*.js',
      },
    },
    resolveAlias: {
      '@components': './components',
    },
  },

  // Generates a consistent build ID across multiple Docker replicas
  generateBuildId: async () => {
    return process.env.GIT_HASH || crypto.randomUUID();
  },

  // Experimental features
  experimental: {
    // Other experimental features can be declared here
  }
};

export default nextConfig;
```

### 1.2 Turbopack Configuration Architecture
Turbopack is the default bundler in modern Next.js environments, achieving stable status for development in Next.js 15 and expanding to alpha for production builds (`next build --turbopack`) in Next.js 15.3 [cite: 1, 5]. The `turbopack` configuration option replaces the legacy `experimental.turbo` flag [cite: 3].

Turbopack fundamentally differs from Webpack by executing a highly optimized Rust-based module graph. It natively handles CSS and modern JavaScript compilation, negating the need for basic loaders like `css-loader` or `babel-loader` (when using `@babel/preset-env`) [cite: 3]. 

However, custom loaders are supported via the `turbopack.rules` configuration. Turbopack allows inline loader configuration via import attributes, enabling granular, per-file loader application without global rules [cite: 2, 3]:

```typescript
// Example of inline loader configuration
import rawText from './data.txt' with {
  turbopackLoader: 'raw-loader',
  turbopackAs: '*.js',
};
```

### 1.3 Output Modes: `standalone` vs. `export`
Next.js supports distinct output modes tailored to specific deployment strategies.

1.  **`output: 'export'`**: This mode generates purely static HTML/CSS/JS files, bypassing the Node.js server entirely [cite: 6]. While ideal for standard CDNs or simple web servers, it inherently breaks features requiring server-side compute, such as dynamic route handlers, Server Actions, Middleware, and default Image Optimization.
2.  **`output: 'standalone'`**: Essential for Docker and self-hosted deployments [cite: 7]. During the build phase, Next.js traces all dependencies and `node_modules` utilized by the application. It creates a `.next/standalone` directory containing a minimal Node.js server and only the explicitly required modules [cite: 8]. This effectively isolates the production footprint from development dependencies.

---

## 2. The `standalone` Output Configuration and Docker Architecture

Containerizing Next.js naïvely by copying the entire project structure and running `npm start` results in bloated, monolithic Docker images frequently exceeding 1GB to 2GB [cite: 8, 9]. This bloated size increases container registry storage costs, prolongs CI/CD pipeline durations, and severely degrades cold start performance in serverless container platforms like Google Cloud Run or AWS Fargate.

To resolve this, the deployment standard dictates combining `output: 'standalone'` with a **Multi-Stage Dockerfile Pattern** using an Alpine Linux base image [cite: 10, 11].

### 2.1 The Standalone Trace Mechanism
When `output: 'standalone'` is invoked, Next.js utilizes `@vercel/nft` (Node File Trace) to analyze the Abstract Syntax Tree (AST) of the compiled application. It detects exactly which external packages from `node_modules` are invoked. The build process then duplicates only these specific files into the `.next/standalone/node_modules` directory [cite: 8, 9]. The resulting output is a self-contained, highly optimized directory ready to be executed via `node server.js` rather than `next start`.

### 2.2 The Multi-Stage Dockerfile Pattern
The multi-stage build relies on layer caching and distinct architectural phases. It ensures that development toolchains, uncompiled assets, and package managers (like `npm` or `yarn`) are entirely excluded from the final production runner image [cite: 8]. 

The three universally recognized stages are:
1.  **Stage 1: `deps`**: Installs dependencies. By isolating `package.json` and lockfiles, Docker caches this layer, preventing re-installation unless dependencies change [cite: 8].
2.  **Stage 2: `builder`**: Copies source code and executes `next build`. This stage generates the `.next/standalone` directory [cite: 8].
3.  **Stage 3: `runner`**: The final, minimal image. It copies only the standalone server, `.next/static`, and `public` assets [cite: 8].

#### Exhaustive Runnable Dockerfile Implementation

```dockerfile
# --- Base Stage ---
# Use a slim, secure Alpine Linux image
ARG NODE_VERSION=20.11.1
FROM node:${NODE_VERSION}-alpine AS base

# --- Stage 1: Dependencies ---
FROM base AS deps
# libc6-compat is required for certain native modules like sharp
RUN apk add --no-cache libc6-compat
WORKDIR /app

# Copy lockfiles and package configurations
COPY package.json package-lock.json* ./
# Clean install for deterministic dependency resolution
RUN npm ci

# --- Stage 2: Builder ---
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Next.js telemetry collection should be disabled for privacy and CI speed
ENV NEXT_TELEMETRY_DISABLED=1

# Execute the build. This produces the .next/standalone directory
RUN npm run build

# --- Stage 3: Production Runner ---
FROM base AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# Security Best Practice: Run container as non-root user
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Copy static assets required for public access
COPY --from=builder /app/public ./public

# Set proper permissions for the .next cache directory
RUN mkdir .next
RUN chown nextjs:nodejs .next

# Copy the optimized standalone output
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# Switch to non-root user
USER nextjs

# Expose standard web port
EXPOSE 3000
ENV PORT=3000

# Optionally set hostname to allow connections from outside the container
ENV HOSTNAME="0.0.0.0"

# Execute the minimal standalone server
CMD ["node", "server.js"]
```

### 2.3 Image Size Optimization Metrics
By adopting this precise multi-stage standalone pattern, deployment telemetry consistently demonstrates massive optimizations. Images historically bloated to 2GB or 7.5GB (when including extensive dev environments) are slashed by over 90%, typically resting between 100MB and 310MB [cite: 7, 8, 9, 10]. This structural efficiency translates directly to faster orchestration deployments and reduced bandwidth overhead.

---

## 3. Environment Variables: The `NEXT_PUBLIC_` Build-Time Limitation

Environment variable management in containerized Next.js applications represents one of the most misunderstood and critically flawed areas of self-hosted deployment [cite: 12, 13]. Next.js enforces strict rules differentiating server-side configuration from client-side execution contexts.

### 3.1 The Mechanics of Build-Time Inlining
By design, Next.js securely restricts environment variables to the Node.js server environment [cite: 14, 15]. To expose a variable to the browser, it must be prefixed with `NEXT_PUBLIC_` [cite: 12, 14, 16]. 

However, the core limitation is that Next.js achieves this exposure by **inlining the values at build time** during `next build` [cite: 12, 14, 16, 17]. The Webpack/Turbopack compiler parses the code, identifies expressions like `process.env.NEXT_PUBLIC_API_URL`, and statically replaces the AST node with a hardcoded string, e.g., `"https://api.example.com"` [cite: 15, 17].

### 3.2 The Docker "Build Once, Deploy Anywhere" Paradox
The 12-Factor App methodology mandates strict separation of configuration from code, dictating that a single artifact (Docker image) should be built once and promoted across multiple environments (Dev, Staging, Prod) by merely swapping environment variables at container startup [cite: 12, 18]. 

Because `NEXT_PUBLIC_` variables are baked into static JavaScript bundles during `docker build`, changing the `NEXT_PUBLIC_` variable in your `docker-compose.yml` or Kubernetes `Deployment` at runtime **will have zero effect on the client** [cite: 12, 14, 18, 19]. The build artifact is permanently sealed [cite: 14, 18].

### 3.3 Strategies for Promoting a Single Docker Image

To achieve genuine environment portability without triggering separate Docker builds for every environment, developers must bypass the `NEXT_PUBLIC_` inlining mechanism.

#### Strategy A: Server-Side Injection via Server Components (App Router)
In the modern App Router, Server Components run entirely on the Node.js runtime [cite: 17]. Therefore, they can read standard (non-public) runtime environment variables and pass them as props to Client Components (`"use client"`).

```tsx
// app/page.tsx (Server Component)
import { ClientInteractiveMap } from './ClientInteractiveMap';

export default function Page() {
  // Read runtime environment variable. Not prefixed with NEXT_PUBLIC_.
  // This is evaluated dynamically at request time (or revalidation time).
  const mapApiKey = process.env.MAP_API_KEY; 

  return (
    <main>
      <h1>Location Services</h1>
      {/* Pass safely to the client boundary */}
      <ClientInteractiveMap apiKey={mapApiKey} />
    </main>
  );
}
```
```tsx
// app/ClientInteractiveMap.tsx (Client Component)
'use client';

export function ClientInteractiveMap({ apiKey }: { apiKey: string | undefined }) {
  // apiKey is securely available at runtime based on the container's environment
  return <div data-key={apiKey}>Map Initialization...</div>;
}
```

#### Strategy B: Dynamic API Route Initialization
If global client-side variables are required outside the React tree (e.g., in external utility libraries or analytics singletons), you must serve them via an API route dynamically [cite: 14, 15].

```tsx
// app/api/config/route.ts
import { NextResponse } from 'next/server';

export async function GET() {
  return NextResponse.json({
    apiUrl: process.env.RUNTIME_API_URL,
    analyticsId: process.env.RUNTIME_ANALYTICS_ID,
  });
}
```
The client application must subsequently fetch this configuration on application initialization, effectively deferring execution until the runtime environment variables are resolved via the network layer [cite: 14, 15].

#### Strategy C: Docker Build Arguments (The Anti-Pattern)
If strict build-once promotion is abandoned, developers can pass `ARG` variables to Docker during the build stage. While this satisfies the Next.js compiler, it fundamentally breaks the CI/CD pipeline's agility by necessitating distinct image compilations for Dev, Staging, and Production [cite: 13, 19].

```dockerfile
# Inside Stage 2: Builder
ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL
RUN npm run build
```

---

## 4. Architectural Runtimes: Edge Network vs. Node.js Environment

In server-side rendering and API execution, Next.js bifurcates the execution context into two distinct runtimes: The Node.js Runtime and the Edge Runtime [cite: 20, 21, 22, 23]. Understanding the API surface differences and cold start characteristics is vital for architectural planning.

### 4.1 The Node.js Runtime (Default)
The Node.js Runtime executes within standard Node.js processes, offering complete access to the Node ecosystem [cite: 20, 21, 23].
*   **Capabilities**: Full support for native modules, `fs` (filesystem), `net` (networking), `child_process`, and unconstrained database drivers (e.g., `pg`, `mysql2`) [cite: 22, 23].
*   **Latency & Cold Starts**: When deployed to serverless environments (like AWS Lambda or Vercel Serverless Functions), cold boots are noticeable (often ~250ms to over 1000ms), delaying the initial Time to First Byte (TTFB) [cite: 20, 21, 24].
*   **Code Size**: Accommodates substantial codebases, with Vercel limits typically hovering around 50MB for serverless functions [cite: 20, 21].

### 4.2 The Edge Runtime
The Edge Runtime is a stripped-down, lightweight environment built upon V8 Isolates. It does not run a full Node.js event loop [cite: 23, 24]. Instead, it strictly enforces compatibility with standard Web APIs (`fetch`, `Request`, `Response`, `Web Streams`, `crypto`) [cite: 20, 21, 24].
*   **Capabilities**: Cannot use modules reliant on `fs`, `eval()`, or Node-native C++ binaries [cite: 23, 24]. "Dynamic code evaluation not supported" is a frequent failure point when migrating complex legacy code to Edge [cite: 24]. 
*   **Latency & Cold Starts**: Near-instantaneous cold boots (sub-10ms) [cite: 21, 24]. Due to their distributed nature across global CDN nodes, Edge functions process requests geographically adjacent to the user, drastically minimizing physical network latency [cite: 22].
*   **Code Size Constraints**: Vercel heavily restricts Edge function sizes, typically limiting them strictly to 1MB–4MB, enforcing extremely lean dependencies [cite: 20, 21, 24].

### 4.3 Use-Case Decision Matrix

| Characteristic | Node.js Runtime | Edge Runtime |
| :--- | :--- | :--- |
| **Execution Environment** | Centralized Server / Serverless Lambda | V8 Isolate on Distributed Global Network |
| **Cold Boot Time** | High (~250ms - 1000ms) [cite: 21, 24] | Low / Instant (Sub-10ms) [cite: 21, 24] |
| **API Surface** | Full Node APIs (`fs`, `net`, etc.) [cite: 20, 23] | Web Standard APIs only (`fetch`, streams) [cite: 23, 24] |
| **Ideal Workloads** | Complex business logic, direct database ORM connections, heavy computational tasks [cite: 22] | Auth checks, localized redirects, header manipulation, A/B testing [cite: 24] |
| **Instrumentation** | Full OpenTelemetry SDK support [cite: 23] | Manual instrumentation via `WebTracerProvider` [cite: 23] |

### 4.4 Implementing the Edge Runtime
The runtime can be specified on a per-route or per-layout basis using the exported `runtime` variable [cite: 22, 24]:

```typescript
// app/api/geolocation/route.ts
export const runtime = 'edge';

export async function GET(request: Request) {
  // Access Web APIs natively
  const { searchParams } = new URL(request.url);
  return new Response("Hello from the Edge network!");
}
```

---

## 5. Vercel-Specific Features vs. Self-Hosted Infrastructure Constraints

Vercel heavily optimizes Next.js features using its proprietary framework-aware infrastructure. When self-hosting via Docker and Kubernetes, developers must manually engineer equivalent solutions to prevent systemic failure, data inconsistency, and degraded performance [cite: 25, 26].

### 5.1 The Caching and ISR Persistence Problem ("Split-Brain")
On Vercel, Incremental Static Regeneration (ISR) and the Data Cache are automatically propagated across a durable, globally consistent edge network [cite: 27]. When a revalidation occurs, the Vercel CDN purges globally across all regions within 300ms, collapsing concurrent requests to prevent backend thundering herds [cite: 27].

In a self-hosted Docker environment, Next.js utilizes the `FileSystemCache` by default, storing ISR and RSC payloads locally on disk within `.next/cache` [cite: 16, 25, 26, 28]. In a horizontal scaling scenario (e.g., Kubernetes with 3+ replicas), this creates severe architectural flaws:
1.  **The Split-Brain Anomaly**: User A hits Pod 1 and receives a fresh cache. User B hits Pod 2, triggering a cache miss or receiving stale data. Responses vary wildly depending on load balancer routing [cite: 25, 26].
2.  **Redundant Compute**: If an ISR page expires, multiple pods will independently and simultaneously rebuild the identical page, needlessly querying databases and exhausting computational resources [cite: 25, 26].
3.  **Deployment Ephemerality**: If a pod crashes and restarts, its local cache is annihilated [cite: 26].

### 5.2 Image Optimization Capabilities
Vercel executes Next.js `next/image` optimization dynamically through dedicated, serverless image-processing workers [cite: 29, 30]. 

Self-hosted Next.js defaults to running Image Optimization on the primary Node.js server loop [cite: 29, 31]. This is highly CPU-intensive and computationally expensive [cite: 30, 32]. Under heavy load, image resizing can bottleneck the main thread, resulting in catastrophic application slowdowns [cite: 25, 31]. Furthermore, Next.js historically utilized WebAssembly alternatives (like Squoosh), but modern production deployments fundamentally require the `sharp` C++ library for reasonable performance [cite: 30, 33].

### 5.3 Server Actions Cryptographic Consistency
Next.js secures Server Actions by encrypting closure variables passed between the server and the client [cite: 16, 28]. During a standard build process, Next.js randomly generates a 32-byte encryption key. 

If multiple Docker containers are built separately, or if rolling deployments occur where Pod A runs Version N and Pod B runs Version N+1, the encryption keys will mismatch [cite: 28]. A Server Action dispatched from the client might hit a container lacking the matching decryption key, immediately failing with "Failed to find Server Action" errors [cite: 16, 34].

**Resolution**: You must declare a deterministic, globally shared `NEXT_SERVER_ACTIONS_ENCRYPTION_KEY` base64-encoded environment variable uniformly across all replica pods [cite: 16, 34].

---

## 6. Overcoming Self-Hosted Limitations: Distributed Cache Handlers

To rectify the "Split-Brain" caching anomaly, Next.js exposes a `cacheHandler` configuration that allows self-hosted developers to redirect caching operations from the local filesystem to a distributed key-value store, typically Redis [cite: 26, 28, 35].

### 6.1 The Singular vs. Plural CacheHandler API
Historically, and stabilized in Next.js 14.1, the singular `cacheHandler` property in `next.config.ts` intercepted legacy ISR generation and standard Route Handler fetches [cite: 28, 36]. With modern Next.js 15+ environments, the framework introduces a more complex caching heuristic, eventually driving towards plural `cacheHandlers` designed specifically to intercept the new `"use cache"` RSC directives [cite: 28].

However, for standard ISR invalidation, overriding the primary `cacheHandler` and forcing `cacheMaxMemorySize: 0` is crucial to completely circumvent local caching [cite: 26, 36].

### 6.2 Redis Distributed Cache Implementation
Implementing a Redis-backed `cacheHandler` demands a custom class conforming to the Next.js Cache API (`get`, `set`, and `revalidateTag`). 

**Step 1: Configuration in `next.config.ts`**
```typescript
// next.config.ts
import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  output: 'standalone',
  // Reference the external caching file
  cacheHandler: process.env.NODE_ENV === 'production' 
    ? require.resolve('./cache-handler.mjs') 
    : undefined,
  // CRITICAL: Disable the built-in memory LRU. If this is omitted, 
  // Next.js will serve stale memory data before consulting Redis.
  cacheMaxMemorySize: 0, 
};

export default nextConfig;
```

**Step 2: Custom Redis Adapter (`cache-handler.mjs`)**
A robust implementation must manage timeouts, tag-based invalidation logic, and graceful degradation (falling back to a minimal in-memory structure if Redis disconnects) [cite: 26, 28, 35]. Open-source solutions like `@neshca/cache-handler` simplify this significantly [cite: 35, 37].

```javascript
// cache-handler.mjs
import { createClient } from 'redis';

const client = createClient({
  url: process.env.REDIS_URL,
});

client.on('error', (err) => console.error('Redis Cache Error', err));

// Establish connection implicitly for the singleton
const connectionPromise = client.connect();

export default class RedisCacheHandler {
  constructor(options) {
    this.options = options;
  }

  async get(key) {
    await connectionPromise;
    try {
      const data = await client.get(`nextjs-cache:${key}`);
      if (!data) return null;
      return JSON.parse(data);
    } catch (err) {
      console.warn("Redis Get Failure, bypassing cache.", err);
      return null; // Fallback to generating the page
    }
  }

  async set(key, data, ctx) {
    await connectionPromise;
    try {
      const payload = JSON.stringify(data);
      // Incorporate tags for revalidateTag capability
      if (ctx.tags) {
        for (const tag of ctx.tags) {
          // Add this key to a Redis SET representing the tag
          await client.sAdd(`nextjs-tags:${tag}`, key);
        }
      }
      
      // Enforce TTL based on Next.js revalidation settings
      const ttl = ctx.revalidate || 31536000; // default to 1 year if undefined
      await client.setEx(`nextjs-cache:${key}`, ttl, payload);
    } catch (err) {
      console.warn("Redis Set Failure", err);
    }
  }

  async revalidateTag(tag) {
    await connectionPromise;
    try {
      // Fetch all cached keys associated with this tag
      const keys = await client.sMembers(`nextjs-tags:${tag}`);
      if (keys.length > 0) {
        // Delete all associated cached pages
        const mappedKeys = keys.map(k => `nextjs-cache:${k}`);
        await client.del(mappedKeys);
      }
    } catch (err) {
      console.warn("Redis Tag Invalidation Failure", err);
    }
  }
}
```

### 6.3 Mitigating the Thundering Herd
In high-traffic self-hosted environments, when a Redis cache key expires, 50 concurrent requests might hit the cluster. Receiving a cache miss simultaneously, 50 Next.js processes will attempt to rebuild the page at once. Advanced self-hosted solutions must implement distributed locks (e.g., Redlock) inside the cache handler to enforce a "Spin-Wait" pattern—holding 49 requests while 1 request calculates and populates the cache [cite: 26].

---

## 7. Image Optimization Strategies in Self-Hosted Environments

### 7.1 The `sharp` Dependency
In previous versions of Next.js, `squoosh` was utilized as a fallback for WebAssembly-based image optimization. However, `squoosh` exhibited severe performance limitations. In modern Next.js 15 environments, manual installation of `sharp` is no longer strictly required as it defaults seamlessly, but verifying `sharp` compilation in Alpine Linux remains crucial [cite: 30, 33]. The required dependency `libc6-compat` must be injected into the Dockerfile [cite: 9].

### 7.2 Independent Image Optimization Services
Because Image Optimization via the default `<Image />` component taxes the Next.js primary event loop, horizontal scalability necessitates offloading [cite: 25, 31, 38]. 

**Option A: Cloud CDNs (Recommended)**
Configure `remotePatterns` in `next.config.ts` and deploy a secondary layer (like CloudFront or Cloudflare) in front of an S3 bucket. The CDN handles the delivery, though Next.js will still perform the initial format conversion to AVIF/WebP [cite: 32].

**Option B: Separate `ipx` Service or Platformatic**
Sophisticated self-hosters deploy an independent image processing service. The frontend Next.js app routes `/_next/image` requests strictly to a dedicated Next.js image optimizer service or a lightweight `ipx` daemon [cite: 25, 38]. This isolates heavy C++ memory allocations from the Next.js instances parsing React logic, dramatically increasing cluster stability under heavy load [cite: 25, 38].

---

## 8. Decision Trees for Next.js Deployment Architecture

The following decision matrices provide structured pathways for architecting Next.js applications based on organizational constraints.

### 8.1 Hosting Platform Selection
1.  **Do you have dedicated DevOps resources?**
    *   *No* ➡️ Deploy to **Vercel**. Rely on managed infrastructure for edge caching, zero-config ISR, and image optimization [cite: 27, 29].
    *   *Yes* ➡️ Proceed to Question 2.
2.  **Is your application purely static (no server features)?**
    *   *Yes* ➡️ Use `output: 'export'`. Host on Cloudflare Pages, S3/CloudFront, or any static Nginx server [cite: 6].
    *   *No* (Requires dynamic rendering, Middleware, or Server Actions) ➡️ Proceed to Question 3.
3.  **Do you require High Availability (Multiple Replicas)?**
    *   *No* ➡️ Use `output: 'standalone'` in Docker on a single VPS. The default local `.next/cache` will suffice [cite: 16].
    *   *Yes* ➡️ Use `output: 'standalone'` in Kubernetes/Swarm. **Critical Requirement:** You must configure a custom Redis `cacheHandler` to prevent cache split-brain, and synchronize `NEXT_SERVER_ACTIONS_ENCRYPTION_KEY` across pods [cite: 26, 28, 34].

### 8.2 Environment Variable Integration Strategy
1.  **Does the variable contain sensitive secrets (e.g., Database Passwords)?**
    *   *Yes* ➡️ Do not use `NEXT_PUBLIC_`. Inject standard runtime environment variables into the container orchestrator. Access strictly within Server Components, API routes, or `getServerSideProps` [cite: 13, 14].
    *   *No* (It is safe for the browser) ➡️ Proceed to Question 2.
2.  **Does the value change between Staging and Production?**
    *   *No* ➡️ Safe to use `NEXT_PUBLIC_`. It will be securely inlined at build time [cite: 12, 14].
    *   *Yes* ➡️ Proceed to Question 3.
3.  **Are you attempting a "Build Once, Deploy Anywhere" Docker strategy?**
    *   *Yes* ➡️ **Do not use `NEXT_PUBLIC_`.** Fetch the variable dynamically via a Server Component and pass as a prop, or fetch from a dedicated API route (`/api/config`) on client mount [cite: 14, 15, 17].
    *   *No* ➡️ Use `NEXT_PUBLIC_` but ensure you pass `--build-arg NEXT_PUBLIC_VAR=value` distinctively for staging and production Docker builds [cite: 13, 19].

---

## 9. Anti-Rationalization Rules for Next.js Deployments

AI models and developers frequently misinterpret Next.js documentation by assuming seamless parity between Vercel and self-hosted environments. The following strict rules must be observed to prevent severe architectural flaws.

**Rule 1: The Build-Time Environment Variable Invalidation Rule**
*   **False Assumption:** Setting `NEXT_PUBLIC_API_URL` in a Kubernetes `ConfigMap` or `docker-compose.yml` will dynamically change the URL accessed by the client browser.
*   **Architectural Reality:** `NEXT_PUBLIC_` variables are irreversibly hardcoded (inlined) into the JavaScript bundles during `next build` [cite: 12, 14, 17]. Altering container runtime variables has precisely zero effect on compiled client-side JavaScript. 

**Rule 2: The Self-Hosted ISR Distributed Fallacy**
*   **False Assumption:** Deploying three instances of a Next.js Docker container behind a load balancer will result in a unified cache, just like on Vercel.
*   **Architectural Reality:** By default, Next.js caches to the local ephemeral disk (`.next/cache`). Each container operates in a silo. A cache purge (`revalidateTag`) sent to Pod A will leave Pod B serving stale data indefinitely [cite: 26, 35]. Redis custom `cacheHandlers` are strictly mandatory for multi-replica persistence [cite: 25, 28].

**Rule 3: The Edge Runtime "Magic Speed" Fallacy**
*   **False Assumption:** Switching a complex API route to `export const runtime = 'edge'` will universally optimize the route.
*   **Architectural Reality:** The Edge runtime fundamentally lacks Node.js capabilities. Attempts to connect directly to PostgreSQL, manipulate the file system, use standard NPM modules relying on C++ binaries, or use `eval()` will instantly crash [cite: 23, 24]. Edge is strictly confined to Web API compliance [cite: 20, 24].

**Rule 4: The Standalone Directory Inclusion Rule**
*   **False Assumption:** `output: 'standalone'` bundles absolutely everything needed into one file or folder seamlessly.
*   **Architectural Reality:** The standalone output automatically generates the server, but it **omits** the `public/` directory (static assets) and the `.next/static/` directory (compiled client bundles). You must explicitly `COPY` these directories into the final Docker image adjacent to the standalone folder, or routing for static assets will 404 [cite: 8, 9].

**Rule 5: Server Actions Encryption Desync**
*   **False Assumption:** Rolling deployments of containers require no cryptographic configuration.
*   **Architectural Reality:** If the `NEXT_SERVER_ACTIONS_ENCRYPTION_KEY` is not manually fixed in the environment via base64 strings, different builds or asynchronous rolling pods will generate unique 32-byte keys [cite: 16]. Server Actions executed by clients bridging pods will suffer decryption failures, entirely breaking forms and mutations [cite: 28, 34].

**Sources:**
1. [dev.to](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHEnzm6oIWDSi5yXKBIIs_dWM7KusRyqa0Ko7xF8QL49RB_yh08gDQfpjppO-jlw79KN6IPjcP0WSqLbLjzLNJwtEUR1em675mjHeVgF-nSwTbr0B6RUsBIRviav4nMWrEXu_8oRMv8CYdlul6F5srqDDhUXD6d9vdnxh5-cGB3rQl6dx7v9yWRFJM5TyxAmMxB8aVvbD0b2z4U)
2. [nextjs.org](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFpogyMOJ6xIxjNVxz1txG1UtTjYudL99_TZKsQ9xVRrwjCRw1YOgSMKQBR_u9MS5CgDArfOmLoHRB3Ii1R4ofbPyR5qUcH2z7knVO08GukXHMOygOvBym9jO8D_wrUMZSd)
3. [nextjs.org](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHL-9UvDxWHrlzQw8UyITE5zYo9aTwFmfFXZL2z_RTObI3JWRoEnlqcsbDKH2O9u1dEix46RmdbLfkjzlrgqrP5-OVPuZmAkYcdpIUpG5r2_fQu-6uzFAB-DL7Er-ACS2zZL64w4zV-SwRJT2aBeDeavRWjGDKu1vtooAA1Y5Wd)
4. [nextjs.org](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHbKywoMUlJ6DkEOkN0WwZTtCraXqBRfepN4t7cGxbDBPTOIUIrV4NULRgX_CavYkqYXe5P0DSY9SOWdl8AEgk9W6O__jKcuWbpzIz245BKtONM3FKo)
5. [nextjs.im](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQERojhLiy0G1TT0jNlkvV7PrXU6fjoC341yZmQacjZ21OMbziB23n5_pDJqD5yoR6x7VUbtb0OIl3OXnqlS7ZE_Q0oRAHXl3UcEaWmCkbbjilpo5FRI7w==)
6. [scribd.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHMqi51FUF1JI1JmrBi5JLYveV7QQz_09xZLGVWbB0zxFbwwfvWZeGybPWaIfssJsADU_nSSILF5JRxH5_m0CrHezgYFGMXEK2j_4FS3UB9trx_lUb2C-nmL7x0Hm0eoA6piY3zyWH1hmRyKSHo7tX8IqGz5bw6LHUE)
7. [reddit.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHo2mR-hMX2CEl2rZG8FyUzhUqfPky41Wx4CFWLgeDMHZN1HdrTa1Pcd9ZdkcJHERn0h7k6klBm3eEeiQLbH4UHFlhxh54Lvb59QLz9vzRQ11HNXJZNggIqRlP19FXnMQHrI8BXfK6amU8uEYxBMxo385V9RqMRJqCKIBmKpR20HytWTAAol34UsCkvbmI3a0o6)
8. [oneuptime.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFpVcAq4PlX_sqUm0a1XqffGofU-6qfHhotGR8hGbqUvWBBG468KwRDDjqcCUZY6akF8XV_ekS6f7oZvW1c9oMiQOuFl4yCfxxXHK2EDVCApld76prckdgtLQ-DoSRXPqKwEU9V763FXXn4iaFoAJb0al8fEl5wDQL04bczXXOJHhM8UIetKM2qzBdSpWh6SoGF7yjftGly35ZDPoYSuedmaS8znlyQcfR3JARhVV_m1zprgdmQsQkiSyH5Fa2TQv6hQJ1sVJCquDA9)
9. [dev.to](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFq8G3a21lf5yFB-AezVxBTqrLinWdQPoeT7UUNZebjp6AZacAf44PBnGD1lB7fb7JF7gilJv6aRvBaQUk0DQHJibv1uY2h_s9Qk9_Qu3LcSy_VatbzpHmjQTYlFPHBt7A9jn4TLgZD3Pm0VZzjDDdowuJXmMUWoH8DOZdHmc79xF0_ZT_PUw==)
10. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGkytmd5TCKqUpg6VIDQ9Hv0myqIS4q5O4A5iolz4fEGsvGXO-DV0Q_GuR2xFY10uEnqqfdU4K3Air-XJf0bqiuQ67QIDPRfmjh7miw77_VMeTxn_zgXEc6B9n9PyK_M8JCexf6c5nd2_U6QCY-16-877CvFo7eE20WSoetb6nYDqqXCqt1NwiRPXW6LSOf2AT78aH8FLy0PgZD9NYp)
11. [github.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGaxmG13FL6LCt4pJ5RZg70jIrNwu4CRx-WisRuLqeFN4LPzenJ2efURS63iofUf4-ngXnigO9-mgozJYW7g-pYabSkgqhRLlCQGN9Gtw-s_-aaYKi0zodV7bbTWfQjeDBXdkfYgtM-IdjF42qTdokPSyzLKzMH6jqDV0DAGsSrI0VV)
12. [teamraft.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFZulIYCzRHlC-Fr0bu9mwp4NJdOMmzu5l--p4CM_cNg0H13064EmZ9oILNKoD2SEM1UBqFpBTXA8p0tuvV-yf2MiXfQco7ynuKvldQUBxTDtUVoAEegD90hI0pqZ3kqJ8ztPLIaBhHJiKaX773NYE=)
13. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEKna_KWDxKBhmPVSV2x2rwJ6KRHgaCkEftydEiyvPHo078Ky9qwUjrbpBcp85OZTmkUek7l75Nh1mULA7p5hLji-7ilPkjufzmOX5QJhens647MbGQuXeVc22t6FCN0y1761_CnfStaS_wWGsR0nvQIGPMW0nAIaaVxsftwtMEHb510Xoz07lQCejNt1Q=)
14. [nextjs.org](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHEEng8SmVPHChzNsf8DSA7Vwv2kWb7pIzhx2fSThi94uXPeij93W-UPK3QHtpoA2n6UM-DNJHXfE9U9u51xHsKfTwaXttFJsNU84TH55MIKhye7rm7DQIgDG7FSosIFRJ8PVDjCyUfDhQgVhWYs_oV)
15. [logrocket.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEJ6Q3lrZLAaPIKvTSN4JJRwTamInHoPhFN7CS50dJ5_I7QWrXtr5WasBDxSjqJ7Jmg33B_Pa_zcMgX2XyVxr4tnYjZIOq6J2Vdh0GipkG08pSg_9HGDkRl9WN0IVOrFmmx3lkiq0Q6ej4Sp6RELawOVPBzERbFoSxB)
16. [nextjs.org](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQG7nmDt3V6VfX2wjvjRA_9Gpq9aZA-uaHtrgnS1_fMsFfYFBA5BqQfnnG_JSe3PFShD3RhDtKnZssryI-hxsSSmIX2kUC3dypKhgLWmMZmjYiDQ5iXiUHTBdt9ZaZVZeOz3wEjrKJ8a)
17. [stackoverflow.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEpKYytRxeRC9eJ2ac3oSCZ0d9zv4lSvgAF-vC7vxv0ZOlNlXAdIEgOnwVC1v_ECJ9XfwEMl2XZplJNhSex3ZGw8LNxINJ_dGnOlSCN53SzK-qe4-2UnFUBZltqPm_-Qi3gXZmJmstNg2f6LGcB-sb4-8dq40nQP7M4bYVzLS1V0WpQJC6AUl30DPh7VklTcmtl0paewcm5x8M7w6E2WpTosQ2gkk1KhwVEkxXdQw==)
18. [tangiblebytes.co.uk](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE1HB4CXY1FfRAQDUJ1JCbXx4H145JSTIQj464UGeoziwlDSJrLYanQ3uAHnb2p2jS8UmGR_63ctum5XG0N1zzU245b3fEB7wr8cJ0bAPo3eRuYnIJLCxjhjhLtDx24qw35ud0mogN5J7157c11qg==)
19. [stackoverflow.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE0l_XLn8oBWIGEB4JLtfs3nqKx6YL3IokGACEY2RU2uf_P2F_i7T96PMbiLVxL93z18msylqeIyRJpEXUdgrINSK6GeI8SRLujq_OkIk8e5ovzg8pUk6JLGsamQFGWC0DxF6exhKoudXDtdirRxvoVs6lGU1L7tB9A2qnTJxgr54qOkZYaCPo3ggEL_GqOmJaeMyCYPgR6kIjkMIv_yx8gJY3XXgGjpYGwMMREFBwPJiJH)
20. [nextjs.org](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHheA1PK48biKNH9cA_lFyeU0IHSvIrFMutJzIdzXkGyA21n_g_Iad69DTOnhqJ1Kd_WI_KtOwDkl1yOgeniKU5pg4xDnw9UC_DgRbYUNKNUix4E6W8NP0WxiZYlm8nmb_2GFBw5DjJI-XEGzsJfFz7KQgAIyPQsWBq7TB49My5mDNpowX7xWJUdnwjgzjl_aRz)
21. [nextjs.org](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFhTOgLH3dVFvrOCVLH7VB__0gW6UfJp-i4fH6-VJfoVm76qQyhUWp12UOy_PRLDcZqCPHyVtcj2GWYKo7LUOWnHmDfJZacpQ5eewNJkINlKwGn6qHPqIFOpTugzFrQXGFjgDrEGk9sEoAJtAM5TUxDBRMCyry68gQPDdIcbJoJmTF_f1CTfOUZzIcui_aTypK-bEo=)
22. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFkcNC_F0CZXEtKBAjB8-2S_Vf0kSxhXOuGq7hyGGx5jTUnhu4WpqIqDhNk72OYItxmLQbxAXDHOPKO2bDa7bCL0ZCrTy5mgQwtEUzGgtRkW7Ju9cXhZ_oRwWs530X54vAVDvLhI4fmjxyD3PbrIpMIU8rr5Ou5r7Ypzev1kb0eMHfzC0RvyCkG5T0mHZkPtaynx7u0R09zvDqzlALUq9Yrw2sY)
23. [oneuptime.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFrrPZCcuafn8S8jCfNZqCMa6ifUWRjsnZAUjVi0s3Ax_CTUVIj8o7fDgmTzJP3-gx-Y4U-dozaq2Ykc9NUOuumE6VrewgkA4ffI_CEnnVOpIy8XjSq5yKtD5_gGcwC1wnayMnZto8pG7mhX4dJ7OkVRAPDtUNeCCK2WmLTd3vaioCF3_UY1lisYj35mo6_Puj88WimYLq0)
24. [dev.to](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGQrGZ_wGvMT7J_cjHSit4Yy9y59vfUkX1IF5zfK_qcidNNGLt5e6C9CHkbwbThpB4ugQzEv3cNU2x23RLjax7EYJL-3w1eIfxjQifFwQFjCfgBmTp6P68JQbRlBu1wD9mkhBLpCAzpHoADAGfNxijLP1q1gzcrEMmF2spXin_GIspyUgWfs0YVlJSuLPGxINim9uvUKrWZYywWe5nx-yMthV_9zFM=)
25. [dlhck.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEBQH_5MnXyHhbzAZYdIGPjYBit-5SMmZsXOSSxF2rTbaRLvR8DZnHZoU19QLitS06Ce6Vs40S9969KtYazwAT7hON7lZp6N_ZDleQP6QmoTSZKq189LhTTyXjqYqVLLjUg9evhIKRcNZfApYVHutmqyxs0xe0XRjRVueYJjBfuRB-nag==)
26. [azguards.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGRckxjyNrsVtNy4xkD4iEAqAQYNEIIyKGmW9EIry2ACbUbayMefOnLSuoedtjhu5jQpf5lIpe9SXEH9ezoi5tOFR3j-L14BnKrw7m3houGytSJ6bGpy3vGmkGPFvYlav5kJWBUx2NIMvz9GuKvcu6TxhGUDv0iOFErwhl26a8bt4ALb2O7yNCwDfoT3stNpSOUld_SQVEzUXI94LMXyca7gxAbT7RXJ8o1libm_9WEuOIZWmIZ_9GMth9-cEGh0wL4Aag=)
27. [vercel.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFU3H-vzQcIp6A9_qWoJLshUdTJS8K7J5WkoNin_9F6ua1jsONyaePU9WTZ0wiIt6RBH4eL6gGxvIv6Uq8-C5qxkcD97GlhyhkgzcZ3Z5kjc4KyxVCYCwbvxLV7iELbJ2Zv72MjBsA-KqRPzUHR)
28. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQElRIbCSB-H3umrX8YgyDOuwLkbQ2i2Gec0rCLQvtJADxdYgKe8QhFz353QIROD3oNbd84_7WIAb7knttMS0Kg1zL02-qjr3Yk-g83vMb7FOdal33vj4TdocOYnzOsB2jgCHoocWk2bIJNcMcp0WgpwcWtKyYMVwbx8xXL1n6nAg9WiptEl73acBGRjpp_7sfyamq0S0m1LvpwbmUD6sw2_jddHEwDYb5ZlsE8n0DYWZDVJY0n2d7Ks0xL0IJNX)
29. [vercel.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFINuEiNBPDWnPuNGYzuVi9MOmt0eY0_SWNXWueb90qQiOw2jn09dAd7zxF-CkUBDYRDJOHym1EjD6HJyfsEPps9saUK0snvTtN25C2aYtnSlKzIaQae8nnpt-O2szQPb1F-8Xj54YX5jYg)
30. [reddit.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHNc6qANx7LkVkfyF87XG5WBOq8yIouTDb1dbzkP6adR5hPHVXpBjQRYZlulx0Qr8nVvZZLQoD98R1TsLB4i2YVl4lPadmePPHZOdyfReqe2v2FwlZkaGetYbvJBzP4moieV7bDzIpahmQnNoyORiSYBV6kZP8GOyv3bm-kMoiDInnPhaoj6zzv0wynSaIqNK2Jh4LsTP8=)
31. [dev.to](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGBXo3RQ4NcLygE1SBMWMQe971yohc50xNVbJVscC6delbcpONgSAngJY8VkTN0acyZq7X3E8r3DiIF-WBLwgNfAifi-4Z6olLmtKscH74bV7qcv8xDLfJJQHtHcO-OZfxKVssPxVZLLjWD02OD8qt_tKeNNysPr422YFTBhP16v68tcCzkylEI7U2JTALfs-_G_MUUqXZABpCoayx6)
32. [strapi.io](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGjO7lU1ksqkoIHD8NOmyQrUVrl9t6MWVLMt9si6e4F44SgBTdI0LhvMmriVDX7qR2SE3zO2ypztlACw6AV2OWvaDi6mR79II5V_xP8GunySic0DmZ9cpDkjkZdbUq9HefJTGVGFo9ylyKbGgYv9MZjHZlnz9X2cA==)
33. [reddit.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEg8nPVWJ43tD4JCZRYIwufc5izlnVfc2UCHV6KjrLlYojTkP4_t2uTEjJ4Z0B5ajQO7Ac2fF690oR6hPxUQ_mdrYzTaGBWiR5O8VdKAzlhLTd-_P1MjKJNzIr_5qdXz97wQOYV-Xs0s1KabYSlZy3HE2mzGtZ0x-eYw9_lCQpBm1mRyUae-5yW_BgYSBkM17jKOMySOcDZFw==)
34. [nextjs.org](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFektfE8IfnzAoSPt2ifhwLtOpFckRctK-YsVtwLSrweMTKFRJ5DAIl-tgTIrLUtiSV5-8LyCkGbbhExJyalKogztN1sDw9hPA7qAsEU5pWBLHxPGLVliaeesRaKjgjjdndRkgDlA==)
35. [dev.to](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFfETieU5O9m7kv9TIBZ7nFii0B4zj5oKijvn5p6EQ3dwiUyVRfG6JXrnICHnRD07CYYLuy-ihT5uk0gdPlHgg06JJvEH5LMlv37htbinRBjOEF1HhGNx0qPJLAmCm8QJeIigkVx7x8SU8uHkGk5gVlpMHVtrFJA2sS)
36. [github.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQH-frbA5wlu9Lf81ydyYaubqUbFoNOg3XQh3Y96kYVDbWJ4JcauVxNy-kL_wDD2yb3fUGepDEFdqk_r-FuUBz3Jmd-4zMo3LzsrRa0yxoNuenOYaW0GAyMcd4nhov8r08DpR2fjYB6b_r8=)
37. [github.io](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE8CEEVxGW_Wsx19QrccDsEe8dJeE0pJnChrPbmwa9_gD0y1xo3_gg2809fHy8Z9VS3A6eZuQvon9jEvE2iSSU6DfstDZZ-MHjgDO932MxGkgSLLBMF4XfH6eC8wm5uKl8elTef0247gA==)
38. [platformatic.dev](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGOT_EG8UhZDquZ8E80l9-q2vJDgUW364a6WXjC8uQSbb4GxmQnOqaIDBPckr0TNbGL0tGrpkfztO1zxiVS-aIVQxMb1ZHqeDLzMomRckpAfQpN_vvnxGZpwkUJ6ynmy3kBFsznCjtTv4t5tBNLD6E_wYWPAdLgWaNgweTm6EtHYg==)
