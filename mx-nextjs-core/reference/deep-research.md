# Next.js 15 App Router Architecture and File Conventions: A Comprehensive Technical Guide

**Key Points:**
*   **Asynchronous Request APIs**: In Next.js 15, `params`, `searchParams`, `cookies()`, and `headers()` transition from synchronous objects to asynchronous Promises to facilitate advanced streaming and partial prerendering capabilities [cite: 1, 2]. 
*   **Strict Component Hierarchy**: The App Router enforces a deterministic rendering wrapper order: `layout` > `template` > `error` > `loading` > `not-found` > `page`. Errors in a `layout` cannot be caught by an `error` boundary in the same route segment [cite: 3, 4, 5].
*   **State Persistence Divergence**: `layout.tsx` preserves state and avoids re-rendering during navigation, whereas `template.tsx` forces a complete remount and state reset for its children on every route change [cite: 6, 7].
*   **Advanced Routing Primitives**: Parallel Routes (`@folder`) and Intercepting Routes (`(.)folder`) enable complex UI paradigms like shareable, context-preserving modals, but strictly require `default.tsx` fallbacks to prevent hard-navigation crashes [cite: 8, 9].
*   **Architectural Modularity**: Implementing Feature-Sliced Design (FSD) in Next.js requires separating the framework's file-based `app/` router from the business logic layers, maintaining a "thin" routing layer that acts only as an entry point [cite: 10, 11].

**The Evolution of the App Router**
The release of Next.js 13 introduced the App Router, shifting the React ecosystem toward Server Components and file-system-based routing with deep nested layout support [cite: 12]. Subsequent iterations up to Next.js 15 have refined this architecture, aggressively optimizing for server-side performance, streaming, and concurrent rendering [cite: 1, 2]. This transition introduces significant paradigm shifts regarding data fetching, state persistence, and error handling. 

**Addressing AI-Generated Anti-Patterns**
Because large language models are predominantly trained on Next.js 13 and 14 documentation, they frequently generate outdated, synchronous data-fetching code or architecturally unsound component hierarchies [cite: 13, 14]. This report codifies strict "Anti-Rationalization Rules" to counteract these programmatic hallucinations, providing a rigorous technical reference for developers and automated agents navigating the Next.js 15 landscape.

---

## 1. Complete File Convention Hierarchy and Rendering Order

The Next.js App Router relies on a specialized set of file conventions that compile into a deterministic React component tree. Understanding the precise component hierarchy is critical for managing data fetching, suspense boundaries, and error bubbling.

### 1.1 The Nested Component Hierarchy
When a user requests a route, Next.js constructs a nested component tree based on the files present in the corresponding route segment. The exact structural encapsulation can be mathematically represented as a composition of React nodes:

\[ \text{Route}(x) = \text{Layout}(\text{Template}(\text{ErrorBoundary}(\text{Suspense}(\text{NotFound}(\text{Page}(x)))))) \]

According to the official specifications [cite: 3, 15, 16], the outermost component is `layout.tsx`, which sequentially wraps the following special files in the same segment:

1.  **`layout.tsx`**: The persistent UI shell. It does not remount on navigation. It wraps all subsequent components [cite: 3].
2.  **`template.tsx`**: Similar to a layout, but creates a new React instance (remounts) on every navigation [cite: 7].
3.  **`error.tsx`**: A React Error Boundary (`<ErrorBoundary>`). It catches rendering errors in all components *below* it in the hierarchy [cite: 4].
4.  **`loading.tsx`**: A React `<Suspense>` boundary. It displays fallback UI while the subsequent components resolve asynchronous operations [cite: 15].
5.  **`not-found.tsx`**: Renders when the `notFound()` function is invoked or when a route is unmatched. It is wrapped by the `<Suspense>` and error boundaries [cite: 16].
6.  **`page.tsx`**: The primary UI content for the specific route segment [cite: 17].

### 1.2 Execution and Firing Conditions

#### `layout.tsx` and `template.tsx`
*   **When they fire**: Rendered on the initial request to the route segment.
*   **Behavioral Note**: Uncached data access inside a `layout.tsx` must be explicitly wrapped in its own `<Suspense>` boundary if Cache Components are enabled. `loading.tsx` sits *below* `layout.tsx` and therefore cannot act as a fallback for the layout's own data fetching [cite: 3, 15].

#### `error.tsx` and `global-error.tsx`
*   **When they fire**: Triggered when an unhandled exception is thrown during rendering in any child component [cite: 18].
*   **Hierarchy Limitation**: Because `error.tsx` is nested *inside* `layout.tsx` and `template.tsx` of the same segment, it **cannot** catch errors thrown by those two files [cite: 4, 19]. Errors bubble up to the nearest parent `error.tsx` [cite: 18].
*   **Global Handling**: To catch errors in the root `app/layout.tsx`, the application must utilize a `global-error.tsx` file, which replaces the entire `<html>` and `<body>` tags upon activation [cite: 4, 19].

#### `loading.tsx`
*   **When it fires**: Activated immediately upon navigation when child components (like `page.tsx`) suspend due to asynchronous data fetching [cite: 15].
*   **Streaming**: Next.js streams the static shell (the layout) immediately, leaving the `loading.tsx` UI in place until the payload resolves [cite: 15].

