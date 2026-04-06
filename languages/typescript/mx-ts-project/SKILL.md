---
name: mx-ts-project
description: Use when configuring tsconfig.json, setting up build tools, managing ESM/CJS interop, configuring monorepos, or managing dependencies. Also use when the user mentions 'tsconfig', 'moduleResolution', 'NodeNext', 'bundler', 'ESM', 'CJS', 'isolatedModules', 'esbuild', 'swc', 'tsup', 'monorepo', 'Turborepo', 'Nx', 'project references', 'dual publishing', 'package.json exports', 'pnpm', or 'Renovate'.
---

# TypeScript Project Config — Build & Module Setup for AI Coding Agents

**This skill loads for build/config work.** It prevents: cargo-culted tsconfigs, wrong moduleResolution, ESM/CJS hell, missing isolatedModules, and over-complicated monorepo setups.

## When to also load
- Core types/language → `mx-ts-core`
- Runtime performance/profiling → `mx-ts-perf`

---

## Level 1: tsconfig Decision Tree (Beginner)

### Step 1: What are you building?

| Project Type | `module` | `moduleResolution` | `target` | `noEmit` |
|---|---|---|---|---|
| **Node.js app** (v20+) | `"NodeNext"` | `"NodeNext"` | `"ES2024"` | `false` |
| **Bundled app** (Vite/webpack/Next) | `"ESNext"` or `"preserve"` | `"Bundler"` | `"ES2022"` | `true` |
| **Library** (npm publish) | `"NodeNext"` | `"NodeNext"` | `"ES2022"` | `false` |

### Node.js App — tsconfig.json

```jsonc
{
  "compilerOptions": {
    // Module system
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "target": "ES2024",

    // Strictness — non-negotiable
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,

    // Emit
    "outDir": "dist",
    "rootDir": "src",
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,

    // AI-agent-friendly flags
    "isolatedModules": true,
    "verbatimModuleSyntax": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["src"],
  "exclude": ["node_modules", "dist"]
}
```

```jsonc
// package.json
{
  "type": "module",
  "engines": { "node": ">=20" }
}
```

**NodeNext requires `.js` extensions on relative imports** — even though the source is `.ts`:
```typescript
import { handler } from './routes/health.js';  // Correct
import { handler } from './routes/health';      // ERROR in NodeNext
```

### Bundled App (Vite/Next/webpack) — tsconfig.json

```jsonc
{
  "compilerOptions": {
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "target": "ES2022",

    "strict": true,
    "noUncheckedIndexedAccess": true,

    // Bundler handles emit — tsc only type-checks
    "noEmit": true,

    "isolatedModules": true,
    "verbatimModuleSyntax": true,
    "esModuleInterop": true,
    "skipLibCheck": true,

    // JSX (React)
    "jsx": "react-jsx"
  },
  "include": ["src", "vite-env.d.ts"]
}
```

**No `.js` extensions needed** — bundler resolves `.ts` files directly. No `outDir` needed — bundler handles output.

### Library (npm publish) — tsconfig.json

```jsonc
{
  "compilerOptions": {
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "target": "ES2022",

    "strict": true,
    "noUncheckedIndexedAccess": true,

    "outDir": "dist",
    "rootDir": "src",
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,

    "isolatedModules": true,
    "verbatimModuleSyntax": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["src"]
}
```

### Why These Flags Matter

| Flag | What It Does | Why Required |
|---|---|---|
| `strict: true` | Enables all strict checks | Baseline. Never disable. |
| `isolatedModules: true` | Enforces single-file transpilation safety | Required for esbuild/swc/Babel. Disables `const enum` across modules. |
| `verbatimModuleSyntax: true` | Forces `import type` for type-only imports | Prevents runtime import of types. Replaces `importsNotUsedAsValues`. TS 5.0+. |
| `noUncheckedIndexedAccess` | `arr[0]` returns `T \| undefined` | Catches real bugs. Beyond `strict`. |
| `skipLibCheck: true` | Skips checking `.d.ts` files | Build speed. Catches YOUR bugs, not library type bugs. |
| `esModuleInterop: true` | Fixes CJS default import mismatch | Prevents "double default" problem. Always enable. |
| `declaration: true` | Emits `.d.ts` files | Required for libraries and cross-project refs. |
| `declarationMap: true` | Source maps for `.d.ts` | Go-to-definition lands in `.ts` source, not `.d.ts`. |

