---
name: mx-nextjs-data
description: "Next.js data fetching, Server Actions, 'use server', form handling, useActionState, Zod validation, revalidatePath, revalidateTag, fetch caching, ISR, on-demand revalidation, Route Handlers, four-layer caching, Data Cache, Router Cache, request memoization, Full Route Cache, generateStaticParams, streaming, mutations"
---

# Next.js Data — Fetching, Mutations, and Caching for AI Coding Agents

**Load this skill when fetching data, handling forms, writing Server Actions, configuring caching/ISR, or managing data mutations in Next.js App Router.**

## When to also load
- `mx-nextjs-core` — File conventions, routing structure
- `mx-nextjs-rsc` — Server/Client boundary affects where data is fetched
- `mx-nextjs-middleware` — Auth verification at data access layer
- `mx-nextjs-perf` — Parallel fetching, streaming, waterfall prevention

---

## Level 1: Server Actions and Form Handling (Beginner)

### Pattern 1: Server Actions Replace API Routes for Mutations

```tsx
// ❌ BAD — Creating an API route + client-side fetch for form submission
// app/api/create-post/route.ts + fetch('/api/create-post', { method: 'POST' })

// ✅ GOOD — Server Action directly in the form
// app/actions/posts.ts
'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';

const CreatePostSchema = z.object({
  title: z.string().min(1).max(200),
  content: z.string().min(1),
});

export async function createPost(prevState: any, formData: FormData) {
  const result = CreatePostSchema.safeParse({
    title: formData.get('title'),
    content: formData.get('content'),
  });

  if (!result.success) {
    return { errors: result.error.flatten().fieldErrors };
  }

  await db.post.create({ data: result.data });
  revalidatePath('/posts');
  return { success: true };
}
```

```tsx
// app/posts/new/page.tsx
'use client';
import { useActionState } from 'react';
import { createPost } from '@/app/actions/posts';

export default function NewPostForm() {
  const [state, formAction, isPending] = useActionState(createPost, null);

  return (
    <form action={formAction}>
      <input name="title" />
      {state?.errors?.title && <p>{state.errors.title}</p>}
      <textarea name="content" />
      {state?.errors?.content && <p>{state.errors.content}</p>}
      <button disabled={isPending}>
        {isPending ? 'Creating...' : 'Create Post'}
      </button>
    </form>
  );
}
```

### Pattern 2: Zod Validation Is Mandatory
Server Actions are public HTTP endpoints. TypeScript types are erased at runtime. Always validate with Zod:

```tsx
// ❌ BAD — Trusting TypeScript types at runtime
export async function updateUser(data: { name: string; email: string }) {
  await db.user.update({ data }); // Attacker can send ANY payload
}

// ✅ GOOD — Runtime validation
const schema = z.object({ name: z.string().min(1), email: z.string().email() });
export async function updateUser(prevState: any, formData: FormData) {
  const result = schema.safeParse(Object.fromEntries(formData));
  if (!result.success) return { errors: result.error.flatten().fieldErrors };
  await db.user.update({ data: result.data });
}
```

### Pattern 3: Auth in Every Server Action
Being on an authenticated page does NOT protect the action endpoint:

```tsx
'use server';
import { auth } from '@/lib/auth';

export async function deletePost(prevState: any, formData: FormData) {
  const session = await auth();
  if (!session) return { error: 'Unauthorized' };

  const postId = formData.get('postId') as string;
  const post = await db.post.findUnique({ where: { id: postId } });
  if (post?.authorId !== session.user.id) return { error: 'Forbidden' };

  await db.post.delete({ where: { id: postId } });
  revalidatePath('/posts');
}
```

### Pattern 4: Route Handler vs Server Action Decision

| Scenario | Use Server Action | Use Route Handler |
|----------|------------------|-------------------|
| Form submission from React component | ✅ | ❌ |
| Internal CRUD mutation | ✅ | ❌ |
| External API consumer / webhook | ❌ | ✅ |
| GET endpoint for client component data | ❌ | ✅ |
| File download / streaming response | ❌ | ✅ |
| Third-party integration (Stripe, etc.) | ❌ | ✅ |

