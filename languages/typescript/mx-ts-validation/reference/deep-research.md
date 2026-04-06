# TypeScript Runtime Validation with Zod for AI Coding Agents: A Comprehensive Technical Reference

**Key Points:**
*   TypeScript's compile-time safety is entirely erased at runtime, making type assertions (`as`) on external data a critical security and stability vulnerability [cite: 1, 2].
*   Runtime validation acts as a necessary "trust boundary" between unpredictable external inputs (APIs, LLM tool calls, user input) and internal system logic [cite: 1, 3].
*   While Zod provides exceptional developer experience and robust schema definition, its interpreter-based architecture introduces performance overhead compared to compiled alternatives like ArkType or modular alternatives like Valibot [cite: 4, 5, 6].
*   The `z.infer` utility establishes a single source of truth, eliminating the dangerous drift between TypeScript interfaces and runtime validation logic [cite: 1].
*   AI coding agents exhibit a strong bias toward "just making it work" via `any` or `as` assertions; explicit anti-rationalization protocols are required to enforce rigorous validation [cite: 7, 8].

**Introduction**
The integration of Artificial Intelligence (AI) coding agents into software engineering workflows has accelerated development but simultaneously exposed a systemic vulnerability: the over-reliance on static type analysis for dynamic data. TypeScript provides robust structural typing during development, but this type system is completely erased at compile time [cite: 2]. Consequently, when an AI agent generates code that handles external data—such as API responses, environment variables, or LLM-generated tool calls—and utilizes the `as` type assertion, it effectively bypasses all safety mechanisms. This technical reference provides an exhaustive guide to implementing runtime validation using Zod, establishing strict trust boundaries, and enforcing anti-rationalization protocols to prevent AI agents from generating unsafe data-handling code.

**Scope of this Guide**
This document synthesizes best practices for schema composition, environment variable validation, and performance optimization using Zod. It further presents a comparative analysis of Zod, Valibot, and ArkType to inform architectural decision-making [cite: 9, 10]. Structured with BAD/GOOD code pairs and formal decision trees, this guide is designed to serve as both an instructional manual for human engineers and a rigid prompt-injection framework for AI coding agents.

## 1. The Danger of Type Assertions (`as`) on External Data

### 1.1 The Illusion of Compile-Time Safety
TypeScript utilizes a structural type system that provides excellent developer tooling and compile-time verification. However, these types do not exist at runtime [cite: 2]. When an AI coding agent or human developer uses the `as` keyword (e.g., `const data = input as User`), they are forcefully overriding the compiler's safety checks. This is not validation; it is an instruction to the compiler to stop asking questions [cite: 11].

If the external input deviates from the expected shape—a common occurrence with probabilistic LLM outputs, lagging client versions, or malicious payloads—the application will silently accept the malformed data [cite: 11]. This leads to catastrophic downstream failures that are exceptionally difficult to debug, as the crash occurs far away from the boundary where the data entered the system.

### 1.2 Tool Calls as Adversarial Boundaries
In the context of AI-driven applications, tool calls must be treated as adversarial boundaries. LLM outputs are inherently probabilistic [cite: 11]. If an LLM is expected to provide a JSON object matching `{ "limit": 20 }`, it may occasionally hallucinate and provide `{ "limit": "999999" }` or omit the field entirely. If the implementation blindly asserts this payload `as ToolCallArgs`, the database query utilizing this limit will crash or leak data.

### 1.3 BAD/GOOD Code Pairs: Type Assertions vs. Parsing

**BAD:** Relying on Type Assertions (Lying to TypeScript)
```typescript
// AI Rationalization: "The API documentation says it returns this shape, so I will just cast it."
interface CreateTicketArgs {
  title: string;
  priority: "low" | "high";
}

async function handleToolCall(rawInput: unknown) {
  // DANGER: Types are erased at runtime. 'rawInput' could be anything.
  const args = rawInput as CreateTicketArgs; 
  
  // If rawInput is { title: 123, priority: "URGENT" }, this proceeds silently.
  // The crash happens deep inside the database layer.
  return await db.tickets.create(args);
}
```

**GOOD:** Enforcing Runtime Validation
```typescript
import { z } from "zod";

// 1. Define the runtime schema
const CreateTicketSchema = z.object({
  title: z.string().min(1),
  priority: z.enum(["low", "high"]),
});

// 2. Infer the type (Single Source of Truth)
type CreateTicketArgs = z.infer<typeof CreateTicketSchema>;

async function handleToolCall(rawInput: unknown) {
  // 3. Parse at the boundary. If it fails, it throws a clear ZodError immediately.
  const args = CreateTicketSchema.parse(rawInput);
  
  // Now 'args' is guaranteed to match the CreateTicketArgs type at runtime.
  return await db.tickets.create(args);
}
```

