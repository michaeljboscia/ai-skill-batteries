---
name: mx-ts-testing
description: Use when writing tests, choosing test frameworks, or reviewing test quality. Also use when the user mentions 'test', 'Vitest', 'Jest', 'mock', 'MSW', 'snapshot', 'integration test', 'Supertest', 'Testcontainers', 'Faker', 'test fixture', 'property-based testing', 'fast-check', 'behavior test', 'coverage', or 'AI-generated test'.
---

# TypeScript Testing — Verification Patterns for AI Coding Agents

**This skill loads when writing tests.** It prevents: testing implementation instead of behavior, snapshot abuse, over-mocking internals, illusory coverage from AI-generated tests, and choosing the wrong test framework.

## When to also load
- Validation (test data schemas) -> `mx-ts-validation`
- Async patterns -> `mx-ts-async`
- Node.js runtime -> `mx-ts-node`

---

## Testing Tool Decision Tree

| Scenario | Tool | Why |
|----------|------|-----|
| Unit tests, new TS/ESM project | Vitest | Native ESM/TS, 10-20x faster watch mode |
| Unit tests, existing Jest codebase | Jest + ts-jest | Don't rewrite working suites |
| React Native tests | Jest | Vitest lacks RN support |
| Network mocking (HTTP/GraphQL) | MSW | Intercepts at network level, library-agnostic |
| HTTP endpoint testing | Supertest | No network port, integrates with Vitest/Jest |
| Real database in tests | Testcontainers | Ephemeral Docker containers, real queries |
| Lightweight Mongo tests | mongodb-memory-server | Faster than Testcontainers for narrow tests |
| Realistic fake data | Faker.js | Seeded for determinism, type-safe |
| Input fuzzing / invariant checking | fast-check | Property-based, auto-shrinks to minimal case |
| Browser E2E | Playwright | Native TS, real browser, auto-waits |
| Component rendering | React Testing Library | Query by role/text, not internals |
| Snapshot regression | Vitest/Jest inline snapshots | Small, focused, deterministic only |

---

## Level 1: Test Behavior Not Implementation (Beginner)

### The Core Principle

Test the **public API** and **observable output**. Never assert against private variables, internal state, or non-exported helpers. If the internals change but the output stays the same, zero tests should break.

### BAD: Testing Implementation (Brittle)

```typescript
import { render } from '@testing-library/react';
import { UserProfile } from './UserProfile';

describe('UserProfile', () => {
  it('should update internal state when button is clicked', () => {
    // BAD: Accessing component instance and internal state
    const component = render(<UserProfile />);
    const instance = component.getInstance();

    expect(instance.state.isExpanded).toBe(false);
    instance.handleExpandToggle(); // BAD: calling internal method
    expect(instance.state.isExpanded).toBe(true);
  });
});
```

### GOOD: Testing Behavior (Resilient)

```typescript
import { render, screen, fireEvent } from '@testing-library/react';
import { UserProfile } from './UserProfile';

describe('UserProfile', () => {
  it('reveals additional details when expand button is clicked', () => {
    render(<UserProfile />);

    const expandBtn = screen.getByRole('button', { name: /expand details/i });
    expect(screen.queryByText(/user email/i)).not.toBeInTheDocument();

    fireEvent.click(expandBtn);

    // Assert the observable DOM change, not internal state
    expect(screen.getByText(/user email/i)).toBeInTheDocument();
  });
});
```

### Test Naming: Describe Behavior, Not Mechanics

| BAD | GOOD |
|-----|------|
| `checkLogin() should return true when token valid` | `grants access when provided a valid, unexpired session token` |
| `throws Error 401 on bad string` | `rejects authentication after 5 consecutive failed attempts` |
| `should call internalParser()` | `extracts structured data from raw CSV input` |
| `returns object with status field` | `confirms payment and issues receipt for valid transactions` |

**Format:** `it('<verb describing outcome> when/after/for <condition>')`. No function names, no HTTP status codes, no type names in the description unless they are part of the public API contract.

### BAD: Service Implementation Test

```typescript
describe('OrderService', () => {
  it('should call calculateTax with correct args', async () => {
    // BAD: spying on internal method
    const spy = vi.spyOn(orderService as any, 'calculateTax');
    await orderService.placeOrder(orderData);
    expect(spy).toHaveBeenCalledWith(100, 'US');
  });
});
```

### GOOD: Service Behavior Test

```typescript
describe('OrderService', () => {
  it('includes 15% tax in the order total for US orders', async () => {
    const order = await orderService.placeOrder({
      items: [{ price: 100, qty: 1 }],
      country: 'US',
    });
    // Assert public output, not internal call
    expect(order.total).toBe(115);
    expect(order.taxAmount).toBe(15);
  });
});
```

