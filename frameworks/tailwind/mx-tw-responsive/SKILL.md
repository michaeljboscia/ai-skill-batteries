---
name: mx-tw-responsive
description: "Tailwind CSS responsive design, mobile-first methodology, breakpoints sm md lg xl 2xl, container queries @container, fluid typography clamp, responsive component patterns, progressive enhancement, viewport vs container"
---

# Tailwind CSS Responsive — Mobile-First and Container Queries for AI Coding Agents

**Load this skill when building responsive layouts, adapting components across screen sizes, or implementing fluid typography.**

## When to also load
- `mx-tw-core` — Breakpoint configuration, v4 features
- `mx-tw-layout` — Grid/Flex patterns that adapt responsively
- `mx-tw-design-system` — Fluid typography token configuration

---

## Level 1: Mobile-First Methodology (Beginner)

### Pattern 1: Unprefixed = Mobile, Prefixed = Larger

```html
<!-- This IS mobile-first -->
<div class="text-base md:text-lg lg:text-xl">
  <!-- Mobile: text-base (always) -->
  <!-- Tablet+: text-lg (md: and up) -->
  <!-- Desktop+: text-xl (lg: and up) -->
</div>

<!-- ❌ BAD: Desktop-first thinking -->
<div class="flex flex-row sm:flex-col md:flex-row">
  <!-- Confusing: sets row, overrides to col at sm, back to row at md -->
</div>

<!-- ✅ GOOD: Mobile-first thinking -->
<div class="flex flex-col md:flex-row">
  <!-- Mobile: stacked (col) -->
  <!-- Tablet+: side by side (row) -->
</div>
```

**The mental model**: Write styles for a 375px phone screen. Then add `md:` for what changes on tablet. Then `lg:` for desktop. If it doesn't need to change, don't add a prefix.

### Pattern 2: Responsive Grid Progression

```html
<!-- 1 → 2 → 3 → 4 columns as screen widens -->
<div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
  <div class="bg-white p-6 rounded-xl shadow-sm">Card</div>
  <!-- ... more cards -->
</div>
```

### Pattern 3: Show/Hide Based on Breakpoint

```html
<!-- Mobile hamburger menu -->
<button class="md:hidden p-2">☰ Menu</button>

<!-- Desktop nav links -->
<nav class="hidden md:flex gap-6">
  <a href="#">About</a>
  <a href="#">Pricing</a>
</nav>
```

### Pattern 4: Responsive Spacing

```html
<!-- Tighter on mobile, more generous on desktop -->
<section class="px-4 py-8 sm:px-6 sm:py-12 lg:px-8 lg:py-16">
  <div class="max-w-7xl mx-auto">
    <h1 class="text-2xl sm:text-3xl lg:text-4xl font-bold">Heading</h1>
  </div>
</section>
```

---

## Level 2: Container Queries (Intermediate)

### Pattern 1: Component-Level Responsiveness

Container queries let components adapt to their PARENT's width, not the viewport. A card in a 300px sidebar behaves differently than the same card in an 800px main area — on the same screen.

```html
<!-- Mark the parent as a container -->
<div class="@container">
  <!-- Child responds to container width, not viewport -->
  <article class="flex flex-col @md:flex-row gap-4 p-4">
    <img src="thumbnail.jpg" class="w-full @md:w-1/3 rounded-lg object-cover" />
    <div>
      <h3 class="text-lg @md:text-xl font-bold">Title</h3>
      <p class="hidden @md:block text-gray-600">
        Long description only shown when container is wide enough
      </p>
    </div>
  </article>
</div>
```

**v4**: Container queries are first-class — no plugin needed. `@container` on parent, `@sm:`, `@md:`, `@lg:` on children.

### Pattern 2: Named Containers

```html
<!-- Named container for specificity -->
<div class="@container/sidebar">
  <nav class="flex flex-col @md/sidebar:flex-row gap-2">
    <a href="#">Link 1</a>
    <a href="#">Link 2</a>
  </nav>
</div>
```

### Pattern 3: Viewport vs Container — Decision Tree

| What you're adapting | Use |
|---------------------|-----|
| Page structure (sidebar visible/hidden) | Viewport breakpoints (`md:`, `lg:`) |
| Navigation layout (hamburger vs horizontal) | Viewport breakpoints |
| Component internal layout (card, widget) | Container queries (`@md:`, `@lg:`) |
| Reusable widget in multiple contexts | Container queries |

**Hybrid architecture**: Viewport for macro page layout. Container for micro component layout.

---

## Level 3: Fluid Typography and Advanced Patterns (Advanced)

### Pattern 1: Fluid Typography with clamp()

```css
/* app.css — Define fluid type scale in @theme */
@import "tailwindcss";

@theme {
  --text-fluid-display: clamp(2.5rem, 1.5rem + 4vw, 5rem);
  --text-fluid-h1: clamp(1.75rem, 1rem + 3vw, 3.5rem);
  --text-fluid-body: clamp(1rem, 0.92rem + 0.4vw, 1.25rem);
}

@utility text-fluid-display {
  font-size: var(--text-fluid-display);
  line-height: 1.05;
  letter-spacing: -0.02em;
}

@utility text-fluid-h1 {
  font-size: var(--text-fluid-h1);
  line-height: 1.15;
}

@utility text-fluid-body {
  font-size: var(--text-fluid-body);
  line-height: 1.6;
}
```