### 1.4 Anti-Rationalization Rules for `as` Assertions
AI coding agents are heavily biased toward writing minimal code to satisfy the compiler [cite: 7]. The following rules must be explicitly injected into the agent's system prompt:

*   **Rule 1:** NEVER use `as Type` on data originating from an external source (API, user input, `process.env`, LLM tool call, webhook).
*   **Rationalization:** "The payload is already validated by the external system."
*   **Correction:** External systems drift. Treat all boundaries as untrusted (`unknown`). Use Zod to parse and narrow the type [cite: 11, 12].
*   **Rule 2:** The `as` keyword is only permissible when working around known TypeScript compiler limitations within deeply internal, tightly controlled business logic, and even then, must be scrutinized [cite: 13].

## 2. Zod `parse` vs `safeParse`: Performance and Implementation Strategy

### 2.1 The Architectural Trade-off
Zod exposes two primary methods for validating data: `.parse()` and `.safeParse()`. 
*   `.parse()` returns the validated data or throws a `ZodError` if validation fails.
*   `.safeParse()` returns an object: `{ success: true, data: T }` or `{ success: false, error: ZodError }`, avoiding exception throwing.

In JavaScript engines like V8, throwing and catching exceptions is computationally expensive. In performance-critical hot loops or scenarios where validation failures are expected (such as parsing user-submitted CSVs), wrapping `.parse()` in a `try/catch` block significantly degrades throughput [cite: 14]. 

Furthermore, Zod relies on a dynamic runtime interpreter rather than Ahead-Of-Time (AOT) or Just-In-Time (JIT) compiled functions. When `parse` is called, Zod recursively traverses the object graph and executes logic for each node [cite: 5]. To mitigate this overhead, schema definitions must be hoisted out of loops, and `safeParse` should be preferred when handling large volumes of data [cite: 15, 16].

### 2.2 Decision Tree: `parse` vs `safeParse`

1.  **Is the code inside a high-frequency loop (e.g., processing 10,000+ items)?**
    *   **Yes:** Use `.safeParse()`. Avoid `try/catch` overhead [cite: 15, 16].
    *   **No:** Proceed to step 2.
2.  **Is a validation failure an exceptional, unrecoverable system state (e.g., missing critical environment variables)?**
    *   **Yes:** Use `.parse()`. Let the application crash fast and loudly [cite: 17].
    *   **No:** Proceed to step 3.
3.  **Do you need to gracefully return validation errors to a client (e.g., HTTP 400 Bad Request form validation)?**
    *   **Yes:** Use `.safeParse()` to extract the `error.issues` and format a standard API response. Alternatively, use `.parse()` inside a centralized Express/Hono error-handling middleware [cite: 18].

### 2.3 BAD/GOOD Code Pairs: Performance Optimization

**BAD:** Reinstantiating schemas and using try/catch in a hot loop [cite: 14]
```typescript
function processLargeDataset(records: unknown[]) {
  const validRecords = [];
  
  for (const record of records) {
    // DANGER: Re-creating the schema inside the loop destroys performance
    const RowSchema = z.object({ id: z.number(), name: z.string() });
    
    try {
      // DANGER: Throwing/catching exceptions in a loop is extremely slow
      validRecords.push(RowSchema.parse(record));
    } catch (e) {
      console.warn("Invalid record dropped");
    }
  }
  return validRecords;
}
```

**GOOD:** Hoisting schemas and utilizing `safeParse` [cite: 14, 15, 16]
```typescript
// 1. Hoist schema to module level to avoid re-instantiation overhead
const RowSchema = z.object({ id: z.number(), name: z.string() });

// 2. Vectorize the operation using z.array() if possible, or use safeParse in loops
const DatasetSchema = z.array(RowSchema);

function processLargeDataset(records: unknown[]) {
  // Option A: If we want to drop invalid items individually without throwing:
  const validRecords = [];
  for (const record of records) {
    const result = RowSchema.safeParse(record); // Fast, no exception thrown
    if (result.success) {
      validRecords.push(result.data);
    }
  }
  return validRecords;
}
```

## 3. Schema Composition Patterns

To maintain Don't Repeat Yourself (DRY) principles, Zod provides an extensive API for composing, extending, and mutating schemas. AI agents frequently fail to utilize these utilities, instead opting to write massive, duplicated schemas.

### 3.1 Core Composition Methods

