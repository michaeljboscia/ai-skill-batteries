# Next.js 15 Data Fetching, Server Actions, and Caching Architecture: A Comprehensive Technical Reference

**Key Points**
*   **Next.js 15 Caching Shift:** The framework has fundamentally transitioned from an aggressive "cached by default" model to an "uncached by default" paradigm, requiring explicit opt-ins for data persistence [cite: 1, 2].
*   **Asynchronous Request APIs:** APIs dependent on request-specific data (e.g., `cookies`, `headers`, `params`, `searchParams`) must now be awaited asynchronously to enable aggressive server-side optimizations [cite: 1, 3].
*   **Server Actions Evolution:** React 19 and Next.js 15 deprecate `useFormState` in favor of `useActionState`, which manages form state, error handling, and pending states directly in client components alongside robust Zod validation patterns [cite: 4, 5].
*   **Four-Layer Caching:** Next.js utilizes a complex, interacting caching system consisting of Request Memoization, Data Cache, Full Route Cache, and Router Cache, each with distinct lifespans and invalidation mechanisms [cite: 6, 7].

**Understanding the Architectural Paradigm Shift**
The evolution from Next.js 14 to Next.js 15 represents a crucial maturation of the App Router architecture. Initial versions of the App Router prioritized default performance through aggressive caching, which occasionally led to unpredictable developer experiences and persistent stale data issues. Research suggests that the Next.js 15 update prioritizes developer control and predictability by requiring explicit declarations for caching and asynchronous handling of request parameters [cite: 2, 8].

**Navigating the Component Ecosystem**
This guide provides a comprehensive technical reference for the Next.js 15 ecosystem, synthesizing data fetching best practices, caching interactions, and mutation strategies. While the ecosystem is stabilizing, the introduction of experimental features like `dynamicIO` and the `use cache` directive indicates that caching primitives will continue to evolve [cite: 8, 9]. Developers must navigate these changes carefully, explicitly balancing the performance benefits of caching with the accuracy requirements of dynamic data.

---

## 1. The Next.js 15 Caching Overhaul and Opt-In Paradigm

The most significant behavioral change in Next.js 15 is the transition from a "cached by default" architecture to an "uncached by default" model [cite: 1]. This modification directly addresses developer feedback regarding the difficulty of debugging stale data caused by opaque caching layers [cite: 2, 10].

### 1.1 The Transition from `force-cache` to `no-store`

In Next.js 14, standard `fetch` requests were automatically cached indefinitely using the `force-cache` directive unless explicitly opted out using `no-store` or dynamic functions [cite: 1, 11]. In Next.js 15, standard `fetch` calls are treated as dynamic and default to `no-store` [cite: 11, 12]. 

To restore the previous caching behavior for a specific request, developers must now explicitly pass the `force-cache` option:

```typescript
// Next.js 14 behavior (Implicitly cached)
// const data = await fetch('https://api.example.com/data');

// Next.js 15 behavior (Explicitly cached)
const data = await fetch('https://api.example.com/data', { 
  cache: 'force-cache' 
});
```

Furthermore, **GET Route Handlers** are no longer cached by default [cite: 2]. Previously, a static `GET` handler without dynamic inputs would be evaluated at build time. To opt a Route Handler into static generation, the file must explicitly define the static configuration:

```typescript
// app/api/cached-data/route.ts
export const dynamic = 'force-static'; // Explicit opt-in required in Next.js 15

export async function GET() {
  const data = await fetchDatabase();
  return Response.json(data);
}
```

### 1.2 Asynchronous Request APIs

To prepare for future optimizations like Partial Prerendering (PPR) and to allow the server to prepare non-request-specific data ahead of time, Next.js 15 mandates that all APIs relying on request-time information be treated as asynchronous [cite: 1, 3]. 

The affected APIs include `cookies()`, `headers()`, `draftMode()`, `params`, and `searchParams` [cite: 1]. These must be awaited before their properties can be accessed.

```typescript
// app/products/[id]/page.tsx
import { cookies } from 'next/headers';

type Props = {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ sort?: string }>;
};

export default async function ProductPage({ params, searchParams }: Props) {
  // 1. Await dynamic route parameters
  const { id } = await params;
  const { sort } = await searchParams;

  // 2. Await request-specific headers/cookies
  const cookieStore = await cookies();
  const theme = cookieStore.get('theme')?.value ?? 'light';

  return (
    <div>
      <h1>Product {id}</h1>
      <p>Sorted by: {sort}</p>
      <p>Theme: {theme}</p>
    </div>
  );
}
```

### 1.3 The `use cache` Directive and `dynamicIO`

Next.js 15 introduces an experimental paradigm known as `dynamicIO`, paired with the `use cache` directive [cite: 8, 13]. When the `dynamicIO` flag is enabled in `next.config.ts`, the application becomes strictly "cache opt-in" [cite: 13]. The `use cache` directive allows developers to cache entire files, individual asynchronous functions, or specific server components [cite: 6, 9].

Functions utilizing the `use cache` directive must be pure; they cannot contain side-effects, mutate state, or manipulate the DOM directly [cite: 9].

```typescript
// next.config.ts
export default {
  experimental: {
    dynamicIO: true,
  },
};
```

