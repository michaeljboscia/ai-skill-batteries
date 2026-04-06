---
name: mx-react-testing
description: React testing — Vitest, React Testing Library, userEvent, getByRole, getByLabelText, MSW v2 network mocking, component tests, integration tests, MemoryRouter, Zustand store reset, async queries, waitFor, accessibility testing, eslint-plugin-jsx-a11y, test utilities with providers
---

# React Testing — Test Patterns for AI Coding Agents

**Load this skill when writing component tests, integration tests, setting up test utilities, mocking network requests, or testing accessibility.**

## When to also load
- `mx-react-forms` — form testing uses getByLabelText and userEvent
- `mx-react-routing` — route testing uses MemoryRouter + initialEntries
- `mx-react-data` — testing TanStack Query requires QueryClientProvider in test wrapper
- `mx-react-state` — Zustand stores must be reset between tests

---

## Level 1: Patterns That Always Work (Beginner)

### 1. Query Priority — Access the Accessibility Tree, Not the DOM

| Priority | Query | Use When |
|----------|-------|----------|
| 1 (best) | `getByRole('button', { name: /submit/i })` | Interactive elements (buttons, links, checkboxes) |
| 2 | `getByLabelText(/email/i)` | Form inputs |
| 3 | `getByText(/welcome/i)` | Non-interactive display text |
| 4 | `getByDisplayValue('current value')` | Inputs with pre-filled values |
| 5 | `getByAltText(/profile photo/i)` | Images |
| 6 (last resort) | `getByTestId('complex-widget')` | Only when no semantic query works |

**If `getByLabelText` fails, it's an accessibility bug in your component — fix the component, not the test.**

```tsx
// BAD: querySelector — tests implementation details, not behavior
const button = container.querySelector('.submit-btn');
const input = container.querySelector('[data-testid="email-input"]');

// GOOD: Accessibility-first queries
const button = screen.getByRole('button', { name: /submit/i });
const input = screen.getByLabelText(/email address/i);
```

### 2. userEvent Over fireEvent

`userEvent` simulates the full browser event chain. `fireEvent` dispatches a single synthetic event.

```tsx
import userEvent from '@testing-library/user-event';

test('submits login form', async () => {
  const user = userEvent.setup(); // Always create at test start
  render(<LoginForm onSubmit={mockSubmit} />);

  // userEvent.type fires keyDown + keyPress + keyUp per character + focus/blur
  await user.type(screen.getByLabelText(/email/i), 'test@example.com');
  await user.type(screen.getByLabelText(/password/i), 'secret123');
  await user.click(screen.getByRole('button', { name: /log in/i }));

  expect(mockSubmit).toHaveBeenCalledWith({
    email: 'test@example.com',
    password: 'secret123',
  });
});
```

### 3. Async Queries for Dynamic Content

```tsx
// BAD: Element doesn't exist yet — test fails
const message = screen.getByText(/success/i); // Throws immediately

// GOOD: waitFor + findBy for async content
const message = await screen.findByText(/success/i); // Polls until found or timeout

// GOOD: waitFor for assertions on changing state
await waitFor(() => {
  expect(screen.getByRole('status')).toHaveTextContent('Saved');
});

// GOOD: waitForElementToBeRemoved for disappearing elements
await waitForElementToBeRemoved(() => screen.queryByText(/loading/i));
```

### 4. Custom Render with Providers

```tsx
// test-utils.tsx — wrap ALL providers your components need
import { render, RenderOptions } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router';
import { ThemeProvider } from './theme';

function createTestQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: { retry: false, gcTime: 0 }, // No retry, no cache in tests
    },
  });
}

interface CustomRenderOptions extends Omit<RenderOptions, 'wrapper'> {
  initialEntries?: string[];
}

function renderWithProviders(ui: React.ReactElement, options: CustomRenderOptions = {}) {
  const { initialEntries = ['/'], ...renderOptions } = options;
  const queryClient = createTestQueryClient();

  function Wrapper({ children }: { children: React.ReactNode }) {
    return (
      <QueryClientProvider client={queryClient}>
        <ThemeProvider>
          <MemoryRouter initialEntries={initialEntries}>
            {children}
          </MemoryRouter>
        </ThemeProvider>
      </QueryClientProvider>
    );
  }

  return { ...render(ui, { wrapper: Wrapper, ...renderOptions }), queryClient };
}

export { renderWithProviders as render };
```

---

## Level 2: Network Mocking & State (Intermediate)

### MSW v2 — Mock at the Network Layer

