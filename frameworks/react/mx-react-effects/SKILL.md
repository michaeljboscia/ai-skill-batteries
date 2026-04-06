---
name: mx-react-effects
description: React useEffect patterns, cleanup functions, AbortController, dependency arrays, stale closures, race conditions, subscriptions, timers, refs, useEffectEvent, debounce, throttle — when to use effects vs event handlers vs inline computation
---

# React Effects — Side Effect Management for AI Coding Agents

**Load this skill when writing useEffect, managing subscriptions, handling cleanup, working with timers, or deciding whether an effect is even needed.**

## When to also load
- `mx-react-data` — data fetching should use TanStack Query, NOT raw useEffect
- `mx-react-state` — stale closures and dependency arrays interact with state
- `mx-react-core` — ref cleanup functions (React 19) replace many useEffect patterns
- `mx-react-perf` — effects that run too often degrade performance

---

## Level 1: Patterns That Always Work (Beginner)

### 1. The #1 Rule: You Probably Don't Need an Effect

useEffect is an ESCAPE HATCH to sync with external systems. Not a lifecycle method.

| Question | Answer | Use |
|----------|--------|-----|
| Can I compute this from props/state? | Yes | Inline calculation or `useMemo` |
| Does this happen because the user did something? | Yes | Event handler |
| Do I need to reset state when a prop changes? | Yes | `key` prop on the component |
| Do I need to sync with something outside React? | Yes | **useEffect** |

### 2. Always Clean Up

Every effect that creates a subscription, timer, or connection MUST return a cleanup function.

```tsx
// BAD: No cleanup — memory leak, stale subscriptions
useEffect(() => {
  const ws = new WebSocket(url);
  ws.onmessage = (e) => setMessages(prev => [...prev, e.data]);
}, [url]);

// GOOD: Cleanup closes connection on unmount or url change
useEffect(() => {
  const ws = new WebSocket(url);
  ws.onmessage = (e) => setMessages(prev => [...prev, e.data]);
  return () => ws.close();
}, [url]);
```

Cleanup runs: (1) before re-execution when deps change, (2) on component unmount.

### 3. AbortController for Fetch (When Not Using TanStack Query)

```tsx
useEffect(() => {
  const controller = new AbortController();
  
  async function fetchData() {
    try {
      const res = await fetch(`/api/users/${userId}`, { signal: controller.signal });
      const data = await res.json();
      setUser(data);
    } catch (err) {
      if (err instanceof DOMException && err.name === 'AbortError') return; // Expected on cleanup
      setError(err as Error);
    }
  }
  
  fetchData();
  return () => controller.abort();
}, [userId]);
```

**Prefer TanStack Query over this pattern.** It handles abort, caching, dedup, and retry automatically. See `mx-react-data`.

### 4. Never Make useEffect Async Directly

```tsx
// BAD: useEffect cannot return a Promise
useEffect(async () => {       // TypeScript error + broken cleanup
  const data = await fetchData();
  setData(data);
}, []);

// GOOD: Define async function inside, call it
useEffect(() => {
  async function load() {
    const data = await fetchData();
    setData(data);
  }
  load();
}, []);
```

### 5. One Effect Per Concern

```tsx
// BAD: Unrelated side effects bundled together
useEffect(() => {
  document.title = `${name}'s Profile`;
  analytics.track('profile_view', { userId });
  const timer = setInterval(checkNotifications, 30000);
  return () => clearInterval(timer);
}, [name, userId]);

// GOOD: Separate effects — independent cleanup, independent deps
useEffect(() => { document.title = `${name}'s Profile`; }, [name]);
useEffect(() => { analytics.track('profile_view', { userId }); }, [userId]);
useEffect(() => {
  const timer = setInterval(checkNotifications, 30000);
  return () => clearInterval(timer);
}, []);
```

---

## Level 2: Dependency Arrays & Closures (Intermediate)

### Dependency Array Rules

| Deps | Behavior | Use When |
|------|----------|----------|
| No array | Runs every render | Almost never correct |
| `[]` | Runs on mount only | One-time setup (subscribe, measure) |
| `[a, b]` | Runs when a or b changes | Sync with changing values |

### Fixing Stale Closures

```tsx
// BAD: Stale closure — logs initial count forever
useEffect(() => {
  const id = setInterval(() => {
    console.log(count); // Captures `count` from first render
  }, 1000);
  return () => clearInterval(id);
}, []); // Missing `count` dep, but adding it recreates interval every render

