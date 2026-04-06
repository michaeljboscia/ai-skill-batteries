# Comprehensive Guide to TypeScript Testing Patterns for AI Coding Agents

**Key Points:**
*   Research suggests that AI-generated code may introduce approximately 1.7x more defects than human-authored code, necessitating highly rigorous automated testing frameworks.
*   Evidence indicates a potential 1.5x to 2x increase in security vulnerabilities within AI-assisted pull requests, particularly concerning improper password handling and insecure object references.
*   The phenomenon of "illusory test coverage" is frequently observed in AI-generated test suites, where high line coverage masks a near-zero mutation score due to hallucinated assertions and missing behavioral verifications.
*   Methodological shifts toward testing behavior rather than implementation details appear critical for maintaining resilient test suites that survive continuous refactoring by autonomous agents.
*   Vitest consistently demonstrates significant performance advantages over Jest (often cited as 10x to 20x faster in watch mode) for modern ECMAScript Module (ESM) and TypeScript codebases, though Jest remains a staple for legacy systems and React Native environments.

**Contextual Overview**
The rapid integration of Large Language Models (LLMs) and AI coding agents into software engineering workflows has fundamentally altered the economics of code generation. While development velocity has accelerated, empirical data highlights a corresponding escalation in technical debt and subtle logical defects. Autonomous agents frequently optimize for localized syntax validation rather than holistic system architecture, generating code that satisfies static type checkers but fails under complex edge cases.

**The Role of Testing Patterns**
To mitigate the risks associated with AI-driven development, human engineers and reviewer agents must enforce strict, standardized testing paradigms. Test suites act as the primary guardrails against algorithmic drift. When an AI agent modifies a codebase, the automated tests must validate the public-facing behavior of the module without artificially constraining its internal implementation. 

**Establishing Guardrails via Anti-Rationalization**
AI coding agents are highly prone to "rationalization"—the tendency to generate plausible but incorrect justifications for taking shortcuts, such as mocking internal functions or asserting against private state. To counteract this, modern testing architectures employ "anti-rationalization rules" [cite: 1, 2]. These are strict, non-negotiable directives designed to prevent LLMs from bypassing architectural boundaries, ensuring that both human and machine contributors adhere to robust engineering principles.

## 1. Testing Behavior vs. Implementation

The foundational principle of software verification, particularly in ecosystems augmented by AI agents, is the strict separation between testing behavior and testing implementation details. Traditional white-box testing often relies on probing intermediate states, private variables, or specific algorithmic steps within a function [cite: 3]. While this can artificially inflate test coverage metrics, it creates highly brittle test suites that break the moment an AI agent or human developer refactors the internal logic to optimize performance.

Implementation-focused tests tightly couple the verification logic to the internal mechanics of the module. If a developer renames a private variable or extracts a helper function, the test fails, even if the public output remains identical. This phenomenon severely degrades the developer experience and negates the velocity benefits of AI coding assistants, as engineers must spend disproportionate time repairing "broken" tests that represent false positives. Conversely, behavioral testing treats the system under test as a "gray box" or "black box," asserting solely against the public API and the observable output given a specific set of inputs [cite: 3, 4]. 

