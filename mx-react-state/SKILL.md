---
name: mx-react-state
description: React state management — useState, useReducer, Zustand stores, Jotai atoms, derived state, state shape normalization, selectors, stale closures, automatic batching, persist middleware, client state architecture
---

# React State — State Management for AI Coding Agents

**Load this skill when choosing a state management approach, designing store architecture, fixing re-render issues caused by state, or managing client-side application state.**

## When to also load
- `mx-react-core` — component boundaries affect where state lives
- `mx-react-data` — server state (TanStack Query) is SEPARATE from client state
- `mx-react-effects` — useEffect interacts with state (stale closures, sync patterns)
- `mx-react-perf` — re-render optimization via selectors and state shape

---

## Level 1: Patterns That Always Work (Beginner)

### 1. useState for Local UI State Only

If state is only used by one component (or its direct children), keep it local.

```tsx
// GOOD: Toggle is local to this component
function Dropdown({ items }: { items: string[] }) {
  const [isOpen, setIsOpen] = useState(false);
  return (
    <div>
      <button onClick={() => setIsOpen(!isOpen)}>Toggle</button>
      {isOpen && <ul>{items.map(i => <li key={i}>{i}</li>)}</ul>}
    </div>
  );
}
```

### 2. Functional Updates to Avoid Stale Closures

When new state depends on previous state, always use the callback form.

```tsx
// BAD: Stale closure — count captured at creation time
function Counter() {
  const [count, setCount] = useState(0);
  const increment = () => {
    setCount(count + 1); // If called twice rapidly, both read same stale `count`
    setCount(count + 1); // Result: count + 1, not count + 2
  };
}

// GOOD: Functional update always reads latest state
function Counter() {
  const [count, setCount] = useState(0);
  const increment = () => {
    setCount(prev => prev + 1);
    setCount(prev => prev + 1); // Result: count + 2
  };
}
```

### 3. Never Mutate State

React uses referential equality. Mutations don't trigger re-renders.

```tsx
// BAD: Mutating array in place
const addItem = (item: Item) => {
  items.push(item);       // Mutates existing array
  setItems(items);         // Same reference — React skips re-render
};

// GOOD: Create new reference
const addItem = (item: Item) => {
  setItems(prev => [...prev, item]);
};

// GOOD: Object spread for updates
const updateUser = (field: string, value: string) => {
  setUser(prev => ({ ...prev, [field]: value }));
};
```

### 4. useReducer for Complex Related State

When state has multiple sub-values that change together, useReducer prevents impossible states.

```tsx
// BAD: Multiple useState with contradictory states possible
const [isLoading, setIsLoading] = useState(false);
const [error, setError] = useState<Error | null>(null);
const [data, setData] = useState<Data | null>(null);
// Bug: isLoading=true AND error!=null simultaneously

// GOOD: useReducer enforces valid state transitions
type State = 
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'success'; data: Data }
  | { status: 'error'; error: Error };

type Action =
  | { type: 'FETCH' }
  | { type: 'SUCCESS'; data: Data }
  | { type: 'ERROR'; error: Error };

function reducer(state: State, action: Action): State {
  switch (action.type) {
    case 'FETCH': return { status: 'loading' };
    case 'SUCCESS': return { status: 'success', data: action.data };
    case 'ERROR': return { status: 'error', error: action.error };
  }
}
```

### 5. Don't Store What You Can Compute

Same rule as `mx-react-core` — applies doubly to stores.

```tsx
// BAD: Storing derived totals in state
const [items, setItems] = useState<CartItem[]>([]);
const [total, setTotal] = useState(0);
useEffect(() => { setTotal(items.reduce((sum, i) => sum + i.price, 0)); }, [items]);

// GOOD: Compute inline
const total = items.reduce((sum, i) => sum + i.price, 0);
```

---

## Level 2: Store Architecture (Intermediate)

### State Management Decision Tree