#### `not-found.tsx` and `default.tsx`
*   **When `not-found.tsx` fires**: Activated either by a direct programmatic call to `notFound()` from `next/navigation`, or automatically by the framework when a URL segment cannot be matched to any directory [cite: 16, 20].
*   **When `default.tsx` fires**: Triggered exclusively within Parallel Routes (`@slots`) when Next.js cannot recover the active state of a slot during a hard page reload. If `default.tsx` is missing, Next.js throws a 404 error [cite: 9, 12].

### 1.3 Anti-Rationalization Rules for File Conventions

| Anti-Pattern (What AI is tempted to do) | The Reality in Next.js 15 | Why it Fails |
| :--- | :--- | :--- |
| **Placing `error.tsx` alongside `layout.tsx` to catch layout data-fetching errors.** | Errors in `layout.tsx` bubble up to the parent segment's `error.tsx` [cite: 4, 5]. | The component hierarchy places `layout.tsx` *above* the local `error.tsx` boundary. The app will crash with an unhandled runtime error if the root has no parent error boundary [cite: 5, 19]. |
| **Omitting `default.tsx` in a Parallel Route `@slot`.** | A `@slot` requires a `default.tsx` file (which can return `null`) to handle hard navigations [cite: 8, 9]. | On a soft client-side navigation, the slot maintains its state. However, on a hard reload, Next.js cannot determine the route for the unmatched slot, resulting in an immediate 404 crash [cite: 12, 21]. |
| **Using `loading.tsx` to show a spinner for data fetched inside `layout.tsx`.** | `loading.tsx` only wraps `page.tsx` and children, not the sibling `layout.tsx` [cite: 15]. | The navigation will block entirely until the layout's asynchronous fetch resolves, resulting in a frozen UI rather than a loading state [cite: 15]. |

---

## 2. Layouts vs. Templates: State Persistence Behavior

While both `layout.tsx` and `template.tsx` act as UI shells that wrap child components, their interaction with the React reconciliation lifecycle is fundamentally opposed. 

### 2.1 State Persistence and DOM Re-creation
**Layouts** are designed for persistent UI. When a user navigates between sibling routes sharing the same layout, the layout component does not re-render. Its state (e.g., a search input string, an expanded sidebar) remains fully intact, and React lifecycle hooks (like `useEffect`) do not re-fire [cite: 6, 22].

**Templates** are designed for ephemeral UI. A `template.tsx` file binds a unique key (derived from the route path) to its root element. When the route changes, React destroys the previous DOM elements and mounts a completely new instance of the template. All state resets to its initial value, and `useEffect` hooks trigger on every navigation [cite: 6, 23].

### 2.2 Decision Tree: Layout vs. Template

| Requirement / Scenario | Use `layout.tsx` | Use `template.tsx` | Justification |
| :--- | :--- | :--- | :--- |
| **Global Navigation/Headers** | **Yes** | No | Prevents unnecessary re-renders of heavy UI elements, boosting performance [cite: 7, 24]. |
| **User Authentication State** | **Yes** | No | Auth contexts must persist across the application without re-evaluating on every click [cite: 22]. |
| **Page-Transition Animations** | No | **Yes** | Animations require DOM elements to mount/unmount to trigger entry and exit framer-motion variants [cite: 6]. |
| **Per-Page Analytics Logging** | No | **Yes** | `useEffect` must fire on every page change to log page views accurately [cite: 6, 23]. |
| **Dynamic Form Resetting** | No | **Yes** | Search filters or feedback forms embedded in the shell must reset their `useState` inputs when navigating to a new category [cite: 7, 23]. |

### 2.3 Code Example: The Divergence in Behavior

```tsx
// app/template.tsx - Resets on every navigation
'use client';
import { useState, useEffect } from 'react';

export default function RootTemplate({ children }: { children: React.ReactNode }) {
  const [renders, setRenders] = useState(0);

  useEffect(() => {
    // This will log every time the user navigates between child pages
    console.log("Template mounted"); 
    setRenders(prev => prev + 1);
  }, []);

  return (
    <div className="template-wrapper">
      <p>Template renders: {renders}</p> 
      {children}
    </div>
  );
}
```

### 2.4 Anti-Rationalization Rules for Layouts/Templates

| Anti-Pattern (What AI is tempted to do) | The Reality in Next.js 15 | Why it Fails |
| :--- | :--- | :--- |
| **Using `layout.tsx` for deeply nested UI that relies on `useEffect` to trigger on navigation.** | `layout.tsx` explicitly prevents `useEffect` from re-firing on navigation within its subtree [cite: 23]. | The logic (e.g., analytics tracking or logging) will only fire once upon initial load, missing all subsequent client-side route changes [cite: 23]. |
| **Replacing `layout.tsx` entirely with `template.tsx` "just to be safe" against stale state.** | Vercel recommends `layout.tsx` as the default. Templates incur a performance cost [cite: 6, 24]. | Forcing global components (navbars, context providers) to unmount and remount destroys React optimization, causing severe bundle execution overhead and UI flickering [cite: 22, 24]. |

---

## 3. Advanced Routing: Route Groups, Parallel Routes, and Intercepting Routes

