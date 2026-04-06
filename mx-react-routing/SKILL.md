---
name: mx-react-routing
description: React routing — React Router v7, TanStack Router, nested layouts, Outlet, data loaders, actions, code splitting, React.lazy, Suspense, auth guards, protected routes, error boundaries per route, prefetching, View Transitions API
---

# React Routing — Navigation & Route Architecture for AI Coding Agents

**Load this skill when configuring routes, implementing layouts, adding auth guards, code-splitting, or choosing between React Router and TanStack Router.**

## When to also load
- `mx-react-data` — route loaders interact with data fetching (TanStack Query integration)
- `mx-react-core` — Error Boundaries per route section
- `mx-react-perf` — code splitting, lazy loading, prefetching
- `mx-react-testing` — testing route navigation with MemoryRouter

---

## Level 1: Patterns That Always Work (Beginner)

### 1. Router Choice Decision Tree

| Primary Need | Choose | Why |
|-------------|--------|-----|
| Migrating from React Router v6 | **React Router v7** | Non-breaking upgrade path |
| End-to-end type safety (params, search, loaders) | **TanStack Router** | Native TS inference, no codegen |
| Full-stack framework (SSR, loaders, actions) | **React Router v7 Framework Mode** | Remix merged in, Vite integration |
| Complex URL state (multi-facet filtering) | **TanStack Router** | Built-in Zod/Valibot search param validation |
| SPA with minimal routing needs | **React Router v7 Library Mode** | Simplest setup |

### 2. Nested Layouts with Outlet

Parent routes render shared UI (nav, sidebar). `<Outlet />` renders child route content.

```tsx
// Layout route
function DashboardLayout() {
  return (
    <div className="flex">
      <Sidebar />
      <main className="flex-1">
        <Outlet />  {/* Child routes render here */}
      </main>
    </div>
  );
}

// Route config
const routes = [
  {
    path: '/dashboard',
    element: <DashboardLayout />,
    children: [
      { index: true, element: <DashboardHome /> },
      { path: 'analytics', element: <Analytics /> },
      { path: 'settings', element: <Settings /> },
    ],
  },
];
```

### 3. Error Boundaries Per Route

```tsx
const routes = [
  {
    path: '/dashboard',
    element: <DashboardLayout />,
    errorElement: <DashboardError />,    // Catches errors in this subtree
    children: [
      {
        path: 'analytics',
        element: <Analytics />,
        errorElement: <AnalyticsError />, // Granular — sidebar stays visible
      },
    ],
  },
];

// Error boundary component
function AnalyticsError() {
  const error = useRouteError();
  if (isRouteErrorResponse(error)) {
    return <div>Analytics {error.status}: {error.statusText}</div>;
  }
  return <div>Analytics failed to load. <button onClick={() => window.location.reload()}>Retry</button></div>;
}
```

### 4. Route-Based Code Splitting

Split at the route level — the highest-impact splitting point.

```tsx
import { lazy, Suspense } from 'react';

const Analytics = lazy(() => import('./pages/Analytics'));
const Settings = lazy(() => import('./pages/Settings'));
const AdminPanel = lazy(() => import('./pages/AdminPanel'));

const routes = [
  {
    path: '/dashboard',
    element: <DashboardLayout />,
    children: [
      { index: true, element: <DashboardHome /> },  // Keep inline if small
      {
        path: 'analytics',
        element: (
          <Suspense fallback={<AnalyticsSkeleton />}>
            <Analytics />
          </Suspense>
        ),
      },
      {
        path: 'settings',
        element: (
          <Suspense fallback={<SettingsSkeleton />}>
            <Settings />
          </Suspense>
        ),
      },
    ],
  },
];
```

---

## Level 2: Data Loaders & Auth Guards (Intermediate)

### React Router v7 Loaders and Actions

Loaders fetch data BEFORE the route renders. No useEffect needed.