In the context of modern web applications, the React Testing Library (RTL) epitomizes this philosophy. RTL intentionally restricts developers from accessing internal component states (such as a React component's internal state variables) and instead forces them to query the DOM exactly as a user would (e.g., finding elements by text, role, or label) [cite: 5]. This ensures that as long as the user experience remains consistent, the underlying component can be completely rewritten without altering a single test.

**Technical Reference: BAD/GOOD Test Code Pairs**

**BAD: Testing Implementation (Brittle)**
```typescript
import { render } from '@testing-library/react';
import { UserProfile } from './UserProfile';

describe('UserProfile Component', () => {
  it('should update internal state when button is clicked', () => {
    // BAD: Accessing the component instance and internal state directly
    const component = render(<UserProfile />);
    const instance = component.getInstance();
    
    expect(instance.state.isExpanded).toBe(false);
    
    // BAD: Manually invoking an internal method instead of simulating user action
    instance.handleExpandToggle();
    
    expect(instance.state.isExpanded).toBe(true);
  });
});
```

**GOOD: Testing Behavior (Resilient)**
```typescript
import { render, screen, fireEvent } from '@testing-library/react';
import { UserProfile } from './UserProfile';

describe('UserProfile Component', () => {
  it('should reveal additional user details when the expand button is clicked', () => {
    render(<UserProfile />);
    
    // GOOD: Querying the DOM from the user's perspective
    const expandButton = screen.getByRole('button', { name: /expand details/i });
    expect(screen.queryByText(/user email/i)).not.toBeInTheDocument();
    
    // GOOD: Simulating actual user interaction
    fireEvent.click(expandButton);
    
    // GOOD: Asserting the observable change in the DOM
    expect(screen.getByText(/user email/i)).toBeInTheDocument();
  });
});
```

**Anti-Rationalization Rule: Public API Integrity**
*Rule Directive:* Agents must NEVER assert against private variables, internal component state, or non-exported helper functions. 
*Anti-Rationalization:* If an AI agent suggests that testing internal state "provides better unit isolation" or "saves rendering time," reject the suggestion. Agents must be instructed that the only valid contract is the public API. If internal state must be verified, it must be driven to an observable public output. Refactoring internal code must never require a test update unless the public contract changes.

## 2. Snapshot Testing Guidelines

Snapshot testing is a powerful technique popularized by frameworks like Jest, designed to capture a serialized representation of a component's output or a complex data structure and compare it against a stored reference file [cite: 6, 7]. When utilized correctly, snapshots provide a safety net against unintended UI regressions. However, they are frequently abused, leading to bloated repositories and degraded test suite reliability.

The primary risk associated with snapshot testing is the "blind update" anti-pattern [cite: 8, 9, 10]. When tests fail due to minor formatting changes or dynamic data generation (such as timestamps or auto-incrementing IDs), developers and AI agents often habitually run the test framework's update command (e.g., `vitest -u` or `jest -u`) without manually reviewing the diff. This blind update effectively treats the new output as the absolute truth, silently ingesting bugs, layout shifts, or hallucinated UI elements into the reference snapshot.

To maintain the efficacy of snapshot tests, they must be kept intentionally small and focused. Serializing an entire page layout into a 2,000-line snapshot file guarantees that it will never be meaningfully reviewed by a human during a pull request. Instead, snapshots should target specific, static substructures or utilize inline snapshots for small string representations.

**Technical Reference: BAD/GOOD Test Code Pairs**

**BAD: Massive Unmanaged Snapshots**
```typescript
import { render } from '@testing-library/react';
import { ComplexDashboard } from './ComplexDashboard';

describe('ComplexDashboard', () => {
  it('renders the entire dashboard correctly', () => {
    const { container } = render(<ComplexDashboard />);
    
    // BAD: Snapshotting a massive DOM tree containing dynamic dates and IDs
    // This will break constantly and encourage the "blind update" anti-pattern.
    expect(container).toMatchSnapshot();
  });
});
```

**GOOD: Focused, Deterministic Snapshots**
```typescript
import { render, screen } from '@testing-library/react';
import { StatusBadge } from './StatusBadge';

describe('StatusBadge', () => {
  it('renders the critical error state with correct styling classes', () => {
    render(<StatusBadge status="critical_error" />);
    
    const badge = screen.getByTestId('status-badge');
    
    // GOOD: Snapshotting a small, isolated component
    // We mock non-deterministic elements if any existed.
    expect(badge).toMatchInlineSnapshot(`
      <span
        class="badge badge-critical font-bold text-red-500"
        data-testid="status-badge"
      >
        Critical Error
      </span>
    `);
  });
});
```

**Anti-Rationalization Rule: Snapshot Blind Updates**
*Rule Directive:* Do not use snapshots for dynamic data, timestamps, randomly generated IDs, or full-page layouts. Snapshots must be small enough to be reviewed in a standard PR interface (under 50 lines).
*Anti-Rationalization:* If an AI agent attempts to resolve a failing test suite by executing a blanket snapshot update command without verifying the semantic correctness of the diff, halt the operation. Agents must not rationalize that "updating the snapshot fixes the build." The agent must explicitly analyze the diff and confirm whether the structural change represents a defect or a deliberate feature enhancement.

## 3. Mocking Best Practices

Mocking is essential for isolating the system under test, preventing side effects, and eliminating reliance on unstable external networks or databases. However, improper mocking strategies lead to test suites that pass in isolation but fail spectacularly in production. A core tenet of robust TypeScript testing is to mock external boundaries (e.g., HTTP APIs, database drivers, third-party services) while leaving internal dependencies and business logic intact [cite: 4].

Historically, developers used tools like Nock or Jest's manual module mocking (`jest.mock()`) to intercept network requests. These approaches often coupled tests tightly to the implementation of the HTTP client (e.g., mocking Axios explicitly) rather than testing the actual network protocol [cite: 11, 12]. This meant that if an engineering team migrated from `axios` to the native `fetch` API, the entire test suite would break, even though the application's network behavior remained identical [cite: 12].

Mock Service Worker (MSW) has emerged as the industry standard for network mocking because it intercepts requests at the network level using standard Service Worker APIs (in the browser) or Node.js interceptors [cite: 12, 13]. This allows the application to execute real HTTP requests, completely agnostic to the underlying fetching library. Furthermore, MSW integrates seamlessly with TypeScript, allowing developers to create highly type-safe REST and GraphQL mocks that share data transfer object (DTO) interfaces with the production codebase [cite: 14, 15]. MSW handlers can also be easily parameterized and reset between tests to avoid state leakage and test pollution [cite: 11, 15].

**Technical Reference: BAD/GOOD Test Code Pairs**

**BAD: Implementation-Coupled Function Mocking**
```typescript
import axios from 'axios';
import { fetchUserData } from './userService';

// BAD: Mocking the internal implementation (axios) directly
jest.mock('axios');
const mockedAxios = axios as jest.Mocked<typeof axios>;

describe('fetchUserData', () => {
  it('returns user data successfully', async () => {
    // BAD: The test knows exactly how the function is implemented
    mockedAxios.get.mockResolvedValueOnce({ data: { id: 1, name: 'Alice' } });
    
    const result = await fetchUserData(1);
    expect(result.name).toBe('Alice');
    expect(mockedAxios.get).toHaveBeenCalledWith('/api/users/1');
  });
});
```

**GOOD: Network-Level Type-Safe Mocking with MSW**
```typescript
import { http, HttpResponse } from 'msw';
import { setupServer } from 'msw/node';
import { fetchUserData } from './userService';

// GOOD: Define a type-safe mock response using MSW
const server = setupServer(
  http.get('https://api.example.com/users/:id', ({ params }) => {
    const { id } = params;
    return HttpResponse.json({
      id: Number(id),
      name: 'Alice',
      role: 'admin'
    });
  })
);

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
// GOOD: Resetting handlers between tests prevents state leakage
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

describe('fetchUserData', () => {
  it('returns user data successfully over the network layer', async () => {
    // The test does not know if fetch, axios, or graphql is used internally
    const result = await fetchUserData(1);
    expect(result.name).toBe('Alice');
  });
  
  it('handles network errors gracefully', async () => {
    // Override the mock for a specific negative test case
    server.use(
      http.get('https://api.example.com/users/:id', () => {
        return new HttpResponse(null, { status: 500 });
      })
    );
    
    await expect(fetchUserData(1)).rejects.toThrow('Internal Server Error');
  });
});
```

**Anti-Rationalization Rule: Network Boundary Integrity**
*Rule Directive:* Mock at the network level (using MSW), not the function level. Do not mock internal utility functions, native JavaScript modules (unless dealing with timers/Dates), or the implementation of HTTP clients.
*Anti-Rationalization:* An AI agent may argue that `vi.mock('axios')` is "faster to write" or "requires less boilerplate." This rationalization must be strictly rejected. Function-level mocking bypasses critical serialization, deserialization, and error-handling pathways. Mocks must enforce network-level boundaries to guarantee that the application successfully handles real-world HTTP paradigms.

## 4. AI-Generated Code Testing Risks & Mitigation

The widespread adoption of AI coding assistants has yielded profound productivity improvements, but it has simultaneously introduced measurable degradation in specific vectors of code quality. Comprehensive empirical analyses of real-world pull requests demonstrate that AI-generated code introduces approximately 1.7x more defects across critical categories compared to human-authored code [cite: 16, 17, 18]. Specifically, these analyses reveal a 75% increase in logic and correctness issues (e.g., unsafe control flow, business logic errors) [cite: 16, 17]. 

Even more concerning is the security posture of AI-generated code. Security vulnerabilities are observed to rise by 1.5x to 2x in AI-authored commits [cite: 16, 18, 19]. This includes a heavy proliferation of improper password handling, insecure object references, cross-site scripting (XSS), and insecure deserialization [cite: 18, 19, 20]. Because LLMs are trained on vast corpora of public repositories—which inherently contain deprecated or insecure patterns—they frequently hallucinate or regenerate these vulnerabilities without contextual awareness [cite: 19].

Furthermore, AI agents tasked with writing test suites often generate what is known as "illusory test coverage" [cite: 21]. In this scenario, the generated tests achieve high line coverage (often approaching 100%) but exhibit a near-zero mutation score [cite: 21, 22, 23]. The AI achieves this by invoking functions to pass coverage metrics but failing to assert meaningful behavioral outcomes. Common failure modes include the "Magic Number Test smell," hallucinating non-existent APIs, and relying on "mental execution" asserts where the AI asserts against the implementation rather than the specification [cite: 21]. 

To combat this, teams must employ property-based testing (e.g., using libraries like `fast-check` in TypeScript). Property-based testing moves beyond hardcoded examples, fuzzing function signatures based on boundary hints and types [cite: 3]. It generates hundreds of randomized, edge-case inputs to verify that certain mathematical or logical invariants hold true, effectively exposing the logic drift and unhandled edge cases typical of LLM-generated functions.

**Technical Reference: BAD/GOOD Test Code Pairs**

**BAD: Illusory Coverage (AI-Hallucinated Test)**
```typescript
import { processTransaction } from './billing';

describe('processTransaction (AI Generated)', () => {
  it('should process the transaction without throwing', () => {
    // BAD: Magic numbers, no boundary testing
    const result = processTransaction(100, 'USD', 'user_123');
    
    // BAD: "Mental execution" assert - testing that the function returns what the AI 
    // assumes it returns, rather than validating business rules. High line coverage, zero utility.
    expect(result).toBeDefined();
    expect(result.status).toBe('SUCCESS'); 
  });
});
```

**GOOD: Property-Based Testing for Robustness**
```typescript
import fc from 'fast-check';
import { processTransaction } from './billing';

describe('processTransaction (Property Based)', () => {
  it('should never process negative amounts or invalid currencies', () => {
    // GOOD: Using fast-check to fuzz the inputs and ensure mathematical invariants hold
    fc.assert(
      fc.property(
        fc.float({ max: -0.01 }), // Negative amounts
        fc.string({ minLength: 1 }), // Random string for currency
        fc.string(),
        (amount, currency, userId) => {
          // Verify the system correctly rejects adversarial inputs
          expect(() => processTransaction(amount, currency, userId)).toThrow();
        }
      )
    );
  });
  
  it('maintains expected tax ratios on valid transactions', () => {
    fc.assert(
      fc.property(
        fc.float({ min: 1, max: 1000000 }),
        fc.constantFrom('USD', 'EUR', 'GBP'),
        fc.uuid(),
        (amount, currency, userId) => {
          const result = processTransaction(amount, currency, userId);
          expect(result.status).toBe('SUCCESS');
          // Invariant: The calculated tax must always be exactly 15% of the base amount
          expect(result.tax).toBeCloseTo(amount * 0.15, 2);
        }
      )
    );
  });
});
```

**Anti-Rationalization Rule: Illusory Coverage Prevention**
*Rule Directive:* Tests must validate structural business invariants and negative edge cases. Achieving 100% line coverage is insufficient. All tests must contain specific, behavior-driven assertions (`expect`) that validate the output against the system specification.
*Anti-Rationalization:* An AI must never rationalize that "the test passes, so the code is fully verified." If the test merely invokes a function and expects it to be defined (`expect(x).toBeDefined()`), the AI is engaging in illusory coverage theater. The agent must be instructed to utilize mutation testing principles and property-based inputs to stress-test the LLM-generated business logic [cite: 21].

## 5. Vitest vs. Jest Decision Tree

The JavaScript and TypeScript testing ecosystem has traditionally been dominated by Meta's Jest, a mature, feature-rich framework released in 2014 [cite: 7, 24]. However, the advent of Vite and native ECMAScript Modules (ESM) has exposed architectural bottlenecks within Jest's isolated Node.js environment model. Vitest, introduced in late 2021, has rapidly ascended as the high-performance alternative, specifically tailored for modern web development workflows [cite: 7, 24, 25].

The performance disparity between the two frameworks is stark. Independent benchmarks and developer reports consistently indicate that Vitest executes tests 10x to 20x faster than Jest in watch mode [cite: 7, 26, 27, 28, 29]. This dramatic acceleration is achieved through Vitest's utilization of Vite's Hot Module Replacement (HMR) capabilities and `esbuild`. Instead of restarting the entire testing process upon a file change, Vitest selectively reruns only the modules affected by the update [cite: 7, 27]. Furthermore, Vitest offers native, out-of-the-box support for ESM and TypeScript without requiring heavy transpilation plugins like `Babel` or `ts-jest` [cite: 24, 29].

Despite Vitest's overwhelming performance advantages for web applications, Jest maintains specific strongholds. Jest 30 has improved performance and TypeScript support (requiring TS 5.4+) [cite: 28, 29], and its massive ecosystem (35 million weekly downloads compared to Vitest's 3.8 million) provides unparalleled stability for legacy enterprise systems [cite: 26]. Crucially, Jest remains the undisputed standard for React Native applications, as Vitest's React Native support remains highly experimental and lacks full parity [cite: 24, 28, 30].