Next.js introduces three advanced routing primitives that solve complex structural and user experience challenges without relying on external state management libraries. 

### 3.1 Route Groups `(folder)`
Route groups allow developers to logically organize files without affecting the URL path [cite: 25]. By wrapping a folder name in parentheses (e.g., `(auth)`), the folder is omitted from the URL segment. 
*   **Primary Use Case**: Applying multiple distinct root layouts (e.g., one layout for `(marketing)` and a different layout for `(dashboard)`) without altering the public URL architecture [cite: 25, 26].

### 3.2 Parallel Routes `@slots`
Parallel routes permit the simultaneous rendering of multiple, independent route segments within the same layout [cite: 9, 27]. They are defined using the `@folder` convention (named slots).
*   **Architecture**: A layout component automatically receives these slots as props alongside the implicit `children` prop [cite: 27, 28].
*   **Independent Navigation**: Each slot can have its own loading and error states, and can be navigated independently [cite: 21, 27].
*   **The `default.tsx` Imperative**: Because soft navigation (client-side) preserves the state of unmatched slots, but hard navigation (server-side reload) requires Next.js to render a valid component for every slot, developers *must* provide a `default.tsx` file (often returning `null`) for unmatched states [cite: 12, 21].

### 3.3 Intercepting Routes `(.)`
Intercepting routes hijack the default routing behavior to display an alternate view within the current layout—typically used for modals [cite: 29]. 
*   **Conventions**: 
    *   `(.)` matches segments on the same level.
    *   `(..)` matches segments one level above.
    *   `(..)(..)` matches segments two levels above.
    *   `(...)` matches segments from the root directory [cite: 29].
*   **Context Preservation**: Clicking a link (e.g., a photo in a feed) updates the URL and opens a modal *without* unmounting the underlying feed. A hard refresh of that new URL, however, serves the full, isolated photo page [cite: 29, 30].

### 3.4 Decision Tree: Advanced Routing Primitives

| Goal / UI Requirement | Primitive to Use | Architectural Pattern |
| :--- | :--- | :--- |
| Separate `/login` and `/dashboard` layouts while keeping URLs clean. | **Route Groups** `(folder)` | `app/(auth)/login/page.tsx` -> maps to `/login` [cite: 26, 31]. |
| Render a side-by-side Dashboard (Team view + Analytics view) simultaneously. | **Parallel Routes** `@slot` | `app/layout.tsx` accepts `{ children, team, analytics }` [cite: 27, 28]. |
| Display a Shareable Modal (e.g., Instagram photo viewer) over a feed. | **Parallel + Intercepting** | `@modal/(.)photo/[id]` intercepts the navigation, while `app/photo/[id]` serves the standalone page [cite: 29, 30]. |

### 3.5 Code Example: The Perfect Modal Pattern
To achieve a shareable modal that preserves the underlying UI context on client navigation but acts as a standalone page on direct URL access, Parallel and Intercepting routes must be combined [cite: 9, 30].

```tsx
// 1. Root Layout - app/layout.tsx
export default function Layout({ children, modal }: { children: React.ReactNode, modal: React.ReactNode }) {
  return (
    <html>
      <body>
        {children}
        {modal} {/* The parallel route slot */}
      </body>
    </html>
  );
}

// 2. Parallel Slot Default - app/@modal/default.tsx
// Crucial to prevent 404s when the modal is not active.
export default function ModalDefault() {
  return null;
}

// 3. Intercepting Route - app/@modal/(.)photo/[id]/page.tsx
import { ModalDialog } from '@/components/ModalDialog';

export default async function InterceptedPhotoModal({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <ModalDialog>
      <h1>Intercepted Photo {id}</h1>
    </ModalDialog>
  );
}

// 4. Standalone Route - app/photo/[id]/page.tsx
export default async function StandalonePhotoPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <h1>Full Page Photo {id}</h1>;
}
```

### 3.6 Anti-Rationalization Rules for Advanced Routing

| Anti-Pattern (What AI is tempted to do) | The Reality in Next.js 15 | Why it Fails |
| :--- | :--- | :--- |
| **Using Intercepting Routes without a Parallel Route `@slot` for a Modal.** | Modals require a dedicated layout slot to render *above* the existing content [cite: 9]. | Without a parallel route, the intercepted route entirely replaces the `children` prop, navigating the user away from the background feed instead of overlaying it [cite: 9]. |
| **Handling modal closure with React state `setIsOpen(false)`.** | Modals powered by Next.js routing are driven by the URL, not internal React state. | Clicking "Close" must invoke `router.back()` to pop the history stack and revert the URL, otherwise the URL and the UI become desynchronized [cite: 8, 30]. |

---

## 4. Next.js 15 Breaking Changes: Asynchronous Request APIs

Perhaps the most disruptive architectural shift in Next.js 15 is the deprecation of synchronous access to dynamic request data. To unlock aggressive server-side optimizations, concurrent rendering, and preparation of static shells prior to request arrival, Next.js 15 mandates that dynamic APIs be treated as Promises [cite: 1, 2, 32].

### 4.1 The Asynchronous Transformation
The following request-scoped APIs have transitioned from synchronous values to asynchronous Promises:
*   `params` [cite: 1, 2]
*   `searchParams` [cite: 1, 2]
*   `cookies()` [cite: 2, 32]
*   `headers()` [cite: 2, 32]
*   `draftMode()` [cite: 2, 32]