| Need | Solution | When |
|------|----------|------|
| Local UI state (toggle, input) | `useState` | State used by 1 component |
| Complex local state | `useReducer` | Multiple related values, state machine |
| Low-frequency global (theme, locale) | React Context | Changes rarely, small number of consumers |
| Shared application state | **Zustand** | Default choice for most apps (~3KB) |
| Atomic/granular interdependent state | Jotai | Spreadsheet-like, many fine-grained atoms |
| Enterprise with audit requirements | Redux Toolkit | Large team, time-travel debugging mandatory |
| Server/async data | TanStack Query | See `mx-react-data` — NEVER mix with above |

### Zustand: Separate Actions from State

Actions nested in a stable object never cause subscriber re-renders.

```tsx
import { create } from 'zustand';

interface AuthState {
  user: User | null;
  isAuthenticated: boolean;
}

interface AuthActions {
  actions: {
    login: (user: User) => void;
    logout: () => void;
  };
}

export const useAuthStore = create<AuthState & AuthActions>((set) => ({
  user: null,
  isAuthenticated: false,
  actions: {
    login: (user) => set({ user, isAuthenticated: true }),
    logout: () => set({ user: null, isAuthenticated: false }),
  },
}));

// Atomic hooks — consumers subscribe to ONLY what they need
export const useUser = () => useAuthStore((s) => s.user);
export const useIsAuth = () => useAuthStore((s) => s.isAuthenticated);
export const useAuthActions = () => useAuthStore((s) => s.actions);
```

### Zustand Selectors: Primitives or useShallow

```tsx
// BAD: New object every render — infinite re-render risk
const { user, theme } = useStore((s) => ({ user: s.user, theme: s.theme }));

// GOOD: Atomic selectors — subscribe to primitives independently
const user = useStore((s) => s.user);
const theme = useStore((s) => s.theme);

// GOOD: useShallow for grouped values (shallow equality comparison)
import { useShallow } from 'zustand/react/shallow';
const { user, theme } = useStore(useShallow((s) => ({ user: s.user, theme: s.theme })));
```

### Zustand Persist with Schema Migration

```tsx
import { persist, createJSONStorage } from 'zustand/middleware';

export const useCartStore = create<CartStore>()(
  persist(
    (set) => ({
      items: [],
      discountCode: null,
      actions: { /* ... */ },
    }),
    {
      name: 'cart-storage',
      version: 2,
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({ items: state.items, discountCode: state.discountCode }),
      migrate: (persisted: any, version: number) => {
        if (version < 2) {
          return { ...persisted, discountCode: null }; // Added in v2
        }
        return persisted as CartStore;
      },
    }
  )
);
```

### State Shape: Normalize Like a Database

```tsx
// BAD: Nested objects with duplicated data
interface BadState {
  posts: Array<{ id: string; author: { id: string; name: string }; title: string }>;
}
// Updating author name requires finding every post by that author

// GOOD: Normalized — IDs as keys, no duplication
interface GoodState {
  users: Record<string, User>;
  posts: Record<string, Post>;       // Post has authorId, not nested author
  postIds: string[];                  // Ordering is a separate concern
}
```

---

## Level 3: Advanced Patterns (Advanced)

### Server State vs Client State — The Two-Layer Architecture

Never mix server-fetched data with client UI state in the same store. See `mx-react-data` for the full pattern.

```tsx
// BAD: Copying TanStack Query data into Zustand
const { data: products } = useQuery({ queryKey: ['products'] });
useEffect(() => { useStore.setState({ products }); }, [products]);
// You just opted out of background refetching, stale-while-revalidate, and cache invalidation

// GOOD: Two layers
// Layer 1: TanStack Query owns server data (products, users, orders)
const { data: products } = useQuery({ queryKey: ['products'], queryFn: fetchProducts });
// Layer 2: Zustand owns client state (filters, cart, UI toggles)
const filters = useFilterStore((s) => s.filters);
const filtered = products?.filter(p => matchesFilters(p, filters));
```

### Zustand Middleware Composition

```tsx
import { devtools, persist } from 'zustand/middleware';
import { immer } from 'zustand/middleware/immer';

const useStore = create<State>()(
  devtools(
    persist(
      immer((set) => ({
        items: [],
        actions: {
          addItem: (item: Item) => set((draft) => {
            draft.items.push(item); // Immer allows "mutations" on draft
          }),
        },
      })),
      { name: 'store', partialize: (s) => ({ items: s.items }) }
    ),
    { name: 'MyApp', enabled: process.env.NODE_ENV === 'development' }
  )
);
```

