---
name: mx-ts-core
description: Use when writing any TypeScript code. Covers strict typing, any prevention, generics, discriminated unions, satisfies operator, exhaustive switch, branded types, template literal types. Also use when the user mentions 'any', 'unknown', 'type guard', 'discriminated union', 'satisfies', 'generics', 'branded type', 'template literal type', 'exhaustive', 'never type', 'type narrowing', 'as const', 'infer', 'mapped type', 'conditional type', 'noUncheckedIndexedAccess', or 'strict mode'.
---

# TypeScript Core Types — Strict Type Safety for AI Coding Agents

**This skill loads for ANY TypeScript work.** It prevents the most common AI failure: using `any` to silence the compiler, `as` to bypass validation, and skipping exhaustive checks on discriminated unions.

## When to also load
- Runtime validation (Zod, io-ts) → `mx-ts-validation`
- Structured logging (Pino, OTel) → `mx-ts-observability`
- Async patterns (promises, streams, concurrency) → `mx-ts-async`

---

## tsconfig Baseline

Every project starts here. Non-negotiable.

```jsonc
{
  "compilerOptions": {
    "strict": true,                        // enables noImplicitAny, strictNullChecks, strictFunctionTypes, strictPropertyInitialization
    "noUncheckedIndexedAccess": true,       // arr[0] is T | undefined, not T
    "exactOptionalProperties": true,        // p?: string means "missing OR string", NOT "undefined OR string"
    "noImplicitOverride": true,             // subclass methods require override keyword
    "useUnknownInCatchVariables": true,     // catch(e) gives unknown, not any
    "noPropertyAccessFromIndexSignature": true
  }
}
```

`noUncheckedIndexedAccess` and `exactOptionalProperties` are NOT included in `strict: true`. They must be enabled separately. The TS team has stated that if starting over, `exactOptionalProperties` would be the default.

---

## Level 1: The Any-Escape Ladder (Beginner)

The ladder from most dangerous to safest. Every rung removes a class of runtime errors.

### Rung 1: `any` to `unknown`

```typescript
// BAD — any infects everything it touches
function parse(input: any) {
  return input.name.toUpperCase(); // no error, crashes at runtime
}

// GOOD — unknown forces narrowing before use
function parse(input: unknown) {
  if (typeof input === "object" && input !== null && "name" in input) {
    const { name } = input as { name: string };
    return name.toUpperCase(); // safe — narrowed
  }
  throw new Error("invalid input shape");
}
```

`any` silences every error downstream. `unknown` is the type-safe top type — nothing is allowed until you prove the shape.

### Rung 2: Type Guards for Narrowing

```typescript
// BAD — as casting bypasses the type system
const user = response as User;

// GOOD — type guard with runtime check
function isUser(value: unknown): value is User {
  return (
    typeof value === "object" &&
    value !== null &&
    "id" in value &&
    "email" in value
  );
}

if (isUser(response)) {
  console.log(response.email); // narrowed to User
}
```

| Narrowing Technique | When to Use |
|---------------------|-------------|
| `typeof x === "string"` | Primitives |
| `x instanceof Error` | Class instances |
| `"key" in x` | Object property presence |
| `isX(x): x is T` | Custom type guards — compound checks |
| `assertX(x): asserts x is T` | Throws if invalid, narrows if not |

### Rung 3: Discriminated Unions

```typescript
// BAD — loose union, no exhaustive checking possible
type ApiResult = { data?: User; error?: string; loading?: boolean };

// GOOD — discriminated union with exhaustive switch
type ApiResult =
  | { status: "loading" }
  | { status: "success"; data: User }
  | { status: "error"; error: string };

function handleResult(result: ApiResult): string {
  switch (result.status) {
    case "loading":
      return "Loading...";
    case "success":
      return result.data.email; // auto-narrowed
    case "error":
      return result.error; // auto-narrowed
    default: {
      const _exhaustive: never = result;
      return _exhaustive; // compile error if variant unhandled
    }
  }
}
```

The `never` in the default branch is the exhaustive check. If a new variant is added to `ApiResult`, the compiler errors on the `default` — you cannot forget to handle it.

### Rung 4: `satisfies` Over `as`

```typescript
// BAD — as const widens nothing, but as X lies to the compiler
const config = { port: 3000, host: "localhost" } as Config;

// BAD — type annotation widens literal types
const routes: Record<string, string> = {
  home: "/",
  about: "/about",
}; // routes.home is string, not "/"

// GOOD — satisfies validates shape WITHOUT widening
const routes = {
  home: "/",
  about: "/about",
} satisfies Record<string, string>;
// routes.home is "/", not string — literal preserved

// GOOD — as const + satisfies = locked and validated
const config = {
  port: 3000,
  host: "localhost",
} as const satisfies { port: number; host: string };
// config.port is 3000, not number
```

