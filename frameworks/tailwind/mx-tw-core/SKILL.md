---
name: mx-tw-core
description: "Tailwind CSS v4 fundamentals, any Tailwind CSS work, CSS-first configuration, @import tailwindcss, @theme directive, design tokens, CSS variables, utility-first philosophy, variants, dark mode, arbitrary values, class ordering, prettier-plugin-tailwindcss, migration from v3"
---

# Tailwind CSS Core — v4 Fundamentals for AI Coding Agents

**Load this skill for ANY Tailwind CSS work.** Covers v4 architecture, configuration, utility philosophy, and variant system.

## When to also load
- `mx-tw-layout` — Flex, Grid, spacing system
- `mx-tw-design-system` — Theme tokens, semantic colors, dark mode
- `mx-tw-components` — CVA, cn(), shadcn/ui patterns
- `mx-tw-perf` — Co-loads automatically on any Tailwind work
- `mx-tw-observability` — Co-loads automatically on any Tailwind work

---

## Level 1: v4 CSS-First Configuration (Beginner)

### Pattern 1: The Entry Point — @import "tailwindcss"

```css
/* ❌ BAD — v3 pattern (deprecated in v4) */
@tailwind base;
@tailwind components;
@tailwind utilities;

/* ✅ GOOD — v4 pattern */
@import "tailwindcss";
```

One import replaces three directives. This is the entire setup — no `tailwind.config.js` needed for greenfield v4 projects.

### Pattern 2: The @theme Directive — Design Tokens in CSS

```css
/* app.css — v4 CSS-first configuration */
@import "tailwindcss";
@plugin "@tailwindcss/typography";

@theme {
  /* Colors → auto-generates bg-brand, text-brand, border-brand */
  --color-brand: #3B82F6;
  --color-brand-hover: #2563EB;

  /* Spacing → auto-generates p-18, m-18, gap-18, w-18 */
  --spacing-18: 4.5rem;

  /* Fonts → auto-generates font-display */
  --font-display: "Clash Display", sans-serif;
  --font-sans: "Inter", system-ui, sans-serif;

  /* Shadows → auto-generates shadow-soft */
  --shadow-soft: 0 4px 20px rgba(0, 0, 0, 0.05);

  /* Border radius → auto-generates rounded-xl */
  --radius-xl: 1rem;
}
```

**Namespace mapping** — the variable prefix determines which utilities are generated:

| Namespace | Example | Generated Utilities |
|-----------|---------|-------------------|
| `--color-*` | `--color-primary: #1E40AF` | `bg-primary`, `text-primary`, `border-primary` |
| `--spacing-*` | `--spacing-128: 32rem` | `p-128`, `m-128`, `gap-128`, `w-128` |
| `--font-*` | `--font-mono: "JetBrains Mono"` | `font-mono` |
| `--text-*` | `--text-h1: 3rem` | `text-h1` |
| `--breakpoint-*` | `--breakpoint-3xl: 1920px` | `3xl:` responsive variant |
| `--radius-*` | `--radius-card: 0.75rem` | `rounded-card` |
| `--shadow-*` | `--shadow-elevated: ...` | `shadow-elevated` |

### Pattern 3: Automatic Content Detection

```css
/* ❌ BAD — v3 required manual content paths */
/* tailwind.config.js: content: ["./src/**/*.{html,tsx}"] */

/* ✅ GOOD — v4 auto-detects. Only add @source for special cases */
@import "tailwindcss";
@source "../shared-components/**/*.tsx";  /* External packages */
@source not "../legacy-app";              /* Exclude paths */
```

v4 scans your project automatically. No configuration needed for standard project structures.

### Pattern 4: PostCSS Setup Changes

```js
// ❌ BAD — v3 PostCSS config
module.exports = {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},  // No longer needed
  }
};

// ✅ GOOD — v4 PostCSS config (autoprefixer built-in)
module.exports = {
  plugins: {
    '@tailwindcss/postcss': {},
  }
};

// ✅ BEST — v4 with Vite (dedicated plugin)
// vite.config.ts
import tailwindcss from '@tailwindcss/vite';
export default { plugins: [tailwindcss()] };
```

