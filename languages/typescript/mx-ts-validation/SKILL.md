---
name: mx-ts-validation
description: Use when handling external data, API responses, user input, form validation, or environment variables. Also use when the user mentions 'Zod', 'validation', 'parse', 'safeParse', 'schema', 'as type assertion', 'runtime validation', 'trust boundary', 'external data', 'API boundary', 'form validation', 'env validation', 'Valibot', or 'ArkType'.
---

# TypeScript Validation -- Runtime Data Safety with Zod for AI Coding Agents

**This skill loads for external data handling.** It prevents: using `as` on API responses, trusting external data without validation, duplicating types and schemas, and skipping environment variable validation.

## When to also load
- Core types --> `mx-ts-core`
- Node.js runtime --> `mx-ts-node`
- Testing validation logic --> `mx-ts-testing`

---

## Level 1: Parse Don't Assert (Beginner)

### Why `as` Is Dangerous

TypeScript types are erased at runtime. `as` does not check anything -- it tells the compiler to stop asking questions. If the data doesn't match, the crash happens far downstream, not at the boundary where it entered.

**BAD:** Lying to TypeScript with `as`
```typescript
// "The API docs say it returns this shape, so I'll just cast it."
interface User { name: string; role: "admin" | "viewer"; }

async function getUser(id: string): Promise<User> {
  const res = await fetch(`/api/users/${id}`);
  const data = await res.json();
  return data as User; // DANGER: zero runtime checks
  // If API returns { fullName: "Alice", role: "ADMIN" } --> silent corruption
}
```

**GOOD:** Runtime validation with Zod
```typescript
import { z } from "zod";

const UserSchema = z.object({
  name: z.string(),
  role: z.enum(["admin", "viewer"]),
});
type User = z.infer<typeof UserSchema>; // Single source of truth

async function getUser(id: string): Promise<User> {
  const res = await fetch(`/api/users/${id}`);
  const data: unknown = await res.json();
  return UserSchema.parse(data); // Throws ZodError immediately if wrong
}
```

### z.infer: Single Source of Truth

Never write a TypeScript `interface` AND a Zod schema for the same data. They will drift.

**BAD:** Two-source anti-pattern
```typescript
interface Order { orderId: string; amount: number; status: "pending" | "shipped"; }

const OrderSchema = z.object({
  orderId: z.string(),
  amount: z.number().positive(),
  status: z.enum(["pending", "shipped"]),
});
// When "delivered" is added to the interface, the schema is forgotten. Contract broken.
```

**GOOD:** Schema-first, type derived
```typescript
const OrderSchema = z.object({
  orderId: z.string(),
  amount: z.number().positive(),
  status: z.enum(["pending", "shipped", "delivered"]),
});
type Order = z.infer<typeof OrderSchema>; // They can NEVER drift.
```

### parse vs safeParse Decision Tree

| Question | Answer | Use |
|----------|--------|-----|
| Inside a hot loop (10K+ items)? | Yes | `safeParse()` -- avoids try/catch overhead |
| Failure = unrecoverable crash (missing env vars)? | Yes | `parse()` -- fail fast and loud |
| Need to return errors to client (HTTP 400)? | Yes | `safeParse()` -- extract `error.issues` |
| Internal data you already validated upstream? | Yes | Neither -- trust the type, don't re-parse |

**Rule:** `safeParse()` is MORE performant than `parse()` + `try/catch`. Exception throwing has real overhead in V8.

---

## Level 2: Schema Composition & Boundaries (Intermediate)

### Composition Methods

| Method | What it does | Use when |
|--------|-------------|----------|
| `.extend()` | Adds fields to object schema | Preferred over merge for performance |
| `.merge()` | Combines two object schemas | Merging schemas from different modules |
| `.pick()` / `.omit()` | Select/discard keys | CRUD variants from base schema |
| `.partial()` | All properties optional | Update/patch operations |
| `.transform()` | Modify data after validation | String to Date, normalize casing |
| `.refine()` | Custom validation logic | Business rules (password === confirm) |
| `.coerce` | Convert input types | Form data, query params, env vars |
| `.passthrough()` | Allow unknown keys | Forwarding payloads you don't fully own |
| `.strip()` | Remove unknown keys (default) | Cleaning untrusted input |
| `.strict()` | Error on unknown keys | Catching typos in config |