*   **`.extend()`**: Adds new fields to an existing object schema. Preferred over `.merge()` for performance reasons [cite: 15].
*   **`.merge()`**: Combines two object schemas.
*   **`.pick()` / `.omit()`**: Creates a new schema by selecting or discarding specific keys, directly mirroring TypeScript's `Pick` and `Omit` utility types [cite: 2].
*   **`.partial()`**: Makes all properties in an object optional.
*   **`.transform()`**: Modifies the parsed data (e.g., converting a string to a Date).
*   **`.refine()`**: Adds custom validation logic that cannot be expressed via standard types (e.g., checking if `password` matches `confirmPassword`) [cite: 17].
*   **`.coerce`**: Automatically casts primitive values (e.g., turning the string `"42"` into the number `42`), which is highly useful for URL query parameters or `.env` files [cite: 19].

### 3.2 BAD/GOOD Code Pairs: Schema Duplication

**BAD:** Duplicating schemas for CRUD operations
```typescript
const CreateUserSchema = z.object({
  name: z.string(),
  email: z.string().email(),
  password: z.string()
});

// AI Rationalization: "I will just copy the fields for the update schema and make them optional."
const UpdateUserSchema = z.object({
  name: z.string().optional(),
  email: z.string().email().optional(),
  password: z.string().optional()
});
```

**GOOD:** Leveraging Composition
```typescript
const BaseUserSchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
  email: z.string().email(),
  password: z.string(),
  createdAt: z.date(),
});

// Derived Schemas
const CreateUserSchema = BaseUserSchema.omit({ id: true, createdAt: true });
const UpdateUserSchema = CreateUserSchema.partial();
const UserResponseSchema = BaseUserSchema.omit({ password: true });

type UserResponse = z.infer<typeof UserResponseSchema>;
```

### 3.3 Advanced Coercion and Refinement
When dealing with HTTP `GET` requests, query parameters are always strings. AI agents often attempt to use `as` or `parseInt` manually. `z.coerce` is the strictly typed solution.

```typescript
const PaginationQuerySchema = z.object({
  // Coerces string "20" to number 20, defaults to 20 if missing
  limit: z.coerce.number().int().min(1).max(100).default(20),
  page: z.coerce.number().int().min(1).default(1),
}).refine(data => data.page * data.limit <= 10000, {
  message: "Pagination exceeds maximum fetch depth of 10000 records",
  path: ["page"]
});
```

## 4. `z.infer` for Type Derivation: The Single Source of Truth

A prevalent anti-pattern among developers and AI agents is defining a TypeScript `interface` and a Zod `schema` separately. This creates a state of architectural drift: when a field is added to the interface, the developer forgets to update the schema, leading to a system that believes it is safe but is entirely exposed at runtime [cite: 1].

Zod natively resolves this via the `z.infer<>` utility, which extracts the exact TypeScript type directly from the schema [cite: 1, 2]. 

### 4.1 BAD/GOOD Code Pairs: Source of Truth

**BAD:** The Two-Source Anti-Pattern [cite: 1]
```typescript
// 1. The interface (Typescript land)
interface Order {
  orderId: string;
  amount: number;
  status: "pending" | "shipped" | "delivered";
}

// 2. The validator (Zod land)
const OrderSchema = z.object({
  orderId: z.string(),
  amount: z.number().positive(),
  status: z.enum(["pending", "shipped", "delivered"])
});

// When 'discountCode' is added to the interface, the schema is forgotten. The contract is broken.
```

**GOOD:** The Single Source of Truth [cite: 1]
```typescript
const OrderSchema = z.object({
  orderId: z.string(),
  amount: z.number().positive(),
  status: z.enum(["pending", "shipped", "delivered"])
});

// The type is derived. They can NEVER drift.
type Order = z.infer<typeof OrderSchema>;
```

### 4.2 Anti-Rationalization Rules for Interfaces
*   **Rule 1:** If a data structure crosses a system boundary, NEVER write a manual TypeScript `interface` or `type` alias for it. 
*   **Rule 2:** Define the Zod schema first, then immediately export the inferred type using `type X = z.infer<typeof XSchema>`.

## 5. The Trust Boundary Pattern

### 5.1 Architecture: Validate at the Edge, Trust Downstream
The core philosophy of runtime validation is the "Trust Boundary" pattern. A trust boundary is anywhere data enters your system from the outside: API requests, database reads (if the database is mutated by other applications), file parsing, user form inputs, and webhook payloads [cite: 1, 3].