```tsx
// Route module: routes/team.$teamId.tsx

// Loader: runs before render
export async function loader({ params }: LoaderFunctionArgs) {
  const team = await db.getTeam(params.teamId);
  if (!team) {
    throw new Response('Team Not Found', { status: 404 }); // Caught by errorElement
  }
  return { team };
}

// Action: handles form mutations
export async function action({ request, params }: ActionFunctionArgs) {
  const formData = await request.formData();
  const name = formData.get('name') as string;
  
  const errors: Record<string, string> = {};
  if (!name || name.length < 2) errors.name = 'Name must be at least 2 characters';
  if (Object.keys(errors).length) return { errors }; // Return errors, don't throw
  
  await db.updateTeam(params.teamId, { name });
  return { success: true };
}

// Component
export default function TeamPage() {
  const { team } = useLoaderData<typeof loader>();
  const actionData = useActionData<typeof action>();
  
  return (
    <Form method="post">
      <input name="name" defaultValue={team.name} />
      {actionData?.errors?.name && <span className="error">{actionData.errors.name}</span>}
      <button type="submit">Save</button>
    </Form>
  );
}
```

**Key rule:** Validation errors return from action (not throw). Thrown responses are for unexpected/unrecoverable errors (404, 403).

### Protected Routes with Auth Guards

```tsx
function ProtectedRoute({ allowedRoles }: { allowedRoles?: string[] }) {
  const { user, isAuthenticated } = useAuth();
  const location = useLocation();

  if (!isAuthenticated) {
    return <Navigate to="/login" replace state={{ from: location }} />;
    // `replace` prevents back-button to protected page
    // `state.from` enables post-login redirect
  }

  if (allowedRoles && !allowedRoles.includes(user.role)) {
    return <Navigate to="/unauthorized" replace />;
  }

  return <Outlet />;
}

// Route config
const routes = [
  { path: '/login', element: <LoginPage /> },
  {
    element: <ProtectedRoute />,
    children: [
      { path: '/dashboard', element: <Dashboard /> },
      { path: '/profile', element: <Profile /> },
    ],
  },
  {
    element: <ProtectedRoute allowedRoles={['admin']} />,
    children: [
      { path: '/admin', element: <AdminPanel /> },
    ],
  },
];

// Post-login redirect
function LoginPage() {
  const location = useLocation();
  const navigate = useNavigate();
  const from = (location.state as any)?.from?.pathname || '/dashboard';
  
  const handleLogin = async (credentials: Credentials) => {
    await login(credentials);
    navigate(from, { replace: true }); // Back to original destination
  };
}
```

**Auth guards are UI controls only.** Always enforce authorization on the server too.

---

## Level 3: Advanced Routing (Advanced)

### Prefetching on Hover / Viewport

```tsx
// React Router v7 — built-in prefetch
<Link to="/analytics" prefetch="intent">   {/* Prefetch on hover */}
  Analytics
</Link>
<Link to="/settings" prefetch="viewport">  {/* Prefetch when visible */}
  Settings
</Link>

// Manual prefetch with TanStack Query integration
function NavLink({ to, queryKey, queryFn, children }: NavLinkProps) {
  const queryClient = useQueryClient();
  return (
    <Link
      to={to}
      onMouseEnter={() => queryClient.prefetchQuery({ queryKey, queryFn, staleTime: 60_000 })}
    >
      {children}
    </Link>
  );
}
```

### View Transitions API

```tsx
// React Router v7 — native view transitions
<Link to="/profile" viewTransition>Profile</Link>

<NavLink to="/dashboard" viewTransition>
  {({ isTransitioning }) => (
    <>
      Dashboard
      {isTransitioning && <Spinner />}
    </>
  )}
</NavLink>

// Form navigation with transitions
<Form method="post" viewTransition>
  <button type="submit">Save</button>
</Form>
```

### TanStack Router: Type-Safe Search Params

