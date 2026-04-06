---
name: mx-react-core
description: React component architecture, JSX, props, composition patterns (compound components, children slots, render props), ref as prop (React 19), React Compiler automatic memoization, component boundaries, error boundaries, single responsibility
---

# React Core — Component Architecture for AI Coding Agents

**Load this skill when writing React components, designing component APIs, structuring component hierarchies, or making composition decisions.**

## When to also load
- `mx-react-state` — when component needs state management beyond local useState
- `mx-react-effects` — when component interacts with external systems (DOM, timers, subscriptions)
- `mx-react-perf` — when optimizing render performance or bundle size
- `mx-react-testing` — when writing component tests

---

## Level 1: Patterns That Always Work (Beginner)

### 1. Single Responsibility Components

Every component does ONE thing. If you're scrolling past 150 lines, split it.

```tsx
// BAD: God component
function UserDashboard({ userId }: { userId: string }) {
  const [user, setUser] = useState(null);
  const [posts, setPosts] = useState([]);
  const [notifications, setNotifications] = useState([]);
  // ... 200 lines of mixed fetching, rendering, event handling
  return (
    <div>
      {/* header, sidebar, posts, notifications, settings all inline */}
    </div>
  );
}

// GOOD: Composed from focused components
function UserDashboard({ userId }: { userId: string }) {
  return (
    <DashboardLayout>
      <UserHeader userId={userId} />
      <PostFeed userId={userId} />
      <NotificationPanel userId={userId} />
    </DashboardLayout>
  );
}
```

### 2. React 19: ref Is a Prop — No forwardRef

`forwardRef` is deprecated in React 19. Pass `ref` directly as a prop.

```tsx
// BAD: Legacy forwardRef wrapper (React 18 and earlier)
const Input = forwardRef<HTMLInputElement, InputProps>((props, ref) => (
  <input ref={ref} {...props} />
));

// GOOD: React 19 — ref is just a prop
function Input({ ref, ...props }: InputProps & { ref?: React.Ref<HTMLInputElement> }) {
  return <input ref={ref} {...props} />;
}
```

Ref cleanup functions (React 19): return a cleanup from ref callbacks to avoid useEffect for DOM measurement/teardown.

```tsx
function MeasuredDiv({ onResize }: { onResize: (rect: DOMRect) => void }) {
  return (
    <div ref={(node) => {
      if (!node) return;
      const observer = new ResizeObserver(() => onResize(node.getBoundingClientRect()));
      observer.observe(node);
      return () => observer.disconnect(); // cleanup — React 19 only
    }} />
  );
}
```

### 3. Stable Keys for Dynamic Lists

Never use array index as key for lists that reorder, filter, or mutate.

```tsx
// BAD: Index as key — breaks reconciliation on reorder
{items.map((item, i) => <ListItem key={i} item={item} />)}

// GOOD: Stable unique identifier
{items.map((item) => <ListItem key={item.id} item={item} />)}
```

### 4. Derive, Don't Synchronize

If a value can be computed from props or state, compute it inline. Never useEffect + setState for derived values.

```tsx
// BAD: useEffect to sync derived state
const [firstName, setFirstName] = useState('');
const [lastName, setLastName] = useState('');
const [fullName, setFullName] = useState('');
useEffect(() => {
  setFullName(`${firstName} ${lastName}`);
}, [firstName, lastName]);

// GOOD: Compute inline
const fullName = `${firstName} ${lastName}`;
```

### 5. Props: Pass What's Needed, Not Everything

Avoid spreading entire objects. Pass only what the child uses.

```tsx
// BAD: Passes entire user object when only name is needed
<UserAvatar user={user} />

// GOOD: Pass specific props
<UserAvatar name={user.name} avatarUrl={user.avatarUrl} />
```

---

## Level 2: Composition Patterns (Intermediate)

### Composition Decision Tree

| Need | Pattern | Example |
|------|---------|---------|
| Layout wrapper, no state sharing | `children` prop | `<Card>{content}</Card>` |
| Named layout slots | Named JSX props | `<Page header={<Nav />} sidebar={<Menu />}>` |
| Multi-part widget with shared state | Compound Components | `<Select><Select.Trigger /><Select.List />` |
| Reusable stateful logic, no UI | Custom Hook | `useDebounce()`, `useAuth()` |
| Behavior injection with custom rendering | Render Props | `<Virtualized>{(item) => <Row />}</Virtualized>` |
| Cross-cutting concern wrapping | HOC (rare — prefer hooks) | `withErrorBoundary(Component)` |