### Schema Composition for CRUD

**BAD:** Duplicating schemas
```typescript
const CreateUserSchema = z.object({ name: z.string(), email: z.string().email(), password: z.string() });
// Copy-paste all fields, make optional... guaranteed drift
const UpdateUserSchema = z.object({ name: z.string().optional(), email: z.string().email().optional() });
```

**GOOD:** Derive from base
```typescript
const BaseUserSchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
  email: z.string().email(),
  password: z.string(),
  createdAt: z.date(),
});

const CreateUserSchema = BaseUserSchema.omit({ id: true, createdAt: true });
const UpdateUserSchema = CreateUserSchema.partial();
const UserResponseSchema = BaseUserSchema.omit({ password: true });

type CreateUser = z.infer<typeof CreateUserSchema>;
type UpdateUser = z.infer<typeof UpdateUserSchema>;
type UserResponse = z.infer<typeof UserResponseSchema>;
```

### Coercion for HTTP/Form Data

Query params and form data are always strings. Don't manually parseInt -- use `z.coerce`.

```typescript
const PaginationSchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  page: z.coerce.number().int().min(1).default(1),
}).refine(d => d.page * d.limit <= 10000, {
  message: "Pagination exceeds max depth of 10,000 records",
  path: ["page"],
});
```

### The Trust Boundary Pattern

A trust boundary is anywhere data enters your system from the outside. Validate at the edge, trust downstream.

```
  UNTRUSTED (unknown)          BOUNDARY (Zod parse)          TRUSTED (typed)
  ========================    =======================    ========================
  API responses                parse() / safeParse()      Internal functions
  User form input              at route handler            Service layer
  process.env                  at app boot                 Business logic
  LLM tool calls               at tool executor            Database writes
  Webhook payloads             at webhook handler           Event processors
  File uploads/CSV             at ingestion layer           Transform pipeline
```

**BAD:** Implicit trust, redundant internal checks
```typescript
app.post("/users", async (req, res) => {
  const userData = req.body; // Express types this as 'any'. Trusting the internet.
  const user = await createUser(userData);
  res.json(user);
});

async function createUser(data: any) {
  if (!data.email || typeof data.email !== "string") throw new Error("Bad email");
  return db.users.insert(data); // Manual checks are incomplete and scattered
}
```

**GOOD:** Parse at edge, trust downstream
```typescript
const CreateUserDTO = z.object({ email: z.string().email(), name: z.string() });
type CreateUserDTO = z.infer<typeof CreateUserDTO>;

// Edge layer -- immigration control
app.post("/users", async (req, res) => {
  const result = CreateUserDTO.safeParse(req.body);
  if (!result.success) return res.status(400).json({ errors: result.error.issues });
  const user = await createUser(result.data); // Validated data only
  res.json(user);
});

// Internal service -- trusted zone. Zero re-validation.
async function createUser(data: CreateUserDTO) {
  return db.users.insert(data);
}
```

### Environment Variable Validation

Environment variables are strings injected at runtime. `process.env` is `Record<string, string | undefined>`. Validate at boot, not scattered through the codebase.

**The env.ts pattern:**

```typescript
// src/env.ts -- THE one file that touches process.env
import { z } from "zod";
import dotenv from "dotenv";
dotenv.config();

const EnvSchema = z.object({
  DATABASE_URL: z.string().url(),
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().min(1).max(65535).default(3000),
  ENABLE_FEATURE_X: z.enum(["true", "false"]).transform(v => v === "true").default("false"),
  API_KEY: z.string().min(1, "API_KEY is required"),
});

export const env = EnvSchema.parse(process.env); // Crash at boot if invalid
export type Env = z.infer<typeof EnvSchema>;
```

**BAD:** Scattered process.env access
```typescript
// In some service file, 200 lines deep
const url = process.env.DATABASE_URL!; // Will crash here, not at startup
```

