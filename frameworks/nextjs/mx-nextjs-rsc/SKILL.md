---
name: mx-nextjs-rsc
description: "React Server Components in Next.js, 'use client' directive, server/client boundary, serialization, component composition, children pattern, streaming SSR, selective hydration, Suspense, bundle size optimization, server-only package, Taint API, RSC payload"
---

# Next.js RSC — Server/Client Component Boundaries for AI Coding Agents

**Load this skill when deciding where to place "use client", composing server and client components, or optimizing the server/client boundary.**

## When to also load
- `mx-nextjs-core` — File conventions, routing primitives
- `mx-nextjs-data` — Server Actions cross the same boundary
- `mx-nextjs-perf` — Bundle analysis, code splitting at boundary
- `mx-react-core` — React fundamentals underlying RSC

---

## Level 1: Server vs Client Component Decision (Beginner)

### Pattern 1: The Decision Checklist
Start from the top. First "yes" determines the component type.

| Question | If Yes → |
|----------|----------|
| Needs `useState`, `useReducer`, `useEffect`? | Client Component |
| Needs event handlers (`onClick`, `onChange`)? | Client Component |
| Needs browser APIs (`window`, `localStorage`)? | Client Component |
| Uses custom hooks with state/effects? | Client Component |
| Fetches data from DB/ORM directly? | Server Component |
| Handles secrets or API keys? | Server Component |
| Renders static content, markdown, text? | Server Component |
| **None of the above?** | **Server Component (default)** |

**The heuristic**: "Does this component need to *react* to anything?" If no → Server Component.

### Pattern 2: "use client" Is a Boundary, Not a Flag

```tsx
// ❌ BAD — "use client" on a page pulls EVERYTHING into the client bundle
'use client';
import ProductDetails from './ProductDetails';  // Now client-side
import ProductReviews from './ProductReviews';   // Now client-side
import { heavyParser } from 'markdown-lib';      // 240KB shipped to browser

export default function ProductPage() {
  const [saved, setSaved] = useState(false);
  return (
    <div>
      <ProductDetails />
      <ProductReviews />
      <button onClick={() => setSaved(!saved)}>Save</button>
    </div>
  );
}

// ✅ GOOD — Extract the interactive part as a leaf client component
// app/product/page.tsx (Server Component — default)
import ProductDetails from './ProductDetails';  // Zero client JS
import ProductReviews from './ProductReviews';   // Zero client JS
import SaveButton from './SaveButton';           // Only this ships JS

export default function ProductPage() {
  return (
    <div>
      <ProductDetails />
      <ProductReviews />
      <SaveButton />
    </div>
  );
}

// app/product/SaveButton.tsx
'use client';
import { useState } from 'react';
export default function SaveButton() {
  const [saved, setSaved] = useState(false);
  return <button onClick={() => setSaved(!saved)}>{saved ? 'Saved' : 'Save'}</button>;
}
```

### Pattern 3: Props Across the Boundary Must Be Serializable
When passing props from Server → Client Components, only serializable values work:

| Serializable (OK) | NOT Serializable (Fails) |
|-------------------|------------------------|
| `string`, `number`, `boolean` | Functions, callbacks |
| Plain objects, arrays | Class instances |
| `null`, `undefined` | `Date` objects (use `.toISOString()`) |
| JSON-compatible data | Promises (except as children) |
| JSX / React elements (children) | Symbols, Maps, Sets |

---

## Level 2: Composition Patterns (Intermediate)

### Pattern 1: Children Pattern — The Core RSC Technique
Client Components CANNOT import Server Components. But they CAN receive them as `children`:

```tsx
// app/layout.tsx (Server Component)
import ThemeProvider from './ThemeProvider';  // Client Component
import ServerNav from './ServerNav';          // Server Component

export default function Layout({ children }: { children: React.ReactNode }) {
  return (
    <ThemeProvider>
      <ServerNav />     {/* Rendered on server, passed as children */}
      {children}        {/* Server-rendered page content */}
    </ThemeProvider>
  );
}

// app/ThemeProvider.tsx
'use client';
import { createContext, useState } from 'react';

export default function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setTheme] = useState('light');
  return (
    <ThemeContext.Provider value={{ theme, setTheme }}>
      {children}  {/* Server Component output rendered here */}
    </ThemeContext.Provider>
  );
}
```

**Why this works**: React renders `ServerNav` on the server → generates RSC Payload → Client Component receives the pre-rendered output as a prop. The Client Component never imports or evaluates the Server Component code.

### Pattern 2: Context Providers Must Be Client Components
React Context (`createContext` / `useContext`) requires client-side state. Place providers as deep as possible:

```tsx
// ❌ BAD — Wrapping root layout makes everything below "client-adjacent"
// This doesn't make children client components, but bloats the provider

// ✅ GOOD — Narrow the provider scope
// app/(dashboard)/layout.tsx
import { AuthProvider } from '@/features/auth/provider'; // Client Component
export default function DashboardLayout({ children }) {
  return <AuthProvider>{children}</AuthProvider>;
}
```

### Pattern 3: Third-Party Library Wrapper Pattern
Many npm packages lack `"use client"` directives. Wrap them:

```tsx
// components/ui/carousel.tsx
'use client';
export { Carousel } from 'some-carousel-lib';  // Re-export with boundary
```

This single line creates the boundary. The carousel works in Server Component pages because the import goes through your client wrapper.

### Pattern 4: Server-Only Boundary Protection

```tsx
// lib/server/db.ts
import 'server-only';  // Build error if imported in Client Component
import { prisma } from './prisma';

export async function getUser(id: string) {
  return prisma.user.findUnique({ where: { id } });
}
```

Add `import 'server-only'` to EVERY file in `lib/server/`. This is a hard build-time boundary — no runtime surprises.

