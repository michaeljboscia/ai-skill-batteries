---
name: mx-react-data
description: React data fetching — TanStack Query v5, SWR, query keys, staleTime, gcTime, mutations, optimistic updates with rollback, cache invalidation, prefetching, parallel queries, waterfall prevention, Suspense + Error Boundaries for loading states, server state vs client state architecture
---

# React Data — Server State & Fetching for AI Coding Agents

**Load this skill when fetching data from APIs, managing server state, configuring caching, implementing mutations, or choosing a data fetching strategy.**

## When to also load
- `mx-react-state` — client state (Zustand) is SEPARATE from server state (TanStack Query)
- `mx-react-effects` — raw useEffect fetch is an anti-pattern; this skill replaces it
- `mx-react-core` — Error Boundaries and Suspense for loading/error UI
- `mx-react-perf` — prefetching, waterfall prevention, structural sharing

---

## Level 1: Patterns That Always Work (Beginner)

### 1. Use TanStack Query for All Server Data

Never fetch in useEffect. TanStack Query handles caching, deduplication, retry, background refetch, and race conditions automatically.

```tsx
// BAD: Manual fetch in useEffect
function UserProfile({ userId }: { userId: string }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);
  
  useEffect(() => {
    let cancelled = false;
    fetch(`/api/users/${userId}`)
      .then(r => r.json())
      .then(data => { if (!cancelled) setUser(data); })
      .catch(err => { if (!cancelled) setError(err); })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [userId]);
  // Missing: caching, retry, dedup, background refetch, shared across components
}

// GOOD: TanStack Query
function UserProfile({ userId }: { userId: string }) {
  const { data: user, isPending, error } = useQuery({
    queryKey: userKeys.detail(userId),
    queryFn: () => fetchUser(userId),
  });
  // Caching, dedup, retry, refetch on focus — all automatic
}
```

### 2. Query Key Factories — Always

Never hardcode query keys as inline arrays. Use a centralized factory.

```tsx
// The factory — one per API domain
export const userKeys = {
  all:     ['users'] as const,
  lists:   ()                        => [...userKeys.all, 'list'] as const,
  list:    (filters: UserFilters)    => [...userKeys.lists(), { filters }] as const,
  details: ()                        => [...userKeys.all, 'detail'] as const,
  detail:  (id: string)             => [...userKeys.details(), id] as const,
};

export const postKeys = {
  all:       ['posts'] as const,
  byUser:    (userId: string)       => [...postKeys.all, 'user', userId] as const,
  detail:    (id: string)           => [...postKeys.all, 'detail', id] as const,
};

// Usage — type-safe, refactor-safe, invalidation-safe
useQuery({ queryKey: userKeys.detail(userId), queryFn: () => fetchUser(userId) });

// Invalidation — partial matching
queryClient.invalidateQueries({ queryKey: userKeys.all }); // Invalidates ALL user queries
queryClient.invalidateQueries({ queryKey: userKeys.detail(userId) }); // Specific user only
```

### 3. Configure Global Defaults

```tsx
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 60_000,        // 1 min fresh — prevents over-fetching on tab switch
      gcTime: 10 * 60_000,      // 10 min in memory after last subscriber unmounts
      retry: 2,                  // 2 retries with exponential backoff
      refetchOnWindowFocus: true, // Only fires when data is stale
    },
  },
});
```

| Setting | Default | What It Controls |
|---------|---------|-----------------|
| `staleTime` | `0` | How long data is "fresh" (no background refetch while fresh) |
| `gcTime` | `5 min` | How long inactive data stays in memory |
| `retry` | `3` | Retry count for failed queries |
| `refetchOnWindowFocus` | `true` | Re-fetch stale data when user returns to tab |

### 4. Suspense + Skeleton UI for Loading States

```tsx
// Skeletons > Spinners — maintain visual layout continuity
function App() {
  return (
    <Suspense fallback={<UserProfileSkeleton />}>
      <UserProfile userId="123" />
    </Suspense>
  );
}

// Enable Suspense mode in TanStack Query
function UserProfile({ userId }: { userId: string }) {
  const { data } = useSuspenseQuery({
    queryKey: userKeys.detail(userId),
    queryFn: () => fetchUser(userId),
  });
  return <div>{data.name}</div>; // data is guaranteed non-null
}
```