---

## Level 2: Caching Architecture (Intermediate)

### Pattern 1: The Four-Layer Cache System

| Layer | Where | Scope | Default in Next.js 15 | Invalidation |
|-------|-------|-------|----------------------|--------------|
| Request Memoization | Server | Single render | Active (auto-dedup) | Automatic (render ends) |
| Data Cache | Server | Across requests/users | **OFF** (`no-store`) | `revalidateTag()`, `revalidatePath()`, time-based |
| Full Route Cache | Server | Across requests/users | Only for static routes | When Data Cache invalidates |
| Router Cache | Client | Single session (browser) | `staleTime: 0` for dynamic | Page refresh, `router.refresh()` |

### Pattern 2: Explicit Caching Opt-In (Next.js 15)

```tsx
// Fetch with explicit caching
const data = await fetch('https://api.example.com/products', {
  cache: 'force-cache',                    // Enable Data Cache
  next: { tags: ['products'] },            // Tag for targeted invalidation
});

// Fetch with time-based revalidation (ISR)
const data = await fetch('https://api.example.com/products', {
  next: { revalidate: 3600 },             // Revalidate every hour
});

// Fetch with no caching (default in Next.js 15)
const data = await fetch('https://api.example.com/user/me');
// No options needed — already uncached by default
```

### Pattern 3: Revalidation Strategies

```tsx
'use server';
import { revalidatePath, revalidateTag } from 'next/cache';

// Path-based: invalidates all data for a route
export async function updateProduct(id: string) {
  await db.product.update({ where: { id }, data: { ... } });
  revalidatePath('/products');         // Invalidates /products page
  revalidatePath('/products/[id]');    // Invalidates the product detail page
}

// Tag-based: more granular, works across pages
export async function updateInventory(productId: string) {
  await db.inventory.update({ ... });
  revalidateTag('products');           // Invalidates all fetches tagged 'products'
  revalidateTag(`product-${productId}`); // Invalidates specific product
}
```

**Prefer tag-based** — it's more precise and works across multiple routes sharing the same data.

### Pattern 4: ISR (Incremental Static Regeneration)

```tsx
// Route segment config for ISR
export const revalidate = 3600; // Revalidate this page every hour

// Or per-fetch ISR
const posts = await fetch('https://cms.example.com/posts', {
  next: { revalidate: 3600 },
});
```

ISR = stale-while-revalidate. First visitor after TTL gets stale page instantly; page regenerates in background for next visitor.

---

## Level 3: Advanced Data Patterns (Advanced)

### Pattern 1: Parallel Fetching — Kill Waterfalls

```tsx
// ❌ BAD — Sequential waterfall (500ms total)
async function Dashboard() {
  const user = await getUser();          // 200ms
  const analytics = await getAnalytics(); // 300ms
  return <>{/* ... */}</>;
}

// ✅ GOOD — Parallel with Promise.all (300ms total)
async function Dashboard() {
  const [user, analytics] = await Promise.all([
    getUser(),
    getAnalytics(),
  ]);
  return <>{/* ... */}</>;
}

// ✅ BETTER — Component-level parallelism with Suspense
function Dashboard() {
  return (
    <>
      <Suspense fallback={<UserSkeleton />}><UserSection /></Suspense>
      <Suspense fallback={<AnalyticsSkeleton />}><AnalyticsSection /></Suspense>
    </>
  );
}
```

### Pattern 2: Preload Pattern for Maximum Performance

```tsx
// lib/server/user.ts
import 'server-only';
import { cache } from 'react';

export const getUser = cache(async (id: string) => {
  return db.user.findUnique({ where: { id } });
});

// Preload function — call without await to start fetch early
export const preloadUser = (id: string) => { void getUser(id); };
```

```tsx
// app/user/[id]/page.tsx
import { preloadUser, getUser } from '@/lib/server/user';

export default async function UserPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  preloadUser(id);  // Start fetch immediately
  // ... other work ...
  const user = await getUser(id);  // Resolves instantly (already in-flight)
  return <UserProfile user={user} />;
}
```

