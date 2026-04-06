---
name: mx-react-perf
description: React performance optimization — React Compiler automatic memoization, useMemo, useCallback, React.memo, useTransition, useDeferredValue, code splitting, React.lazy, Suspense, TanStack Virtual, virtualization, bundle analysis, Core Web Vitals INP LCP CLS, React Profiler API, production monitoring
---

# React Performance — Optimization & Measurement for AI Coding Agents

**Load this skill when optimizing render performance, reducing bundle size, virtualizing lists, measuring Core Web Vitals, or deciding whether to memoize.**

## When to also load
- `mx-react-core` — component splitting for render isolation, React Compiler rules
- `mx-react-data` — prefetching, staleTime, structural sharing
- `mx-react-state` — selector optimization, store architecture affects re-renders
- `mx-react-routing` — route-level code splitting, lazy loading

---

## Level 1: Patterns That Always Work (Beginner)

### 1. Measure First, Optimize Never... Until You Measure

The #1 performance anti-pattern is optimizing without profiling. React is fast by default. Most "slow" components are fine.

**Profiling workflow:**
1. Open React DevTools → Profiler tab
2. Enable "Record why each component rendered"
3. Record → interact → stop
4. Read the flame graph: red = slow, gray = didn't render
5. Optimize ONLY what the flame graph identifies as slow

### 2. The React Compiler Handles Memoization

React Compiler (stable 2025) auto-memoizes at build time. It analyzes data flow and inserts the equivalent of `useMemo`/`useCallback`/`React.memo` automatically.

```tsx
// BAD: Manual memoization clutter (pre-2025 pattern)
const MemoizedList = React.memo(({ items, onSelect }: ListProps) => {
  return <ul>{items.map(i => <li key={i.id} onClick={() => onSelect(i.id)}>{i.name}</li>)}</ul>;
});

function App({ rawData }: { rawData: Item[] }) {
  const [filter, setFilter] = useState('');
  const filtered = useMemo(() => rawData.filter(i => i.name.includes(filter)), [rawData, filter]);
  const handleSelect = useCallback((id: string) => { console.log(id); }, []);

  return <MemoizedList items={filtered} onSelect={handleSelect} />;
}

// GOOD: Clean code — compiler optimizes automatically
function ItemList({ items, onSelect }: ListProps) {
  return <ul>{items.map(i => <li key={i.id} onClick={() => onSelect(i.id)}>{i.name}</li>)}</ul>;
}

function App({ rawData }: { rawData: Item[] }) {
  const [filter, setFilter] = useState('');
  const filtered = rawData.filter(i => i.name.includes(filter));
  const handleSelect = (id: string) => { console.log(id); };

  return <ItemList items={filtered} onSelect={handleSelect} />;
}
```

### When Manual Memoization IS Still Needed

| Scenario | Tool | Why |
|----------|------|-----|
| External uncompiled library prop | `useMemo`/`useCallback` | Compiler can't optimize across boundaries |
| useEffect dependency that triggers network call | `useMemo` | Need guaranteed referential stability |
| Legacy class component boundary | `React.memo` | Compiler doesn't touch class components |
| Profiler proves compiler missed a hot path | Manual memo | Escape hatch for measured bottlenecks |

### 3. Code Splitting at Route Boundaries

The highest-impact optimization. Don't ship admin panel code to regular users.

```tsx
const AdminPanel = lazy(() => import('./AdminPanel'));
const Analytics = lazy(() => import('./Analytics'));

// Skeleton fallback, not spinner
<Suspense fallback={<AdminSkeleton />}>
  <AdminPanel />
</Suspense>
```

**Don't split small components.** The HTTP request overhead exceeds bundle savings for anything under ~5KB gzipped.

---

## Level 2: Concurrency & Virtualization (Intermediate)

### useTransition — Keep UI Responsive During Heavy Work

Marks state updates as non-urgent. React keeps the current UI responsive while computing the new state in the background.