---

## Level 2: Mutations & Cache Management (Intermediate)

### Optimistic Updates — The Full Pattern

Three callbacks, always in this order: `onMutate` → `onError` → `onSettled`.

```tsx
function useUpdateTodo() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (updated: Todo) => api.updateTodo(updated),

    onMutate: async (updated) => {
      // 1. Cancel in-flight queries (prevent race condition overwriting our optimistic data)
      await queryClient.cancelQueries({ queryKey: todoKeys.lists() });
      
      // 2. Snapshot previous state for rollback
      const previous = queryClient.getQueryData<Todo[]>(todoKeys.lists());
      
      // 3. Optimistically update cache
      queryClient.setQueryData<Todo[]>(todoKeys.lists(), (old) =>
        old?.map(t => t.id === updated.id ? updated : t) ?? []
      );
      
      return { previous }; // Passed to onError as context
    },

    onError: (_err, _updated, context) => {
      // 4. Rollback on failure
      if (context?.previous) {
        queryClient.setQueryData(todoKeys.lists(), context.previous);
      }
    },

    onSettled: () => {
      // 5. Always re-sync with server (runs on success AND failure)
      queryClient.invalidateQueries({ queryKey: todoKeys.lists() });
    },
  });
}
```

### Invalidation Strategies

```tsx
// After mutation — invalidate related queries
const mutation = useMutation({
  mutationFn: createPost,
  onSuccess: () => {
    queryClient.invalidateQueries({ queryKey: postKeys.all });    // All post queries
    queryClient.invalidateQueries({ queryKey: userKeys.detail(userId) }); // User's post count
  },
});

// Partial matching — invalidate a subtree
queryClient.invalidateQueries({ queryKey: ['posts'] });          // All posts
queryClient.invalidateQueries({ queryKey: ['posts', 'list'] });  // Just lists, not details

// Exact match — single query only
queryClient.invalidateQueries({ queryKey: postKeys.detail('123'), exact: true });
```

### Parallel Queries — Prevent Waterfalls

```tsx
// BAD: Sequential fetch — waterfall (PostList waits for UserProfile to finish)
function Dashboard({ userId }: { userId: string }) {
  const { data: user } = useQuery({ queryKey: userKeys.detail(userId), queryFn: fetchUser });
  const { data: posts } = useQuery({
    queryKey: postKeys.byUser(userId),
    queryFn: () => fetchPosts(userId),
    enabled: !!user, // Waits for user — unnecessary dependency!
  });
}

// GOOD: Independent queries run in parallel automatically
function Dashboard({ userId }: { userId: string }) {
  const { data: user } = useQuery({ queryKey: userKeys.detail(userId), queryFn: () => fetchUser(userId) });
  const { data: posts } = useQuery({ queryKey: postKeys.byUser(userId), queryFn: () => fetchPosts(userId) });
  // Both fire simultaneously — no waterfall
}

// GOOD: Dynamic array of parallel queries
const results = useQueries({
  queries: teamIds.map(id => ({
    queryKey: teamKeys.detail(id),
    queryFn: () => fetchTeam(id),
  })),
});
```

---

## Level 3: Advanced Architecture (Advanced)

### Server State vs Client State — The Two-Layer Rule

| Layer | Tool | What Goes Here | Examples |
|-------|------|---------------|----------|
| Server state | TanStack Query | Remote, async, shared ownership | Users, products, orders, comments |
| Client state | Zustand / Context | Local, sync, ephemeral | Filters, cart, modals, theme, selected tab |

Zustand filters can DRIVE TanStack Query keys:

```tsx
function ProductList() {
  const filters = useFilterStore((s) => s.filters); // Client state
  const { data } = useQuery({
    queryKey: productKeys.list(filters),              // Filters in query key
    queryFn: () => fetchProducts(filters),            // Re-fetches when filters change
  });
}
```

### Prefetching on Hover/Route Anticipation

