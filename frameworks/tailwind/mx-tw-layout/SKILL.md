---
name: mx-tw-layout
description: "Tailwind CSS layout patterns, Flexbox, CSS Grid, spacing system, visual rhythm, gap vs space, positioning, container, max-width, card grids, bento grids, holy grail layout, sidebar, sticky header, centering patterns"
---

# Tailwind CSS Layout — Flex, Grid, and Spacing for AI Coding Agents

**Load this skill when building page layouts, component structures, card grids, or any spatial arrangement with Tailwind CSS.**

## When to also load
- `mx-tw-core` — v4 configuration, variants, dark mode
- `mx-tw-responsive` — Breakpoints, container queries, fluid sizing
- `mx-tw-design-system` — Spacing tokens, theme customization
- `mx-tw-components` — Component extraction patterns

---

## Level 1: Flex vs Grid and Spacing Fundamentals (Beginner)

### Pattern 1: Flex vs Grid Decision

| Question | If Yes → |
|----------|----------|
| Aligning items in ONE direction (row or column)? | **Flexbox** (`flex`) |
| Items should size based on their content? | **Flexbox** (`flex`) |
| Need rows AND columns simultaneously? | **Grid** (`grid`) |
| Building a card grid with equal-width items? | **Grid** (`grid grid-cols-*`) |
| Page-level structure (header, sidebar, main, footer)? | **Grid** (`grid`) |
| Centering a single element? | Either — Grid is simplest (`grid place-items-center`) |

### Pattern 2: Common Flex Patterns

```html
<!-- Nav bar — content-driven spacing -->
<nav class="flex items-center justify-between px-6 py-4">
  <div class="font-bold text-xl">Logo</div>
  <div class="flex items-center gap-6">
    <a href="#">About</a>
    <a href="#">Pricing</a>
    <button class="bg-blue-600 text-white px-4 py-2 rounded-lg">Sign Up</button>
  </div>
</nav>

<!-- Center an element vertically and horizontally -->
<div class="flex items-center justify-center min-h-screen">
  <div class="max-w-md p-8 bg-white shadow-lg rounded-xl">Centered content</div>
</div>
```

### Pattern 3: Common Grid Patterns

```html
<!-- Responsive card grid — 1 col mobile, 2 tablet, 3 desktop -->
<div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
  <div class="bg-white p-6 rounded-xl shadow-sm">Card 1</div>
  <div class="bg-white p-6 rounded-xl shadow-sm">Card 2</div>
  <div class="bg-white p-6 rounded-xl shadow-sm">Card 3</div>
</div>

<!-- Grid centering — simplest syntax -->
<div class="grid place-items-center min-h-screen">
  <div>Perfectly centered</div>
</div>
```

### Pattern 4: gap > space-x/y

```html
<!-- ❌ BAD — space-x breaks on wrap, uses margin hacks -->
<div class="flex flex-wrap space-x-4 space-y-4">
  <div>Item 1</div><div>Item 2</div><div>Item 3</div>
</div>

<!-- ✅ GOOD — gap works perfectly with wrap -->
<div class="flex flex-wrap gap-4">
  <div>Item 1</div><div>Item 2</div><div>Item 3</div>
</div>
```

**Rule**: Use `gap-*` inside flex/grid containers. Only use `space-y-*` for stacked block elements outside flex/grid (like paragraphs in an article).

### Pattern 5: The 4px Spacing Scale — Visual Rhythm

Every spacing unit = 0.25rem = 4px. Consistent spacing creates visual rhythm.

| Class | Value | Pixels |
|-------|-------|--------|
| `p-1` | 0.25rem | 4px |
| `p-2` | 0.5rem | 8px |
| `p-3` | 0.75rem | 12px |
| `p-4` | 1rem | 16px |
| `p-6` | 1.5rem | 24px |
| `p-8` | 2rem | 32px |
| `p-12` | 3rem | 48px |
| `p-16` | 4rem | 64px |