```tsx
import { useState, useTransition } from 'react';

function SearchableList({ items }: { items: Item[] }) {
  const [query, setQuery] = useState('');
  const [filtered, setFiltered] = useState(items);
  const [isPending, startTransition] = useTransition();

  const handleSearch = (value: string) => {
    setQuery(value);                          // Urgent: update input immediately
    startTransition(() => {
      setFiltered(items.filter(i => i.name.toLowerCase().includes(value.toLowerCase())));
    });                                        // Non-urgent: filter can lag
  };

  return (
    <>
      <input value={query} onChange={e => handleSearch(e.target.value)} />
      {isPending && <span>Filtering...</span>}
      <ul>{filtered.map(i => <li key={i.id}>{i.name}</li>)}</ul>
    </>
  );
}
```

### useDeferredValue — Defer Expensive Child Renders

```tsx
import { useDeferredValue } from 'react';

function Dashboard({ searchQuery }: { searchQuery: string }) {
  const deferredQuery = useDeferredValue(searchQuery);
  // Input updates instantly; chart re-renders with a slight delay
  return (
    <>
      <SearchInput value={searchQuery} />
      <ExpensiveChart query={deferredQuery} />  {/* Renders with deferred value */}
    </>
  );
}
```

| Tool | Use When |
|------|----------|
| `useTransition` | You control the state update and want to wrap it |
| `useDeferredValue` | You receive the value as a prop and want to defer its downstream effects |

### TanStack Virtual — Virtualize Long Lists

Render only visible items. 10,000 rows in the DOM = frozen browser. 10,000 rows virtualized = 20 DOM nodes.

```tsx
import { useVirtualizer } from '@tanstack/react-virtual';

function VirtualList({ items }: { items: Item[] }) {
  const parentRef = useRef<HTMLDivElement>(null);

  const virtualizer = useVirtualizer({
    count: items.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 50,   // Estimated row height in px
    overscan: 5,               // Render 5 extra items above/below viewport
  });

  return (
    <div ref={parentRef} style={{ height: '400px', overflow: 'auto' }}>
      <div style={{ height: `${virtualizer.getTotalSize()}px`, position: 'relative' }}>
        {virtualizer.getVirtualItems().map(virtualRow => (
          <div
            key={virtualRow.key}
            style={{
              position: 'absolute',
              top: 0,
              transform: `translateY(${virtualRow.start}px)`,
              height: `${virtualRow.size}px`,
              width: '100%',
            }}
          >
            {items[virtualRow.index].name}
          </div>
        ))}
      </div>
    </div>
  );
}
```

**Virtualization decision:** Use when list exceeds ~100 items or total DOM nodes exceed ~1,000. Don't virtualize short lists — the overhead isn't worth it.

---

## Level 3: Production Measurement (Advanced)

### Core Web Vitals — The Three Metrics

| Metric | Target | What It Measures | React Impact |
|--------|--------|-----------------|-------------|
| **LCP** | < 2.5s | Largest visible content painted | SSR, code splitting, image optimization |
| **INP** | < 200ms | Worst interaction responsiveness | useTransition, event handler speed, state updates |
| **CLS** | < 0.1 | Visual stability (layout shifts) | Skeleton fallbacks, image dimensions, dynamic content |

INP replaced FID in March 2024. It measures the FULL interaction lifecycle (input → processing → paint), not just input delay.

### web-vitals Library

```tsx
import { onLCP, onINP, onCLS } from 'web-vitals';

function reportWebVitals() {
  onLCP((metric) => analytics.send('web_vital', { name: 'LCP', value: metric.value }));
  onINP((metric) => analytics.send('web_vital', { name: 'INP', value: metric.value }));
  onCLS((metric) => analytics.send('web_vital', { name: 'CLS', value: metric.value }));
}
```

### React Profiler API in Production

```tsx
<Profiler id="ProductList" onRender={(id, phase, actualDuration, baseDuration) => {
  if (actualDuration > 16) { // Exceeds 60fps frame budget
    metrics.send('slow_render', {
      component: id,
      phase,                    // "mount" or "update"
      actualDuration,           // Time spent rendering this commit
      baseDuration,             // Time for full subtree without memoization
    });
  }
}}>
  <ProductList />
</Profiler>
```