When an application invokes `await params`, Next.js suspends the rendering of that specific component while simultaneously streaming the rest of the layout (the static shell) to the client [cite: 33]. This architectural requirement completely breaks codebases and type definitions migrating from Next.js 14 [cite: 14, 34].

### 4.2 Before and After: Code Migration

#### Next.js 14 (Synchronous - Deprecated)
```tsx
// ❌ FAILS IN NEXT.JS 15
export default function ProductPage({ 
  params, 
  searchParams 
}: { 
  params: { id: string }, 
  searchParams: { sort: string } 
}) {
  const id = params.id; // Throws error or undefined
  const sort = searchParams.sort; 

  return <div>Product {id} - Sort: {sort}</div>;
}
```

#### Next.js 15 (Asynchronous - Required)
```tsx
// ✅ REQUIRED IN NEXT.JS 15
export default async function ProductPage({ 
  params, 
  searchParams 
}: { 
  params: Promise<{ id: string }>, 
  searchParams: Promise<{ [key: string]: string | string[] | undefined }> 
}) {
  // Must await the props before destructuring
  const resolvedParams = await params;
  const resolvedSearchParams = await searchParams;

  const id = resolvedParams.id;
  const sort = resolvedSearchParams.sort;

  return <div>Product {id} - Sort: {sort}</div>;
}
```

### 4.3 Static Generation Opt-out Caveat
A critical nuance in Next.js 15 concerns `searchParams`. Merely awaiting `searchParams` does not statically generate the route [cite: 35]. If a `page.tsx` accesses `searchParams`, the *entire route segment* is opted into dynamic rendering [cite: 35]. To preserve static generation (SSG) for base routes, components utilizing `searchParams` must be isolated via `<Suspense>` client boundaries or separated into explicitly dynamic routes [cite: 35].

### 4.4 Anti-Rationalization Rules for Request APIs

| Anti-Pattern (What AI is tempted to do) | The Reality in Next.js 15 | Why it Fails |
| :--- | :--- | :--- |
| **Destructuring `params` in the function signature: `async ({ params: { id } }) => ...`** | `params` is a Promise and cannot be destructured synchronously in the signature [cite: 1]. | A type error is thrown: `Property 'id' does not exist on type 'Promise<{ id: string }>'`. The compilation will fail [cite: 34, 36]. |
| **Using `export const dynamic = 'force-dynamic'` to silence `searchParams` build errors.** | This masks the core issue and aggressively de-optimizes the entire application route [cite: 35]. | It opts the entire route into server-side rendering (SSR), abandoning static generation (SSG) for pages that do not actually require dynamic processing, severely degrading Time to First Byte (TTFB) [cite: 35]. |
| **Using `use() ` on `params` in Server Components.** | While React's `use()` unwraps Promises, standard `async/await` is the mandated and type-safe approach in Server Components [cite: 1, 32]. | Code generated by LLMs may misuse React 19's `use()` within async Server Components, leading to linter warnings or nested suspense hydration mismatches [cite: 13]. |

---

## 5. Project Structure Patterns and Feature-Sliced Design (FSD)

As Next.js applications scale, dumping all components, hooks, and utilities into a global `src/components` folder creates tightly coupled, unmaintainable monolithic structures [cite: 26]. The industry has converged on several structural patterns optimized for the App Router.

### 5.1 Colocation and Private Folders
Next.js intentionally allows the colocation of non-routable files inside the `app/` directory. A route only becomes public when a `page.tsx` or `route.ts` file is present [cite: 25].
*   **Colocation**: Developers can place `button.tsx` or `api-helpers.ts` directly next to the `page.tsx` that consumes them [cite: 25, 26].
*   **Private Folders `_folder`**: Prefixing a folder with an underscore (e.g., `_components`) explicitly removes it and its children from the routing system, strictly enforcing that no URL can ever map to it [cite: 25].

### 5.2 Feature-Sliced Design (FSD) in Next.js
Feature-Sliced Design (FSD) is a rigorous frontend architectural methodology that enforces unidirectional dependencies. It groups code by business domain (Features) rather than technical role (Components/Hooks) [cite: 11, 37].

FSD dictates a strict hierarchy of Layers (bottom to top dependencies):
1.  **Shared**: Generic UI, reusable utilities (e.g., `ui/button`).
2.  **Entities**: Business domain models (e.g., `user/model`, `article/api`).
3.  **Features**: User interactions delivering business value (e.g., `auth/login`, `article/add-comment`).
4.  **Widgets**: Complex composite blocks (e.g., `header`, `user-profile-card`).
5.  **Pages**: The composition of widgets to form a view.
6.  **App**: Global initialization, providers, routing [cite: 37, 38].

**The Conflict with the App Router**
FSD's requirement for a flat layer hierarchy inherently conflicts with the Next.js `app/` directory, which relies on deeply nested folder structures mapped to URLs [cite: 10, 37].

**The Architectural Solution**
To integrate FSD with Next.js 15, the `app/` directory must be treated *exclusively* as a thin routing layer. It must contain no business logic [cite: 10, 11]. 