---

## Level 2: ESM/CJS & Dual Publishing (Intermediate)

### The Module System Decision

**Default to ESM.** CJS is legacy. Node.js v22+ can even `require()` ESM modules natively.

| Signal | Use ESM | Use CJS | Use Dual |
|---|---|---|---|
| New Node.js app | Yes | - | - |
| New library | Yes | - | If consumers stuck on CJS |
| Existing CJS app | Migrate over time | Keep if stable | - |
| Bundled app | Yes (via bundler) | - | - |

### package.json `exports` Field (Dual Publishing)

```jsonc
{
  "name": "my-library",
  "version": "1.0.0",
  "type": "module",
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "import": "./dist/esm/index.js",
      "require": "./dist/cjs/index.cjs"
    },
    "./utils": {
      "types": "./dist/utils.d.ts",
      "import": "./dist/esm/utils.js",
      "require": "./dist/cjs/utils.cjs"
    }
  },
  "files": ["dist"]
}
```

**Critical: `types` MUST be first** in each export block. Order matters. Node.js uses first matching condition.

### tsup Config for Dual Publishing

```typescript
// tsup.config.ts
import { defineConfig } from 'tsup';

export default defineConfig({
  entry: ['src/index.ts', 'src/utils.ts'],
  format: ['esm', 'cjs'],
  dts: true,
  splitting: true,
  sourcemap: true,
  clean: true,
  outDir: 'dist',
});
```

tsup (powered by esbuild) compiles ESM + CJS from the same source. Generates `.js` (ESM) and `.cjs` (CJS) with matching `.d.ts` files.

### `verbatimModuleSyntax` in Practice

```typescript
// CORRECT — explicit type-only imports
import type { User } from './models.js';
import { createUser } from './models.js';

// ERROR with verbatimModuleSyntax — ambiguous
import { User, createUser } from './models.js';
// (if User is only a type, this fails)
```

This flag forces the developer to be explicit. esbuild/swc process files individually and cannot determine cross-file type usage. `verbatimModuleSyntax` makes every import self-documenting.

### Node.js Subpath Imports (Alternative to tsconfig paths)

```jsonc
// package.json
{
  "imports": {
    "#db": "./src/database/index.js",
    "#utils/*": "./src/utils/*.js"
  }
}
```

```typescript
import { pool } from '#db';
import { hash } from '#utils/crypto.js';
```

Subpath imports are resolved by Node.js at runtime — no extra build-time path resolver needed. Turborepo recommends these over tsconfig `paths`. Works with all tools (tsc, esbuild, Vitest) without extra plugins.

---

## Level 3: Monorepo & Build Speed (Advanced)

### Monorepo Tooling Decision Tree

```
Do you need a monorepo?
├── Single app, 1-2 packages → NO. Use workspace packages only.
├── Multiple apps sharing code → YES
│   ├── < 10 packages, simple deps → Turborepo
│   │   (caching + task orchestration, minimal config)
│   └── > 10 packages, complex graph → Nx
│       (dependency graph, code gen, affected commands, constraints)
```

### Turborepo Setup (Recommended Default)

```jsonc
// turbo.json
{
  "$schema": "https://turbo.build/schema.json",
  "tasks": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": ["dist/**"]
    },
    "check": {
      "dependsOn": ["^build"]
    },
    "test": {
      "dependsOn": ["^build"]
    },
    "dev": {
      "cache": false,
      "persistent": true
    }
  }
}
```