```typescript
// lib/data.ts
import { db } from '@/lib/db';

// Explicitly cache this function's return value
export async function getAnalytics() {
  'use cache';
  const data = await db.analytics.aggregate();
  return data;
}
```

This feature is complemented by functions like `cacheLife` (to set custom cache durations profiles like "days" or "hours") and `cacheTag` (to tag the cache for on-demand invalidation) [cite: 13, 14].

### Anti-Rationalization Rules: Next.js 15 Caching
*   **AI Anti-Pattern:** Generating code that assumes `fetch('/api/data')` is permanently cached by default.
    *   **Correction:** In Next.js 15, `fetch` defaults to `no-store` [cite: 11]. You must explicitly append `{ cache: 'force-cache' }` [cite: 15].
*   **AI Anti-Pattern:** Accessing `params.id` or `searchParams.query` synchronously in Next.js 15 page props.
    *   **Correction:** `params` and `searchParams` are Promises and must be destructured after an `await` [cite: 1, 16].
*   **AI Anti-Pattern:** Creating `app/api/data/route.ts` with a `GET` method and assuming it will compile to static HTML automatically.
    *   **Correction:** `GET` handlers are completely dynamic by default in Next.js 15. You must add `export const dynamic = 'force-static'` to cache them [cite: 2, 17].

---

## 2. The Four-Layer Caching Architecture

Understanding Next.js caching requires abandoning the mental model of a single, unified cache. Next.js App Router relies on four distinct caching layers operating at different stages of the request lifecycle [cite: 7, 18]. When caching issues arise (e.g., stale data, unwanted refetches), they are almost always due to a misunderstanding of how these layers interact [cite: 7].

### 2.1 Layer 1: Request Memoization
**Scope:** Single render pass, single request (Server-side).
**Lifespan:** Destroyed immediately after the React component tree finishes rendering [cite: 7, 19].

Request Memoization is a React feature, not strictly a Next.js feature [cite: 7]. If the same `fetch` URL and options are called in multiple server components during a single render cycle, React intercepts the redundant calls and executes only one actual network request [cite: 6]. The result is shared across the render tree, preventing identical API or database calls and removing the need to fetch data at the top of the tree and pass it down via props [cite: 19, 20].

### 2.2 Layer 2: The Data Cache
**Scope:** Persistent across multiple requests and users (Server-side).
**Lifespan:** Indefinite (if `force-cache` is used) until actively revalidated or purged [cite: 6, 7].

The Data Cache persists the results of `fetch` requests across multiple users. When a `fetch` is explicitly opted into caching (`force-cache`), Next.js stores the JSON payload in the server's file system or an external cache (like Vercel Data Cache) [cite: 6, 7]. This drastically reduces load on the origin database or backend API [cite: 20]. 

### 2.3 Layer 3: The Full Route Cache
**Scope:** Persistent across multiple requests and users (Server-side).
**Lifespan:** Persists until the deployment is updated or underlying Data Cache is invalidated [cite: 6, 19].

The Full Route Cache (historically related to Static Site Generation) stores the fully rendered HTML and the React Server Component (RSC) payload for an entire static route [cite: 7, 19]. Instead of rendering the React component tree for every visitor, Next.js serves the pre-rendered HTML/RSC payload. 

**Interaction Rule:** The Full Route Cache and Data Cache are inextricably linked. If you invalidate the Data Cache (via `revalidateTag`), Next.js automatically invalidates the Full Route Cache for any page that depends on that data, regenerating the page in the background (Incremental Static Regeneration) [cite: 6].

### 2.4 Layer 4: The Router Cache
**Scope:** Client-side only (Browser memory).
**Lifespan:** Session-based. Invalidated on full page refresh [cite: 6].

The Router Cache stores the React Server Component payloads of visited routes and prefetched routes in the user's browser [cite: 6, 19]. This enables instant back/forward navigation without network requests. In Next.js 15, the `staleTime` for dynamic page segments has been reduced to `0`, meaning the client will always fetch the latest page component data during in-app navigation, preventing the common "stale data after navigation" bug prevalent in Next.js 14 [cite: 2, 11].

### 2.5 Cache Invalidation Strategies: `revalidatePath` vs `revalidateTag`

To purge cached data, Next.js provides two primary mechanisms:

1.  **`revalidatePath(path)`**: Purges the Data Cache and Full Route Cache for a specific URL route [cite: 6]. It is a blunt instrument, useful when a single page's data has mutated.
2.  **`revalidateTag(tag)`**: Purges cached data globally based on a custom string tag [cite: 6, 8]. This is highly precise and the recommended pattern for complex apps.

```typescript
// Fetching with a cache tag
const data = await fetch('https://api.example.com/posts', {
  cache: 'force-cache',
  next: { tags: ['posts-list'] }
});

// Mutating and revalidating in a Server Action
'use server';
import { revalidateTag } from 'next/cache';

export async function createPost(formData: FormData) {
  await db.post.create({...});
  // Invalidates the specific fetch anywhere in the app
  revalidateTag('posts-list'); 
}
```

