---
name: mx-tw-design-system
description: "Tailwind CSS design system, @theme directive, design tokens, CSS variables, semantic colors, dark mode systematic implementation, typography system, @tailwindcss/typography, extending vs overriding theme, OKLCH colors, font loading, next-themes"
---

# Tailwind CSS Design System — Tokens, Theming, and Typography for AI Coding Agents

**Load this skill when configuring design tokens, building a color system, implementing dark mode, or setting up typography in Tailwind CSS v4.**

## When to also load
- `mx-tw-core` — v4 configuration fundamentals, @theme directive basics
- `mx-tw-components` — CVA variants consume design tokens
- `mx-tw-responsive` — Fluid typography with clamp()
- `mx-tw-animation` — Dark mode affects animation colors

---

## Level 1: Semantic Color Architecture (Beginner)

### Pattern 1: Semantic Names Over Literal Colors

```css
/* ❌ BAD — Literal colors tightly couple components to specific values */
/* Using bg-blue-500 everywhere. Rebrand to purple? Audit every file. */

/* ✅ GOOD — Semantic tokens abstract intent from implementation */
@import "tailwindcss";

@theme {
  --color-*: initial;  /* Strip all default colors for strict control */

  /* Brand */
  --color-primary: oklch(0.55 0.22 255);
  --color-primary-hover: oklch(0.45 0.22 255);

  /* Surfaces */
  --color-surface: oklch(0.98 0.01 240);
  --color-surface-muted: oklch(0.95 0.01 240);
  --color-surface-inverse: oklch(0.20 0.02 240);

  /* Text */
  --color-text: oklch(0.20 0.02 240);
  --color-text-muted: oklch(0.50 0.02 240);
  --color-text-inverse: oklch(0.98 0.01 240);

  /* Feedback */
  --color-destructive: oklch(0.55 0.20 20);
  --color-success: oklch(0.55 0.20 145);

  /* Structural */
  --color-border: oklch(0.90 0.01 240);
}
```

Components use: `bg-surface`, `text-text-muted`, `border-border`. Rebranding = change one CSS file.

### Pattern 2: The --color-*: initial Approach

By default, @theme *extends* Tailwind's palette. Every default color (slate, gray, red, blue, etc.) generates utilities. For production design systems, strip them:

```css
@theme {
  --color-*: initial;  /* Removes ALL default colors */
  /* Now only YOUR tokens exist. No bg-blue-500, no text-gray-700 */

  --color-primary: ...;
  --color-surface: ...;
}
```

**When to extend (keep defaults)**: Prototypes, MVPs, projects without design guidelines.
**When to override (initial)**: Production apps, brand-specific projects, teams needing guardrails.

### Pattern 3: OKLCH for Modern Color Spaces

```css
/* OKLCH = perceptually uniform color space. Better for: */
/* - Consistent perceived brightness across hues */
/* - Easy lightness/chroma adjustments */
/* - color-mix() compatibility in v4 */

@theme {
  --color-primary: oklch(0.55 0.22 255);       /* Blue */
  --color-primary-hover: oklch(0.45 0.22 255);  /* Darker blue (same hue, less lightness) */
}
```

---

## Level 2: Systematic Dark Mode (Intermediate)

### Pattern 1: CSS Variable Override Strategy

The best dark mode architecture avoids littering markup with `dark:` prefixes. Components use semantic tokens; CSS swaps the values.

```css
@import "tailwindcss";
@custom-variant dark (&:where([data-theme="dark"], [data-theme="dark"] *));

@layer base {
  :root, [data-theme="light"] {
    --bg-base: oklch(1 0 0);
    --text-base: oklch(0.15 0 0);
    --border-base: oklch(0.9 0 0);
    --primary-base: oklch(0.6 0.2 250);
  }

  [data-theme="dark"] {
    --bg-base: oklch(0.15 0 0);
    --text-base: oklch(0.95 0 0);
    --border-base: oklch(0.25 0 0);
    --primary-base: oklch(0.7 0.2 250);  /* Lighter for dark backgrounds */
  }
}

@theme inline {
  --color-surface: var(--bg-base);
  --color-text: var(--text-base);
  --color-border: var(--border-base);
  --color-primary: var(--primary-base);
}
```

Now `bg-surface text-text border-border` works in BOTH modes. Zero `dark:` prefixes in components.

### Pattern 2: Preventing FOUC (Flash of Unstyled Content)

```html
<head>
  <script>
    // Synchronous — runs before body renders
    (function() {
      var saved = localStorage.getItem('theme');
      var system = window.matchMedia('(prefers-color-scheme: dark)').matches;
      if (saved === 'dark' || (!saved && system)) {
        document.documentElement.setAttribute('data-theme', 'dark');
      } else {
        document.documentElement.setAttribute('data-theme', 'light');
      }
    })();
  </script>
</head>
```

For Next.js: use `next-themes` with `attribute="data-theme"` — handles SSR hydration mismatch, system detection, and persistence.

### Pattern 3: When dark: Prefixes ARE Appropriate

Use `dark:` for edge cases where the semantic token approach doesn't apply:
- One-off decorative overrides
- Third-party component styling
- Shadows (dark mode often needs different shadow colors, not just swapped values)

```html
<!-- Shadow needs different opacity, not a variable swap -->
<div class="shadow-lg dark:shadow-none dark:ring-1 dark:ring-white/10">
```

---