---

## Level 3: Streaming, Hydration, and Advanced Patterns (Advanced)

### Pattern 1: Streaming SSR with Suspense
Server Components can be `async`. Wrap them in Suspense for streaming:

```tsx
// app/dashboard/page.tsx (Server Component)
import { Suspense } from 'react';

export default function Dashboard() {
  return (
    <div>
      <h1>Dashboard</h1>
      <Suspense fallback={<RevenueChartSkeleton />}>
        <RevenueChart />  {/* async SC — streams when ready */}
      </Suspense>
      <Suspense fallback={<ActivitySkeleton />}>
        <RecentActivity /> {/* async SC — streams independently */}
      </Suspense>
    </div>
  );
}

// components/RevenueChart.tsx (Server Component)
async function RevenueChart() {
  const data = await fetchRevenue(); // Takes 2 seconds
  return <Chart data={data} />;
}
```

The `<h1>Dashboard</h1>` renders instantly. Each Suspense boundary streams its content as the async fetch resolves. No waterfall.

### Pattern 2: Selective Hydration Priority
React 18+ prioritizes hydrating components the user is interacting with. If a user clicks a button while other components are still hydrating, React bumps that button's component to the front of the hydration queue. Structure your component tree so interactive elements are in separate Suspense boundaries for maximum responsiveness.

### Pattern 3: Preventing Secret Leakage

| Protection Layer | Mechanism | Strength |
|-----------------|-----------|----------|
| `import 'server-only'` | Build-time error | Strong — compile fails |
| `NEXT_PUBLIC_` prefix convention | Only `NEXT_PUBLIC_*` vars reach client | Strong — by design |
| Data Access Layer (DAL) | Verify auth at data access point | Strong — defense in depth |
| Taint API (experimental) | Runtime error if tainted value crosses boundary | Moderate — reference-copy bypasses |
| **Never pass full DB objects** | Serialize only needed fields to client | Pattern — prevents accidental leaks |

```tsx
// ❌ BAD — Passes entire user object (may contain internal fields)
<ClientProfile user={user} />

// ✅ GOOD — Explicit field selection
<ClientProfile name={user.name} avatar={user.avatarUrl} />
```

---

## Performance: Make It Fast

### Perf 1: Push "use client" to Leaf Nodes
Every `"use client"` file + all its transitive imports ship to the browser. The higher in the tree, the bigger the bundle. Measure with `@next/bundle-analyzer`:
```bash
ANALYZE=true next build
```

### Perf 2: Lazy-Load Heavy Client Components
For client components below the fold, use `next/dynamic`:

```tsx
import dynamic from 'next/dynamic';
const HeavyEditor = dynamic(() => import('./HeavyEditor'), {
  loading: () => <EditorSkeleton />,
  ssr: false,  // Skip SSR for browser-only components
});
```

### Perf 3: Zero-Cost Server Dependencies
Server Components can import massive libraries (markdown parsers, image processors, data transformers) with zero client bundle cost. Prefer server-side processing over shipping libraries to the browser.

---

## Observability: Know It's Working

### Obs 1: Monitor Client Bundle Size
Check `First Load JS` in `next build` output. If a page shows unexpectedly high JS, a `"use client"` cascade is likely. Target: <100KB First Load JS per route.

### Obs 2: Track Hydration Errors
Hydration mismatches (server HTML ≠ client render) create console errors and degrade UX. Common causes: `Date.now()`, `Math.random()`, `typeof window` checks in render. Use error monitoring (Sentry) to catch these in production.

### Obs 3: Instrument Server Component Render Time
Use OpenTelemetry spans (see `mx-nextjs-observability`) around expensive server component data fetches to identify rendering bottlenecks.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Put "use client" on Page or Layout Files
**You will be tempted to:** Add `"use client"` to `page.tsx` because you need one interactive element.
**Why that fails:** Every import in that file becomes client-side. Layouts/pages should be Server Components. Extract the interactive piece into a leaf client component.
**The right way:** Keep pages as Server Components. Create `ComponentName.tsx` with `"use client"` for the interactive part.

### Rule 2: Never Use useEffect for Data Fetching in Next.js
**You will be tempted to:** Write `useEffect(() => { fetch('/api/data')... }, [])` in a client component.
**Why that fails:** Creates a client-side waterfall — page loads, JS executes, fetch fires, data arrives. Three round trips. Server Components fetch data in one server-side operation with zero client JS.
**The right way:** Fetch data in a Server Component using `async/await`. Pass the result as props to Client Components that need it for display.

### Rule 3: Never Import Server Components in Client Components
**You will be tempted to:** `import ServerWidget from './ServerWidget'` inside a `"use client"` file.
**Why that fails:** The bundler treats ServerWidget as a Client Component — server-only code (DB queries, secrets) ships to the browser. Build may fail or secrets may leak.
**The right way:** Use the children/props pattern — pass Server Components as `children` to Client Components from a parent Server Component.

### Rule 4: Always Wrap Third-Party UI Libraries
**You will be tempted to:** Import `import { Carousel } from 'fancy-carousel'` directly in a Server Component.
**Why that fails:** If the library uses hooks/browser APIs internally but lacks `"use client"`, the build fails with cryptic errors.
**The right way:** Create a one-line wrapper: `'use client'; export { Carousel } from 'fancy-carousel';`

### Rule 5: Never Pass Functions as Props Across the Boundary
**You will be tempted to:** Pass `onDelete={handleDelete}` from Server Component to Client Component.
**Why that fails:** Functions are not serializable. You get a runtime error: "Functions cannot be passed directly to Client Components."
**The right way:** Use Server Actions (`"use server"`) for mutations. Pass the action as a prop — Server Actions ARE serializable because they become HTTP endpoints.