### Anti-Rationalization Rules: 4-Layer System
*   **AI Anti-Pattern:** Assuming `router.refresh()` clears the Data Cache on the server.
    *   **Correction:** `router.refresh()` only invalidates the client-side **Router Cache** and triggers a new request to the server. It does *not* purge the server-side **Data Cache** [cite: 6].
*   **AI Anti-Pattern:** Using `revalidatePath` inside a Client Component.
    *   **Correction:** `revalidatePath` and `revalidateTag` are Node.js environment functions. They can only be executed within Server Actions or Route Handlers [cite: 6, 21].
*   **AI Anti-Pattern:** Explaining that Request Memoization persists across different users.
    *   **Correction:** Request Memoization is strictly bound to a single render pass for a single request. It wipes immediately after rendering [cite: 6, 7].

---

## 3. Server Actions and Form Handling Architecture

Server Actions represent a paradigm shift in handling mutations, allowing developers to execute secure, server-side functions directly from client components or HTML forms without manually constructing API endpoints [cite: 21, 22].

### 3.1 `useActionState` vs `useFormStatus`

In React 19 and Next.js 15, the `useFormState` hook is deprecated and replaced by the more generic `useActionState` [cite: 5, 15]. 

*   **`useActionState`:** A hook imported from `react` that manages the state of a Server Action. It accepts a Server Action and an initial state, returning an array containing the current state, a bound action to pass to the `<form action={...}>`, and an `isPending` boolean [cite: 23]. Because it returns `isPending`, it often eliminates the need for `useFormStatus` entirely for simple forms [cite: 4].
*   **`useFormStatus`:** A hook imported from `react-dom` that tracks whether the parent `<form>` is currently submitting. It must be used in a child component nested *inside* the `<form>` [cite: 23]. It is primarily useful for creating deeply nested, reusable submit buttons that don't have direct access to the `useActionState` pending flag [cite: 23, 24].

### 3.2 The Zod Validation Pattern

For production-grade applications, Server Actions must validate incoming `FormData`. Because Server Actions are publicly exposed endpoints (even if hidden in UI), trusting client data is a severe security vulnerability [cite: 2]. The industry standard pattern utilizes **Zod** for schema validation, returning an `ActionState` object containing success flags, messages, and field-level errors [cite: 5, 25].

### 3.3 Runnable Code Example: End-to-End Form Architecture

Below is a complete, runnable architecture demonstrating `useActionState`, Zod validation, error handling, and the Next.js 15 `<Form>` component [cite: 1, 26].

**1. Define the Types and Schema (`actions/schema.ts`)**
```typescript
import { z } from 'zod';

export const CreateUserSchema = z.object({
  username: z.string().min(3, "Username must be at least 3 characters."),
  email: z.string().email("Please enter a valid email address."),
});

// The standard Action State pattern
export type ActionState = {
  success: boolean;
  message: string;
  errors?: {
    username?: string[];
    email?: string[];
  };
  inputs?: {
    username: string;
    email: string;
  };
};
```

**2. Create the Server Action (`actions/user.ts`)**
```typescript
'use server';

import { revalidatePath } from 'next/cache';
import { ActionState, CreateUserSchema } from './schema';
import { db } from '@/lib/db'; // Fictional DB

export async function createUserAction(
  prevState: ActionState, 
  formData: FormData
): Promise<ActionState> {
  const rawData = {
    username: formData.get('username') as string,
    email: formData.get('email') as string,
  };

  // 1. Zod Validation
  const validatedFields = CreateUserSchema.safeParse(rawData);

  if (!validatedFields.success) {
    return {
      success: false,
      message: 'Please fix the validation errors.',
      errors: validatedFields.error.flatten().fieldErrors,
      inputs: rawData, // Return inputs to preserve user data
    };
  }

  // 2. Database Mutation (Simulated)
  try {
    await db.user.create({ data: validatedFields.data });
    
    // 3. Cache Invalidation
    revalidatePath('/users');
    
    return {
      success: true,
      message: 'User created successfully!',
    };
  } catch (error) {
    return {
      success: false,
      message: 'An internal server error occurred.',
      inputs: rawData,
    };
  }
}
```

**3. Wire it into the Client Component (`components/UserForm.tsx`)**
```tsx
'use client';

import { useActionState } from 'react';
import Form from 'next/form'; // Next.js 15 Form component
import { createUserAction } from '@/actions/user';
import { ActionState } from '@/actions/schema';

const initialState: ActionState = {
  success: false,
  message: '',
};

export function UserForm() {
  // useActionState tuple: [currentState, boundAction, pendingStatus]
  const [state, formAction, isPending] = useActionState(
    createUserAction, 
    initialState
  );

  return (
    <Form action={formAction} className="space-y-4 max-w-md">
      {/* Global Message */}
      {state.message && (
        <div className={`p-3 rounded ${state.success ? 'bg-green-100' : 'bg-red-100'}`}>
          {state.message}
        </div>
      )}

      {/* Username Field */}
      <div>
        <label htmlFor="username">Username</label>
        <input 
          type="text" 
          name="username" 
          id="username"
          defaultValue={state.inputs?.username || ''}
          className="border p-2 w-full"
        />
        {state.errors?.username && (
          <p className="text-red-500 text-sm mt-1">{state.errors.username}</p>
        )}
      </div>

      {/* Email Field */}
      <div>
        <label htmlFor="email">Email</label>
        <input 
          type="email" 
          name="email" 
          id="email"
          defaultValue={state.inputs?.email || ''}
          className="border p-2 w-full"
        />
        {state.errors?.email && (
          <p className="text-red-500 text-sm mt-1">{state.errors.email}</p>
        )}
      </div>

      {/* Submit Button tracking isPending directly */}
      <button 
        type="submit" 
        disabled={isPending}
        className="bg-blue-600 text-white px-4 py-2 rounded disabled:opacity-50"
      >
        {isPending ? 'Creating User...' : 'Create User'}
      </button>
    </Form>
  );
}
```