```html
<!-- ❌ BAD — Random spacing destroys rhythm -->
<div class="p-5">
  <h2 class="mb-3">Title</h2>
  <p class="mb-5">Text</p>
  <button class="mt-2 px-3 py-2">Click</button>
</div>

<!-- ✅ GOOD — Consistent increments (4, 8 pattern) -->
<div class="p-8">
  <h2 class="mb-4">Title</h2>
  <p class="mb-8">Text</p>
  <button class="px-4 py-2">Click</button>
</div>
```

---

## Level 2: Page-Level Layouts (Intermediate)

### Pattern 1: Application Shell — Sidebar + Sticky Header

```html
<div class="flex h-screen overflow-hidden bg-gray-50">
  <!-- Fixed sidebar -->
  <aside class="w-64 bg-white border-r hidden lg:flex flex-col">
    <div class="h-16 flex items-center px-6 border-b font-bold">Brand</div>
    <nav class="flex-1 overflow-y-auto p-4 flex flex-col gap-1">
      <a href="#" class="px-3 py-2 bg-gray-100 rounded-lg">Dashboard</a>
      <a href="#" class="px-3 py-2 hover:bg-gray-50 rounded-lg">Settings</a>
    </nav>
  </aside>

  <!-- Main content area -->
  <div class="flex-1 flex flex-col overflow-hidden">
    <header class="h-16 bg-white border-b flex items-center px-6 shrink-0">
      Header
    </header>
    <main class="flex-1 overflow-y-auto p-6">
      <div class="max-w-5xl mx-auto">Content here</div>
    </main>
  </div>
</div>
```

### Pattern 2: Holy Grail Layout

```html
<div class="min-h-screen grid grid-rows-[auto_1fr_auto]">
  <header class="bg-gray-900 text-white p-4">Header</header>
  <div class="grid grid-cols-1 md:grid-cols-[240px_1fr_240px] gap-6 p-6">
    <aside class="bg-gray-100 p-4 rounded-lg">Left Sidebar</aside>
    <main class="bg-white p-6 shadow rounded-lg">Main Content</main>
    <aside class="bg-gray-100 p-4 rounded-lg">Right Sidebar</aside>
  </div>
  <footer class="bg-gray-900 text-white p-4 text-center">Footer</footer>
</div>
```

### Pattern 3: Bento Grid

```html
<div class="grid grid-cols-1 md:grid-cols-4 gap-4 p-8 auto-rows-[200px]">
  <!-- Hero: spans 2 cols, 2 rows -->
  <div class="bg-indigo-500 rounded-2xl md:col-span-2 md:row-span-2 p-6 text-white flex flex-col justify-end">
    <h2 class="text-2xl font-bold">Main Feature</h2>
  </div>
  <div class="bg-white border rounded-2xl p-6 shadow-sm">Metric A</div>
  <div class="bg-emerald-400 rounded-2xl md:row-span-2 p-6">Tall Item</div>
  <div class="bg-amber-400 rounded-2xl md:col-span-3 p-6">Wide Strip</div>
</div>
```

### Pattern 4: Container and Max-Width

```html
<!-- ❌ BAD — Nested containers, missing padding -->
<div class="container mx-auto">
  <div class="max-w-7xl mx-auto"><p>Content</p></div>
</div>

<!-- ✅ GOOD — Single fluid container with responsive padding -->
<section class="w-full bg-white">
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
    <div class="grid grid-cols-1 md:grid-cols-2 gap-8">
      <!-- Content -->
    </div>
  </div>
</section>
```

**Decision**: Use `max-w-7xl mx-auto px-4 sm:px-6 lg:px-8` for fluid centering. Use `container mx-auto` only if you want breakpoint-snapping widths.

---

## Level 3: Advanced Positioning and Patterns (Advanced)

### Pattern 1: When to Use Absolute Positioning

| Need | Use | NOT |
|------|-----|-----|
| Center a div | `flex items-center justify-center` or `grid place-items-center` | `absolute top-1/2 left-1/2 -translate-x/y-1/2` |
| Notification badge | `relative` parent + `absolute -top-2 -right-2` child | Margin hacks |
| Sticky header | `sticky top-0 z-50` | `fixed` (breaks document flow) |
| Modal overlay | `fixed inset-0 z-50` | `absolute` (scrolls away) |
| Tooltip/popover | `absolute` with `relative` parent | None — this is correct |