```tsx
function ProductCard({ product }: { product: Product }) {
  const queryClient = useQueryClient();
  
  return (
    <Link
      to={`/products/${product.id}`}
      onMouseEnter={() => {
        queryClient.prefetchQuery({
          queryKey: productKeys.detail(product.id),
          queryFn: () => fetchProduct(product.id),
          staleTime: 60_000, // Don't re-prefetch if recent
        });
      }}
    >
      {product.name}
    </Link>
  );
}
```

### TanStack Query vs SWR Decision

| Context | Choose | Why |
|---------|--------|-----|
| Complex mutations, optimistic updates | **TanStack Query** | Built-in rollback context, DevTools |
| Read-heavy, minimal mutations | **SWR** | Smaller bundle (~4KB), simpler API |
| Next.js with Vercel deployment | **SWR** | First-class Vercel integration |
| Enterprise dashboard | **TanStack Query** | Garbage collection, DevTools, granular cache control |
| Both coexist? | Yes | TQ for complex data flows, SWR for simple reads |

---

## Performance: Make It Fast

### 1. staleTime > 0 Prevents Over-Fetching
Default `staleTime: 0` means every mount/focus triggers a background fetch. Set `staleTime: 60_000` globally for most apps.

### 2. Prefetch on Hover
Pre-populate cache before navigation. User sees instant data on page load. See prefetch pattern above.

### 3. Structural Sharing
TanStack Query preserves referential identity for unchanged parts of the response. A re-fetch that returns the same data won't trigger re-renders in components using `===` equality on nested objects.

### 4. Deduplication Is Automatic
Multiple components calling `useQuery` with the same key = ONE network request. Never worry about duplicate fetches.

---

## Observability: Know It's Working

### 1. TanStack Query DevTools

```tsx
import { ReactQueryDevtools } from '@tanstack/react-query-devtools';

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <Router />
      <ReactQueryDevtools initialIsOpen={false} /> {/* Dev only */}
    </QueryClientProvider>
  );
}
```

Shows cache state, query timing, stale/fresh status, active/inactive queries.

### 2. Error Boundaries per Data Section

```tsx
<ErrorBoundary fallback={<DataFetchError section="user-profile" />}>
  <Suspense fallback={<UserSkeleton />}>
    <UserProfile />
  </Suspense>
</ErrorBoundary>
```

### 3. Mutation Error Tracking

```tsx
const queryClient = new QueryClient({
  defaultOptions: {
    mutations: {
      onError: (error) => {
        Sentry.captureException(error, { tags: { type: 'mutation' } });
      },
    },
  },
});
```

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Fetch in useEffect
**You will be tempted to:** Write `useEffect(() => { fetch(url)... }, [])` for "simplicity."
**Why that fails:** No caching, no dedup, no retry, no background refetch, race conditions, boilerplate loading/error state, memory leaks. You're reimplementing TanStack Query badly.
**The right way:** `useQuery` for reads, `useMutation` for writes. Always.

### Rule 2: No Copying Query Data into State
**You will be tempted to:** `useEffect(() => setProducts(queryData), [queryData])` to "normalize" it.
**Why that fails:** You opted out of background refetching, stale-while-revalidate, cache invalidation, and optimistic updates. Your copy is immediately stale.
**The right way:** Consume `data` directly from `useQuery`. Transform in the query's `select` option if needed.

### Rule 3: No Skipping the Optimistic Pattern
**You will be tempted to:** Show a spinner for every mutation and wait for the server.
**Why that fails:** Users expect instant feedback for micro-interactions (likes, toggles, status changes). Spinners for sub-second operations feel broken.
**The right way:** `onMutate` (cancel + snapshot + optimistic update) → `onError` (rollback) → `onSettled` (invalidate).

### Rule 4: No Inline Query Keys
**You will be tempted to:** `useQuery({ queryKey: ['users', userId, 'posts'] })` scattered across files.
**Why that fails:** Typos break caching silently. Refactoring misses invalidation targets. No single source of truth for cache structure.
**The right way:** Query Key Factory per domain. Every key traced to one object.

### Rule 5: No Waterfalls from `enabled` Chains
**You will be tempted to:** `enabled: !!user` to "wait for data" when the second query doesn't actually depend on the first.
**Why that fails:** Sequential fetching doubles load time. If queries are independent, they should run in parallel.
**The right way:** Only use `enabled` when query B literally needs data from query A's response as input. Otherwise, fire in parallel.