```html
<!-- Smooth scaling — no breakpoint jumps -->
<h1 class="text-fluid-display font-bold">Hero Title</h1>
<p class="text-fluid-body text-gray-600">Body text scales smoothly.</p>
```

**The clamp() formula**: `clamp(min, preferred, max)` where preferred is usually `Xrem + Yvw` for smooth interpolation.

### Pattern 2: Responsive Navigation Pattern

```html
<header class="flex items-center justify-between p-4 lg:px-8">
  <div class="font-bold text-xl">Logo</div>

  <!-- Mobile: hamburger trigger -->
  <button class="lg:hidden p-2 rounded-lg hover:bg-gray-100" aria-label="Menu">
    <svg class="w-6 h-6"><!-- hamburger icon --></svg>
  </button>

  <!-- Desktop: inline nav (single DOM, not duplicated) -->
  <nav id="main-nav" class="
    hidden absolute top-full left-0 w-full flex-col bg-white shadow-lg
    lg:static lg:flex lg:flex-row lg:w-auto lg:shadow-none lg:gap-6
  ">
    <a href="#" class="p-4 lg:p-0 hover:text-blue-600 transition-colors">Home</a>
    <a href="#" class="p-4 lg:p-0 hover:text-blue-600 transition-colors">About</a>
    <a href="#" class="p-4 lg:p-0 hover:text-blue-600 transition-colors">Pricing</a>
  </nav>
</header>
```

**Key**: Single nav in DOM. CSS transforms its layout. No duplicate HTML for mobile/desktop.

### Pattern 3: Responsive Data Display

```html
<!-- Mobile: stacked key-value pairs. Desktop: data grid -->
<div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
  <div class="p-4 bg-white rounded-lg shadow-sm">
    <p class="text-sm text-gray-500">Revenue</p>
    <p class="text-2xl font-bold">$48.2K</p>
  </div>
  <div class="p-4 bg-white rounded-lg shadow-sm">
    <p class="text-sm text-gray-500">Users</p>
    <p class="text-2xl font-bold">2,847</p>
  </div>
  <!-- ... -->
</div>
```

---

## Performance: Make It Fast

### Perf 1: Mobile-First = Less CSS on Mobile
Mobile devices parse fewer CSS rules because breakpoint styles only apply at larger widths. The base (unprefixed) CSS is the smallest payload.

### Perf 2: Container Queries Are GPU-Optimized
Browser engines handle container queries on the compositor thread. They don't trigger JS-level observers or layout recalculations.

### Perf 3: Fluid Typography Eliminates Breakpoint Overhead
One `clamp()` rule replaces 5+ breakpoint-specific font-size rules. Smaller CSS, smoother rendering, less to maintain.

---

## Observability: Know It's Working

### Obs 1: Test at Real Device Widths
Don't just resize your browser. Test: 375px (iPhone SE), 390px (iPhone 15), 768px (iPad portrait), 1024px (iPad landscape), 1440px (laptop), 1920px (desktop).

### Obs 2: Test Components in Different Container Sizes
A card component should work in a 300px sidebar AND an 800px main area. Container queries make this testable — but only if you actually test both contexts.

### Obs 3: Check for Horizontal Scroll
At every breakpoint, verify no element causes horizontal overflow. Common culprit: fixed-width elements (`w-96`) on mobile.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Write Desktop-First
**You will be tempted to:** Start with the desktop layout, then add `sm:` overrides to fix mobile.
**Why that fails:** Creates complex override chains. Mobile styles fight desktop defaults. More CSS shipped to mobile devices.
**The right way:** Unprefixed = mobile. Add complexity at `md:` and `lg:`.

### Rule 2: Never Use Viewport Breakpoints for Component Internals
**You will be tempted to:** `md:flex-row` inside a card component.
**Why that fails:** Works when the card is full-width. Breaks when the card is in a narrow sidebar on a wide screen — `md:` fires based on viewport, not available space.
**The right way:** `@container` on parent + `@md:flex-row` on children. Component adapts to its context.

### Rule 3: Never Micromanage Breakpoints for Typography
**You will be tempted to:** `text-sm sm:text-base md:text-lg lg:text-xl xl:text-2xl`.
**Why that fails:** 5 discrete jumps. Looks jarring between breakpoints. Bloats class strings.
**The right way:** Fluid typography with `clamp()`. One class, smooth continuous scaling.

### Rule 4: Never Duplicate DOM for Mobile/Desktop
**You will be tempted to:** Render `<MobileNav>` and `<DesktopNav>` as separate components, toggling with `hidden md:block`.
**Why that fails:** Duplicate HTML in the DOM. Screen readers see both. Double maintenance burden.
**The right way:** Single nav element. CSS transforms its layout at breakpoints. JS toggles visibility on mobile.

### Rule 5: Never Ship Without Checking 375px
**You will be tempted to:** Test at 768px and call it "mobile tested."
**Why that fails:** 375px is the most common mobile width (iPhone SE/Mini). Text overflow, horizontal scrollbars, and cramped buttons all appear here.
**The right way:** 375px is your PRIMARY test width. If it works there, it works everywhere wider.
