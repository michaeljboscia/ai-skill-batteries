---
name: mx-tw-perf
description: "Tailwind CSS performance, any Tailwind CSS work, @apply anti-pattern, content detection, tree-shaking, dynamic class generation, bundle size optimization, CLS prevention, Oxide engine, Lightning CSS, purging, minification, Brotli compression, production CSS"
---

# Tailwind CSS Performance — Production Optimization for AI Coding Agents

**This skill co-loads with mx-tw-core for ANY Tailwind CSS work.** Every class, every component should follow perf-aware patterns by default.

## When to also load
- `mx-tw-core` — v4 configuration, @source directive
- `mx-tw-layout` — aspect-ratio for CLS prevention
- `mx-tw-design-system` — Override defaults to shrink output
- `mx-tw-animation` — GPU-only animation properties

---

## Level 1: @apply and Tree-Shaking Basics (Beginner)

### Pattern 1: @apply Is an Anti-Pattern

```css
/* ❌ BAD — @apply recreates traditional CSS classes */
.btn-primary {
  @apply px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600;
}
/* This DUPLICATES the underlying CSS. px-4 gets compiled twice. */

/* ✅ GOOD — Extract HTML into a component, not classes into CSS */
/* Button.tsx component with utilities inline */
```

**Why the Tailwind creator discourages @apply**: It defeats the utility-first premise. Components should abstract HTML structure + styles together. CSS-only abstractions hide the co-located relationship.