```html
<!-- ✅ GOOD — Badge overlay (correct use of absolute) -->
<button class="relative bg-blue-600 text-white px-4 py-2 rounded-lg">
  Inbox
  <span class="absolute -top-2 -right-2 flex size-5 items-center justify-center rounded-full bg-red-500 text-xs font-bold ring-2 ring-white">
    3
  </span>
</button>
```

### Pattern 2: Cards with Consistent Internal Structure

```html
<article class="bg-white rounded-xl shadow-sm border overflow-hidden flex flex-col">
  <div class="aspect-video bg-gray-200"></div>
  <div class="p-6 flex-1 flex flex-col">
    <h3 class="text-lg font-semibold mb-2">Title</h3>
    <p class="text-gray-600 flex-1 mb-4">Description that may vary in length.</p>
    <button class="w-full py-2 bg-blue-600 text-white rounded-lg">Action</button>
  </div>
</article>
```

Key: `flex-1` on the description pushes the button to the bottom regardless of text length.

---

## Performance: Make It Fast

### Perf 1: Grid Over Flex for Card Layouts
Grid automatically handles equal column widths and alignment. Flex with percentage widths and negative margins is fragile and verbose.

### Perf 2: Use aspect-ratio to Prevent CLS
`aspect-video` or `aspect-[16/9]` reserves space before images load, preventing layout shift.

### Perf 3: Avoid Animating Layout Properties
Never transition `width`, `height`, `margin`, or `padding`. Use `transform` (scale, translate) and `opacity` instead — they're GPU-accelerated.

---

## Observability: Know It's Working

### Obs 1: Check Spacing Consistency
Scan your components for mixed spacing values (p-3 next to p-5 with no system). Spacing should follow a consistent scale within each section.

### Obs 2: Test at Every Breakpoint
Check layouts at 375px (mobile), 768px (tablet), 1024px (laptop), 1440px (desktop). Grid layouts that look fine at 1440 often break at 768.

### Obs 3: Verify Flex-1 Push Patterns
Cards with varying content lengths should maintain aligned bottoms. If buttons float at different heights, the `flex-1` push pattern is missing.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Emulate Grid with Flex + Percentages
**You will be tempted to:** Use `flex flex-wrap` with `w-1/3` and negative margins for card grids.
**Why that fails:** Breaks on wrapping, requires margin hacks, doesn't maintain row alignment.
**The right way:** `grid grid-cols-3 gap-4` — clean DOM, automatic spacing, perfect alignment.

### Rule 2: Never Mix Inconsistent Spacing
**You will be tempted to:** Use `p-3` here, `p-5` there, `mb-3` next to `mb-7`.
**Why that fails:** Destroys visual rhythm. The user's eye detects asymmetry subconsciously — the site looks "off" without anyone knowing why.
**The right way:** Pick consistent increments from the 4px scale. Within a section, use the same gap/padding values. Common good combos: 4/8, 6/12, 8/16.

### Rule 3: Never Use Absolute Positioning to Center Things
**You will be tempted to:** `absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2` for centering.
**Why that fails:** Removes the element from document flow. Sibling elements ignore it. Doesn't work responsively.
**The right way:** `flex items-center justify-center` or `grid place-items-center`.

### Rule 4: Never Use space-x/y Inside Flex/Grid
**You will be tempted to:** `flex space-x-4` because it's familiar.
**Why that fails:** Uses margin hacks that break when items wrap. Creates edge-case bugs with conditional rendering.
**The right way:** `flex gap-4` — applies spacing between items at the container level, handles wrapping correctly.

### Rule 5: Never Nest Containers
**You will be tempted to:** Wrap `container mx-auto` inside another `max-w-7xl mx-auto`.
**Why that fails:** Redundant constraints. The inner container's centering fights the outer one's, potentially causing horizontal scrollbars.
**The right way:** One centering pattern per section. Either `container mx-auto px-4` OR `max-w-7xl mx-auto px-4`.
