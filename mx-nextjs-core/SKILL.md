---
name: mx-nextjs-core
description: "Next.js App Router architecture, file conventions (page.tsx, layout.tsx, loading.tsx, error.tsx, template.tsx, route.ts, not-found.tsx, default.tsx), route groups, parallel routes, intercepting routes, project structure, Next.js 15 breaking changes, await params, searchParams Promise, App Router patterns"
---

# Next.js Core — App Router Architecture for AI Coding Agents

**Load this skill for ANY Next.js App Router work — routing, file conventions, project structure, or page creation.**

## When to also load
- `mx-nextjs-rsc` — Server vs Client component decisions
- `mx-nextjs-data` — Data fetching, Server Actions, caching
- `mx-nextjs-perf` — Co-loads automatically on any Next.js work
- `mx-nextjs-observability` — Co-loads automatically on any Next.js work
- `mx-nextjs-seo` — Metadata API, OG images, sitemap
- `mx-nextjs-middleware` — Edge middleware, auth redirects
- `mx-nextjs-deploy` — Vercel vs self-hosted, Docker, env vars

---

## Level 1: File Conventions and Component Hierarchy (Beginner)

### Pattern 1: The Rendering Hierarchy
Next.js wraps route files in a strict order. Errors in `layout.tsx` CANNOT be caught by `error.tsx` in the same segment.

```
layout.tsx → template.tsx → error.tsx → loading.tsx → not-found.tsx → page.tsx
```

### Pattern 2: Async Params — Next.js 15 Breaking Change
`params`, `searchParams`, `cookies()`, `headers()`, and `draftMode()` are all Promises in Next.js 15.

```tsx
// ❌ BAD — Next.js 14 pattern, fails in Next.js 15
export default function Page({ params }: { params: { slug: string } }) {
  return <h1>{params.slug}</h1>;
}

// ✅ GOOD — Await the Promise
export default async function Page({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  return <h1>{slug}</h1>;
}
```

Applies to: `page.tsx`, `layout.tsx`, `route.ts`, `default.tsx`, `generateMetadata`, `generateViewport`.

### Pattern 3: Required Root Files
Every Next.js App Router project needs:
- `app/layout.tsx` — Root layout (mandatory). Defines `<html>` and `<body>`.
- `app/page.tsx` — Home route.
- `app/not-found.tsx` — Global 404 page.
- `app/error.tsx` — Global error boundary (must be `"use client"`).
- `app/global-error.tsx` — Catches errors in root layout itself (replaces entire `<html>`).

### Pattern 4: File Convention Cheat Sheet

| File | Purpose | Re-renders on nav? | Must be Client Component? |
|------|---------|--------------------|-|
| `layout.tsx` | Persistent UI shell | No — state preserved | No |
| `template.tsx` | Ephemeral UI shell | Yes — full remount | Often yes (needs hooks) |
| `error.tsx` | Error boundary | On error only | **Yes** (mandatory) |
| `loading.tsx` | Suspense fallback | Shown during fetch | No |
| `not-found.tsx` | 404 UI | When `notFound()` called | No |
| `page.tsx` | Route content | Yes | No |
| `route.ts` | API endpoint | N/A (HTTP handler) | N/A |
| `default.tsx` | Parallel route fallback | On hard navigation | No |

### Pattern 5: Layout vs Template Decision

| Need | Use layout | Use template |
|------|-----------|-------------|
| Persistent nav/sidebar | ✅ | ❌ |
| Auth/theme context providers | ✅ | ❌ |
| Page-view analytics on every nav | ❌ | ✅ |
| Per-page form reset | ❌ | ✅ |
| Entrance animations (framer-motion) | ❌ | ✅ |
| **Default choice** | **✅ 99% of cases** | Only when you need remount |

---

## Level 2: Advanced Routing Primitives (Intermediate)

### Pattern 1: Route Groups — Different Layouts, Same URL Space