**Priority order:** children > compound > custom hooks > render props > HOCs

### Compound Components with Context

Use for multi-part UI widgets (Tabs, Accordions, Selects, Menus) where children share implicit state.

```tsx
// 1. Typed context
interface TabsContextType {
  activeTab: string;
  setActiveTab: (id: string) => void;
}
const TabsContext = createContext<TabsContextType | null>(null);

function useTabsContext() {
  const ctx = useContext(TabsContext);
  if (!ctx) throw new Error('Tab components must be used within <Tabs>');
  return ctx;
}

// 2. Parent manages state
function Tabs({ children, defaultTab }: { children: ReactNode; defaultTab: string }) {
  const [activeTab, setActiveTab] = useState(defaultTab);
  return (
    <TabsContext.Provider value={{ activeTab, setActiveTab }}>
      <div role="tablist">{children}</div>
    </TabsContext.Provider>
  );
}

// 3. Children consume context
Tabs.Tab = function Tab({ id, children }: { id: string; children: ReactNode }) {
  const { activeTab, setActiveTab } = useTabsContext();
  return (
    <button role="tab" aria-selected={activeTab === id} onClick={() => setActiveTab(id)}>
      {children}
    </button>
  );
};

Tabs.Panel = function Panel({ id, children }: { id: string; children: ReactNode }) {
  const { activeTab } = useTabsContext();
  if (activeTab !== id) return null;
  return <div role="tabpanel">{children}</div>;
};

// Consumer controls layout
<Tabs defaultTab="profile">
  <Tabs.Tab id="profile">Profile</Tabs.Tab>
  <Tabs.Tab id="settings">Settings</Tabs.Tab>
  <Tabs.Panel id="profile"><ProfileForm /></Tabs.Panel>
  <Tabs.Panel id="settings"><SettingsForm /></Tabs.Panel>
</Tabs>
```

### Error Boundaries: Strategic Placement

Place error boundaries per route section, not one global boundary.

```tsx
// BAD: Single global boundary — entire app crashes on any error
<ErrorBoundary fallback={<CrashPage />}>
  <App />
</ErrorBoundary>

// GOOD: Granular boundaries — failures are isolated
<Layout>
  <ErrorBoundary fallback={<HeaderError />}>
    <Header />
  </ErrorBoundary>
  <ErrorBoundary fallback={<ContentError />}>
    <MainContent />
  </ErrorBoundary>
  <ErrorBoundary fallback={<SidebarError />}>
    <Sidebar />
  </ErrorBoundary>
</Layout>
```

Use `react-error-boundary` for functional component support + `onError` reporting to Sentry/monitoring.

---

## Level 3: Architecture at Scale (Advanced)

### React Compiler Compatibility

The React Compiler (stable 2025) auto-memoizes at build time. Your code must follow the Rules of React:

| Rule | What It Means | Violation Example |
|------|--------------|-------------------|
| Components are idempotent | Same props → same output | Reading `Date.now()` in render |
| Props and state are immutable | Never mutate, always replace | `state.items.push(newItem)` |
| Side effects outside render | No fetch/DOM mutation in render body | `document.title = name` at top level |
| No hook call order changes | Hooks always called in same order | `if (cond) { useState() }` |

When the compiler can't prove a component follows these rules, it skips optimization for that component. The ESLint plugin (`eslint-plugin-react-compiler`) reports violations.

### Component API Design Principles

1. **Prefer composition over configuration.** A `<Card>` with 15 boolean props is worse than `<Card><Card.Header /><Card.Body />`.
2. **Use TypeScript discriminated unions** for components with mutually exclusive modes:

```tsx
type ButtonProps =
  | { variant: 'link'; href: string; onClick?: never }
  | { variant: 'button'; onClick: () => void; href?: never };
```

3. **asChild pattern** (Radix UI) for zero-wrapper-element composition:

```tsx
// Consumer chooses the rendered element
<Tooltip.Trigger asChild>
  <a href="/help">Help</a>
</Tooltip.Trigger>
```

### Colocation Principle

Keep logic close to where it's used. Extract to shared modules only when genuinely reused.

| What | Colocate With | Extract When |
|------|--------------|-------------|
| Component styles | Same file or CSS module | Design system tokens |
| Types/interfaces | Same file | Used by 3+ components |
| Helper functions | Same file | Truly generic utility |
| Test files | `__tests__/` adjacent | Never extract tests far |

---

## Performance: Make It Fast