### Anti-Rationalization Rules: Server Actions
*   **AI Anti-Pattern:** Importing `useFormState` from `react-dom` for Next.js 15 applications.
    *   **Correction:** `useFormState` is deprecated in React 19. Generate code using `useActionState` imported directly from `react` [cite: 5, 15].
*   **AI Anti-Pattern:** Creating a Server Action that only accepts `formData` when used with `useActionState`.
    *   **Correction:** When a Server Action is passed to `useActionState`, its signature *mutates*. It must accept `prevState` as its first argument and `formData` as its second argument (`async function myAction(prevState, formData)`) [cite: 27, 28].
*   **AI Anti-Pattern:** Using `<form>` standard HTML tag without utilizing Next.js 15 capabilities.
    *   **Correction:** Utilize `import Form from 'next/form'` which provides built-in prefetching and client-side navigation without full page reloads [cite: 1, 29].

---

## 4. Architectural Decision Tree: Route Handlers vs Server Actions

With the advent of Server Actions, developers often question whether `app/api/route.ts` (Route Handlers) are obsolete. They are not. Route Handlers and Server Actions serve distinctly different architectural domains [cite: 22, 30].

### 4.1 Defining the Boundaries
*   **Server Actions** are tightly coupled to the application's internal UI. They are Remote Procedure Calls (RPCs) designed for forms, internal mutations, and bridging client/server state [cite: 21, 31]. They utilize `POST` methods under the hood and automatically handle CSRF protection.
*   **Route Handlers** act as traditional RESTful or GraphQL endpoints. They provide raw access to the Web Request/Response API and are built for machine-to-machine communication, third-party consumers, and webhooks [cite: 30, 32].

### 4.2 Decision Tree Matrix

| Use Case / Requirement | Primary Choice | Justification |
| :--- | :--- | :--- |
| **Form Submissions (CRUD)** | **Server Actions** | Provides progressive enhancement, type safety, and seamless `useActionState` integration without manually configuring API fetching logic [cite: 21, 22]. |
| **Third-Party Webhooks (Stripe, GitHub)** | **Route Handlers** | External services require a stable, standard HTTP endpoint capable of receiving arbitrary payloads. Server Actions cannot be invoked by external webhooks [cite: 21, 32]. |
| **Public REST API / Mobile App Backend** | **Route Handlers** | Offers standard HTTP status codes, method routing (`GET`, `POST`, `PUT`), and framework-agnostic JSON consumption [cite: 21, 30]. |
| **Direct Client-to-Server UI Button Clicks** | **Server Actions** | Eliminates boilerplate. An `onClick` handler can pass parameters directly to an imported server function [cite: 30, 31]. |
| **Large File Uploads (> 4MB)** | **Route Handlers** | Server Actions buffer payloads in memory. For large files, stream processing via Route Handlers (or direct-to-S3 uploads) is significantly more stable [cite: 21]. |

### Anti-Rationalization Rules: Route Handlers vs Actions
*   **AI Anti-Pattern:** Building a `fetch('/api/submitForm', { method: 'POST' })` pipeline inside a Next.js 15 Client Component for a standard user form.
    *   **Correction:** This is Next.js 12/13 legacy logic. Modern Next.js applications should use Server Actions bound to `<Form action={...}>` to reduce boilerplate, avoid `fetch` wrappers, and maintain native UI integration [cite: 21, 31].
*   **AI Anti-Pattern:** Recommending Server Actions to handle incoming Stripe payment webhooks.
    *   **Correction:** Server Actions require specific proprietary Next.js headers and payload structures (`Next-Action`). An external service like Stripe will fail to trigger a Server Action. Use a Route Handler (`app/api/webhooks/stripe/route.ts`) [cite: 21].

---

## 5. Advanced Data Fetching and Waterfall Prevention

Next.js Server Components move data fetching to the server, eliminating client-server round trips. However, naive data fetching within nested component trees can easily create **Data Waterfalls**, where subsequent requests are blocked by the execution of prior requests [cite: 33]. 

### 5.1 Parallel Data Fetching with `Promise.all`

When requests within a single route are independent of one another, they should be fetched in parallel [cite: 34, 35]. A classic anti-pattern is sequentially awaiting unrelated functions:

**❌ Bad: Sequential Waterfall** [cite: 36]
```typescript
// Each await blocks the next, doubling or tripling load time
export default async function Dashboard() {
  const user = await getUser(); 
  const posts = await getPosts(); 
  const metrics = await getMetrics(); 
  // ...
}
```