**Decision Tree matrix for Engineering Teams:**

| Parameter | Choose Vitest | Choose Jest |
| :--- | :--- | :--- |
| **Primary Framework** | Vue, Svelte, Vite-based React, Nuxt [cite: 24, 26] | React Native, Next.js (Legacy), CRA [cite: 24, 26] |
| **Module System** | Native ESM, TypeScript-first [cite: 6, 25, 29] | CommonJS, heavily reliant on Babel/ts-jest [cite: 28] |
| **Performance Needs** | Requires instant HMR, 10-20x faster watch mode [cite: 7, 26, 27] | CI/CD environments where raw cold-start parallelization is sufficient [cite: 7] |
| **Ecosystem Maturity** | Willing to adopt modern plugins (growing fast) [cite: 26] | Requires battle-tested, esoteric plugins (35M weekly downloads) [cite: 26] |
| **Migration Path** | Simple drop-in replacement (change `jest.*` to `vi.*`) [cite: 25] | N/A (already established) |

For greenfield projects in 2026, Vitest is unequivocally the recommended default for web applications [cite: 25]. The migration path is remarkably frictionless, as Vitest intentionally exposes a Jest-compatible API, allowing teams to seamlessly translate assertions and mocking syntax without rewriting fundamental test logic [cite: 24, 25, 31].