**GOOD:** Centralized, typed, fail-fast
```typescript
import { env } from "./env";
app.listen(env.PORT); // env.PORT is number, guaranteed present
```

---

## Level 3: Ecosystem & Integration (Advanced)

### Zod + tRPC (End-to-End Type Safety)

tRPC uses Zod schemas as the contract between client and server. No code generation needed.

```typescript
// server
const appRouter = router({
  createUser: publicProcedure
    .input(CreateUserSchema) // Zod schema = runtime validation + type inference
    .mutation(({ input }) => {
      // input is fully typed as CreateUser
      return db.users.create(input);
    }),
});

// client -- fully typed, zero code generation
const user = await trpc.createUser.mutate({ name: "Alice", email: "alice@co.com" });
```

### Zod + React Hook Form (Client + Server Validation)

Always validate BOTH client-side (UX) and server-side (security).

```typescript
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";

const SignupForm = () => {
  const { register, handleSubmit, formState: { errors } } = useForm<CreateUser>({
    resolver: zodResolver(CreateUserSchema), // Same schema, client-side
  });
  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <input {...register("email")} />
      {errors.email && <span>{errors.email.message}</span>}
    </form>
  );
};
```

### Zod + OpenAPI Generation

```typescript
import { createDocument } from "zod-openapi";
// Generate OpenAPI v3.x spec from Zod schemas -- docs stay in sync with code

// Reverse direction: generate Zod from existing OpenAPI spec
// npm: openapi-zod-client or orval
```

### Library Decision Tree

```
Need validation library?
|
+--> Using tRPC, React Hook Form, or existing Zod ecosystem?
|    YES --> Zod (ecosystem lock-in is worth it)
|
+--> Edge function / Cloudflare Worker / mobile where bundle size is critical?
|    YES --> Valibot (~5-12 KB tree-shaken vs Zod's ~50-64 KB)
|
+--> High-throughput backend validating 500K+ objects/request?
|    YES --> ArkType (JIT compiled, ~100x Zod v3 throughput)
|
+--> fp-ts ecosystem project?
|    YES --> io-ts
|
+--> Default / unsure?
     --> Zod (best DX, largest ecosystem, v4 improved perf 6-14x)
```

### Comparison Table

| Criteria | Zod | Valibot | ArkType |
|----------|-----|---------|---------|
| Bundle size | ~50-64 KB | ~5-12 KB | ~38-44 KB |
| Runtime perf | ~5-6M ops/s | Faster than Zod | ~70M+ ops/s (JIT) |
| DX | Best (chainable API) | Good (functional) | Good (TS-native syntax) |
| Ecosystem | Massive (tRPC, RHF, OpenAPI) | Growing | Newer, fewer integrations |
| Tree-shaking | Zod Mini (v4) | Excellent (modular) | Medium |
| v4 improvements | 6-14x faster, JIT compilation | N/A | N/A |
| Error path perf | Good | Good | Slower on error paths |

### Standard Schema Interoperability

Use the `Standard Schema` spec interface to avoid vendor lock-in. Start with Zod for ecosystem, swap to ArkType later if perf bottlenecks arise -- without rewriting route definitions.

---

## Performance: Make It Fast

### Schema Hoisting

**BAD:** Schema in a loop
```typescript
for (const record of records) {
  const S = z.object({ id: z.number() }); // Re-created 10,000 times
  try { S.parse(record); } catch {} // try/catch overhead in hot loop
}
```

**GOOD:** Hoist + safeParse
```typescript
const RecordSchema = z.object({ id: z.number() }); // Module-level, created once

function processRecords(records: unknown[]) {
  return records.filter(r => {
    const result = RecordSchema.safeParse(r);
    return result.success;
  }).map(r => RecordSchema.parse(r)); // Or: collect from safeParse results
}
```

### Vectorize with z.array()

When validating a collection, prefer `z.array(ItemSchema).parse(items)` over looping with individual parses. Zod can optimize the batch.

### Valibot for Edge Functions

If deploying to Cloudflare Workers or Supabase Edge Functions where cold start and bundle size matter, consider Valibot. Same validation guarantees, ~90% smaller bundle.