## Level 3: Typography System and Theme Architecture (Advanced)

### Pattern 1: Granular Typography Tokens

```css
@theme {
  /* Font families */
  --font-sans: "Inter", system-ui, sans-serif;
  --font-display: "Clash Display", sans-serif;
  --font-mono: "JetBrains Mono", monospace;

  /* Font sizes with linked sub-properties (v4 double-dash syntax) */
  --text-h1: 3rem;
  --text-h1--line-height: 1.1;
  --text-h1--font-weight: 700;
  --text-h1--letter-spacing: -0.02em;

  --text-h2: 2rem;
  --text-h2--line-height: 1.2;
  --text-h2--font-weight: 600;

  --text-body: 1rem;
  --text-body--line-height: 1.6;

  --text-caption: 0.75rem;
  --text-caption--line-height: 1.5;
  --text-caption--font-weight: 500;
}
```

Using `text-h1` in HTML auto-applies the font-size, line-height, font-weight, AND letter-spacing. One class = complete typographic style.

### Pattern 2: @tailwindcss/typography Plugin

```css
@import "tailwindcss";
@plugin "@tailwindcss/typography";

/* Theme the prose classes with your design tokens */
@theme {
  --color-prose-body: var(--text-base);
  --color-prose-headings: var(--text-base);
  --color-prose-links: var(--primary-base);
  --color-prose-bold: var(--text-base);
  --color-prose-quotes: oklch(0.50 0.02 240);
}
```

```html
<!-- Renders CMS/Markdown content with your design system typography -->
<article class="prose prose-lg max-w-none">
  <!-- Raw HTML from CMS renders beautifully -->
</article>
```

### Pattern 3: Extending vs Overriding the Full Theme

```css
/* EXTEND — keeps defaults + adds your tokens */
@theme {
  --color-brand: #1E40AF;          /* Adds bg-brand alongside bg-blue-500 etc */
  --spacing-128: 32rem;             /* Adds p-128 alongside p-4, p-8 etc */
}

/* OVERRIDE — removes defaults, only your tokens exist */
@theme {
  --color-*: initial;               /* Removes ALL default colors */
  --spacing-*: initial;             /* Removes ALL default spacing */
  --*: initial;                     /* Nuclear: removes ENTIRE default theme */

  --color-primary: oklch(0.55 0.22 255);
  --spacing-sm: 0.5rem;
  --spacing-md: 1rem;
  --spacing-lg: 2rem;
}
```

---

## Performance: Make It Fast

### Perf 1: Override Removes ~16KB of Unused CSS Variables
The default theme generates CSS variables for every color shade, spacing value, etc. Using `--color-*: initial` strips them from the output.

### Perf 2: CSS Variables Enable Runtime Theme Switching
Unlike build-time Tailwind config, CSS variables can be swapped at runtime — no rebuild needed for dark mode or multi-brand theming.

### Perf 3: OKLCH + color-mix() for Dynamic Opacity
v4 supports `color-mix()` natively. Instead of generating 10 opacity variants, use: `bg-primary/50` (50% opacity of your primary token).

---

## Observability: Know It's Working

### Obs 1: Verify Both Themes in Storybook
Every component must be visually verified in light AND dark mode. Use `@storybook/addon-themes` with `withThemeByClassName` decorator.

### Obs 2: Check Contrast Ratios
WCAG AA requires 4.5:1 for normal text, 3:1 for large text. Dark mode often fails this — dark text on dark backgrounds, or brand colors that "vibrate" on black.

### Obs 3: Audit for Hardcoded Colors
`grep -r "bg-\[#" src/` catches arbitrary hex colors. Every instance should be a design token.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Hardcode Hex Colors in Components
**You will be tempted to:** Write `bg-[#2463EB]` because you're reading from a Figma spec.
**Why that fails:** Breaks design system cohesion. Can't be themed. Can't switch in dark mode.
**The right way:** Add the color to `@theme` as a semantic token. Use `bg-primary`.

### Rule 2: Never Use Default Palette in Production
**You will be tempted to:** Ship `text-gray-500`, `bg-blue-600` because it "looks right."
**Why that fails:** Every AI-generated site uses the same default palette. It's the #1 reason sites look generic.
**The right way:** `--color-*: initial` + define your own semantic palette from the brand guidelines.

### Rule 3: Never Implement Dark Mode as an Afterthought
**You will be tempted to:** Build everything in light mode, then add `dark:` prefixes everywhere.
**Why that fails:** Thousands of `dark:bg-slate-900 dark:text-white` scattered across files. Unmaintainable. Inconsistent.
**The right way:** CSS variable architecture from day one. Components use semantic tokens. Dark mode = swap variables at `:root` level.

### Rule 4: Never Skip the FOUC Prevention Script
**You will be tempted to:** Let JavaScript handle theme detection after hydration.
**Why that fails:** Users see a white flash before dark mode applies. On slow connections, it's jarring.
**The right way:** Synchronous `<script>` in `<head>` that reads localStorage before the body renders.

### Rule 5: Never Manually Pair Text Sizes with Line Heights
**You will be tempted to:** Write `text-3xl leading-tight font-bold tracking-tight` on every heading.
**Why that fails:** Inconsistent — some headings get the right pairing, others don't.
**The right way:** Use v4 linked sub-properties: `--text-h1--line-height`, `--text-h1--font-weight`. One class (`text-h1`) does everything.