---

## Level 2: Mocking & Snapshots (Intermediate)

### MSW for Network Mocking

Mock at the **network boundary**, not the function level. MSW intercepts real HTTP requests regardless of whether the code uses fetch, axios, or got. Switching HTTP libraries never breaks your tests.

### BAD: Function-Level Mock (Coupled to Implementation)

```typescript
import axios from 'axios';
import { fetchUserData } from './userService';

jest.mock('axios');
const mockedAxios = axios as jest.Mocked<typeof axios>;

describe('fetchUserData', () => {
  it('returns user data', async () => {
    // BAD: test knows the function uses axios.get
    mockedAxios.get.mockResolvedValueOnce({ data: { id: 1, name: 'Alice' } });
    const result = await fetchUserData(1);
    expect(result.name).toBe('Alice');
    expect(mockedAxios.get).toHaveBeenCalledWith('/api/users/1');
  });
});
```

### GOOD: Network-Level Mock with MSW

```typescript
import { http, HttpResponse } from 'msw';
import { setupServer } from 'msw/node';
import { fetchUserData } from './userService';

const server = setupServer(
  http.get('https://api.example.com/users/:id', ({ params }) => {
    return HttpResponse.json({ id: Number(params.id), name: 'Alice', role: 'admin' });
  })
);

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers()); // Prevent state leakage
afterAll(() => server.close());

describe('fetchUserData', () => {
  it('returns user data over the network layer', async () => {
    // Test has no idea if fetch, axios, or got is used internally
    const result = await fetchUserData(1);
    expect(result.name).toBe('Alice');
  });

  it('handles server errors gracefully', async () => {
    server.use(
      http.get('https://api.example.com/users/:id', () => {
        return new HttpResponse(null, { status: 500 });
      })
    );
    await expect(fetchUserData(1)).rejects.toThrow('Internal Server Error');
  });
});
```

### Type-Safe Mocks

When you must mock (timers, Dates, non-network I/O), keep type safety:

```typescript
// Vitest type-safe mock
const mockLogger = vi.fn<(msg: string, level: 'info' | 'error') => void>();

// Interface-based test double
interface EmailSender { send(to: string, body: string): Promise<boolean>; }

const fakeEmailSender: EmailSender = {
  send: vi.fn().mockResolvedValue(true),
};
```

### Faker.js for Test Data

```typescript
import { faker } from '@faker-js/faker';

// Seeded for deterministic tests
faker.seed(42);

function buildUser(overrides: Partial<User> = {}): User {
  return {
    id: faker.string.uuid(),
    name: faker.person.fullName(),
    email: faker.internet.email(),
    createdAt: faker.date.past(),
    ...overrides, // Caller overrides specific fields
  };
}

// Usage: buildUser({ name: 'Alice' }) — realistic defaults + targeted overrides
```

### Factory/Builder Pattern for Test Fixtures

```typescript
class OrderFixture {
  private data: Partial<Order> = {};
  withItems(count: number): this {
    this.data.items = Array.from({ length: count }, () => ({
      sku: faker.string.alphanumeric(8),
      price: faker.number.float({ min: 1, max: 500, fractionDigits: 2 }),
      qty: faker.number.int({ min: 1, max: 10 }),
    }));
    return this;
  }
  withCountry(country: string): this { this.data.country = country; return this; }
  build(): Order {
    return { id: faker.string.uuid(), items: [], country: 'US', status: 'pending', ...this.data };
  }
}
// Usage: new OrderFixture().withItems(3).withCountry('DE').build()
```

### Snapshot Guidelines

Snapshots assert **"hasn't changed"**, NOT **"is correct"**. Regression safety net, not a substitute for behavioral assertions.

| Do | Don't |
|----|-------|
| Snapshot small, static components (< 50 lines) | Snapshot entire page layouts |
| Use inline snapshots for short strings | Use `.toMatchSnapshot()` on large DOM trees |
| Redact timestamps, UUIDs, random values | Snapshot objects with dynamic fields |
| Review every diff before updating | Run `vitest -u` or `jest -u` blindly |

**BAD:** `expect(container).toMatchSnapshot()` on a full dashboard -- 2000-line snapshot nobody reviews.

**GOOD:** Inline snapshot on a small, deterministic component:
```typescript
it('renders critical error badge with correct styling', () => {
  render(<StatusBadge status="critical_error" />);
  expect(screen.getByTestId('status-badge')).toMatchInlineSnapshot(`
    <span class="badge badge-critical font-bold text-red-500" data-testid="status-badge">
      Critical Error
    </span>
  `);
});
```