| I need to... | Use |
|-------------|-----|
| Validate shape, keep literal types | `satisfies Type` |
| Lock values AND validate shape | `as const satisfies Type` |
| Assert a value is narrower than inferred | `as const` (no satisfies needed) |
| Override the type system (NEVER) | `as Type` — forbidden except `.json` imports |

---

## Level 2: Advanced Type Patterns (Intermediate)

### Generic Constraints with `extends`

```typescript
// BAD — unconstrained generic, no safety
function getId<T>(item: T): string {
  return item.id; // ERROR: Property 'id' does not exist on type 'T'
}

// BAD — uses any to silence the error
function getId(item: any): string {
  return item.id; // compiles, crashes if item has no id
}

// GOOD — constrained generic preserves type info
function getId<T extends { id: string }>(item: T): string {
  return item.id; // safe — T guaranteed to have id
}
```

| Generic Constraint Need | Pattern |
|------------------------|---------|
| Must have specific properties | `<T extends { id: string }>` |
| Must be a subtype | `<T extends BaseConfig>` |
| Key of an object | `<T, K extends keyof T>` |
| Array of anything | `<T extends readonly unknown[]>` |
| Minimum constraint | Use the smallest interface that makes the code work |

### Branded Types

Zero runtime overhead. Prevents mixing semantically different values of the same base type.

```typescript
// Declare the brand
type UserId = string & { readonly __brand: unique symbol };
type OrderId = string & { readonly __brand: unique symbol };

// Constructor with validation
function createUserId(id: string): UserId {
  if (!id.startsWith("usr_")) throw new Error("Invalid user ID");
  return id as UserId; // as is OK here — guarded by runtime check
}

// Compiler prevents mixing
function getUser(id: UserId): User { /* ... */ }

getUser(createUserId("usr_123")); // OK
getUser("usr_123");               // ERROR — string is not UserId
getUser(orderId);                 // ERROR — OrderId is not UserId
```

Use branded types for: IDs (UserId vs OrderId), units (Meters vs Kilometers), validated strings (EmailAddress, Url).

### Template Literal Types

Type-level string pattern matching.

```typescript
type Version = "v1" | "v2";
type Resource = "users" | "orders";
type ApiRoute = `/api/${Version}/${Resource}`;
// = "/api/v1/users" | "/api/v1/orders" | "/api/v2/users" | "/api/v2/orders"

type EventName = `on${Capitalize<"click" | "hover" | "focus">}`;
// = "onClick" | "onHover" | "onFocus"

// Extract parts from template literals
type ExtractVersion<T> = T extends `/api/${infer V}/${string}` ? V : never;
type V = ExtractVersion<"/api/v2/users">; // "v2"
```

---

## Level 3: Type-Level Programming (Advanced)

### Conditional Types

```typescript
type IsString<T> = T extends string ? true : false;
type A = IsString<"hello">; // true
type B = IsString<42>;       // false

// Practical: unwrap Promise types
type Unwrap<T> = T extends Promise<infer U> ? U : T;
type X = Unwrap<Promise<string>>; // string
type Y = Unwrap<number>;          // number
```

### Mapped Types

Transform every property of an object type.

```typescript
// Make all properties optional and nullable
type Patchable<T> = {
  [K in keyof T]?: T[K] | null;
};

// Remap keys with as
type Getters<T> = {
  [K in keyof T as `get${Capitalize<string & K>}`]: () => T[K];
};

type UserGetters = Getters<{ name: string; age: number }>;
// { getName: () => string; getAge: () => number }
```

### The `infer` Keyword

Extract types from within other types.

```typescript
// Extract return type of a function
type ReturnOf<T> = T extends (...args: unknown[]) => infer R ? R : never;

// Extract element type from array
type ElementOf<T> = T extends readonly (infer E)[] ? E : never;

// Extract the success data from a Result union
type SuccessData<T> = T extends { status: "success"; data: infer D } ? D : never;
```

### Exhaustive Switch with `never` — The Complete Pattern

```typescript
type Shape =
  | { kind: "circle"; radius: number }
  | { kind: "rect"; width: number; height: number }
  | { kind: "triangle"; base: number; height: number };

function area(shape: Shape): number {
  switch (shape.kind) {
    case "circle":
      return Math.PI * shape.radius ** 2;
    case "rect":
      return shape.width * shape.height;
    case "triangle":
      return (shape.base * shape.height) / 2;
    default: {
      const _exhaustive: never = shape;
      return _exhaustive;
    }
  }
}
```

If someone adds `| { kind: "polygon"; sides: number[] }` to `Shape`, the compiler immediately errors on the `default` branch because `{ kind: "polygon"; ... }` is not assignable to `never`. This is the ONLY acceptable way to handle discriminated union switches.

---

## Performance: Make It Fast

Strict types directly help V8's JIT compiler. Here is why.