### Bundle Analysis

Run in CI to catch regressions:

```bash
# Vite
npx vite-bundle-visualizer

# Webpack
npx webpack-bundle-analyzer dist/stats.json
```

Alert thresholds: total bundle < 200KB gzipped, any single route chunk < 50KB gzipped.

---

## Performance: Make It Fast

This IS the performance skill. Here are the highest-impact patterns ranked:

| Rank | Technique | Impact | Effort |
|------|-----------|--------|--------|
| 1 | Route-level code splitting | High | Low |
| 2 | TanStack Virtual for long lists | High | Medium |
| 3 | useTransition for heavy state updates | High | Low |
| 4 | Prefetch data on hover | Medium | Low |
| 5 | Skeleton UI (not spinners) | Medium (perceived) | Low |
| 6 | Image optimization (lazy, srcset, WebP) | Medium | Low |
| 7 | Component splitting for render isolation | Medium | Medium |
| 8 | Tree shaking (import specific exports) | Medium | Low |

---

## Observability: Know It's Working

### 1. Real User Monitoring (RUM)

Track Core Web Vitals from real users, not just lab tests. Tools: Sentry Performance, Datadog RUM, LogRocket, Vercel Analytics, Google CrUX.

### 2. Profiler Alerts

Send React Profiler data to your monitoring backend. Set alerts:
- Component render > 16ms (60fps miss)
- Component render > 50ms (noticeable jank)
- Component render > 100ms (user-visible delay)

### 3. Bundle Size CI Gate

Fail CI if bundle grows beyond threshold. Prevents gradual bloat.

```yaml
# Example: size-limit in CI
- name: Check bundle size
  run: npx size-limit
```

### 4. Lighthouse in CI

Run Lighthouse on every PR for performance score, accessibility score, and Core Web Vitals. Fail if performance score drops below 90.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Memoization Without Measurement
**You will be tempted to:** Wrap every component in `React.memo`, every callback in `useCallback`, every value in `useMemo`.
**Why that fails:** The React Compiler already does this automatically with higher precision. Manual memoization adds code complexity, can create stale closure bugs, and may conflict with compiler output. Meta removed thousands of manual memos when deploying the compiler.
**The right way:** Write clean code. Profile with React DevTools. Add manual memoization ONLY for specific measured bottlenecks or external library interop.

### Rule 2: No Premature Virtualization
**You will be tempted to:** Virtualize every list "just in case."
**Why that fails:** Virtualization adds complexity (fixed heights, scroll containers, keyboard navigation). For lists under 100 items, the overhead exceeds the benefit. Also breaks Cmd+F search.
**The right way:** Render normally. Profile. Virtualize when you measure > 1,000 DOM nodes or visible jank during scroll.

### Rule 3: No Optimizing Without Profiling
**You will be tempted to:** "I think this component is slow, let me optimize it."
**Why that fails:** Developer intuition about performance is wrong ~80% of the time. You'll optimize a component that renders in 2ms while missing one that takes 200ms.
**The right way:** React DevTools Profiler → flame graph → identify actual bottleneck → optimize that specific component.

### Rule 4: No Splitting Every Component
**You will be tempted to:** `lazy(() => import('./SmallButton'))` for tiny shared components.
**Why that fails:** Each lazy import creates a separate HTTP request. For small components (< 5KB), the request overhead exceeds the bundle savings. You're making the app slower, not faster.
**The right way:** Split at route boundaries and heavy feature modules (editors, admin panels, charts). Keep shared UI in the main bundle.

### Rule 5: No Ignoring INP
**You will be tempted to:** Focus only on LCP and bundle size because they're easier to measure.
**Why that fails:** INP measures how responsive your app feels during interaction. A fast-loading app that janks on every click still feels broken. INP replaced FID because real-world interaction quality matters more than first input.
**The right way:** Profile interactions with React DevTools. Use `useTransition` for heavy state updates. Keep event handlers fast. Monitor INP via web-vitals library.