```tsx
import { createFileRoute } from '@tanstack/react-router';
import { z } from 'zod';

const productSearchSchema = z.object({
  page: z.number().default(1),
  category: z.string().optional(),
  sort: z.enum(['price', 'name', 'rating']).default('name'),
});

export const Route = createFileRoute('/products')({
  validateSearch: productSearchSchema,
  component: ProductList,
});

function ProductList() {
  const { page, category, sort } = Route.useSearch(); // Fully typed!
  const navigate = Route.useNavigate();
  
  return (
    <button onClick={() => navigate({ search: { page: page + 1 } })}>
      Next Page
    </button>
  );
}
```

---

## Performance: Make It Fast

### 1. Route-Level Code Splitting Is the Highest-Impact Optimization
Split every route that isn't on the critical rendering path. Admin panels, settings, analytics — all lazy loaded.

### 2. Prefetch on Intent, Not on Mount
`prefetch="intent"` loads code/data on hover (~200ms before click). User perceives instant navigation. Don't prefetch everything on mount — that wastes bandwidth.

### 3. Skeleton Fallbacks, Not Spinners
Suspense fallbacks should mirror the page layout (skeleton screens). Spinners cause layout shift and feel slower.

### 4. Avoid Over-Nesting Layouts
Each layout level adds a render boundary. 3-4 levels max. Deep nesting creates waterfall renders and complex error boundary chains.

---

## Observability: Know It's Working

### 1. Route Error Tracking

```tsx
// Global route error handler
function RootErrorBoundary() {
  const error = useRouteError();
  useEffect(() => {
    Sentry.captureException(error, {
      tags: { boundary: 'route', path: window.location.pathname },
    });
  }, [error]);
  return <ErrorPage />;
}
```

### 2. Navigation Timing

```tsx
// Track slow navigations
import { useNavigation } from 'react-router';

function NavigationMonitor() {
  const navigation = useNavigation();
  const startRef = useRef<number>(0);
  
  useEffect(() => {
    if (navigation.state === 'loading') {
      startRef.current = performance.now();
    }
    if (navigation.state === 'idle' && startRef.current > 0) {
      const duration = performance.now() - startRef.current;
      if (duration > 1000) {
        metrics.send('slow_navigation', { duration, path: window.location.pathname });
      }
      startRef.current = 0;
    }
  }, [navigation.state]);
  
  return null;
}
```

### 3. Bundle Size Monitoring
Use `vite-plugin-visualizer` or Webpack Bundle Analyzer in CI. Alert when any route chunk exceeds 50KB gzipped.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Flat Route Trees
**You will be tempted to:** Define 30 routes at the top level with no nesting.
**Why that fails:** No shared layouts, no code splitting boundaries, no granular error handling. Every page duplicates nav/sidebar.
**The right way:** Nest routes under layout routes. Use `<Outlet />` for shared chrome.

### Rule 2: No Data Fetching in Components (Use Loaders)
**You will be tempted to:** `useEffect(() => { fetch(url)... })` inside route components.
**Why that fails:** Data fetches after render, causing loading waterfalls. Loaders fetch BEFORE render — the page arrives ready.
**The right way:** React Router `loader` function, or TanStack Query `prefetchQuery` in route beforeLoad.

### Rule 3: No Auth Logic Scattered Across Components
**You will be tempted to:** Check `isAuthenticated` at the top of every page component.
**Why that fails:** One missed check = security hole. Auth logic duplicated everywhere. No centralized redirect behavior.
**The right way:** `ProtectedRoute` wrapper as a layout route. All children inherit auth enforcement.

### Rule 4: No Lazy Loading Everything
**You will be tempted to:** `lazy(() => import('./Button'))` for tiny components.
**Why that fails:** Code splitting tiny components adds HTTP request overhead that exceeds the bundle savings. Split at ROUTE boundaries, not component boundaries.
**The right way:** Lazy load route-level pages and heavy feature modules (admin panels, editors). Keep small shared components in the main bundle.

### Rule 5: Don't Skip Error Boundaries on Routes
**You will be tempted to:** Only add one global error boundary and call it done.
**Why that fails:** Any route error crashes the entire app. Sidebar, nav, and unrelated content all disappear.
**The right way:** `errorElement` on every route group. Failures isolate to the section that broke. Parent layout stays visible.