### Testing Zustand Stores

```tsx
import { beforeEach, describe, expect, it } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useCartStore } from './cartStore';

// CRITICAL: Reset store between tests
beforeEach(() => {
  useCartStore.setState(useCartStore.getInitialState());
});

it('adds item to cart', () => {
  const { result } = renderHook(() => useCartStore());
  act(() => { result.current.actions.addItem({ id: '1', price: 10 }); });
  expect(result.current.items).toHaveLength(1);
});
```

---

## Performance: Make It Fast

### 1. Select Primitives, Not Objects
Each Zustand selector should return a primitive or use `useShallow`. Object selectors create new references every render → unnecessary re-renders.

### 2. Actions Are Stable References
The `actions` object pattern means components subscribing to actions NEVER re-render when data state changes.

### 3. Automatic Batching (React 18+)
Multiple `setState` calls in the same synchronous block are batched into one re-render. No manual optimization needed. Use `flushSync` ONLY when you need synchronous DOM reads between state updates (extremely rare).

### 4. Small Focused Stores
One store per domain (auth, cart, ui). A monolithic store means every state change notifies every subscriber — even with selectors, the selector function still runs.

---

## Observability: Know It's Working

### 1. Redux DevTools via Zustand

```tsx
import { devtools } from 'zustand/middleware';

const useStore = create<State>()(
  devtools((set) => ({ /* ... */ }), {
    name: 'AuthStore',
    enabled: process.env.NODE_ENV === 'development',
  })
);
```

Time-travel debugging, action logging, and state diffing — all free via the Redux DevTools browser extension.

### 2. Re-render Profiling

Use React DevTools Profiler: Record → interact → analyze flame graph. Enable "Record why each component rendered" in settings. Look for components re-rendering when their visible output hasn't changed.

### 3. Production Monitoring

Track re-render frequency of critical components via the `<Profiler>` API (see `mx-react-core`). Alert when `actualDuration` exceeds frame budget (16ms).

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Don't Default to Redux
**You will be tempted to:** Import Redux Toolkit because your training data is Redux-heavy.
**Why that fails:** RTK adds ~15KB, mandatory Provider wrapper, action/reducer boilerplate. Zustand does the same job at ~3KB with zero boilerplate for 95% of apps.
**The right way:** Zustand for most apps. RTK only when enterprise team mandates time-travel debugging or event-sourced architecture.

### Rule 2: Don't Put Everything in Global State
**You will be tempted to:** Create a global store with `isModalOpen`, `selectedTab`, `searchQuery`, `formData` — all mixed together.
**Why that fails:** Every state change re-runs every selector. Local state changes become global re-render events. Testing requires mocking the entire store.
**The right way:** Local `useState` for component UI state. Zustand only for genuinely shared state (auth, cart, notifications).

### Rule 3: Never Copy Server Data into Client State
**You will be tempted to:** `useEffect(() => setProducts(queryData), [queryData])` to "make it available" in Zustand.
**Why that fails:** You just broke background refetching, stale-while-revalidate, cache invalidation, and optimistic updates. The copy immediately goes stale.
**The right way:** TanStack Query owns server data. Zustand owns client state. They're separate layers. See `mx-react-data`.

### Rule 4: Don't Create Monolithic Stores
**You will be tempted to:** Put auth, cart, UI, preferences, and notifications in one giant `useAppStore`.
**Why that fails:** Every subscriber evaluates selectors on every change. Testing requires full store setup. Code splitting is impossible.
**The right way:** One store per domain: `useAuthStore`, `useCartStore`, `useUIStore`. Each < 50 lines of state.

### Rule 5: Don't Suppress exhaustive-deps for State
**You will be tempted to:** `// eslint-disable-next-line react-hooks/exhaustive-deps` when a state dependency causes infinite loops.
**Why that fails:** The infinite loop IS the bug. Suppressing the lint hides a stale closure or unstable reference that will cause subtle, hard-to-debug data inconsistencies.
**The right way:** Stabilize the dependency (useCallback, move inside effect, extract to useRef). See `mx-react-effects`.