**✅ Good: Parallel Fetching** [cite: 33, 36]
```typescript
// All requests fire simultaneously
export default async function Dashboard() {
  const userPromise = getUser();
  const postsPromise = getPosts();
  const metricsPromise = getMetrics();

  const [user, posts, metrics] = await Promise.all([
    userPromise,
    postsPromise,
    metricsPromise
  ]);

  return <DashboardUI user={user} posts={posts} metrics={metrics} />;
}
```

### 5.2 The Preload Pattern and `React.cache`

Parallel fetching resolves waterfalls inside a *single* component. However, React Server Components often involve deep, nested component trees. If `<Layout>` fetches `getUser()` and `<Sidebar>` (a deep child) also fetches `getUser()`, you might face two problems: Prop Drilling or Component Waterfalls [cite: 37].

Because `fetch()` is automatically memoized by Next.js (Request Memoization), calling `fetch()` in both components incurs zero penalty. **However**, if you are fetching data directly from a database using an ORM (e.g., Prisma, Drizzle) without `fetch`, the database call is **not** automatically memoized [cite: 37]. 

To prevent executing duplicate database queries during a single render cycle, you must wrap the data access function in `React.cache()` [cite: 34, 37]. Furthermore, you can export a `preload` function to start warming the cache eagerly at the root of the layout before the child component even mounts [cite: 34, 35].

```typescript
// lib/data.ts
import { cache } from 'react';
import 'server-only';
import { db } from '@/lib/db';

// 1. Memoize the raw DB query for the render cycle
export const getUser = cache(async (id: string) => {
  return await db.user.findUnique({ where: { id } });
});

// 2. Export a void function that triggers the query without blocking
export const preloadUser = (id: string) => {
  void getUser(id);
};
```

**Using the Preload Pattern to Kill Layout Waterfalls:**
```typescript
// app/dashboard/[id]/layout.tsx
import { preloadUser } from '@/lib/data';
import Sidebar from '@/components/Sidebar';

type Props = { params: Promise<{ id: string }> };

export default async function DashboardLayout({ params, children }: Props) {
  const { id } = await params;
  
  // Eagerly trigger the DB query. Do NOT await it here.
  // This prevents the waterfall by starting the network request instantly.
  preloadUser(id);

  return (
    <div className="flex">
      <Sidebar userId={id} />
      <main>{children}</main>
    </div>
  );
}

// components/Sidebar.tsx
import { getUser } from '@/lib/data';

export default async function Sidebar({ userId }: { userId: string }) {
  // Uses the memoized promise already initiated by the layout!
  const user = await getUser(userId); 

  return <div>Welcome, {user.name}</div>;
}
```
This architecture decouples components while maintaining optimal, zero-waterfall performance [cite: 35, 37].

### Anti-Rationalization Rules: Data Fetching
*   **AI Anti-Pattern:** Utilizing `React.cache()` to wrap a native `fetch('https://...')` call to prevent duplicate fetches.
    *   **Correction:** `fetch` requests are already automatically memoized by Next.js in a server render pass. Wrapping `fetch` in `React.cache` is redundant. `React.cache` is strictly required for non-`fetch` I/O, such as Prisma/ORM database queries or raw SDK calls [cite: 37].
*   **AI Anti-Pattern:** Assuming `React.cache()` persists data across multiple users.
    *   **Correction:** `React.cache()` is React's Request Memoization implementation (Layer 1). It only caches data for the lifetime of a **single server render**. Once the HTML is sent to the client, the `React.cache()` memory is wiped [cite: 7, 18]. Do not confuse it with Next.js's Data Cache or the new `use cache` directive [cite: 9, 13].