## 6. Test Naming Conventions

The structural organization and naming of tests serve as living documentation for autonomous agents and human engineers alike. A poorly named test obscures the intended behavior of the system, forcing agents to reverse-engineer the implementation to understand the module's purpose. The industry standard utilizes the `describe` and `it` (or `test`) block structure, but the critical requirement is that these blocks must contain precise behavioral descriptions.

Test names should follow a clear "Action -> Expected Outcome -> Context/Condition" format. They should avoid referencing specific function names or variable types in the `it` block, as these represent implementation details that are subject to refactoring.

**Technical Reference: BAD/GOOD Test Code Pairs**

**BAD: Implementation-Focused Naming**
```typescript
describe('AuthService', () => {
  // BAD: Names the specific internal function, uses developer jargon
  it('checkLogin() should return true when token is valid', () => {
    // ...
  });
  
  // BAD: Describes the structural shape rather than the business rule
  it('throws Error 401 on bad string', () => {
    // ...
  });
});
```

**GOOD: Behavioral-Focused Naming**
```typescript
describe('Authentication Service', () => {
  // GOOD: Describes the business outcome from a user/system perspective
  it('grants system access when provided with a valid, unexpired session token', () => {
    // ...
  });
  
  // GOOD: Explains the exact condition and expected security behavior
  it('rejects authentication and locks the account after 5 consecutive failed attempts', () => {
    // ...
  });
});
```