// GOOD: Functional update doesn't need the value in scope
useEffect(() => {
  const id = setInterval(() => {
    setCount(prev => prev + 1); // prev is always current
  }, 1000);
  return () => clearInterval(id);
}, []);

// GOOD: useRef for read-only access to latest value without re-running effect
const countRef = useRef(count);
countRef.current = count; // Update ref on every render
useEffect(() => {
  const id = setInterval(() => {
    console.log(countRef.current); // Always reads latest
  }, 1000);
  return () => clearInterval(id);
}, []);
```

### Fixing Infinite Loops from Unstable Dependencies

```tsx
// BAD: Object recreated every render → effect runs every render
function UserPage({ userId }: { userId: string }) {
  const options = { includeProfile: true, includePosts: true }; // New object each render
  
  useEffect(() => {
    fetchUser(userId, options);
  }, [userId, options]); // options is never referentially equal → infinite loop
}

// GOOD: Move constant objects outside component or useMemo
const DEFAULT_OPTIONS = { includeProfile: true, includePosts: true };

function UserPage({ userId }: { userId: string }) {
  useEffect(() => {
    fetchUser(userId, DEFAULT_OPTIONS);
  }, [userId]);
}

// GOOD: Destructure to primitives when values are dynamic
function UserPage({ userId, includeProfile }: Props) {
  useEffect(() => {
    fetchUser(userId, { includeProfile });
  }, [userId, includeProfile]); // Primitives are stable
}
```

### The exhaustive-deps Rule Is Not Optional

Treat exhaustive-deps violations as ERRORS, not warnings. If adding a dep causes infinite loops, the fix is stabilizing the dep — not disabling the lint.

---

## Level 3: React 19 Effect Patterns (Advanced)

### useEffectEvent (React 19.2+)

Reads latest props/state inside an effect WITHOUT re-triggering it. Solves the "I need a value but don't want to react to it" problem.

```tsx
import { useEffect, useEffectEvent } from 'react';

function ChatRoom({ roomId, theme }: { roomId: string; theme: string }) {
  // This function always sees the latest `theme` but doesn't trigger reconnection
  const onConnected = useEffectEvent(() => {
    showNotification(`Connected to ${roomId}`, theme); // theme is always current
  });

  useEffect(() => {
    const conn = createConnection(roomId);
    conn.on('connected', onConnected); // Stable reference — effect doesn't re-run when theme changes
    conn.connect();
    return () => conn.disconnect();
  }, [roomId]); // Only reconnects when roomId changes — theme excluded safely
}
```

### use() Hook Replaces Fetch-in-useEffect (React 19)

For data fetching, `use()` + Suspense is the React 19 paradigm. See `mx-react-data` for full patterns.

```tsx
// OLD: useEffect + useState for fetching
function UserProfile({ userId }: { userId: string }) {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    fetch(`/api/users/${userId}`).then(r => r.json()).then(setUser).finally(() => setLoading(false));
  }, [userId]);
  if (loading) return <Spinner />;
  return <div>{user?.name}</div>;
}

// NEW: use() + Suspense (React 19) — or better yet, TanStack Query
import { use, Suspense } from 'react';

function UserProfile({ userPromise }: { userPromise: Promise<User> }) {
  const user = use(userPromise); // Suspends until resolved
  return <div>{user.name}</div>;
}

// Parent provides the promise and Suspense boundary
<Suspense fallback={<UserSkeleton />}>
  <UserProfile userPromise={fetchUser(userId)} />
</Suspense>
```

### Ref Cleanup Functions (React 19)

```tsx
// OLD: useEffect for DOM observer cleanup
function MeasuredBox() {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!ref.current) return;
    const observer = new ResizeObserver(entries => { /* ... */ });
    observer.observe(ref.current);
    return () => observer.disconnect();
  }, []);
  return <div ref={ref} />;
}