**When @apply IS acceptable**:
1. Overriding third-party library styles (you can't modify their DOM)
2. Styling CMS/Markdown content (no control over rendered HTML)

### Pattern 2: Never Concatenate Class Strings

```tsx
// ❌ BAD — Scanner sees `bg-${color}-500`, not `bg-red-500`
<div className={`bg-${color}-500 text-${color}-900`} />

// ❌ BAD — Scanner sees template literal, not complete classes
<div className={`text-${size === 'lg' ? '2xl' : 'base'}`} />

// ✅ GOOD — Complete strings visible to scanner
const colorMap = {
  red: 'bg-red-500 text-red-900',
  blue: 'bg-blue-500 text-blue-900',
  green: 'bg-green-500 text-green-900',
};
<div className={colorMap[color]} />

// ✅ GOOD — Ternary with complete strings
<div className={isActive ? 'bg-blue-500 text-white' : 'bg-gray-200 text-gray-800'} />
```

The scanner reads files as TEXT. It cannot execute JavaScript. Partial strings get purged.

### Pattern 3: Content Detection in v4

```css
/* v4 auto-detects files. Only use @source for special cases: */
@import "tailwindcss";
@source "../shared-ui-lib/**/*.tsx";     /* Monorepo packages */
@source "../node_modules/@company/ui";   /* npm package with TW classes */
@source not "../legacy-php";             /* Exclude for faster builds */
```

---

## Level 2: Bundle Size Optimization (Intermediate)

### Pattern 1: The 10KB Production Target

| Stage | Size | Action |
|-------|------|--------|
| Development CSS | ~3.5MB | All possible utilities generated |
| After tree-shaking | ~100-200KB | Only used classes remain |
| After minification (cssnano) | ~50-80KB | Whitespace/comments removed |
| After Brotli compression | **<10KB** | Network transfer size |

### Pattern 2: Strip Default Theme for Strict Systems

```css
@theme {
  --color-*: initial;    /* Removes ~200+ default color utilities */
  --spacing-*: initial;  /* If using custom spacing only */
}
```

Default theme generates ~16KB of CSS variables. Stripping unused namespaces shrinks output.

### Pattern 3: Safelisting as Last Resort

```css
/* v4: Safelist specific dynamic classes */
@source inline("bg-red-500 bg-blue-500 bg-green-500 text-red-900 text-blue-900 text-green-900");
```

Only use for truly dynamic classes (user-selected colors, CMS-driven themes). Every safelisted class adds to the bundle regardless of usage.

### Pattern 4: Disable Unused Core Plugins (v3)

```js
// tailwind.config.js (v3 only — v4 handles this automatically)
module.exports = {
  corePlugins: {
    float: false,       // Not using float layout
    objectFit: false,   // Not using object-fit
    // ... disable what you don't use
  }
};
```

---

## Level 3: CLS Prevention and Engine Architecture (Advanced)

### Pattern 1: Prevent Image CLS with aspect-ratio

```html
<!-- ❌ BAD — No dimensions. Image loads → content shifts down -->
<img src="/hero.jpg" class="w-full" />

<!-- ✅ GOOD — Space reserved before image loads -->
<img src="/hero.jpg" class="w-full h-auto aspect-video object-cover" />

<!-- Or with explicit aspect ratio -->
<div class="w-full aspect-[4/3] bg-gray-200">
  <img src="/product.jpg" class="w-full h-full object-cover" loading="lazy" />
</div>
```

### Pattern 2: Prevent Font CLS

Web fonts cause layout shift when fallback font metrics don't match custom font metrics.

**Next.js**: `next/font` auto-calculates `size-adjust`, `ascent-override`, `descent-override` for zero-CLS font swaps.

**Manual**: Use `@font-face` metric overrides:
```css
@font-face {
  font-family: 'Inter';
  src: url('/fonts/inter.woff2') format('woff2');
  font-display: swap;
  size-adjust: 107%;       /* Match fallback font metrics */
  ascent-override: 90%;
  descent-override: 22%;
}
```

### Pattern 3: Avoid Dynamic Tailwind Classes that Cause CLS

```html
<!-- ❌ BAD — Conditional class added after JS hydration shifts layout -->
<div class={cn("p-4", isLoaded && "p-8")}>
  <!-- Jumps from p-4 to p-8 on hydration -->
</div>

<!-- ✅ GOOD — Same padding always, content changes inside -->
<div class="p-8">
  {isLoaded ? <Content /> : <Skeleton />}
</div>
```

### Pattern 4: Oxide Engine Performance Characteristics

| Metric | v3 | v4 (Oxide) | Improvement |
|--------|----|-----------:|-------------|
| Full build | ~600ms | ~120ms | 5× faster |
| Incremental (new CSS) | 44ms | 5ms | 9× faster |
| Incremental (no new CSS) | 35ms | 0.19ms | 182× faster |
| Install size | — | -35% | Smaller node_modules |

Lightning CSS replaces PostCSS + autoprefixer + postcss-import. All built into the v4 engine.

---

## Observability: Know It's Working

### Obs 1: Measure Production CSS Size
After build, check the CSS file size. `ls -la .next/static/css/` or equivalent. If >50KB uncompressed, investigate.

### Obs 2: Audit for Dynamic Class Concatenation
`grep -r 'bg-\${' src/` and `grep -r 'text-\${' src/` to find string interpolation in class names. Every match is a potential purging failure.

### Obs 3: Monitor Core Web Vitals — CLS Specifically
Use Lighthouse, PageSpeed Insights, or `web-vitals` library. CLS target: <0.1. If higher, check for images without aspect-ratio, font loading without metric overrides, or conditional padding changes.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Use @apply to "Clean Up HTML"
**You will be tempted to:** Extract `@apply bg-blue-500 text-white px-4 py-2 rounded-lg` into `.btn`.
**Why that fails:** Duplicates CSS declarations. Hides the styling from the HTML. Defeats utility-first.
**The right way:** Extract the HTML into a React/Vue component. Keep utilities inline.

### Rule 2: Never Concatenate Partial Class Strings
**You will be tempted to:** `bg-${theme.color}-500` because it's "DRY."
**Why that fails:** Tailwind's scanner is a text parser. It can't execute JS. The class gets purged and your element has no background.
**The right way:** Static lookup objects with complete class strings.

### Rule 3: Never Ship Without Checking Bundle Size
**You will be tempted to:** Trust that tree-shaking "just works" without verifying.
**Why that fails:** Misconfigured @source paths, dynamic class generation, or excessive safelisting can 10× the bundle.
**The right way:** Check compressed CSS size in production build. Target: <10KB over the wire.

### Rule 4: Never Animate Layout Properties
**You will be tempted to:** `transition-all` on an element that changes `width` or `height`.
**Why that fails:** Layout recalculation on every frame. Drops to <30fps on mobile. Causes CLS.
**The right way:** Animate `transform` (scale, translate) and `opacity` only. These are GPU-composited.

### Rule 5: Never Skip aspect-ratio on Media Elements
**You will be tempted to:** `<img src="..." class="w-full">` without height or aspect-ratio.
**Why that fails:** Browser allocates 0px height until image loads. Content below shifts down = CLS failure.
**The right way:** Always include `aspect-video` or `aspect-[W/H]` on images, videos, and embeds.