Mock Service Worker intercepts HTTP at the service worker level — your code makes real fetch/axios calls that get intercepted.

```tsx
// mocks/handlers.ts
import { http, HttpResponse } from 'msw';

export const handlers = [
  http.get('/api/users/:id', ({ params }) => {
    return HttpResponse.json({
      id: params.id,
      name: 'Test User',
      email: 'test@example.com',
    });
  }),

  http.post('/api/users', async ({ request }) => {
    const body = await request.json();
    return HttpResponse.json({ id: '123', ...body }, { status: 201 });
  }),

  http.get('/api/users/:id', ({ params }) => {
    if (params.id === 'not-found') {
      return new HttpResponse(null, { status: 404 });
    }
    return HttpResponse.json({ id: params.id, name: 'User' });
  }),
];

// mocks/server.ts
import { setupServer } from 'msw/node';
import { handlers } from './handlers';
export const server = setupServer(...handlers);

// vitest.setup.ts
import { server } from './mocks/server';
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

Override handlers per test for error scenarios:

```tsx
import { server } from '../mocks/server';
import { http, HttpResponse } from 'msw';

test('shows error when API fails', async () => {
  // Override for this single test
  server.use(
    http.get('/api/users/:id', () => {
      return new HttpResponse(null, { status: 500 });
    })
  );

  render(<UserProfile userId="123" />);
  expect(await screen.findByRole('alert')).toHaveTextContent(/error/i);
});
```

### Zustand Store Reset Between Tests

```tsx
import { beforeEach } from 'vitest';
import { useAuthStore } from '../stores/authStore';
import { useCartStore } from '../stores/cartStore';

// CRITICAL: Reset ALL stores between tests to prevent leakage
beforeEach(() => {
  useAuthStore.setState(useAuthStore.getInitialState());
  useCartStore.setState(useCartStore.getInitialState());
});
```

### Testing with Pre-Seeded Store State

```tsx
test('shows admin controls for admin users', () => {
  // Seed store before render
  useAuthStore.setState({ user: { role: 'admin', name: 'Admin' }, isAuthenticated: true });

  render(<Dashboard />);
  expect(screen.getByRole('button', { name: /manage users/i })).toBeInTheDocument();
});

test('hides admin controls for regular users', () => {
  useAuthStore.setState({ user: { role: 'user', name: 'Regular' }, isAuthenticated: true });

  render(<Dashboard />);
  expect(screen.queryByRole('button', { name: /manage users/i })).not.toBeInTheDocument();
});
```

### Testing Router Navigation

```tsx
import { MemoryRouter, Route, Routes } from 'react-router';

test('navigates to profile page', async () => {
  const user = userEvent.setup();

  render(
    <MemoryRouter initialEntries={['/']}>
      <Routes>
        <Route path="/" element={<HomePage />} />
        <Route path="/profile" element={<ProfilePage />} />
      </Routes>
    </MemoryRouter>
  );

  await user.click(screen.getByRole('link', { name: /profile/i }));
  expect(screen.getByRole('heading', { name: /your profile/i })).toBeInTheDocument();
});
```

---

## Level 3: Advanced Testing Patterns (Advanced)

### Accessibility Testing with jest-axe

```tsx
import { axe, toHaveNoViolations } from 'jest-axe';
expect.extend(toHaveNoViolations);

test('form has no accessibility violations', async () => {
  const { container } = render(<ContactForm />);
  const results = await axe(container);
  expect(results).toHaveNoViolations();
});
```

Complement with `eslint-plugin-jsx-a11y` for static analysis at lint time.

### Testing React Hook Form

```tsx
test('validates email and shows error', async () => {
  const user = userEvent.setup();
  render(<SignupForm />);

  // Submit without filling email
  await user.click(screen.getByRole('button', { name: /sign up/i }));

  // Error should appear and be accessible
  const error = await screen.findByRole('alert');
  expect(error).toHaveTextContent(/email is required/i);

  // Input should be marked invalid
  expect(screen.getByLabelText(/email/i)).toHaveAttribute('aria-invalid', 'true');
});

test('submits valid form data', async () => {
  const user = userEvent.setup();
  const mockSubmit = vi.fn();
  render(<SignupForm onSubmit={mockSubmit} />);

  await user.type(screen.getByLabelText(/email/i), 'valid@test.com');
  await user.type(screen.getByLabelText(/password/i), 'StrongPass123!');
  await user.click(screen.getByRole('button', { name: /sign up/i }));

  await waitFor(() => {
    expect(mockSubmit).toHaveBeenCalledWith(
      expect.objectContaining({ email: 'valid@test.com' })
    );
  });
});
```

### Testing TanStack Query Hooks

```tsx
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useUserQuery } from './useUserQuery';