| Concept | What V8 Does | How Strict Types Help |
|---------|-------------|----------------------|
| Hidden Classes | V8 assigns a hidden class to every object shape. Same-shape objects share JIT-optimized code. | Consistent interfaces = monomorphic call sites = fastest path |
| Inline Caches | V8 caches property lookups. Polymorphic (many shapes) = slow megamorphic fallback. | Discriminated unions keep each branch monomorphic |
| Deoptimization | V8 deoptimizes when runtime type differs from what JIT assumed. | `any` causes deopt storms — the JIT cannot predict shapes |
| Type Narrowing | After a guard, V8 knows the exact shape within that branch. | Type guards map 1:1 to V8's type specialization |

**Practical rule:** Objects flowing through hot paths should have a fixed shape. Discriminated unions with consistent discriminant properties are the fastest pattern because each `case` branch sees exactly one hidden class.

---

## Observability: Know It's Working

### ESLint Config — The Guardrail

```jsonc
// eslint.config.js (flat config)
{
  "rules": {
    "@typescript-eslint/no-explicit-any": "error",
    "@typescript-eslint/no-unsafe-assignment": "error",
    "@typescript-eslint/no-unsafe-member-access": "error",
    "@typescript-eslint/no-unsafe-return": "error",
    "@typescript-eslint/no-unsafe-call": "error",
    "@typescript-eslint/no-unsafe-argument": "error",
    "@typescript-eslint/no-floating-promises": "error",
    "@typescript-eslint/no-misused-promises": "error",
    "@typescript-eslint/strict-boolean-expressions": "error",
    "@typescript-eslint/switch-exhaustiveness-check": "error"
  }
}
```

| Rule | What It Catches |
|------|----------------|
| `no-explicit-any` | Direct `any` annotations |
| `no-unsafe-assignment` | `any` spreading to typed variables |
| `no-unsafe-member-access` | `.foo` on an `any` value |
| `no-unsafe-return` | Returning `any` from typed functions |
| `no-unsafe-call` | Calling an `any` value as a function |
| `no-unsafe-argument` | Passing `any` into typed parameters |
| `no-floating-promises` | Promises without `await` or `.catch()` — silent failures |
| `no-misused-promises` | Async functions in non-async positions (event handlers) |
| `switch-exhaustiveness-check` | Switch on union without handling all variants |

The `no-unsafe-*` family catches `any` **infection** — where a single `any` silently propagates through assignments, returns, and calls until the entire module is untyped.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No `any` for External Data

**You will be tempted to:** Type API responses, JSON files, or third-party library returns as `any` because "the shape is dynamic" or "I'll validate it later."
**Why that fails:** `any` infects every variable it touches. One `any` return type makes the entire call chain untyped. "Later" never comes.
**The right way:** Use `unknown` and narrow with a type guard, or use a runtime validator (`mx-ts-validation`). For third-party libraries, check DefinitelyTyped (`@types/*`) first.

### Rule 2: No `as` Casting to Fix Type Errors

**You will be tempted to:** Write `value as User` or `value as string` when the compiler complains about incompatible types.
**Why that fails:** `as` is a lie to the compiler. It performs zero runtime checks. If the shape doesn't match, you get the exact crash `any` would have caused, just with a false sense of safety.
**The right way:** Write a type guard (`isUser(value)`), use `satisfies` for object literals, or fix the actual type mismatch. The only acceptable `as` is inside a branded-type constructor that is guarded by a runtime validation check immediately above it.

### Rule 3: No Empty `default` in Discriminated Union Switches

**You will be tempted to:** Write `default: return undefined` or `default: break` to "handle" unknown variants, because "it's safe enough."
**Why that fails:** When a new variant is added to the union, the compiler stays silent. The new variant hits the empty default, returns garbage, and you get a runtime bug instead of a compile error.
**The right way:** Always use the `never` exhaustive check pattern: `default: { const _exhaustive: never = value; return _exhaustive; }`. The compiler will error the moment an unhandled variant exists.

### Rule 4: No Unconstrained Generics to Avoid Thinking About the Type

**You will be tempted to:** Write `function process<T>(item: T)` without constraints, because constraining T "is too complicated" or "limits flexibility."
**Why that fails:** An unconstrained `T` is `unknown` with extra steps. Inside the function, you cannot access any properties. This leads to `as` casts or `any` escapes inside the body.
**The right way:** Add the minimum constraint: `<T extends { id: string }>`. If you cannot define a constraint, the function is too generic — split it into concrete overloads or narrow the use case.

### Rule 5: No `// @ts-ignore` or `// @ts-expect-error` Without a Linked Issue

**You will be tempted to:** Suppress a type error with `@ts-ignore` because "the types are wrong" or "it works at runtime."
**Why that fails:** Suppressed errors are invisible tech debt. They rot. When the surrounding code changes, the suppressed error hides a real bug.
**The right way:** If suppression is truly necessary (library type bug), use `@ts-expect-error` (not `@ts-ignore`) with a comment linking to the upstream issue: `// @ts-expect-error — https://github.com/lib/issue/123`. When the issue is fixed, `@ts-expect-error` auto-fails, reminding you to remove it. `@ts-ignore` never fails and never reminds you.