1.  Move the Next.js `app/` folder to the root of the project.
2.  Maintain the FSD `src/` folder containing the layers (`shared`, `entities`, `features`, `widgets`, `pages`).
3.  The `app/` folder files (`page.tsx`, `layout.tsx`) only serve as entry points, directly importing and returning components from the FSD `pages` or `widgets` layers [cite: 10].

```tsx
// app/blog/[slug]/page.tsx (Next.js Thin Routing Layer)
import { BlogPostPage } from '@/pages/blog-post'; // Importing from FSD layer

export default async function Page({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  // No fetch logic, no UI building here. Delegate entirely to FSD.
  return <BlogPostPage slug={slug} />; 
}
```

### 5.3 Clean Architecture vs. Feature-Sliced Design
While Clean Architecture organizes code in concentric circles separating infrastructure from domain logic, it often results in heavy boilerplate [cite: 39]. FSD is distinctly "frontend-first," adapting Clean Architecture concepts by distributing business logic vertically across specific features and coupling it closely with its UI representation [cite: 39]. FSD is explicitly recommended for Next.js applications expected to scale beyond 20+ feature domains [cite: 11].

### 5.4 Anti-Rationalization Rules for Project Structure

| Anti-Pattern (What AI is tempted to do) | The Reality in Next.js 15 | Why it Fails |
| :--- | :--- | :--- |
| **Placing API fetch logic and raw SQL/ORM calls directly inside the `app/[route]/page.tsx`.** | Next.js permits this, but it violates separation of concerns and FSD principles [cite: 11, 31]. | Code becomes un-testable and tightly coupled to the routing framework. Reusing the data fetching logic for a separate component leads to duplication and N+1 query problems [cite: 11, 14]. |
| **Generating a `pages/` folder for FSD and assuming Next.js will ignore it.** | Next.js still supports the legacy Pages Router (`src/pages`). Having both `app/` and an FSD `src/pages` causes fatal build conflicts [cite: 10]. | The framework attempts to compile the FSD `pages/` layer as legacy routes, crashing the build. The FSD `pages` folder must be renamed (e.g., `views`) or Next.js must be carefully configured via a root `pages/README.md` workaround [cite: 10]. |
| **Over-engineering small apps with FSD Entities.** | FSD is highly boilerplate-intensive. Entities should not be preemptively created [cite: 11]. | For small-scale projects, adopting FSD leads to massive directory bloat. Logic should start in `Features` or `Pages` and only promote to `Entities` when explicitly shared [cite: 11]. |

---

## Conclusion

The Next.js 15 App Router is an uncompromisingly powerful framework that demands strict adherence to its conventions. The transition of request APIs to asynchronous Promises isolates data fetching from shell rendering, unlocking unparalleled streaming performance. Simultaneously, advanced paradigms like Parallel and Intercepting routes eliminate the need for complex client-side state management for UX elements like modals. By adhering to the precise file hierarchy, acknowledging the state persistence differences between layouts and templates, and structurally isolating business logic via methodologies like Feature-Sliced Design, engineering teams can build resilient, highly scalable applications resistant to the common pitfalls of modern web development. Automated agents and human developers alike must override outdated heuristics and conform to these architectural realities to prevent silent failures and critical production regressions.