**Turborepo's stance:** Do NOT use TS project references. Use Node.js subpath imports instead of tsconfig `paths`. Let Turborepo handle task ordering and caching.

### Internal Packages (Turborepo Pattern)

```
monorepo/
├── apps/
│   ├── web/          ← Next.js app
│   └── api/          ← Node.js server
├── packages/
│   ├── shared/       ← Shared types + utils
│   │   ├── src/
│   │   │   └── index.ts
│   │   ├── tsconfig.json
│   │   └── package.json
│   └── config/       ← Shared tsconfig, eslint
├── turbo.json
├── package.json      ← workspaces: ["apps/*", "packages/*"]
└── pnpm-workspace.yaml
```

Shared base tsconfig at root — all packages extend it:
```jsonc
// packages/shared/tsconfig.json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "outDir": "dist",
    "rootDir": "src"
  },
  "include": ["src"]
}
```

### Nx Setup (Complex Monorepos)

Nx auto-syncs TS project references. Provides:
- `nx affected --target=test` — only test what changed
- `nx graph` — visualize dependency graph
- Module boundary enforcement via `@nx/enforce-module-boundaries`

Use Nx when: you need code generation, enforced architectural constraints, or have 10+ interconnected packages.

### TS Project References (When Nx or Manual)

```jsonc
// tsconfig.json (root)
{
  "references": [
    { "path": "./packages/shared" },
    { "path": "./packages/api" }
  ],
  "files": []
}

// packages/shared/tsconfig.json
{
  "compilerOptions": {
    "composite": true,
    "declaration": true,
    "declarationMap": true,
    "outDir": "dist",
    "rootDir": "src"
  },
  "include": ["src"]
}
```

Build with `tsc --build` (`tsc -b`) to leverage incremental compilation across projects.

**`composite: true`** enforces: `declaration` must be on, all source files must be in `include`, `rootDir` defaults to tsconfig directory. These constraints enable incremental cross-project builds.

---

## Performance: Make It Fast

### The Speed Rule: Separate Type-Checking from Transpilation

```
tsc (type-check only)  →  noEmit: true    →  Catches type errors
esbuild/swc (compile)  →  Transpiles TS   →  10-100x faster than tsc emit
```

Never use `tsc` for both checking AND emitting in dev. Use `tsc --noEmit` for type safety, esbuild/swc for fast compilation.

### Build Speed Toolkit

| Technique | Impact | When to Use |
|---|---|---|
| `skipLibCheck: true` | 30-50% faster tsc | Always |
| `noEmit: true` + esbuild | 10-100x faster builds | Bundled apps |
| `incremental: true` | 40-70% faster rebuilds | Any project with `tsBuildInfoFile` |
| `tsc -b` (project refs) | Only rebuilds changed packages | Monorepos |
| tsup / esbuild for emit | Sub-second builds | Libraries |
| swc (via `@swc/core`) | Rust-based transpiler | When esbuild isn't enough |

### Incremental Builds

```jsonc
{
  "compilerOptions": {
    "incremental": true,
    "tsBuildInfoFile": "./dist/.tsbuildinfo"
  }
}
```

Stores dependency graph on disk. Subsequent `tsc` only re-checks changed files. Commit `.tsbuildinfo` to git for CI speed (controversial but effective).

---

## Observability: Know It's Working

### Dependency Management with Renovate

```jsonc
// renovate.json (repository root)
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:recommended",
    "schedule:weekends",
    ":automergeMinor",
    ":automergeDigest"
  ],
  "packageRules": [
    {
      "groupName": "TypeScript tooling",
      "matchPackageNames": ["typescript", "tsup", "esbuild", "@swc/core"],
      "automerge": false
    },
    {
      "groupName": "Lint & format",
      "matchPackageNames": ["eslint", "prettier", "biome"],
      "automerge": true
    }
  ]
}
```

**Renovate over Dependabot:** 90+ package manager support, automerge, dependency dashboard, shared presets across repos, regex manager for non-standard deps.