---

## Level 2: Variant System and Dynamic Utilities (Intermediate)

### Pattern 1: Responsive Variants (Mobile-First)

```html
<!-- Unprefixed = ALL screens (mobile baseline) -->
<!-- Prefixed = min-width breakpoint and UP -->
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
```

| Prefix | Min-width | Target |
|--------|-----------|--------|
| (none) | 0px | Mobile (base) |
| `sm:` | 640px | Large phones |
| `md:` | 768px | Tablets |
| `lg:` | 1024px | Laptops |
| `xl:` | 1280px | Desktops |
| `2xl:` | 1536px | Ultra-wide |

### Pattern 2: State Variants

```html
<button class="
  bg-blue-600 text-white px-4 py-2 rounded-lg
  hover:bg-blue-500
  active:bg-blue-700 active:scale-95
  focus-visible:ring-2 focus-visible:ring-blue-400 focus-visible:ring-offset-2
  disabled:opacity-50 disabled:cursor-not-allowed
  transition-colors duration-200
">
  Submit
</button>
```

### Pattern 3: Dark Mode

```css
/* v4 default: uses @media (prefers-color-scheme: dark) automatically */

/* For manual toggle (class-based), add this AFTER the import: */
@import "tailwindcss";
@custom-variant dark (&:where(.dark, .dark *));

/* Or for data-attribute strategy: */
@custom-variant dark (&:where([data-theme="dark"], [data-theme="dark"] *));
```

### Pattern 4: Dynamic Utilities (v4 Innovation)

```html
<!-- v4 resolves spacing dynamically — no brackets needed -->
<div class="mt-29">     <!-- 29 × 0.25rem = 7.25rem -->
<div class="grid-cols-15"> <!-- 15-column grid, no config needed -->
<div class="p-17">      <!-- 17 × 0.25rem = 4.25rem -->

<!-- Arbitrary brackets still work for true one-offs -->
<div class="top-[113px]">  <!-- Exact pixel offset for iframe alignment -->
```

### Pattern 5: v4 Renamed Utilities

| v3 (Deprecated) | v4 (Current) | Why |
|-----------------|-------------|-----|
| `outline-none` | `outline-hidden` | True `outline-none` now maps to `outline-style: none` |
| `bg-gradient-to-r` | `bg-linear-to-r` | Aligns with CSS `linear-gradient()` |
| `shadow-sm` | `shadow-xs` | Shadow scale recalibrated |
| `shadow` (default) | `shadow-sm` | Default shadow shifted |
| `ring` (3px default) | `ring-3` | `ring` now defaults to 1px |
| `border` (gray-200) | `border border-gray-200` | Defaults to `currentColor` now |
| `flex-shrink-*` | `shrink-*` | Streamlined |
| `flex-grow-*` | `grow-*` | Streamlined |

---

## Level 3: Tooling, Migration, and Advanced Patterns (Advanced)

### Pattern 1: Prettier Configuration for v4

```json
// .prettierrc — MUST use tailwindStylesheet, not tailwindConfig
{
  "plugins": ["prettier-plugin-tailwindcss"],
  "tailwindStylesheet": "./src/app.css",
  "tailwindFunctions": ["clsx", "cva", "cn", "twMerge"]
}
```

`tailwindStylesheet` points to your CSS file (where `@theme` lives). The old `tailwindConfig` property won't find v4 tokens.

### Pattern 2: Custom Utilities via @utility

```css
/* Define reusable utilities without @apply */
@import "tailwindcss";

@utility flex-center {
  display: flex;
  align-items: center;
  justify-content: center;
}

/* Now usable as: <div class="flex-center"> */
/* Works with variants: <div class="md:flex-center hover:flex-center"> */
```

### Pattern 3: v3 → v4 Migration Checklist