---

## Level 3: Integration & AI Code Testing (Advanced)

### Supertest for HTTP Endpoint Testing

```typescript
import request from 'supertest';
import { createApp } from './app';

describe('POST /api/orders', () => {
  const app = createApp();

  it('creates an order and returns 201 with order ID', async () => {
    const res = await request(app)
      .post('/api/orders')
      .send({ items: [{ sku: 'ABC', qty: 2 }], country: 'US' })
      .expect(201);
    expect(res.body).toMatchObject({ id: expect.any(String), status: 'pending' });
  });

  it('rejects invalid payload with 400 and validation errors', async () => {
    const res = await request(app).post('/api/orders').send({ items: [] }).expect(400);
    expect(res.body.errors).toContainEqual(
      expect.objectContaining({ field: 'items', message: expect.any(String) })
    );
  });
});
```

### Testcontainers for Real Database Tests

```typescript
import { PostgreSqlContainer } from '@testcontainers/postgresql';

describe('UserRepository (real Postgres)', () => {
  let container: any, pool: Pool;
  beforeAll(async () => {
    container = await new PostgreSqlContainer('postgres:16').start();
    pool = new Pool({ connectionString: container.getConnectionUri() });
    await runMigrations(pool);
  }, 60_000);
  afterAll(async () => { await pool.end(); await container.stop(); });

  it('inserts and retrieves a user', async () => {
    const repo = new UserRepository(pool);
    const created = await repo.create({ name: 'Alice', email: 'a@b.com' });
    const found = await repo.findById(created.id);
    expect(found?.name).toBe('Alice');
  });
});
// Transactional teardown (faster than restarting container):
// beforeEach: tx = await pool.connect(); await tx.query('BEGIN');
// afterEach: await tx.query('ROLLBACK'); tx.release();
```

### Property-Based Testing with fast-check

Property-based testing generates hundreds of randomized inputs to verify **invariants**. It catches the edge cases that AI-generated happy-path tests miss.

### BAD: AI-Generated Illusory Coverage

```typescript
describe('processTransaction (AI Generated)', () => {
  it('should process the transaction', () => {
    // BAD: magic numbers, no boundary testing
    const result = processTransaction(100, 'USD', 'user_123');

    // BAD: "mental execution" assert — tests what AI assumes, not the spec
    expect(result).toBeDefined();
    expect(result.status).toBe('SUCCESS'); // High line coverage, zero utility
  });
});
```

### GOOD: Property-Based Invariant Testing

```typescript
import fc from 'fast-check';
import { processTransaction } from './billing';

describe('processTransaction (Property Based)', () => {
  it('rejects negative amounts regardless of currency', () => {
    fc.assert(
      fc.property(
        fc.float({ max: -0.01 }),
        fc.constantFrom('USD', 'EUR', 'GBP'),
        fc.uuid(),
        (amount, currency, userId) => {
          expect(() => processTransaction(amount, currency, userId)).toThrow();
        }
      )
    );
  });

  it('maintains exact 15% tax ratio on all valid transactions', () => {
    fc.assert(
      fc.property(
        fc.float({ min: 1, max: 1_000_000 }),
        fc.constantFrom('USD', 'EUR', 'GBP'),
        fc.uuid(),
        (amount, currency, userId) => {
          const result = processTransaction(amount, currency, userId);
          expect(result.status).toBe('SUCCESS');
          expect(result.tax).toBeCloseTo(amount * 0.15, 2);
        }
      )
    );
  });
});
```

### AI-Generated Code: The 1.7x Defect Problem

Empirical data shows AI-generated code introduces **1.7x more defects** than human-authored code:

| Defect Category | AI vs Human Multiplier |
|-----------------|----------------------|
| Logic/correctness errors | 1.75x |
| Code quality issues | 1.64x |
| Security vulnerabilities | 1.5-2.0x |
| Performance regressions | 1.42x |

**AI test suites create "illusory coverage"** — high line coverage but near-zero mutation score. The tests invoke functions to hit coverage metrics but fail to assert meaningful outcomes.

### AI Test Failure Modes

| Failure Mode | What Happens | Detection |
|--------------|-------------|-----------|
| Magic Number Test | Hardcoded inputs/outputs with no boundary exploration | Review: any test with only 1-2 example inputs |
| Mental Execution Assert | AI asserts what it *thinks* the code returns, not the spec | Mutation testing: flip a condition, test still passes |
| Hallucinated API | References non-existent functions or params | TypeScript compiler catches this (if types are strict) |
| Logic Drift | Tests pass but don't match actual business requirements | Spec review: compare test assertions to requirements doc |
| Coverage Theater | `expect(result).toBeDefined()` as the sole assertion | Grep for weak assertions: `.toBeDefined()`, `.toBeTruthy()` |