**Anti-Rationalization Rule: Behavioral Descriptions**
*Rule Directive:* Test names must describe the system's observable behavior, not its internal mechanics. Do not use function names, HTTP status codes, or data types in the `it` description unless absolutely necessary for external API contracts.
*Anti-Rationalization:* If an AI agent attempts to write a test named `it('should call internalParser()')`, explicitly reject the output. The agent must not rationalize that naming internal functions makes tests "easier to search." Test names act as behavioral contracts; they must remain valid even if `internalParser()` is entirely removed from the codebase.

## 7. Conclusion

As the software industry transitions toward AI-augmented development, the architectural integrity of test suites becomes the paramount defense against systemic entropy. AI coding assistants fundamentally alter the risk landscape, introducing logic defects at a rate of 1.7x [cite: 18] and significantly elevating the frequency of severe security vulnerabilities like XSS and insecure object references [cite: 19, 20]. Without proper guardrails, these autonomous agents readily generate illusory test coverage [cite: 21], creating a false sense of security while leaving critical business invariants exposed.

By enforcing strict behavioral testing paradigms [cite: 3, 4], leveraging network-level mocking via MSW [cite: 12], migrating to high-performance runners like Vitest [cite: 7], and utilizing property-based fuzzing to expose LLM logic drift [cite: 3], engineering teams can harness the immense velocity of AI generation while strictly quarantining its inherent defects. The imposition of Anti-Rationalization rules ensures that LLM agents adhere strictly to these patterns, preventing the degradation of software architecture through plausible but fundamentally flawed autonomous justifications [cite: 1, 2].