The rule is strictly binary:
*   **Untrusted Data (Left of the wall):** Treat as `unknown`. Must be validated using Zod [cite: 1, 12, 20].
*   **Trusted Data (Right of the wall):** Once parsed, data flows into internal functions. TypeScript is now sufficient. Do not re-validate data internally [cite: 1, 14, 20].

Think of the edge handler as immigration control for your data. It checks the passport (validates the shape). Everything past that checkpoint can safely assume the entity is who they claim to be without re-checking the passport at every internal door [cite: 3].

### 5.2 BAD/GOOD Code Pairs: Trust Boundaries

**BAD:** Implicit trust and redundant internal checks
```typescript
// AI Rationalization: "Req.body is typed by Express, so it's safe."
app.post("/users", async (req, res) => {
  // DANGER: Express types req.body as 'any'. We are implicitly trusting the internet.
  const userData = req.body; 
  
  // Internal service is forced to do manual sanity checks
  const user = await createUserService(userData);
  res.json(user);
});

async function createUserService(data: any) {
  // Redundant, poorly typed manual validation deep in the system
  if (!data.email || typeof data.email !== "string") throw new Error("Bad email");
  return db.users.insert(data);
}
```

**GOOD:** Hard boundaries with `unknown` [cite: 12]
```typescript
const CreateUserSchema = z.object({
  email: z.string().email(),
  name: z.string()
});
type CreateUserDTO = z.infer<typeof CreateUserSchema>;

// 1. Edge Layer (Immigration Control)
app.post("/users", async (req, res) => {
  try {
    // Force the boundary to be 'unknown'
    const rawBody: unknown = req.body;
    
    // Narrow 'unknown' -> 'CreateUserDTO'
    const validatedData = CreateUserSchema.parse(rawBody);
    
    // Pass strictly validated data to downstream internal services
    const user = await createUserService(validatedData);
    res.json(user);
  } catch (err) {
    res.status(400).json({ error: "Invalid payload" });
  }
});

// 2. Downstream Internal Service (Trusted Zone)
// Relies purely on TypeScript. Zero runtime validation overhead here. [cite: 3, 20]
async function createUserService(data: CreateUserDTO) {
  return db.users.insert(data);
}
```

## 6. Zod for Environment Variable Validation (`dotenv` Pattern)

Environment variables are strings injected at runtime. By default, Node.js types `process.env` as `Record<string, string | undefined>`. Accessing variables via `process.env.DATABASE_URL` throughout the codebase guarantees runtime crashes if operations ops forget to provision a key [cite: 19, 21, 22].

Zod must be used to validate environment variables at application boot. This provides IDE autocompletion, instant fail-fast behavior on missing keys, and automatic type coercion (e.g., parsing the string `"3000"` into the number `3000`) [cite: 17, 19, 21].

### 6.1 The Complete `env.ts` Pattern

**Step 1: Define the Schema and Parse (`src/env.ts`)**
```typescript
import { z } from "zod";
import dotenv from "dotenv";

// Load variables from .env file into process.env
dotenv.config();

const EnvSchema = z.object({
  // Must be a valid URL
  DATABASE_URL: z.string().url(),
  
  // Enforce specific environments
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  
  // Coerce string to number, enforce port boundaries [cite: 17, 19]
  PORT: z.coerce.number().min(1).max(65535).default(3000),
  
  // Boolean coercion from string
  ENABLE_FEATURE_X: z.enum(["true", "false"])
    .transform((val) => val === "true")
    .default("false"),
});

// Parse process.env. If this fails, it throws immediately at boot.
// This prevents silent failures deep in the application. [cite: 17]
export const env = EnvSchema.parse(process.env);

// Export the derived type for utility usage
export type Env = z.infer<typeof EnvSchema>;
```

**Step 2: Utilize throughout the application**
```typescript
// BAD: 
// const port = process.env.PORT; // Type is string | undefined

// GOOD:
import { env } from "./env";
// env.PORT is strictly typed as a `number`
// env.DATABASE_URL is strictly typed as a `string`
app.listen(env.PORT, () => {
  console.log(`Listening on ${env.PORT} in ${env.NODE_ENV} mode`);
});
```

### 6.2 Anti-Rationalization Rules for Config
*   **Rule 1:** NEVER access `process.env` directly in business logic. 
*   **Rule 2:** All environment variables must route through a centralized, Zod-validated `env.ts` file. 

## 7. Ecosystem Comparison: Zod vs Valibot vs ArkType

As the TypeScript validation ecosystem has matured, alternatives to Zod have emerged to address its limitations, specifically regarding bundle size and runtime throughput. Choosing between Zod, Valibot, and ArkType requires analyzing the specific architectural constraints of the target deployment environment [cite: 4, 9, 10].