### Mitigation Strategy

1. **Property-based testing** (fast-check) to fuzz boundaries AI missed
2. **Mutation testing** (`@stryker-mutator/core`) to verify tests actually catch bugs
3. **Spec-first assertions** — write `expect()` from the requirements doc, not the implementation
4. **Grep-audit weak assertions** — `toBeDefined()`, `toBeTruthy()`, `not.toThrow()` as sole assertions are red flags
5. **Tiered trust** — AI-generated tests get human review on any code touching auth, billing, or data integrity

---

## Performance: Make It Fast

### Vitest Configuration

```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config';
export default defineConfig({
  test: {
    globals: true,
    environment: 'node',        // or 'jsdom' for browser APIs
    include: ['src/**/*.test.ts'],
    pool: 'threads',            // Worker threads (default, fastest)
    poolOptions: { threads: { maxThreads: 4, minThreads: 1 } },
    testTimeout: 10_000,        // 10s per test
    hookTimeout: 30_000,        // 30s for beforeAll (container startup)
    coverage: {
      provider: 'v8',
      thresholds: { branches: 80, functions: 80, lines: 80, statements: 80 },
    },
  },
});
```

Vitest re-runs only affected tests via HMR -- no full restart. `pool: 'forks'` gives full process isolation (needed if tests mutate globals) but is slower.

---

## Observability: Know It's Working

### Vitest vs Jest Decision Matrix

| Parameter | Choose Vitest | Choose Jest |
|-----------|--------------|-------------|
| **Module system** | Native ESM, TS-first | CommonJS, Babel/ts-jest |
| **Project type** | New project, Vite/Vue/Svelte/Nuxt | React Native, legacy CRA |
| **Watch mode speed** | 10-20x faster (HMR) | Adequate for CI-only |
| **TS support** | Zero-config | Requires ts-jest setup |
| **Ecosystem size** | Growing (3.8M weekly) | Massive (35M weekly) |
| **Migration effort** | `jest.mock` -> `vi.mock`, mostly drop-in | N/A |

**Default for 2026:** Vitest for all new web TS projects. Jest for React Native and existing large codebases. Never rewrite a working Jest suite just for speed.

### Coverage Is Necessary But Not Sufficient

100% line coverage with `expect(x).toBeDefined()` everywhere is worthless. **Mutation testing is the real quality signal.** `npx stryker run` mutates source code (flips conditions, removes statements, changes operators) and re-runs tests. Surviving mutations = test gaps. Target mutation score > 70% on business-critical modules.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Assert Against Internal State
**You will be tempted to:** Spy on private methods, access `component.state`, or mock internal utility functions "for better isolation."
**The right way:** Assert observable output through the public API. If internal state matters, it must surface through a public interface. If you refactor internals and tests break, the tests were wrong.

### Rule 2: Never Mock at the Function Level for Network Calls
**You will be tempted to:** `vi.mock('axios')` or `jest.mock('node-fetch')` because "MSW has more boilerplate."
**The right way:** MSW at the network boundary. Function-level mocks bypass serialization, error handling, and retry logic. They break when you swap HTTP libraries. The 5 extra lines of MSW setup save hours of debugging production-only failures.

### Rule 3: Never Blindly Update Snapshots
**You will be tempted to:** Run `vitest -u` or `jest -u` to make CI green after a refactor.
**The right way:** Review every snapshot diff. A blind update silently accepts regressions, layout shifts, and hallucinated content into the reference file. If a snapshot is too large to review (50+ lines), it is too large to exist.

### Rule 4: Never Ship AI-Generated Tests Without Mutation Testing
**You will be tempted to:** Accept an AI-generated test suite because "it achieves 95% coverage."
**The right way:** Run mutation testing (`stryker run`) on the covered code. If mutations survive, the tests are illusory. High coverage + low mutation score = Coverage Theater. Fix the assertions before shipping.

### Rule 5: Never Use `toBeDefined()` or `toBeTruthy()` as Sole Assertions
**You will be tempted to:** Write `expect(result).toBeDefined()` and call it tested.
**The right way:** Assert the **specific value, shape, or property** that the specification requires. `toBeDefined` proves the function returned something. It does not prove the function returned the right thing. Every test needs at least one assertion that would fail if the business logic were wrong.