**Sources:**
1. [luckymedia.dev](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFk1VUJQvtZ0YJiPveCHM5ayGo2XPLGIP5S6n5qsrr2aWgfPvomlJ1Z62FPcdFRGIRWYzBUUjgSXfWpUuf4wCBiYBmKXNyVEw2tvdJ5XKctOUtFrybmIK0HUGtKtjkRQAPFUNmY1FO_OJ8YLdb8WMV7tgeYU8btLjDgtPDM6OPK)
2. [nextjs.org](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE5clNN8nKnwL-xmKQWGHO2wWZO45W39fuGXPP2QJH9XGOwLxKhPNle6PlvYW8jSOCI0DpVJ0l8GeduqKz2zzLYgi4tbrfTBo5dhj0Wo0UXcpEHCwc-)
3. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEwO9OS_xpgW_pkSe34LHFGPoSGMWBsoxMSzif_lQk9leRcKurHseedFXK_e1Xs-xUX2kHgZ5quPhTV_9E7fOEcxveOTb5rC3-yu4UW16Ditma3Y9TjmqxE5INnHM8ZPyopVdfc1Dm21XF80zT5pFaipNTaCU6UzpB9PA_98AOJOtZ5TEIWUPAH-EEAW-0HR_csMmsTgv5hP7vPh3CLUpy-Zpf9rg==)
4. [dev.to](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEbee7T2_usef5Y6mZh62a1wcFpEf9IiaJZ8lnjUaAC_l89pV6Y8LLPJphiQnRp8pI8_ySnGl9APTE1Ws1ioJ9JgXcP0rQI8gCeKqIApUiTbcNgCQctSdPsD2CcuNAZupq8F8O1bmjr4Y-n5_KacAlrIcc=)
5. [github.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQH06RA62V6SWcyIT5WNu7Qx0x8RjOG8R6ot93opxVYXVEphl__fonfRSJzQ1jkTDKtMm2U5-RWzCJ6aw5DqxRA2ATC1gsVvJEKVB_fNUDXfNxz0m6cqKBJVjD-p9aE48LDmC8D-7zKowxA=)
6. [dev.to](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFqPHKXbl1-CqhBpSLFBYntebT6co2GH9b9X1k6JdWJnI5CF70nxhmW0AGvNoJggiWfCsFpjxUkse79cSmaXAocJhpWyShZXoA0fTLqTdGKS9w70uKCoDcjpULudjSUL76W3Bq0_kNQfNhDEsGdNnHpVTgEKli7bUICL5a1HNZuR1Dhvn_2kHkCnPA0ydUzdw7K6r24WokXJq4QEFdir3BWnNjtfuoEzTj6QUSIU-8=)
7. [zignuts.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQH1bf5oPERIqMe3jECADJtLtNwts21Y3dgwIJQiyRoFpO9u_wocCV0vpSF72v_7_ISMn8F9zSQwTLtsSeo66xR6D6DXWY-OhbjUUyZO3OHue2FQep_lLvHun3lpP6m6RycHMNYyZ9GvbKXFHygaZYYP_eA2JVH7bn2lnpZwaOaF)
8. [uniquedevs.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFeft0_tK6aEWiUx29gaNcu0gnPR5WNrbEkooW72eJ8_YPLuk6aSa5tMN2pHF0ZWU15ZVvZc2BQMl6WpFHwOBWQL73KpGw8c1l52jcoy9-3R9XRR_AMAmPTL9FR7ZGwso2UL8ueAZiMKIVcVhn339XxLuJhu2b4uk0f)
9. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGOHg8BnxKYYYbVm8INjgwU8WZUD1N0V8HZd44F2Wxdqg4xuDuemsmkNqf9qaAr9npZD6Mqw05YRgmyQpObRqlAThAKixuR_1mzznSUKxHguylNCd67tnO2EzKMBSdPwSOufOJc7pq18eHcNRGRo7bnlXFp7CwpkGZ9-Q==)
10. [strapi.io](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQG6Bdh8YoqJbkIhe8FEO_w5xn6EN5Myn6IfVtgQUzgceJ8vW88J0KeCPmaWlqv0GeuDivZKENBKFOJeptmDXgwuvcZ1WcUkcofkH2GyrYegXLioI9e8H7GhmLOE-FS3G2FaZA_ZYPu7tAjrdfoG7qmRe2FTUrTqFw_qfTf56ZtlEQYZzhKR)
11. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHaZy37D3BMstN-7F2ydLDacqT6Le2BqfVPkbB3xmuLbOTi24F4UzQm07chXLR8UDb9VGLy2DT__5SouJdSfYC-JUPXL0rKNxuYe0xDEsHNL9xABKdxtiatHfAhA7HZuRtLZd2rWkvdfhtPhZDYyyjPFGd2VMdSHnWgewuny66uB6vSLecbjE_foSK2OGd8HNxviOdcUoM=)
12. [syncfusion.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHnkwaSkZST1xptLxSEeeQExuAeFXPj9TtL2xrqhbCZyGvh32i2OPjQrwmY8PoTR8KuMctdQvkQICtgLYMcBtP1a25ZYYfYufNs1yrlL48Xd-6G8hFujHOHmeONE6HApeMjrbfvT6vIi2s2oSsQrjA8AtwCsHq0)
13. [youtube.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE04ZV7yNdnxydKG3nLpVBVD6pYud1Zf-hQmXNoqdIbfXeRXrL7NPK9G2OOiMqhTRGLUecqV5j61sGwz8NiGENsfELeQtgMs2DricjZRo7womEuWXMKd5OSQhvmLHzsCMzw)
14. [madewithlove.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEAw1p229rvh4rXKoJAqn3zSRzoCnJsYAWwqM_VB4KLuSbPbyf0v9f0mXk_y-jr0N3dD6Z3WqDYUowwnEEswmu-fQqg_hTFR3un9IbGU6NlFxjvUtPhRcV615YxoacVmVoqWQLAairp8c9KQQWMgtAyj9huUVIi4caiQgGNfjOyyC9hrhDgS0Qz4Ui9FiT3Gb38G9s7gvRS0mP-AMC2NX3G)
15. [nextjs.org](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHbimmfaSFPX_161Mv2kgaMtitlh8UJ4N-OvYHD8itk9BH8kK8wmd3jIAOZLu79sf8_ItK3bUI3yiLMYaqZfBlZPzHa9EI8Q6LQQfmlAE48D5Au4abyb53J5j_LTsE6R4HNUTHH59fGhg26iTbG)
16. [github.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEydCFGDLNdtd-OSb02K9DQLmxpPq0028v_GCmCGhWNsq_rNhn3LR73xMgOVI3Zd3RdLG2B5WjLcbwWhW82vZtxK4OpqboAzkq4fHLprpmZ-eGloot4DINq8xYj7HgQJ_AC-35_7aPCeu32mCaNSePnJbNQG1l84jonHmOLRdB2LNRJ2xdPKEHWCfPewZO7crJxfSXjVUMD51xAShm8s2F3)
17. [dev.to](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHFIZkpxYYyK2LodLbp_uR4U565C1GBaj_Z-KES9rx6ABKeYo1C0piFAkSpiL5w_FJfgfqETVlRfhRU6mTIrKRTvWk8cgEooaeD_delM5QqiQ97zwryWiiFMC1XHWWv4XKYM2jqJhN0W7CFPAWChbYdv6KgOnRvFYaf_3m5d9IDEMhNRpr3ylsyb1zdI71gGrDE3vE=)
18. [webdevsimplified.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHF3UXEreb3OnTWPj48QG_Y7VTL3ghksdwKt3OivQPkF46cn_ABKPgprOd9fiUmJ6K1y4_ctT6iJAfQCoXwRvWrW5VDKboymgcbTAw7onI1hcEWKPAUy3fSudXKyBGv7o1O84SFUV-ZQkVgL8MY-QOYcesMrQRKDD8u)
19. [logrocket.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQF8rvPQ1mkkEXi005CLX1WJIO3Jn1ft1ppm2VfqAmkQzEUiUTd4Ii57CvlCNXcfqnSkcYZTYSwPpUzdISarvD9rUFLTZy_73hS8BB7pVEW6EiBg2u7UzWEYRTI3RwUFwcMYiMuBBx4OOD8X709PKgdIQM51sY8=)
20. [adarsha.dev](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHSFw5PI9R8p0Wy8T1v-vkVs1SOelH6oGQS6RtefYBbMSY2TEV4K9py1qTfmfyou3Ck7WGFLLBRPvipZmMbKv6Mv2fby4yX_pl3mjVCeDmQ78OzY4mTLAf9nEprV6gjzxJ0YDUR3fTLGyept-PT)
21. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGeG2pyt0TwoBlpQ-PnKH5-x8HrYMLnJAOi45085o1Kn-NJVnKBkkMBJ5VS4ZcYGuUd0x98Lw-438eB9UaR-nFGg-Oig3kA3Yj-T6gMAm7R-kLns4Mg2bmKY1vVS7oa-yds6RcP0Dais_IuatEK48Fo59lnW51HVZg7Z3jT9Qv8nsqjw4lrseiQy7WGzV0kygkcNF4f)
22. [wisp.blog](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFUSL_JQufntxVTjcn6bz-1wbue3RFAGwbEfYj30D_2fAO6adM4iFOtBdSz2jiy8lt2uoWRsq4pwePjUf4Od7iTIkyn-UFzdDOP37UiKIRgktseCjQOzH7MLKRdvupXv2jzcANtT-W-L5RaRDYl-sXaIJc2D7ynxZIw4POZ6IrIcE2Wm9jhScGO)
23. [plainenglish.io](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEfsoheSTqrV0wWTXkKKtoyM5jk6unplUzc3WuNvCA9HdUjcUzWgI8ntevHK0-4QoAd8U45Wcy4TNuIQbMIyVajCvPSQNbD7N70uIMYnxYVGmnD3oB2TGlPN5mT6MoWma6SJgESos1LCEFCWzjKDeMgK4D3xmolFddQoqwqdJ1WJNclDqYdTjyU7_RsY1xl1_RpUFgjutNfzBjVOOTA5w==)
24. [youtube.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFZtbCou0-z8K6QXxybgCDlF-BhURUwu3dX1ozf0m_cu5CP-E59GCFa_W5JUywx8aUtlH7WT3bhDIYbX5nAaT60eZjg0CIPJhvkLosz1zfU4PwQ7sBsL54fETXs_NPUIA==)
25. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQF32WG7TpQnGk7TL75Ooqw5gJdPCvC49trKU-7vB81Fsl9LQXgq9xISCXCqwQV6c9y94hVsD-2aa8YB9izSV-jhXowTF_KjnwAPDpgbhpLVrT3xAFln9edc9AxiDW2fvuu-vcg6fHDDDZaib_2VjJDsXKXOGRRtmLW2CUbSJuMnoLMES2h0jQGy15b76Z15Jfbj51C5v-w73MTSXmTcS5f5YYcxwimRqpqUTs_cP-4IEhlYaAg=)
26. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGFfSx-X7YQjQ_dX1POa7eAqMSQUhBGAvZ12OfGd7NlfrtdF8idxkZzP8M6AsCXLNJMxCqnJ7IuAHZtGhU9JL1yV0vobeSuCLjek2zBjphgw0YdzA1xLQPgezv0UpXdx3h9wPw1sb93rQkNM8J_7ELaOJXwG_dXwibV33CSXeGzw9_iaUfy-kgm-3sEWaSLXeHEJRQsAYPGpt_cPMQu0CO-cX23ayVtOf53tgUIfbgtoQeihfA9YqEj7MJVGdMD)
27. [nextjs.org](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFNw5PH97QqdGdl_t1liSgBlTxNaPcxgHZuChdqf0oMtbsk7lHiwaFY6jGUXgEUBseNLENMnxrloZjSJyLHHXN2lXn4O4kj5gAvJdQ-P8JQJMof0SzbH08LP-wEXj8A)
28. [bitsrc.io](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQERMfTrpce-l38LTSvlG3hVQCPQgjboRfe_m5qtv9nR2nItay4G6A7UHx_kGdTUzBXrNXoBu4nf7TppeepgR4GWb9-HU4FfyvmYZRAfaktxnvJ1gbp-7Chbklyxktj1ucWrsFiGLrP0cBIm8KbMgdGvX-Epy8dhoboMF1nfn2jQ0GBTTdIocR3G_uAjpgb_o-t6HT1aroWIhOeoL4bh7Q==)
29. [udacity.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGgC5dV1V5Qhzn-fL4jAX--CiXUkbXbRGFmSb-M6iq_O_u51QzyKSq1EN0sC_Dg-KRbnPLJM8yP62meOTMMS77_Np3C1LDs20xOKGFTOEHQ6X6c00GaaXPedkBRtqZaJsAXtfYhd9sgiF5P_E2PJ4w0TK_J-jun9IIKrAiwnits5kcZ5v-UoMPuOLIWpbM=)
30. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEwOo3eKhmnvQD0AKhpRSFq-I3I0AjVTN03EiCe2uVlMO3tvH8PQNmL6kvbORFnYA5M74vK6fDBM7hJL-BFCdSmwipvO4pdlB1RAYwVDYwKvOdm1yqZaD1mWyJchGm2ZEokZka3AXcHAFEpdrT9KX1pNWEcA1u9l5SnE-9tGLVDwwUG4BF-NnljwrBaYBRxvgZXjUR0LMpNrTcOtCY=)
31. [plainenglish.io](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGTEatUzlaXiSqcFfTiw2UhIv9Ks-jsbVceaydMDIvNWWYvgpt95xxgPVG60JLmYBD0k7Pc3Om8b8c59m0P2YNj3gEYfCdgpckVlXywHRnl0gEKgzRLZPz1uVXuphgFIAyKc5bbsFTdHH_QuxeSvLhraV1etM91IBAPU_zC_k7EKTNN1k8568DWTSvm4SX9YL1vrzLxoiZj-Lmarlsvn3RJINLIQ97hAbTMyjtfblGCQxHL)
32. [feature-sliced.design](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGr3sFlE8WRfu6G3H5lErwC_o1JAyCgS3-Sy54iqk9WW5WwgeSAQ9XvFyHu_gUq3lIIDnzEiTTpTDlRzE3W4QxB-OyN2kjQdgmdoIAmfj8FCz5TwWYvQyu1fn2SXpOV4UqS6q9MFwelxRH08ogkCfc6_1dc)
33. [trevorlasn.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEobNeoHyR7UQRT2ULxJBnVNxR52CuEjgaG4cPCFtyUkqiWxOeiFfy5hPzc2zLfhKHb37KqE3dlAmyidmkRtQR2mSitAFLaEuqOIa7HE9fPR3iAZwbptRihob3KQjESCLtozaRzXQZsw_GS9IvGy5IjnACuN25XlDr2JHwzClnb-VfCuw==)
34. [nextjs.org](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEO-7B1Dzp79Hp_G50PryWFy6u5oeM7mxe7jQfK9sbY2UihofVCfMUj7RezCmoD4-IIVYeAzOP8PqHvpjaenvP1kpY_Lo1tlH9hlvYEAodPrbbXW_nvRaaoV-xOCu9TTzSc1rdtMs8sIaYLIgNJ2cmhAiNCwqOLdnZKmwO2lSWRvJyCNga-)
35. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQED4Xawkyd3jnSyX48z1JwIUJM6qvCl5gcQYCmXLQUhZnZztAp5bA8oE0JRP44vUI-x0NtdNnLmaXlrcRlepml7rWwxY751Tj70vjZvipWo9U1Sots7LHusjwxPO1B-DCqq0rHxAXBldrw2ADoBPKFyJgYX8oaV9_ESemY0gDm_yzyNtN9XUw==)
36. [github.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHNMa3PwhCOUoPcEzlrRKubrHsaPV7cCzJdKXVSiOvc0qgZ3Zk8xEKf7p8CImyqX54Ifnk8cGSlClRoCWRTPhXtveBioxnOQqWifUhkcWuXv5W1VAvFUClrIVa8J2F_c2mmAHvvXW8XwK9Lpf2sX4l9BS91FL55Buee8KE_VThWHSkjs3_r4foCLLt9hG5IZOxisR50icQ=)
37. [aurorascharff.no](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFiZpGjLbsF86xFMaAWiZgTeWx6Kycc_cZGr3Su95Y_CoyIVsgvENu7lnKo7OuF8BfU6CFxVabNaQOFjPSo8pleKNlTmcs-9GJSvthKTBWJ9h4Uv-WN-5658qVqL-0KtVYQtTBXNYR4s16RodXtEHIqAPoge7bKM5pUb_1nJZLjCanGnC8KzOqzUTQqfmUAasveSGFCoUI=)