### Pattern 3: generateStaticParams for Build-Time Rendering

```tsx
// app/blog/[slug]/page.tsx
export async function generateStaticParams() {
  const posts = await db.post.findMany({ select: { slug: true } });
  return posts.map((post) => ({ slug: post.slug }));
}

export default async function BlogPost({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const post = await db.post.findUnique({ where: { slug } });
  return <article>{post.content}</article>;
}
```

Pages pre-render at build time. New slugs fall back to dynamic rendering, then cache for subsequent visits.

### Pattern 4: Don't Call Your Own Route Handlers from Server Components

```tsx
// ❌ BAD — Unnecessary network hop
async function ProductList() {
  const res = await fetch('http://localhost:3000/api/products');
  const products = await res.json();
  return <>{/* ... */}</>;
}

// ✅ GOOD — Call the logic directly
import { getProducts } from '@/lib/server/products';
async function ProductList() {
  const products = await getProducts();
  return <>{/* ... */}</>;
}
```

---

## Performance: Make It Fast

### Perf 1: Tag-Based Revalidation Over Path-Based
`revalidateTag()` is surgical — only fetches with that tag re-execute. `revalidatePath()` blows away everything for that route. Use tags for fine-grained invalidation.

### Perf 2: POST Requests Are Never Cached or Deduped
By design. Mutations must always execute. Don't try to cache them.

### Perf 3: searchParams Forces Dynamic Rendering
Accessing `searchParams` anywhere opts the entire route segment into SSR. Isolate searchParams-dependent logic in a client component wrapped with `<Suspense>` to keep the rest of the page static.

---

## Observability: Know It's Working

### Obs 1: Monitor Cache Hit Rates
Use `next.config.ts` logging to surface cache behavior: `logging: { fetches: { fullUrl: true } }`. Shows whether fetches hit Data Cache or go to origin.

### Obs 2: Track Revalidation Failures
Failed `revalidateTag()`/`revalidatePath()` calls are silent — stale data persists. Log revalidation calls and monitor for ISR failures, especially on self-hosted deployments.

### Obs 3: Instrument Server Action Duration
Wrap Server Actions with OpenTelemetry spans to track mutation latency. Slow actions degrade form UX directly.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Assume fetch Is Cached
**You will be tempted to:** Write `fetch(url)` and assume it caches (Next.js 14 behavior).
**Why that fails:** Next.js 15 defaults to `no-store`. Every navigation re-fetches. Performance degrades, origin gets hammered.
**The right way:** Explicitly add `{ cache: 'force-cache' }` or `{ next: { revalidate: N } }` when you want caching.

### Rule 2: Never Use useEffect + fetch for Data
**You will be tempted to:** `useEffect(() => { fetch('/api/data')... })` in a client component.
**Why that fails:** Client-side waterfall — component renders → JS executes → fetch fires → data arrives. 3 round trips minimum. Invisible to crawlers.
**The right way:** Fetch in Server Components with `async/await`. Or use Server Actions for mutations.

### Rule 3: Never Skip Zod Validation in Server Actions
**You will be tempted to:** Trust TypeScript types and skip runtime validation.
**Why that fails:** Server Actions are public HTTP endpoints. Attackers bypass your UI and send raw POST requests with any payload.
**The right way:** `schema.safeParse(data)` in every Server Action. Return `error.flatten().fieldErrors` to the client.

### Rule 4: Never Forget Auth in Server Actions
**You will be tempted to:** Skip auth checks because "the page already checks auth."
**Why that fails:** Server Actions are reachable via direct HTTP POST. Page-level auth doesn't protect the endpoint.
**The right way:** Verify authentication AND authorization inside every Server Action body.

### Rule 5: useActionState Replaces useFormState
**You will be tempted to:** Import `useFormState` from `react-dom` (React 18 pattern).
**Why that fails:** Deprecated in React 19. `useActionState` from `react` is the replacement with identical API plus `isPending`.
**The right way:** `const [state, formAction, isPending] = useActionState(action, initialState);`