```typescript
// Valibot equivalent
import * as v from "valibot";
const UserSchema = v.object({ name: v.string(), role: v.picklist(["admin", "viewer"]) });
type User = v.InferOutput<typeof UserSchema>;
```

---

## Observability: Know It's Working

### Log Validation Failures at Boundaries

```typescript
app.post("/webhooks/stripe", async (req, res) => {
  const result = StripeEventSchema.safeParse(req.body);
  if (!result.success) {
    // Structured log -- searchable in Grafana/Datadog
    logger.warn("Validation failure at boundary", {
      boundary: "stripe-webhook",
      issues: result.error.issues,
      rawKeys: Object.keys(req.body ?? {}),
    });
    return res.status(400).json({ error: "Invalid payload" });
  }
  await handleStripeEvent(result.data);
  res.sendStatus(200);
});
```

### Sentry Integration for Parse Errors

```typescript
import * as Sentry from "@sentry/node";

function parseOrCapture<T>(schema: z.ZodSchema<T>, data: unknown, context: string): T | null {
  const result = schema.safeParse(data);
  if (result.success) return result.data;
  Sentry.captureException(result.error, {
    tags: { boundary: context },
    extra: { issues: result.error.issues },
  });
  return null;
}
```

### Metrics to Track

| Metric | Why |
|--------|-----|
| Validation failure rate per boundary | Detect API contract drift early |
| Schema parse latency (p50/p99) | Catch perf regressions from complex schemas |
| Unknown key frequency | Detect upstream schema changes you haven't handled |

---

## Enforcement: Anti-Rationalization Rules

These 5 rules exist because AI coding agents (and humans) have a strong bias toward "just making it work" with `as` or `any`. Each rule includes the rationalization it blocks.

### Rule 1: NEVER `as` on External Data

> **Rationalization:** "The API docs say it returns this shape, so `as` is safe."
>
> **Why it's wrong:** Docs lie. API versions drift. `as` is erased at runtime. Silent corruption propagates until it crashes far from the boundary.
>
> **Required action:** Define a Zod schema. Use `parse()` or `safeParse()`. Handle failure.

### Rule 2: Schema First, Type Derived

> **Rationalization:** "I already wrote the TypeScript interface, I don't want to write a Zod schema too."
>
> **Why it's wrong:** Two sources of truth = guaranteed drift. The interface will eventually mismatch the schema.
>
> **Required action:** Delete the manual interface. Write the Zod schema. Export `type X = z.infer<typeof XSchema>`.

### Rule 3: safeParse in Hot Paths

> **Rationalization:** "I'll just wrap parse() in try/catch, same thing."
>
> **Why it's wrong:** Exception throwing is expensive in V8. In a loop of 10K+ items, try/catch destroys throughput.
>
> **Required action:** Hoist schema to module level. Use `safeParse()` in loops. Reserve `parse()` for fail-fast boot checks.

### Rule 4: Centralized env.ts, Not Scattered process.env

> **Rationalization:** "I'm just reading one env var, it's faster to check inline."
>
> **Why it's wrong:** Scattered process.env checks cause apps to fail deep in execution when a variable is missing. No autocompletion. No type safety.
>
> **Required action:** All env vars route through a single Zod-validated `env.ts` file, parsed at boot.

### Rule 5: Validate at Boundary, Trust Downstream

> **Rationalization:** "I should validate this data again in the service layer to be safe."
>
> **Why it's wrong:** Re-validating already-parsed data adds latency and couples internal services to external schemas. Parse once at the edge.
>
> **Required action:** Edge handler validates with Zod. Internal functions accept the inferred type. No re-parsing.

### Quick Reference: When `as` IS Acceptable

`as` is only permissible when ALL of these are true:
1. The data originates entirely within your own process (not external)
2. TypeScript's type narrowing cannot express the constraint (known compiler limitation)
3. The assertion is accompanied by a comment explaining WHY
4. It never touches data from: API responses, user input, process.env, LLM output, webhooks, file reads, database results from multi-writer databases