function createWrapper() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  );
}

test('fetches user data', async () => {
  // MSW handles the network mock
  const { result } = renderHook(() => useUserQuery('123'), { wrapper: createWrapper() });

  await waitFor(() => expect(result.current.isSuccess).toBe(true));
  expect(result.current.data).toEqual({ id: '123', name: 'Test User', email: 'test@example.com' });
});
```

### Integration Tests > Unit Tests for React

Prefer integration tests that exercise multiple components together over isolated unit tests.

```tsx
// GOOD: Integration test — tests the full user flow
test('user can filter and select a product', async () => {
  const user = userEvent.setup();
  render(<ProductCatalog />); // Renders search, filter, list, detail

  await user.type(screen.getByLabelText(/search/i), 'widget');
  await waitFor(() => {
    expect(screen.getByText(/premium widget/i)).toBeInTheDocument();
  });

  await user.click(screen.getByText(/premium widget/i));
  expect(await screen.findByRole('heading', { name: /premium widget/i })).toBeInTheDocument();
});
```

---

## Performance: Make It Fast

### 1. Avoid Unnecessary waitFor
If the change is synchronous, assert immediately. `waitFor` adds polling overhead.

### 2. Use vi.mock Sparingly
Mock at boundaries (network via MSW, stores via setState). Don't mock internal modules — it makes tests brittle and tightly coupled to implementation.

### 3. Parallel Test Execution
Vitest runs test files in parallel by default. Keep tests independent (reset stores, use fresh QueryClient) so they don't interfere.

### 4. Skip Snapshot Tests as Primary Strategy
Snapshots break on every UI change and teach nothing about behavior. Use sparingly for structural regression checks on design system components, not as the primary test strategy.

---

## Observability: Know It's Working

### 1. Coverage Reports

```bash
vitest --coverage
```

Focus on branch coverage over line coverage. 80% coverage on critical paths > 100% coverage with trivial tests.

### 2. Test Timing

Watch for slow tests (> 5s). Usually caused by unnecessary waitFor, missing MSW handlers (fetch timeout), or missing store reset (state leaking between tests).

### 3. CI Integration

Run tests on every PR. Display coverage diff. Fail on coverage regression for critical paths.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No querySelector in Tests
**You will be tempted to:** `container.querySelector('.my-class')` or `document.getElementById('foo')`.
**Why that fails:** Tests implementation details (CSS classes, DOM IDs). Refactoring HTML/CSS breaks tests even when behavior is identical. Proves nothing about accessibility.
**The right way:** `screen.getByRole`, `screen.getByLabelText`, `screen.getByText`. If you can't query by these, the component has an accessibility bug.

### Rule 2: No Testing Implementation Details
**You will be tempted to:** Assert on component state, hook return values, or internal function calls.
**Why that fails:** Tests become tightly coupled to HOW the code works. Any refactor (even a pure improvement) breaks tests. You're testing the wrong thing.
**The right way:** Test what the user sees and does. Click buttons, type in inputs, assert on visible text and ARIA states. If the user can't observe it, don't test it.

### Rule 3: No Snapshot Tests as Primary Strategy
**You will be tempted to:** `expect(container).toMatchSnapshot()` for every component.
**Why that fails:** Snapshots break on every HTML/CSS change. Developers blindly update snapshots without reviewing. They catch nothing meaningful about behavior. They bloat the repo.
**The right way:** Behavior assertions (`expect(screen.getByText(...)).toBeInTheDocument()`). Use snapshots ONLY for structural regression on stable design system components.

### Rule 4: No Mocking Internal Modules
**You will be tempted to:** `vi.mock('./useAuth')` to return fake auth state.
**Why that fails:** Tests pass with broken implementations. The mock is a parallel reality that diverges from the real module. Integration between modules is never tested.
**The right way:** Mock at system boundaries: MSW for network, `useAuthStore.setState()` for store state, `MemoryRouter` for navigation. Let internal code run for real.

### Rule 5: No Missing Store Resets
**You will be tempted to:** Skip `beforeEach(() => store.setState(store.getInitialState()))`.
**Why that fails:** Test A sets auth state to admin. Test B runs as admin even though it should test anonymous behavior. Tests pass individually, fail together. Order-dependent bugs that appear in CI but not locally.
**The right way:** Reset EVERY Zustand store in `beforeEach`. Create fresh QueryClient per test. Clean up MSW handlers in `afterEach`.