```
app/
├── (marketing)/
│   ├── layout.tsx      ← Marketing layout (centered, minimal)
│   ├── page.tsx        ← /
│   └── about/page.tsx  ← /about
├── (dashboard)/
│   ├── layout.tsx      ← Dashboard layout (sidebar, auth)
│   ├── settings/page.tsx ← /settings
│   └── analytics/page.tsx ← /analytics
└── layout.tsx          ← Root layout (shared <html>, <body>)
```

Parentheses are stripped from URLs. `(marketing)/about/page.tsx` → `/about`.

### Pattern 2: Parallel Routes — Independent Sections

```tsx
// app/layout.tsx — slots become props
export default function Layout({
  children,
  team,
  analytics,
}: {
  children: React.ReactNode;
  team: React.ReactNode;
  analytics: React.ReactNode;
}) {
  return (
    <div className="dashboard">
      <div className="main">{children}</div>
      <div className="sidebar">{team}</div>
      <div className="bottom">{analytics}</div>
    </div>
  );
}
```

Each `@slot` has its own `loading.tsx` and `error.tsx`. **Always create `default.tsx` (returning `null`) in every `@slot`** — without it, hard refresh triggers 404.

### Pattern 3: Intercepting Routes — Modal Pattern

Combine `@modal` parallel route + `(.)` intercepting route for URL-shareable modals:

```
app/
├── @modal/
│   ├── default.tsx          ← returns null (required)
│   └── (.)photo/[id]/
│       └── page.tsx         ← Modal overlay (soft nav)
├── photo/[id]/
│   └── page.tsx             ← Full page (hard nav/direct URL)
├── layout.tsx               ← Renders {children} + {modal}
└── page.tsx                 ← Feed/gallery
```

**Close modals with `router.back()`**, not React state — the URL drives the modal.

### Pattern 4: Routing Decision Tree

| UI Goal | Primitive | Example |
|---------|-----------|---------|
| Separate layouts per section | Route group `(name)` | `(marketing)` vs `(dashboard)` |
| Side-by-side independent views | Parallel route `@slot` | Dashboard with `@team` + `@analytics` |
| Conditional rendering by auth | Parallel route | `@auth` slot checks role, returns different UI |
| Shareable modal overlay | Parallel + intercepting | `@modal/(.)item/[id]` over feed |
| URL-preserving modal | Intercepting `(.)` | Photo viewer, login modal |

---

## Level 3: Project Structure and Architecture (Advanced)

### Pattern 1: Recommended App Router Structure

```
src/
├── app/                    ← Routes ONLY (thin layer)
│   ├── (marketing)/
│   ├── (dashboard)/
│   ├── api/
│   ├── layout.tsx
│   └── page.tsx
├── components/             ← Shared UI components
│   ├── ui/                 ← Design system primitives
│   └── forms/
├── features/               ← Domain modules
│   ├── auth/
│   ├── products/
│   └── checkout/
├── lib/                    ← Utilities, DB clients, configs
│   ├── server/             ← Add `import 'server-only'` to every file
│   └── utils.ts
├── hooks/                  ← Custom React hooks
└── types/                  ← Shared TypeScript types
```

**Key rule**: `app/` is a thin routing layer. Page files import from `features/` or `components/`. Business logic never lives in `app/`.

### Pattern 2: Private Folders and Colocation
- Prefix with `_` to exclude from routing: `app/_components/button.tsx` is never URL-accessible.
- Colocate route-specific components inside route folders — they're ignored unless named `page.tsx` or `route.ts`.

### Pattern 3: searchParams Opts Into Dynamic Rendering
Accessing `searchParams` anywhere in a route forces the entire segment into dynamic rendering:

```tsx
// ❌ BAD — Makes entire /products route dynamic
export default async function Products({
  searchParams,
}: {
  searchParams: Promise<{ sort?: string }>;
}) {
  const { sort } = await searchParams;
  return <ProductList sort={sort} />;
}

// ✅ GOOD — Isolate searchParams in a client component with Suspense
export default function Products() {
  return (
    <StaticProductShell>
      <Suspense fallback={<ProductSkeleton />}>
        <DynamicProductList /> {/* This component reads searchParams */}
      </Suspense>
    </StaticProductShell>
  );
}
```