**Sources:**
1. [dev.to](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGH5cQwwzQUBhL_fu3b64T10XnGO9iCsax-MLV8g7jZjHRTe-izjg4l6ZudpQa3BCj1qQhcLojjPZZ4rxX9dyQfe6-275xkQgPlcHun0a7U8dElYGis624Ru_7PCsCAkBxiok27egh_YVkkOEe9b_VuvzTVCL5fXS010HTRGG6AGiwjL5Kt7PowN9RQN_GZxXVqdrm0)
2. [luckymedia.dev](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFI_vX3pAKvupzWjxi0NwgmhUJLzcBhxqL0KmkxmkiF80CgYpTFJ7Kx9DaHnjQ60b_hvv55-4sPVPsxR0X5kNHucVKWMqGGqWedkDivyNHa1agtYRpV3mFuAwgrG-tgnbklqetORTGIKpdQ3ujfwNnJxAWmVUSrV1nixw38fDBU)
3. [nextjs.org](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFJlWLm-rhqq40vqWKcOUxWDGEKt-KdK04SDtTgNCwu58qEfo7Z9Q8eiCeK9AhcE1o1w5fZ-JfcnrFQFOh-f-GpQh-PuY11Og0ySq3UiUc-acs01w108skf7_XQRM2P8ac6Wts_UCK5G19SFu5mIKfcZcW46LFgiw==)
4. [nextjs.org](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQG7wZXXwVK6NgxBDIB26uYttMjkGtHaZqeMmIVKrMwZftu-7COqbIgKGi01HdXQByXHYUub6pEE1rLq0rGk-8DxNQ-psz-SxIbZ7EqZbm6_psRpvOcqO0ilPAA1vhLkx_nFyjATkAFjMR3pItSIz0sYsRXeB0nuSpDgdH_-6YGILQVcMfiN)
5. [youtube.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGCPVAz8V8hjwKT8X-nx8TKC9Ybc3h86d4Efs2QXaG8bXJs_zk9OZlaaX-J9d2nQSKVhmgcb3AViXQaaG7-sx-Xy_4QjBoF1SEY9ssqmTcAwLFebWr6-O-uPo9ndEU-RUhP)
6. [stackoverflow.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGZdvBanigbH01QAOuCVAkSnMRjJBbutbqMZpQsbZHXjGQMK8FQfmxDre5d_ZPLWmHD1V2VCAvWCM3xWyLMvnEXTrERR1RHRWti1G7vcDmG4ujH-t6g8gRdL2W7mm29lJ1Tz71nBEu8BQEM_Rb8MwqAUJyRnjtZv9H7citCWrNGIF6fAOZv9eem8oGj9rXUIJV0RBx1E0976PhWNIjBvzA0y-w=)
7. [dev.to](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHwuPmJCUWmy0ILxsrZ6emJZvkqMEbDqVa3HGaV29ezkmQ8G1LFezzX6phzaP38zh1-FS8f4V4PYHiXiYO6UejQvtS8Ol7f0O2er7x9Eak4Yeqjx67d7t0dLO25pg10pAHslf2wmuSZcGjUiXRocJpqtIQW9yjRRSWBSlAxLYZagxS2WzjvoRSsIchAnQ==)
8. [oneuptime.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEU9ofUEGQ-v28nLFTqCxmI02i8bIBWh1IfrLrK9OxjG45qjUh_7jeg_f0IbOr3qpR_gxoEht9ATVeGu1DD4AdcHTz2uGNR3gN74ZaHFnWuEDpL-RRWwe0kiDfB5LcDqSRBoldjYYBgSQIvD0n-hKZ0qlooHzAQ3CtW8mAuKsiHSz7l0A==)
9. [dev.to](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQH5EdR7gRDTQBatdll2oAGrUH-MHZlr75sFBuz57RoakeUhqsuFf4CxmDhmbdj7yOuynj2AIiFpGui-LkVaejFywcJ8TDAQwN7rp_h7z6s0-mdWU_yS2uxq6I5qu2NzYVGqT1L7tq1JGOH21NVzFybTSENWEOhfOUZHZxy2yrrWbqkWQr422sswjgyfJGaER5uAisrZKInOnyDzuc5uA6qt)
10. [feature-sliced.design](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGbi1IgLjUDPsTtI2gCr4jThXcuYY1PWWQyTVlVGRwdhsTtNX420dSCJTqayA-yQ1SGol8XbQFoqeXtEx4L_rYKyk7Kxp6xG4NOLzZYb1t7aCF5z-DSE3p9I1JWiElSDilYB0KmxcGX24IQ_Qto36rt)
11. [lobehub.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQF4MOkxrFsEdjJEIJlwEuWSGhAuxK77pGiZnCbP6QFfJ-OEmMxv4-unx5lyuIrX0H08TJ7oKqEWBHXRH5zGCtmGzBLnGS7rJTvXXXfeO8LvSQr8pbCHTPZxT0NpwYertQyVsfry8I4X0hgx)
12. [logrocket.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQERHYrqwK8D7BSa-VM_YjmxlsxbbHGWn46I-hXHZ-IBUQ5Yj1As_YONZZ6TfHWWvPE9P9ISDU3wzHcnsxkge_dbvdBBDNH3DRPHy-T6FdEeyKn10lTG42Tlwf7aHpCh_HQdW34wiDpJjcloHVnT78Eub-jZY0xAGKVfE6mYZ_HSOw==)
13. [youtube.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGcwg-2OcxdvD9E7LDbbYZHItgojEsTVjM-AIN75hA8A_2qfJzX2VHaF6o1c50C4JT6ieQXUhzoXfx4esEfeC5tkYIwXMqAwxAG8wZSC0kmGg16D7ddX34TxzCwnFS5Pueu)
14. [dev.to](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQF7HY41RN6FRckWYFdjyLpgi1GPS9EBF4jkN3QZo6MoImq6YNHzGldxx-G6privYQceqFNrGnjjHeQ0iouFArZg46l7uRRdv7I9Y3YIfhSHHaYbCMGEdwkI5Yb0ji0XfZxAcK_0YchcBu65L0GZacNB11cilL7ptpVP4v3v-paQyKGHnUIUoiwy5alNERqTjI6oLOraK1PV5Vd1okCokzpRpi4x_DxDVxkxsUAp4A==)
15. [nextjs.org](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGrdtl1rBv5MgcWZvA5CQWdX9nlG7q5vrrupOg15aj-7kr6LAIqmcNbHHHrhpvl41k3n6TGLwVUfdG5bG8wfrNUniMMgLR3lUOQRJCl_UYlQbkWQJAfafdSoDQ_kZaiLFznKqhZ0F8p3Xs0oznh76T3V5heUk0yKq4=)
16. [nextjs.org](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGb5rWChpvGUuK4zxWfdtdHMLgVN34pGS2mvQReP4GWou3YaoGpkNAoE_inbzQISZWQGxfIdUsY_QnsyG2n1PVu1RLCtTbEVrMmgog2AWRzfKGtYHI1r3RcNpfHF0wSZq9kTyu73-47Ef1h4UrkRKGtcsDg8FQdXhDSrw==)
17. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFhAu5AbtvKP01cLAm7DoTXzFGC5-bkAiSCWCZn3pF9uN_VUnT_jPY5-epuhMM9NtYwJNQByBbRGuEMrSyMtD0ZtcJxP0nU71ygfAjdSYiYa2vSQOeAv5EkEwFwLu1f9kINNROwLgampP-1wVYl857f0OJjnqZfHL-iG1EK5TkHxhKCiBbl_I3OyF4uX1LYN-uCmlZUupePH-Y=)
18. [nextjs.org](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFh63Nxtolp0EXg1QNkLwZRY8_PSku8lrIrYBdfiojb-tQdjN2FXbF6xRivn6u6n7e8Ffy1vjU1kvoeDFCEXK7UR107J_Q27usRRrlEzF7bEhSxbpMhlsfyJb3KGyfdudJ-qLKOLTxtauwY_Xpii4Us)
19. [devanddeliver.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGltzDiQhen_IvjbrCSsEZFhwc72FqbIFaELiIjtqpmSBM1Ng7EbhPEjEP8DqPV3ipIcDMBgXJwcR3abMAEkFMiYF3lpVkYvircFyoTZcg89RRIwUc5w4NEU-9QJlk3S0wp3E9_Tkx6NvapdqTKFW7cFWnHqSt2HkIcU2FXt9fS0DLOT1BjZGWEqiUmIYL4ZoYewxPicjSQinrk)
20. [youtube.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGi58u3psINlAqCumdbQch4s-DbYoOgtbcu4_KayiCxmxg0DHXrUNsAYEtqTChcAli1FIULcee03LKbJ0Lb1v03fYmDP86zChMO-M9fQgS3z7P5TGMw5TkGB2HVPcdoG7uF)
21. [bti360.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHsz9l830-oNRzKQwOs0fyKdDI-b-eKIsE8-UYpwM2hOuMuhiJHBBcTCLbH6wgA0IiaqQQ3G6fG_Ngi5L3XvLOfbjvsnGnzeMgqIBpvI33ZUdNBGK4lv8fHAbW7sqcKQLf5UhalN3DC_ucy60lDR40tWBxcPJKKpl4=)
22. [builder.io](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHEhgHBWS2qQEXkR8JosiJz-458H88S09z7B91lO6xev71gQRlcCQJP3w5Yi0ykU_Y_do8gxSoHla9aVtA-YYngjaoG_NHOO0N4Wxe4LVKMZg3S5inI8Jkj8B_KZlvQpZNFhzx9dA8Wswab2utj)
23. [youtube.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGZr2qArQQpSg_m-k05QxbEMuyS8rYTuBebSwvlgH-FAn2tDvZnJ9_9kWXAsDihQ6RPz2YzgvYC3k7F8FPmO5B9jv0oDKrehqEp191fghdtuHpQ_YetPhKvu_i47UPCSB6r)
24. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEheGStnYmUeSeJbN41BmM8NhKPvUnDOt0Ze46ooVZGNRM267HAci366HGHrEP-xM1GGsJflVNCvQikPNPktUwuuTzctpUyYb058ZsfsD0I6dYthvDImhI21TGap8XdMzkwtkEh2rz9ocIr50x1EurbLhWIDFvfrCRLAVnFDiamaWpgYG-jmTUoN96DK-g_KB6xDk39RnBy1HCl5GzU3cJcEAcdUrN3_YxpcDZm8w==)
25. [nextjs.org](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGWohDfoB7_K_nCsGVgTrg4trfuoMI1thnHGN-4aTBvnW1JsIZ3JWjaBg7PxUOdcNg8-nFBlp4lPafL5nZ9OcoA8OX68gSk6AiUP3GA5iDYjkANrvnS_YTcECIud8wR0-spDzeYV8Y_-jFPTl8eaA3YYvEF)
26. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQF8Hl_EEQcAmueRMFLYbG_qD5daltqvHLxWDRLg-rEUDSa-L3sUGYxnMtM-BwBEH3FzZ3yH5g--S4rJLqWvAiXHFP0edPzJZqW-PyWYojjz_cm_wMD2rYnOxOEsyjfKmaA2Hou2LxNzwdboQ9m9coPaKsl4jq5NaHMH8jSlwKPrTUfhMZkHG5s6QuRuL0pJxYIxUrY_7swKE5J_Kv9hUYiUEHINABYpdFX2hQskMJVf37pzym3rKywVar0W2aBML32Fb6xgE1EqcPM=)
27. [nextjs.org](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFG-AnmwydIlfbub39GTvgexjTL72Ppt6uIkRqmVb7dauKn5kdYIpQnjmLKgOP1K2talpwUU5E6-BDS9fvF3o84JEj3k1U7VQDO-dwPVOgtNH_RXgwS6Y9-FunLPkRnHZGADmnSXFz5nQegdUMCx2j8hmOvaNeufJGBuFTChwfhKbLlnGah4w==)
28. [nextjs.org](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGhD7ATANdSH9SBoqPH7gYus8zAQI7Z38Ct8SiuSFuFEZ6FY7fK0AQS0qzURkEqfCZllbX-0pmGgWv5m8wRhtvIuVxGk8uBh7alyPO63FFC-E9m4sb9RiiaaNJx4w-CslmWbFxV-LvaRv9wfPuzesOh-d0tJdlwzoUVm8bie971YA==)
29. [builder.io](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEFgUqUdWpUIDzm607SSMWNOXqNnmAmw4bsB1fw_au2RkjrYMCp20b2la8UXmGFkUuH7UQ4QzvAnEiJ7QQxu6Iz2Hyw3KNtcSYXVaiSPQeTisMOv8VCbWD9B90BZK3xmumzTNJN8-xh1Il0EWuxWWA=)
30. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEF-mTirK8JJ4hItfLU_roFCTeVCMujpfGN-ji3V5QiIYM3Ij-eZ2ngpsawoOhJWxjieMGe5w1q6KQAsG0ZsKHQbXcWTctatC_wi4QOOTQMtY_C1RuZxQg1PcrKdnJkfGOxzaDqI9bZrmAi03lnqs0JOXIGJ_6lUGlKtaawC4cXtghCgC2NJXGg7FVsiI43_CXjYzwGpTfAja9xL7-Xzi0aJvf0lsfrGPFiK3u_A_GR7L5u)
31. [plainenglish.io](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGrkQH9Np0HR0R708V3NrhLlOEGtQF7DepkI8yg8TRHKtw6g1BVlfNowxx171Aw1DPJzq55QTcvzUfYBW5Mbj07RVuAXSkWqLFWbdW6yz4d5tzqwCSgAicxY2QurrTma96rIwRqaL4i-4HrpDvMeZ-Xr1vie5tRWeE3RINpjTN2zdAlDB5h4ONwqoHk_L4zjwKlvX-TuTfboH07VSPSVQ==)
32. [github.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFZsHuUDYp9qutAQSqGtJ1oAZkrU4ToE_yJCBQhKutD0m7N2IL_MFk6xfbrO8wgrh_w4INB6iPEIDxBVBmnmGvtovma9zfoXhdiKYTN60w_lBo-138Kob0peh3xQitlq4c6fwEi)
33. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFzHdXgIvpfaikZLLYB52qHVmWtqPZfAnG_ONMKzL-TQHKMAIOsFMicMAAq-qwJRp8i2Kk1affDg9nGHOHieiWNYHXudeyruSAUkKty4wOHFoM5t4GYG8l_-rU3uPK5zMXQWjT-HAeIn0omv-4F6Nc0goDiamAsZMdtZ-fqe45k6zKeAOzSQv4kgQL2d5juR1_ukg2nEnWbdw==)
34. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEPdy6uPF43up_b8DZCGb6DVHtAG9IW1KsQxO6TqjUjlvF2XOQS-LGGeUAagRHRJl7CMsdyQGq3UdiwaGj6CNy6F-CXYLfx6c2KY7z8oyPQ2VhmyVhtufZhv4gMTodq5-DJmjVly_Syo_nTvslXGS6FOBnCV-HJ6icvO3DCHt_NHRcH1I8VnvZxzQrItw3aFluqBmIvugB-jX6WDminHMA5x3sDFeEuPQ==)
35. [buildwithmatija.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFDJRz787RRtPZe2JCf28jk4JRBonHyT6wWNO6f6F4GN3caALZbT1HoXeJbNicsYJZqZQ64SNyZ0itu7wn1wczT3ktQ-0r8QYM6mOBdhBFwWlBAkqsBXDgkIDnR-j-BXMfEj9-gcPxlc3Xnd2-r1tlECz8eTbdFOBP2HtmKCfFAZVqzcXM=)
36. [github.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEeoXXGB587iF_sbWOE2-Esu4AxyDbTiD9vv4gyIzlzNvjJJsMLLkoTi5GJ5MDb-JIzzMJVKd7mHVeYMXh3uS1dDS0njhfMvzKVzPpAeUvbNzwaNUGg46HRYtDeoYJXKt2ugeAI)
37. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFxJz4UCB-LwdXIqml579IvQQ3GqLoWyjkqrf1hWBgukK8ctWqWaJRzXuy9XfLM0ozGDE8KNlkJjTq3TnrJYyMbhJ23mBgdUZOC1Ba6NWMBVmip4zZFhRB3HYH3symkFH_VgBEHAswOLlhITeVmKhPMv3m-pOq9IOYqlnFjDZSxe3R1xfWQmIATkQ8=)
38. [delvestack.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFj7oOxUGVuaOiA8DgcuG5vCZNiq45bB_OmMTCirN85ia3ojOqKW-3jKbFy5IVoJDlFvvrV3YBeK8fEUK-ODWQEi5VromTPtJv8GVndj8BjC6S1DTUaQF_t0inljwemLDwd_dlFYsGOeW75LK2aDcs58EGufIE=)
39. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHQKROrZBK1vtGoW7Tta7SK4wiv_sWa1FbVh8REa3JHIUrHyBU45lHDUu25py8Jm0hpAON7mOPgSIzn6xzhAII5J2dfydM-7mxzQiJHG0mx2b6YywXWxkzcKpujJNeCApSLzlrBkeM21JxPwCqoYnIigIQEWhrQWsDVQlK4mUDLgU-rkn01skOjbRIfIeyNbGAfwwdAQG2Sz8rhlliBYgvSwJqlT8hUI20=)