1. **Upgrade**: `npm install tailwindcss@latest @tailwindcss/postcss` (or `@tailwindcss/vite`)
2. **Strip autoprefixer**: Remove from PostCSS config (built-in now)
3. **Replace directives**: `@tailwind base/components/utilities` → `@import "tailwindcss"`
4. **Migrate config**: Move `theme.extend` values to `@theme` CSS variables
5. **Rename utilities**: `outline-none` → `outline-hidden`, etc. (see table above)
6. **Run codemod**: `npx @tailwindcss/upgrade` automates most changes
7. **Update Prettier**: Switch to `tailwindStylesheet` property

---

## Performance: Make It Fast

### Perf 1: Oxide Engine — Rust-Powered Builds
v4 uses the Oxide engine (Rust) + Lightning CSS. 5× faster full builds, 100× faster incremental. 35% smaller install. No action needed — it's the default.

### Perf 2: Use the Spacing Scale, Not Arbitrary Values
`p-4` (1rem) reuses a single CSS rule across your entire app. `p-[17px]` creates a unique rule. Stick to the scale for smaller bundles.

### Perf 3: Never Concatenate Class Strings Dynamically
```tsx
// ❌ BAD — scanner can't detect these, styles get purged
<div className={`bg-${color}-500`} />

// ✅ GOOD — complete strings visible to scanner
const colorMap = { red: 'bg-red-500', blue: 'bg-blue-500' };
<div className={colorMap[color]} />
```

---

## Observability: Know It's Working

### Obs 1: Check "First Load CSS" in Build Output
After `next build` or your production build, verify CSS bundle size. Target: <10KB compressed. If larger, check for dynamic class generation or excessive arbitrary values.

### Obs 2: Use prettier-plugin-tailwindcss for Consistency
Inconsistent class ordering causes merge conflicts and makes code review harder. The plugin auto-sorts classes in the canonical Tailwind order.

### Obs 3: ESLint Plugin for Token Enforcement
`eslint-plugin-tailwindcss` catches: arbitrary values (`no-arbitrary-value`), unknown classes (`no-custom-classname`), missing shorthands (`enforces-shorthand`).

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Generate tailwind.config.js for v4 Projects
**You will be tempted to:** Create a `tailwind.config.js` with `content`, `theme.extend`, and plugins.
**Why that fails:** v4 uses CSS-first configuration. JS config disables auto-detection and the Oxide engine optimizations.
**The right way:** All configuration in CSS via `@theme`, `@plugin`, and `@source` directives.

### Rule 2: Never Use v3 Directive Syntax
**You will be tempted to:** Write `@tailwind base; @tailwind components; @tailwind utilities;`
**Why that fails:** These directives don't exist in v4. The build silently fails or produces no output.
**The right way:** `@import "tailwindcss";` — one line replaces all three.

### Rule 3: Never Over-Use Arbitrary Values
**You will be tempted to:** Write `w-[32px]`, `text-[16px]`, `p-[12px]` from Figma specs.
**Why that fails:** Destroys design system cohesion. Each arbitrary value creates a unique CSS rule. 32px = `w-8`, 16px = `text-base`, 12px = `p-3`.
**The right way:** Map pixel values to the 4px spacing scale. 1 unit = 0.25rem = 4px. Only use brackets for true one-offs with no scale equivalent.

### Rule 4: Never Assume v3 Defaults
**You will be tempted to:** Add `border` and expect `gray-200`, or `ring` and expect 3px blue.
**Why that fails:** v4 defaults `border` and `ring` to `currentColor`, and `ring` width to 1px.
**The right way:** Be explicit: `border border-gray-200`, `ring-3 ring-blue-500`.

### Rule 5: Never Use darkMode: 'class' in JavaScript Config
**You will be tempted to:** Add `darkMode: 'class'` to a config file.
**Why that fails:** This config key is deprecated in v4. Dark mode is CSS-only now.
**The right way:** `@custom-variant dark (&:where(.dark, .dark *));` in your CSS file.