---

## Performance: Make It Fast

### Perf 1: Layouts Don't Re-render
Layouts skip re-rendering on navigation — this is free perf. Put heavy computations and shared data fetching in layouts to avoid redundant work.

### Perf 2: Streaming with loading.tsx
Every route segment with async data should have a `loading.tsx`. This enables streaming SSR — the shell renders instantly while data fetches in the background. Users see content faster.

### Perf 3: Parallel Data Fetching via Component Structure
Instead of sequential awaits in one component, split into parallel components each wrapped in Suspense:

```tsx
// ❌ BAD — Sequential waterfall
async function Dashboard() {
  const user = await getUser();     // 200ms
  const posts = await getPosts();   // 300ms  → Total: 500ms
  return <>{/* ... */}</>;
}

// ✅ GOOD — Parallel via component structure
function Dashboard() {
  return (
    <>
      <Suspense fallback={<UserSkeleton />}>
        <UserSection />   {/* Fetches independently */}
      </Suspense>
      <Suspense fallback={<PostsSkeleton />}>
        <PostsSection />  {/* Fetches independently */}
      </Suspense>
    </>
  );  // Total: max(200ms, 300ms) = 300ms
}
```

---

## Observability: Know It's Working

### Obs 1: Error Boundaries Per Route Segment
Place `error.tsx` at every meaningful route segment — not just root. Each boundary catches errors in its subtree, preventing full-page crashes. Log the error in `error.tsx` to your monitoring system.

### Obs 2: Template for Page-View Tracking
Use `template.tsx` (not layout) for analytics that must fire on every navigation:

```tsx
'use client';
import { useEffect } from 'react';
import { usePathname } from 'next/navigation';
import { trackPageView } from '@/lib/analytics';

export default function AnalyticsTemplate({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  useEffect(() => { trackPageView(pathname); }, [pathname]);
  return <>{children}</>;
}
```

### Obs 3: Monitor 404s with not-found.tsx
Log `notFound()` invocations in your `not-found.tsx` to detect broken links and crawl errors before they impact SEO.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Generate Pages Router Patterns
**You will be tempted to:** Use `getServerSideProps`, `getStaticProps`, `pages/` directory, `next/router`, or `next/head`.
**Why that fails:** These are Pages Router APIs. They do not exist in App Router. The app will fail to compile.
**The right way:** Use `async` Server Components for data fetching, `app/` directory for routes, `next/navigation` for routing hooks, Metadata API for SEO.

### Rule 2: Always Await params and searchParams
**You will be tempted to:** Destructure `params` synchronously: `({ params: { slug } })`.
**Why that fails:** `params` is a Promise in Next.js 15. Synchronous destructuring produces `undefined` or a type error.
**The right way:** `const { slug } = await params;` — always await before destructuring.

### Rule 3: Never Omit default.tsx in Parallel Routes
**You will be tempted to:** Skip `default.tsx` in `@slot` folders since soft navigation works without it.
**Why that fails:** Hard refresh (F5, direct URL) crashes with 404 because Next.js can't determine what to render for unmatched slots.
**The right way:** Always create `default.tsx` in every `@slot` — even if it just returns `null`.

### Rule 4: error.tsx Cannot Catch Layout Errors
**You will be tempted to:** Rely on `error.tsx` to handle errors from `layout.tsx` in the same segment.
**Why that fails:** `layout.tsx` wraps `error.tsx` in the hierarchy — errors bubble UP to the parent segment's error boundary.
**The right way:** Use `global-error.tsx` for root layout errors. For nested layouts, the parent segment's `error.tsx` catches the error.

### Rule 5: Never Use loading.tsx for Layout Data
**You will be tempted to:** Expect `loading.tsx` to show a spinner while `layout.tsx` fetches data.
**Why that fails:** `loading.tsx` wraps `page.tsx`, not `layout.tsx`. The layout blocks until its fetch completes — frozen UI, no spinner.
**The right way:** Wrap async layout data in its own `<Suspense>` boundary inside the layout component.