### 7.1 Zod: The Industry Standard
*   **Strengths:** Massive ecosystem adoption, unparalleled Developer Experience (DX), extensive third-party integrations (tRPC, React Hook Form, OpenAPI generators), and excellent documentation [cite: 4, 9].
*   **Weaknesses:** Large bundle size (~50-64 KB minified/gzipped), making it heavier for strict frontend performance budgets. Interpretation-based runtime engine makes it significantly slower than JIT-compiled alternatives (executing ~5M-6M ops/sec compared to competitors' 70M+ ops/sec) [cite: 5, 9, 23, 24].
*   **When to use:** Server-side Node.js applications, standard React/Next.js applications without extreme mobile bundle-size constraints, and any project utilizing tools that natively expect Zod schemas (e.g., tRPC) [cite: 25].

### 7.2 Valibot: The Modular, Tree-Shakeable Alternative
*   **Strengths:** Designed around modular, functional composition. Instead of a large class with chained methods, Valibot relies on pure functions. This allows modern bundlers (Webpack, Vite) to aggressively tree-shake unused validation logic, resulting in bundle sizes as small as ~5-12 KB [cite: 4, 9, 26].
*   **Weaknesses:** Functional API can be slightly more verbose than Zod's chained API. Slightly slower than ArkType on raw throughput, though highly optimized for cold-start and bundle metrics [cite: 27].
*   **When to use:** Frontend applications targeting rural mobile networks, Edge compute environments (Cloudflare Workers) where cold-start times are critical, and highly constrained serverless functions [cite: 4, 9, 15].

### 7.3 ArkType: The High-Performance JIT Validator
*   **Strengths:** The absolute fastest runtime performance via Just-In-Time (JIT) compilation using `new Function(...)` to bypass recursive call-stack overhead [cite: 6]. Definitions mirror native TypeScript syntax strings 1:1 (e.g., `type("string.email")`), resulting in 50% shorter schema definitions [cite: 10, 25].
*   **Weaknesses:** Larger bundle size than Valibot (~38-44 KB) [cite: 23, 28]. Newer ecosystem, meaning fewer native integrations compared to Zod [cite: 25].
*   **When to use:** High-throughput backend systems validating massive payloads (e.g., 500,000+ objects per request) where Zod's interpreter causes CPU bottlenecks or Out-Of-Memory (OOM) crashes [cite: 6, 29].

### 7.4 Standard Schema Interoperability
To avoid vendor lock-in, developers should leverage the `Standard Schema` specification interface. This allows APIs to accept Zod, Valibot, or ArkType schemas interchangeably, enabling teams to start with Zod for its ecosystem and swap to ArkType later if performance bottlenecks arise without rewriting route definitions [cite: 4, 9].

## 8. Master Anti-Rationalization Protocol for AI Agents

To ensure AI coding agents produce secure, robust code, the following directives must be placed in their system prompts to pre-empt common AI rationalizations [cite: 7, 8, 30].

**Table 1: AI Anti-Rationalization Matrix**

| AI Rationalization / Excuse | Why it is WRONG | Required AI Action |
| :--- | :--- | :--- |
| *"The external API docs say it returns this exact `interface`, so `as` is safe."* | Docs lie. API versions drift. `as` is erased at runtime and causes fatal system crashes [cite: 1, 2]. | Use Zod. Define the schema, use `safeParse`, and handle the failure case gracefully. |
| *"I already wrote the TypeScript interface, I don't want to write a Zod schema too."* | Double-entry bookkeeping guarantees architectural drift. The interface will inevitably mismatch the schema [cite: 1]. | Delete the manual interface. Write the Zod schema and export it using `type X = z.infer<typeof XSchema>`. |
| *"I need to validate an array of 100,000 items quickly, I will use `try/catch` and `Zod.parse`."* | Exception throwing is extremely slow in V8 engines. It will block the event loop [cite: 14]. | Hoist the schema out of the loop and use `.safeParse()` to avoid exception overhead [cite: 15, 16]. |
| *"I only need the 'id' field, so I'll just check `if (data.id)` and cast it."* | Shallow validation allows nested malicious payloads or incorrect data structures to bypass security [cite: 11]. | Define the exact expected structure. Use `.pick()` on an existing Zod schema to extract just the `id`. |
| *"I'm just reading `process.env.API_KEY`, it's faster to check it inline."* | Scattered `process.env` checks cause applications to fail deep in the execution tree when a variable is missing [cite: 17, 21]. | Route all environment variables through a single `env.ts` file validated strictly by Zod on application boot [cite: 22]. |

**Conclusion**
For modern software development, specifically in environments augmented by autonomous AI agents, static typing is a development tool, not a security boundary. By strictly enforcing runtime validation via Zod, establishing clear trust boundaries at system edges, and aggressively rejecting the use of the `as` keyword on external data, engineering teams can close the gap between compile-time assumptions and runtime reality. Whether optimizing for DX with Zod, bundle size with Valibot, or throughput with ArkType, the fundamental principle remains: Validate once at the edge, and trust everywhere downstream.

**Sources:**
1. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFNBcARxw46hUW33gJb1NVkRf7v1oQ7XLcXd_Vhy2NYggFJVdu9sJrAyRKSST8dlfP7YloGsjBENZRP3x5L2ZMEDnNUvNGgsgydl29RtnKl1PaC7EbWWBVaIcMYPaV1rmkIGFd5T4yU51VXW5GKiGcseB0jLFtluQeslnY-beAms8mJQMzW3FGzbWxQmQ6J8JxWisMT)
2. [dev.to](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHZZCPBHaYx0XBTjuHukYnV7auMud4tsP1Yfvg9R2sTcHvUvEjybiYp8hYK-81-nP0lzOsjOqYxyfIZnR2bnDNPNBKhZCdyYC9huWve0cZE-V2VSfO2Jv8YrAZnE64PldN4uEqBepDyPzo05133z2P91UQ0mGqwz7DNA82w6AuP8P93-s57clHjGu6u0qzAiQ==)
3. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHx4rDiX_a8DutAfv4ScECAjBnmn930xuztHq2Mps8L1Ipd4bziXl8e8ij8LoTfwhnKq86avhhjtBdttgGWPwU4C5l6QcoHpNAAW_Q3avRPq_Rd5OIvtg3hUOnGwlNOshBi-MmjkGcja4KYFgQlsxJO819RfewvNzHgaFqm7lHm-CNOllIKmKcU1lhjxQAD3uh7sbbN-7qkUFCI3_2PM1_IiI-1MyznS_U=)
4. [mintlify.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE-2hrhu_HRnEW42MHL-kCwW7nsTs7j2XAfrwy-NKCpfEtoORgOsIjDnyLqHlJsjMWmmsEXNj6T5UyeYO_THoo9P3VAzXz196tLyhKqmtpvEjGbClMeH67YrfUPH01B8Tof8igFeyo6hFov-ORsDgEd4ZuA3BjKGMmwvY_gPg==)
5. [logrocket.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQExZsjgjJyOWp8bNrrqi691ce6twlvB8UqrPJS91C65hSl9kMVXWf2IzXJ_UwBrIsKCXMoWOUqEaLOGGu9efjspEd1G7GQ_fYkjEQw7giFkXKMDRspruSJTDnDgCqVh)
6. [substack.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEyI584ij3gsympq8vgwIfXArySExIyG6r2aJD9qkgPNvG3rudlib_yomh16_6H7zo_T6BXPTgR6cPCN1Otv133l1Jf45CJAyPmFTL2kZG4aLOunBmG5Y0EHYMT9aedhWhAhRGku2imrnLFk2TdYc4ZeJTpqclc)
7. [github.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGIBsBgGttYFrZzB2E4vniLVKryPa6WaWNbOInkSsN8NeXTQZm3uR2vKpKtxDciKiin7GUq_M3JZK4xT0XISXkWbjzNo0hHP1ENOZmRmC7IloMig7bPYK9xqSTlAeS-tiNAsWw5yc2IQ9fJ80_kROlY-Ubl5VrysybvAiDz)
8. [lobehub.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFNbhPz0joyrHkHJEebF9pIAw5z8okQ8i9OtWSUkPJiox5QUPGN07QiL7PwljiL2cj_amy365yjnn3opvfQVJd2R95yR_scu2qygo338a-1ZA_RbQTYR6K1xsQwe_ELbQO0vY5qLMciJ0TNWOV_H5g3CkeR26RSfDRn6DBLyIJcmFxRQvE23YLM7sSRr84=)
9. [mintlify.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFsCkoGGpHQdflX4PNQa4V_rwOon0hFaXMoCdPM49UGswmJZA5uvHartnWWSRLGkiDeQ3Pv_N8zrDjPAkMLe4q8Hy2WEhkzH6n-4hSENAZdxFjkP8AHpFznN97bHHwvH_PWhZg7xlWdrmufcz7wJzld-J_AWBE5KgJB)
10. [mintlify.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFR9N0pQaFXWjueZMg6qg-lA5oBs08ZpRr9TNOgi8lfP3eGZJBZK-DDO-JLWue3tY1KMe6iAgsyfgHn6fbIFzhm3jSBq-8VZp1MCT0eN6boNPAuW2Hy83chZI4MJ3BjKJ2Ughvfy7zwfKZk29dwX6BFf7491oFcd4mhc9fu172a)
11. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHyU56FHYUNV7usMFfQDCQXthGccQHJEJqRpn-lduVLzY2q3oBr9CVQW-WUiXFn-H4N5mLvYdYkXPciqRs5T1f__yYNFfMphlpoOEFiVTnjVZYU-7KsuENTK9U3CBhug_FERQs5MSTii7agIGwLWBig8OFCBaFZQfQvHvoqs7icpoWcAcYxsU6hNKNMKG4uBWN6-X1F5_zAP3mxqq7FSTv4XlViSf4=)
12. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFHFeCe4ZPL734lFc8gVelLVxpwcpBraSIy03s5nkSHxh9QDEBH_l2-r90R-RdK_Sw9LDSh9DPm9UUNVaeEklDZyHaqr9q1SQy7o33TXMSYFDalfGFG_vB6AhpSJrDhQrxsIDledQ3aN-7K5s6N4A5OfO95TsZ-AsLxrE6zgyqamF3su1dMzFk0b7N9JTgbP3jeT7EWXweMF40hi3bNHz_s-Qo3Eg6YV6hCRP9ZpdR5vw==)
13. [reddit.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHcrofaO83EZ5Di6c8ZVY7z58Zxl1zW0smlfHFBsg2EAGFyaOSp5tqjaLk7RdYFHkYXH0lyU6IILHnbuj0rlS44WPg7PaKvamnKXc16tac5nWl1Sxz0RgnaJBSE-422KJRC8X2gk8Dmxpg7bFDLUkfnc-t-M5P67wDVkrIJuyYaBQaR7PTRl2XPWY8X0x78WkbT_MvmRyPls7R9yaCl2g==)
14. [stevekinney.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFfCLsEG-5FaUlswom3khiTyTNKEBFmpsTMHUEy90vHnMb773zMeq-hJVux_oWeKA1Ki-_T3WeLYDA5SLfaYuBeLmm2amSxgEHWcymHu-94e1axxK_J2XRt6cnCnjZOpwW6y1fsGo8ckMLO_m9WJqc7UFTZ1M7Jp65uIzkPEv8=)
15. [mintlify.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQG6Z0aXuKUykCo4VsPPzvdvkg8pyjK99fRW8BW93JFsws0MqLZ1zaHDah55WSlWh9XFUtSsVuXoPqWGeGqLk91lfj8yXep4aA9sm0umIrriNQs5zIxOsqMnf1041UWUXIoHygsl_Ot-lc7Wxs5cZQ==)
16. [mintlify.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFaWs-cYFmnDKsZFaKBdOMwjZeZo5AUm5KdpvyFMgVAmbe_dCk-EXgan6piI-dgEk1pKMAyWyCzEXiwGvN18DPzqSr51onYGTp5FFJr8uOS6TOu5IttypFVUhuro-3_w2MmL4xJxGNwo3zNsjbPPoM5n7M=)
17. [dev.to](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHCXzam0ZYZJuMZIrBAgP5NMgCMkTzDwX3g-ih-MzagRmGQPVG0dE6fML_wnNxZBad2LD-LiGLNo49AagJPBR6iqMoLotQwNQ4De9sg87tOlaDtcgAOkTQBXC26ic-Cm38jshMfqQq-g93EYRyx2f0SqAalz20JdKREkrrHHGDLbyw5BjD_9oS_G2F5gj0AWQ==)
18. [codesignal.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEeLy4lhGwh4Bd_UBA4TD67NJULrcNc5OZBuGowfkVeKV-h12EVSXdpYoN2GT9u711S0VfPut6Zz5XxIiYfwNAlXx3g224my5IEtsEJ9H8jsj2LA5M8z7yKUMg6VvBnPvMM2O4pT_LFW5gXhNWfJpSyZuR1c9kqkJOWGfU3rcJuHSv2_DwCCc80PtrPeeyhJZ-IRAMgWDhPVVdx3xvL9goAPvuOC0Ir8FeK20ZTO1aKI8hgqAS1CmKloaP8b9U4UoHS)
19. [youtube.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHKNc_dWb1543BDP0Pa0gc8wOK1Vzpb6MfTr2OJ6c6Nj_rWlv0LYW5QDjZauS53004IbnoqbTK2MniKy22NQFVRVoGo7LFxAP7McrP2jim67yELIB0IgEMfFu2ygbOInRe8)
20. [logrocket.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE33b9A6YTYqE3VzBTFA4FuYKF6Ct3odTLFzKXuhxIJZlaJDJ2XYKjKZ1ZFSGnZ8URaekDthtlt_ANFtJ3VbasY_jfnzZsxjPh9ub66TMfElLOdSgXhIPpkhqCHrqpR47MrAZUuQFrB3BTfmdj1GcAVdV_VP4lhd-Tf9n3LX66M)
21. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGg1RsF9Yq-UBuPxR_QqG-UIJWhHDkmd3F1TIvbyPTHkXLteiz80NgC3iqC2whWM4CtyaENECadcTgFUgq_DyZwPOzgqhPYVqug105w_TnlO3ZqFa8Yh4rWiKcWbP9tZFSIz1JB-Ip2nDjh3-gdAYE2gBPch6zkchwGST-20Ng0Or4uRJvrVsiTByaMQyKKDMZeYMUUhOjZkboA_Ya-ZuHeX6o=)
22. [creatures.sh](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHhgbGcyvI3GKwkh0UORVX-4DQE7BSIVIVTtfNF0Gerkk-q4O7Go88LqwU293OyRqPO3xLs_S24_Ni-bvPgCETe_14tPMjDXMJRJhUZQTiQqyFcfCvEV8bE2wvXYfX7jZs4tgDpiIORIEjFW3_Dd84NXDjE)
23. [ycombinator.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGHFGC3VKyneXlOEn1NST7_YXLNL87NuBlNeQm5p7SwAd3PxDlC5OvbjfrmvB3P0fPfiHIDhsQAO8xnFtkNnQ6LnL_Yv_F-2RiWhXV_lrKwPBwDBHJllhOjJUzaGiypuuCt6nc=)
24. [ycombinator.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEFMcvgY8sTf7waiFBpQTGEcLPik5j_I7XjWHc4ujPp-shOXeiSuOIYQOr7rPAHbrsP_ysVm_x3xEi7wJsF_6xbY-wcgYNWrXgbC_7LtyZYulUUvp7joLO6zpfXv0ggDAJhfbI=)
25. [reddit.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHR7sOmYo66PHYf_6Me9fDWKWhjFCFqhkVjvP8_Yrxv7rDARaf7SJz8Lujc2PFqSJGX_yx20tNNirOvFK7dSHqDijXW-pSYdTXmkYMOo9ZZ9IkaAqhzl7u1jXtXSCVTm4NIIKSNmrRD-Omn171Zckto_SQNu9QXvJXxEUkkFWK4JeW0fqKaUyNEzjTU5yJ7OsJdj5EQcZzSf-FM3Q==)
26. [valibot.dev](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHnw3LSoRxBk7s6coBH2mGnTBYB4LFRnxdOEHQYmd4FaokAV5mwJKMBT79VtkZcaelniYpYkoaSEf3OwdbrUcCl3vCHBcubXU4-0ZzagOhlnjkKYb8=)
27. [github.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE8qYaq5rJlN5PpqPHOY0TMl0Pycz1EMe3ynT8UseZv9Io7AoA6zePt-pRqKGiZh9KhC1AjII7UgNwdqnx6FD2jbTlY8CHIZCaJpZyGS-2_mIPzEBDQPNhjvXxMShCMR6BbuHRRfpE04g==)
28. [pkgpulse.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGhtynq-O4QTYDUGHqTxi0WsE2OzCBj6azlLZjV0vbl7K0CbEfyUf7cdqIndVz7s59fKjpBUW-MhTiXjmVKM_bP5QvGfnjEzOe4UGj1TitAvSAQA9MiEmzWbjNUXhp4mWPpHGnHGu6_TBw=)
29. [github.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHbTZ9FvWXox3YCg3kBaztTHSgF6GTjESP1kFfCUsP7aIiu7Q28zq-C2xu7COWmjIIk0GJCOpIm3ditBNpGKue_0KE2BIT-5-Hm5F1g8rBbnLd-BDrF4g5UMkqvCtPu2yvQOtY=)
30. [lobehub.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFts5SuKtTo-BPIZJ_BBKEzF9mApP46vWOrHdXgB-E42OZJ5r_HwsSZMM6KwG2rck02ThdEInTo32GSysaO0ZFQPJbhKO6ZTGdg8S1mEGwPKKzb-3l9VkAaYUxFB-oSIc3esJpkA7jOwdsDDx4LUwtAj_nyNnBOcYNzq2U=)