### Security Auditing

```bash
# Built-in vulnerability scanning
pnpm audit              # Check known vulnerabilities
pnpm audit --fix        # Auto-add overrides for fixable vulns

# CI pipeline check
pnpm audit --audit-level=high  # Fail CI on high+ severity
```

### `sideEffects` in package.json

```jsonc
{
  "sideEffects": false                          // All modules are tree-shakeable
  // OR
  "sideEffects": ["*.css", "./src/polyfills.ts"] // Protect files with actual side effects
}
```

Without `sideEffects: false`, bundlers cannot safely remove unused exports. This single field can cut bundle size by 30-60% for libraries.

### pnpm Over npm

| Feature | pnpm | npm |
|---|---|---|
| Disk usage | Content-addressable store, 70-80% savings | Full copies per project |
| Phantom deps | Prevented (strict `node_modules`) | Allowed (hoisting) |
| Speed | Fastest install in benchmarks | Slower |
| Monorepo | `pnpm-workspace.yaml`, built-in | `workspaces` field, basic |
| Lockfile | `pnpm-lock.yaml`, deterministic | `package-lock.json` |

**Phantom dependencies** cause up to 85% of vulnerability false positives in npm projects. pnpm's strict isolation eliminates them.

```yaml
# pnpm-workspace.yaml
packages:
  - 'apps/*'
  - 'packages/*'
```

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Cargo-Culting tsconfig

**You will be tempted to:** Copy a tsconfig from a blog post or starter template without understanding it.
**The right way:** Use the decision tree above. Every field must have a reason. If you cannot explain why a flag is set, delete it. Common cargo-culted mistakes:
- `"lib": ["ESNext"]` when `"target"` already implies it
- `"baseUrl": "."` with no `paths` — does nothing useful
- `"resolveJsonModule": true` when no JSON imports exist
- `"allowJs": true` in a pure TS project

### Rule 2: No Downgrading moduleResolution

**You will be tempted to:** Switch from `"NodeNext"` to `"node"` (legacy Node10) because `.js` extensions are "annoying."
**The right way:** `"NodeNext"` for Node.js, `"Bundler"` for bundled apps. Legacy `"node"` resolution is deprecated behavior. The `.js` extension requirement exists because Node.js ESM loader requires it — TypeScript is enforcing real runtime behavior. If extensions bother you, you are using the wrong `moduleResolution` for your project type.

### Rule 3: No Skipping isolatedModules

**You will be tempted to:** Disable `isolatedModules` because `const enum` or namespace merging "doesn't work."
**The right way:** Keep `isolatedModules: true`. Always. If esbuild, swc, Babel, or any single-file transpiler touches your code, `isolatedModules` is mandatory. `const enum` across modules is an anti-pattern anyway — use regular `enum` or `as const` objects. Disabling this flag means your type-checker and your transpiler see different code, which produces silent runtime bugs.

### Rule 4: No Over-Engineering Monorepo Config

**You will be tempted to:** Add TS project references + tsconfig paths + custom build scripts + Nx + Turborepo all at once.
**The right way:** Start with pnpm workspaces + Turborepo + subpath imports. Add project references only if Nx is managing them. Add tsconfig `paths` only if subpath imports are insufficient (they rarely are). Every layer of indirection is a maintenance burden. Turborepo explicitly recommends AGAINST project references.

### Rule 5: No Ignoring verbatimModuleSyntax

**You will be tempted to:** Leave it off because "it's just a style thing" or "it creates too many import changes."
**The right way:** Enable `verbatimModuleSyntax: true` in all new projects (TS 5.0+). It replaces `importsNotUsedAsValues` and `preserveValueImports` — both deprecated. It ensures every import statement is unambiguous: values are values, types are types. This is not style — it is correctness. Without it, esbuild/swc may emit runtime imports for type-only symbols, causing crashes or bloated bundles.