### 1. Let the Compiler Work

Remove manual `useMemo`, `useCallback`, and `React.memo` unless profiling proves the compiler missed a case. Manual memoization adds complexity and can conflict with compiler optimizations.

### 2. Component Splitting for Render Isolation

When one part of the UI updates frequently, isolate it so the rest doesn't re-render:

```tsx
// BAD: Entire form re-renders when clock ticks
function Dashboard() {
  const [time, setTime] = useState(new Date());
  useEffect(() => { const id = setInterval(() => setTime(new Date()), 1000); return () => clearInterval(id); }, []);
  return (
    <div>
      <Clock time={time} />
      <ExpensiveChart />  {/* re-renders every second! */}
    </div>
  );
}

// GOOD: Clock owns its own state — ExpensiveChart never re-renders
function Dashboard() {
  return (
    <div>
      <LiveClock />
      <ExpensiveChart />
    </div>
  );
}

function LiveClock() {
  const [time, setTime] = useState(new Date());
  useEffect(() => { const id = setInterval(() => setTime(new Date()), 1000); return () => clearInterval(id); }, []);
  return <Clock time={time} />;
}
```

### 3. Lazy Load Heavy Subtrees

```tsx
const AdminPanel = lazy(() => import('./AdminPanel'));

function App() {
  return (
    <Suspense fallback={<AdminSkeleton />}>
      {isAdmin && <AdminPanel />}
    </Suspense>
  );
}
```

---

## Observability: Know It's Working

### 1. Error Boundary Reporting

```tsx
import { ErrorBoundary } from 'react-error-boundary';
import * as Sentry from '@sentry/react';

<ErrorBoundary
  fallback={<ErrorFallback />}
  onError={(error, info) => {
    Sentry.captureException(error, { extra: { componentStack: info.componentStack } });
  }}
>
  <App />
</ErrorBoundary>
```

### 2. React Profiler in Production

```tsx
<Profiler id="MainFeed" onRender={(id, phase, actualDuration) => {
  if (actualDuration > 16) { // > 1 frame at 60fps
    metrics.send('slow_render', { component: id, phase, duration: actualDuration });
  }
}}>
  <MainFeed />
</Profiler>
```

### 3. Core Web Vitals Monitoring

Track the three metrics that matter: **LCP** (< 2.5s), **INP** (< 200ms), **CLS** (< 0.1). Use `web-vitals` library or RUM tools (Sentry, Datadog, LogRocket).

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No forwardRef in React 19
**You will be tempted to:** Wrap components in `forwardRef()` because your training data is 95% pre-React-19.
**Why that fails:** `forwardRef` is deprecated. It adds an unnecessary HOC wrapper, breaks the simple mental model, and confuses TypeScript inference.
**The right way:** Accept `ref` as a regular prop: `function Input({ ref, ...props }: Props & { ref?: Ref<HTMLInputElement> })`

### Rule 2: No Manual Memoization by Default
**You will be tempted to:** Wrap every callback in `useCallback` and every computed value in `useMemo`.
**Why that fails:** The React Compiler handles this automatically with higher precision. Manual memoization adds code complexity, can create stale closure bugs, and may conflict with compiler output.
**The right way:** Write clean code. Profile with React DevTools. Add manual memoization ONLY for specific measured bottlenecks or external library interop.

### Rule 3: No God Components
**You will be tempted to:** Generate one 300-line component that handles fetching, state, rendering, and event handling all together.
**Why that fails:** Untestable, unreviewable, impossible to reuse parts independently. Every state change re-renders everything.
**The right way:** Split: container (data) + presentational (UI). Or custom hook (logic) + component (rendering). Max ~150 lines per component file.

### Rule 4: No Config Object APIs When Composition Works
**You will be tempted to:** Build `<DataTable columns={[...]} sortable filterable paginated headerRenderer={...} />` with 20 props.
**Why that fails:** Every new feature adds a prop. Consumer can't customize structure. TypeScript types become unreadable. Testing requires massive prop objects.
**The right way:** Compound pattern: `<Table><Table.Header sortable /><Table.Body><Table.Row /></Table.Body><Table.Pagination /></Table>`

### Rule 5: No Prop Drilling Past 2 Levels
**You will be tempted to:** Pass `theme`, `user`, `locale` through 5 levels of components.
**Why that fails:** Every intermediate component must know about props it doesn't use. Adding a prop means editing every component in the chain.
**The right way:** Context for truly global values (theme, auth, locale). Zustand for shared application state. See `mx-react-state`.