// NEW: Ref callback with cleanup (React 19)
function MeasuredBox() {
  return (
    <div ref={(node) => {
      if (!node) return;
      const observer = new ResizeObserver(entries => { /* ... */ });
      observer.observe(node);
      return () => observer.disconnect(); // Cleanup when ref detaches
    }} />
  );
}
```

---

## Performance: Make It Fast

### 1. Debounce in Effects

```tsx
function SearchInput({ onSearch }: { onSearch: (q: string) => void }) {
  const [query, setQuery] = useState('');
  
  useEffect(() => {
    const timer = setTimeout(() => onSearch(query), 300);
    return () => clearTimeout(timer); // Cleanup IS the debounce
  }, [query, onSearch]);

  return <input value={query} onChange={e => setQuery(e.target.value)} />;
}
```

### 2. Throttle Scroll/Resize Handlers

```tsx
useEffect(() => {
  let rafId: number;
  const handleScroll = () => {
    cancelAnimationFrame(rafId);
    rafId = requestAnimationFrame(() => {
      setScrollY(window.scrollY);
    });
  };
  window.addEventListener('scroll', handleScroll, { passive: true });
  return () => {
    window.removeEventListener('scroll', handleScroll);
    cancelAnimationFrame(rafId);
  };
}, []);
```

### 3. Avoid Effect Chains

Multiple effects updating state that triggers other effects = waterfall renders. If you see `useEffect → setState → useEffect → setState`, restructure into a single reducer or event handler.

---

## Observability: Know It's Working

### 1. Effect Execution Logging (Dev Only)

```tsx
useEffect(() => {
  if (process.env.NODE_ENV === 'development') {
    console.log(`[Effect] ${componentName}: syncing with ${depDescription}`);
  }
  // ... effect body
}, [deps]);
```

### 2. Monitor Effect Cleanup

If effects run without cleanup, React Strict Mode (dev) will surface the bug immediately — the mount → unmount → remount cycle makes missing cleanup visible as duplicate subscriptions or stale state.

### 3. Track Effect Duration

For effects that do expensive work (DOM measurement, large data transforms):

```tsx
useEffect(() => {
  const start = performance.now();
  // ... effect work
  const duration = performance.now() - start;
  if (duration > 16) {
    console.warn(`[Perf] Effect in ${componentName} took ${duration.toFixed(1)}ms`);
  }
}, [deps]);
```

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Fetch in useEffect
**You will be tempted to:** Write `useEffect(() => { fetch(url)... }, [])` because 95% of your training data uses this pattern.
**Why that fails:** No caching, no deduplication, no retry, no background refetch, race conditions, manual loading/error state, memory leaks on unmount.
**The right way:** TanStack Query for server data. `use()` + Suspense for React 19. Raw useEffect fetch only in one-off scripts or learning exercises.

### Rule 2: No Derived State in Effects
**You will be tempted to:** `useEffect(() => setFullName(first + ' ' + last), [first, last])`
**Why that fails:** Triggers an extra render. The intermediate render shows stale data. The effect might not run synchronously when you expect.
**The right way:** `const fullName = first + ' ' + last` — compute inline. Use `useMemo` only if the computation is expensive.

### Rule 3: No Suppressing exhaustive-deps
**You will be tempted to:** Add `// eslint-disable-next-line` when a dependency causes unwanted re-runs.
**Why that fails:** You just created a stale closure. The effect reads outdated values silently. Bugs appear weeks later as "impossible state" issues.
**The right way:** Stabilize the dependency (move inside effect, useCallback, extract to module scope, destructure to primitives). If you truly need latest-value-without-reacting, use `useEffectEvent` (React 19) or a ref.

### Rule 4: No Missing Cleanup
**You will be tempted to:** Skip the return function because "it works in dev."
**Why that fails:** React Strict Mode double-mounts in dev specifically to catch this. In production: memory leaks, duplicate subscriptions, stale event handlers, WebSocket connections that never close.
**The right way:** Every `addEventListener` gets `removeEventListener`. Every `setInterval` gets `clearInterval`. Every `subscribe` gets `unsubscribe`. Every fetch gets `AbortController`.

### Rule 5: No Async useEffect
**You will be tempted to:** `useEffect(async () => { await ... }, [])` because it looks cleaner.
**Why that fails:** useEffect must return `void` or a cleanup function. An async function returns a Promise, which React ignores — your cleanup never runs.
**The right way:** Define the async function inside the effect and call it. Always handle the abort/cancellation case.