**Sources:**
1. [lobehub.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFkkRIN6yfgcfIfwWPatF_a4vXBJIL58MhX-H2WeM_bqyapbvR1nxjS46unZ2orwtWx37cCcgfx3ohMf5Br5A0y-FtuSVtNg6gltIoKfHWLAW7uOKUWtimLNEqawQLJAP-HeXZl-hBGpga3J8umyKibLZbUZ8zTLipFGw==)
2. [lobehub.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEruM_DW5G9pVX_weZzz_GoE2y7IV4ynWy4tnauqsvac4F0F__2Sgp4t4H4Bo0ukNHNbBLv0IJlNe9k6XFmGz5tFWGYjNAVcPqgi4D8i0A-Tmo1wnvX7mOQhkvsyLsHKL8t2idRGErrKxnbT05h-tqx8BrXM19KkGiG3moPnA==)
3. [reddit.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEIPdYfGe7VcuGi0rqUPrERQnhYFLIzEsGYu22rQ4ckBmNm24N0s0rGPun-UJl-5u6LnDqcmRBMbn9z8sV0ftiiUGht_lxpltmOt4tNTgJY6j7lwHWoKc4TVcsm0mgIzENNOEr2alMob6V7hP_DedMNoeFrxUGRnEbH85eZ8F0QjAwj3dnvHInGcGbhDn2XTy3UCZ_xL1ObJmcuoqZ0Rg==)
4. [github.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFuRhMaIjovezerc5tOf9jYb15SvCB0qzvF1yUOUYMAoGLXWx5mxIm3y8Lnhp9iy2dYJOv_RIV7ObhfAZ1Bb6SbOkJHM3ySwOkQ_N5HmXMfbXqJ)
5. [makersden.io](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFHFIY6cBWWa5n6eIjJVX0feg7PZm6pP8Hba-tYq1dEU76m7DIzJfdG06jjRSaAggCMID-toP_VJmt417DtayTG7YjfKcBBJkCilWjvWBZHe4Dn40RKxz-t9PGBpkZTc1abxeYcyBXk6YdeY08QOtYB9otZCDU=)
6. [makersden.io](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGHN7srT4JDxee2LhTAeuej7zSNNKkj3yl53vYxb-TepTySkdx8MRbFSZVWXQR8DQZSSCINUN44F_hm4GingGZ3tvbk-jptaCIRNEIBBMmiXk8e-ikQliDRccFlWdGFH3wSRfEa0Rlb40fgVQ==)
7. [betterstack.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHHJTMzaAaIBXVv7_EsAp9IbK2Dr57YaC8neYhh705n7HwrMXLcEZNUOTmBnXH0TYkCyLYHIBwkM7GFjaFAxj-hv_ojCmgKRSEblXi_eURQAYNtYstcfs0fpHiLtnT85n0b8hatBoBfYGkNxAd1MHpzFttzWhUu375LTT0IpA==)
8. [microsoft.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE55Rv2-Nutj4ujSLdvCxGAgkMOwANnKFB0uaGIajU60rvJcPPpU95elpuf7vjCuzjQmf4HRYs8fjlL9Shgh99sx67Qu0XWVWijxyMnoYTOtZ45W9V6drpLfFR9jSzcVRkSPcv02uCu6k8f4IsrlmepujHwr_Pk2ztEJrt2lHgVXzGmLmGmn03iy4VziQg=)
9. [mintlify.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQG9MRpJpVMu1ed087yl6ia07DzVO8xU8VKl4QEdalwF_Uhdyj7xA8wqqdeZwUzwilwHqGz7Ug255WiAA56FbEL1wD3oWckrByAwUoYWENrzlARTXdiOWnLIeuE4VcFJVQesKMoCfEvehYOugds24fULG62sF1nqLMAg)
10. [aemo.com.au](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFGetNI2bzPb4usYkj8LBNdcr9Gwa9WxdJoAdyCp3dxl6PKWRAWB6Cq_l0iwxc7VBbqF4wdGpqImeVy1ox7zb9fpt2ESVyFt9qH9AYdOrAZLHJDtqOn5TtRyjdBeaA=)
11. [isqua.ru](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEv2oNdox5DfwBSccb6zoLGIS2iU2apggGp_ihgddnw-1sMYrh11-VNEdZYreOW9nwNN4JsmKkrkF6EI2sC89rUiXlRohQyYy8agLBTokHVHxbZ2EYx_akRLdFVWGMJPyYM1Uuk4gOYzlg4CVRXZr-Io3pnmzE=)
12. [oneuptime.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE4PTidNy8Y8HWR4UjYj7bDiCoZzVauSf3cxQM23RIG3wseSqWZr1rtrIn-9wmnUafuA94AsI2Eo_gVMGgk6C59cChxFBHC-VbmFnJiGTUIsQPv1_jDvSV4KGz558yX_ztQgtOMqbwAJV1vM11R1t2zSoG_bhiDWZa0iwO-LvA=)
13. [stackademic.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEK6X5GQhcR9ABZ89V4FXrXMx4e_yg_kokJXfQ9WDEgE7Jg1eYl8Qy6I2Syjm5nz7rMrDVkDuAyMqOPyHJRtXKf1sTaFWYTTfrhxlL9-cROUbR4p5CJJeFiUW2IsSwd_BYLDQLqPECUJn6H3Bgkumu8XMoCMZOomHdvUGzHq88uI9End-oh2ZuL8wpb0HrRxgKng0T_2Fb_)
14. [codesandbox.io](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEVvP0gWvT9QfV1iIH9SfplCKWT9JWAUNx7xWUCjck_q9PPzu3PbTqUrKY69oZjYugIm_Oz1HBSNzXYCxy3CNhkpRCplO8PeXvRaAc5v-VFXIQj6Tob8W0iBcJsY6qc_YP1NEfPZ7lyQ7Ui__6syr9iaUg6hn1dulv70w==)
15. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEexRRflqzDgDmbFT_ifiFCkho7EDSbtZybQMIjSqsGBCt6FC5VQc4lMfPaVEPWcO9RlsKk1Bj2j1BnFYzr1yPjKP0FyxlfLkNJ-sydxv7Pfdw8PDpEj5yyFFpOKeYCNT2ql3aru8ybKTPF9FTzpzSERRmGLEtX0nmfJOw10kB3TZThbDptMhhlEuwQbbjQ1USWMGNFf1jaV_Y_EapaWQ==)
16. [techintelpro.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQF8Ng4_f76nLgaE17U0rRf5E-ty5JjPidav8QplpPCXE5tKCsdLM0ivLYpFg7GRPkfrfP3A9ekIIDKUXMC9cR4JVvhNRs92mjIJAwDQDfEksLZYpyF3HYHEIaAb1CSJMo4CFNDgzttZzLfoA2cjMIoYaCEuL2PwIGkByeOvX3fLyJ_VkSyoHHmcVvWyFZIhjNUwJ61GT9bx9ARsGKaL5Rrg)
17. [devops.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGcza6kNUjK_7ZgquZvB0kYqNyAAAZNu3673aC1cbgX7POcyVzwijmZu7gqxeCaeZIuzcFHggbLQgAQM1IP7WC0lcSPUfOEoPh3WztP17Zghefds5yeaOQQVFGT9X1XvDiKzPmdMp5FZ5B3fAVlnxwEx5-2A8mHFRIoXjft4jDtb59cQ3ErZJvl2BtXTqKpcp831LSSWg==)
18. [businesswire.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEcranMeUU3vHDvLrs7KCl1L8gyTwgJc4v_HN8fU2p0skk_8133DY2iXzIDB6KBphApUZiTcPlKYu5fOhYDuhb5bDanUVGzUvOtIeEmH8fVdPA5oZb9ptVQ5ybvEXfc50Gh2jc0vJ1Z3lPY7_quQORbRAunwnewnKFTRYEF6Cx0rBIEP95fdvDQZ85PYbLupJqLajCGOxqowE_nu6l0TsjOn8FCMCgYA1bjqjmkfNF_RKZw32dTioTDXTPWcs0W7gFClaRM1je5NMIDily1C5cMMvmTcETHzmZElPaF4RfWsDzlUILFbW080dBhVA==)
19. [bcianswers.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQH-d53eO7z6uGnvZReXv0Sg63JeTtDCorWE6VtFUJe-x3LiZEj4wSjMIq9ygrs9Tr6QAkNuvp6TuyoMR3giJQiObeFyGPn5wHv2TDnvWRfb_0S5l0mwH99wLPyp8ID3mIv3JnqIkls7esA7rgdExj-SNXcvmj3afb2anE4F2w3yhbPB2cr7ZUE=)
20. [theregister.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGAO5LZv3AW-UqhPniODceUyPOEHVI6GNVOMx56zg2zAQl6XaXwjSKSMV5Gp27z3CYu-oWuINL-NxSA6Mk_6skbYbySc7MZhvxh9HLxO-6stnlxJlnKFB9TYMcICn-9RJX7sv_eftmhe7Q8)
21. [lobehub.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFAbknaOqJ6F31sa8sTqokxoTLLYhjZpl-9xce55kk8GAwRjCxNMV4dvS9wDEAtKyELOGzNafNhqGKzcCQaDC_hQBSE7LmaSt2W25FIC9Cu1L1WyVaFiRLSR-jXaruR1OE1N9v9-Gv5W_h2IXHmShgZdaARdnZxSvqv_din)
22. [lobehub.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGHPu9GX0nSRgXKmg1xSaMrCcHzFGzhxz5uVW8q1SnzVQoS2zuU3-X8ra5-UgEQ9zQGTx9WFT8HLMbPu4EUyQRJHK_ZIuzkXSQEfdgQxJxl6PvlDTfAZ2ofi75uzIJOkYYMFxNy3fucvdB28Enp0GQKEm1yZDXas-9xEpJOVjQs)
23. [github.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGxpq68QlxOEfMFH7BfGj7zFlsdRFKnsfVgV1yZV_MR8gkce6lMVVCFPeIeYRLVpiq7-SaDsZJU-x47l8hidd-MlEUtxTu_mh2PaDjU1sNjnNM9h2hIjnn9i8KuKg==)
24. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEYPz__nQ7GTPG8UjW7kSP-zV_p-od8tlw6D8l5LKorrGduomUwyn1PeiX9NHyyDWduyDBLqUqGKqC1Wfr7AvKeS3r-E-OJbm8RMZVcBc5OuSfn0Y136apvHhdt2Id7EX_KPHJx8cgB3xNwMgGGqwm45Iis7QfzLTzvPUSk2XMFcE25vhpZ7q76kQ8PeyXpqD8TdsvmKg==)
25. [howtotestfrontend.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFe-i1p9GQinBZ740Ops6Fanc8D9Qx3BGMGX5drILp52Et_6qPQYlpno76uefJhEbdvGbqQPJoRYsgWQ7c5t0v9y7mpov0Zv1L8iTc6IIhcK9qGp-3tfxdLYIPgefYQO3VyvhJDstiyqebXkuyNIyJQpWTBH08x49xEDg==)
26. [generalistprogrammer.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEFluOuaV6_pw1FQ8PFWdWFLXyzBgQ1vFDF9NLJmLikhmRNIW076K6ySrobTpVCfPMEIqEsNkDcdy7TxnV3_52zVzUD_1zuklL9QPU5z3qXgTOJX4xGgaxGKYcgQOpbo7f4I_UYFpz0ySO8HXhALdhXYA==)
27. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQH9RrAy6VTfAp8HZJtfvfiLvmtrwlO3j9fKPljMECELXLvCpDEBUIh_0T5Sr2_x0FPM3z4P1ePBosUFIGqdUPWqNvkkbEOttlHyl9K_dBIQqgK1eIcMUvmUAnkFjyl1G9md9QJ8s0MfNQOHuCVRB1b6YqqBOMQZeDSOR0MqPB24sP22ofqnLhLeZlQyIA==)
28. [nucamp.co](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFYw2-uoW-3vUsBsJ_M_GOl6Oc-xPNkKl5OkajY6jrcQqqL2AuS7xNzjVCDQYaSWa-tkJCpSdkOQnGgdL0N1GgurJN70WJzS9j3gGM6AIhE2crtE6IOF2xCfFyNoD4czDlpqdlICJE_70OeEiMgi4uaNoWg48tDViYie5uYwQ26IWPAMqNFGWlCARCmAmXEAfJbuTcwuPIbSvK1sLuu)
29. [dev.to](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQF120F_mDMzTXUpXGFyf1yS1yrRcjqIWkcbPQrBCoWFfHwo0W_4q8iy5y-Mkt8Xla2P4CCKuxnxpOYNF_tFq3W50K1lhWGtectMIOoW0iJxbyG-RD5_gfcGJvtH6nBsT2YZE3WfSXVGaCyxdb19UZlwfxacJMApzktJjiVBKsth1YnSHy0gpaWi-O7fQoAf9zlSnmNwXbWKrA==)
30. [stackoverflow.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHknZC7i97qWmspf0BKGDsP6iiq3TAOAcDE87ay50TtLyLApEbpCGgpCB9kRTu_jp-LwbXtzRDyxKH10SkHg1ORAt-XN_y08B7-S4vH9Q_cx04NWX_eKtvRogp2LGXvW7_8Zry4jkxabxElWqs633TpxvoLIxy9mok4sgkxgsIA4y1cM0upmHepj8yvCrJU0p8yFz8=)
31. [reddit.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE9o6VYpEHzQ3rNJbi0-7lS9X4qlzwSudQqox8dtakiiYNIGK9QJCAhnTLqJBsvKRQ1iMFqzAKyYZJ2xCcRtcCAxLQ0X0UBrmsGtd-Tn9dRU-QcNFQzPvAOeUk8MmC9mg_9e1BvtnO5-kjEZgJ-WFcL-ZyuLrETDvjaZsk4YIPd09UNlQXsWFBesYArwrO_eQ4zFUvW8tRmn_whIz4RkNE=)
