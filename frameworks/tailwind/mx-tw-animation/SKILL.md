---
name: mx-tw-animation
description: "Tailwind CSS animations, transitions, hover states, focus-visible, focus-within, active states, prefers-reduced-motion, motion-safe, motion-reduce, keyframes, @theme animations, entrance animations, scroll reveals, tailwindcss-animate, accessibility"
---

# Tailwind CSS Animation — Transitions, Motion, and Accessibility for AI Coding Agents

**Load this skill when adding transitions, hover effects, animations, focus styles, or implementing motion-safe accessibility in Tailwind CSS.**

## When to also load
- `mx-tw-core` — v4 @theme for custom keyframes
- `mx-tw-components` — Interactive component state patterns
- `mx-tw-design-system` — Dark mode affects animation colors
- `mx-tw-responsive` — Animations may need viewport-aware triggers

---

## Level 1: Transitions and Interactive States (Beginner)

### Pattern 1: Every Interactive Element Needs a Transition

```html
<!-- ❌ BAD — Instant color flip, feels broken -->
<button class="bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-500">
  Click
</button>

<!-- ✅ GOOD — Smooth 200ms color transition -->
<button class="bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-500 transition-colors duration-200">
  Click
</button>
```

### Pattern 2: Transition Property Scope

| Utility | What It Transitions | Performance |
|---------|-------------------|-------------|
| `transition-colors` | color, background-color, border-color, fill, stroke | Good |
| `transition-opacity` | opacity | Excellent (GPU) |
| `transition-transform` | transform (scale, translate, rotate) | Excellent (GPU) |
| `transition-shadow` | box-shadow | Good |
| `transition-all` | Everything | Avoid — triggers unnecessary interpolation |

**Rule**: Be specific. `transition-colors` for color changes, `transition-transform` for movement.

### Pattern 3: Duration and Easing

```html
<!-- Micro-interactions: 150-200ms, ease-out -->
<button class="transition-colors duration-200 ease-out hover:bg-blue-500">

<!-- Enter animations: 300-500ms, ease-out (fast start, slow finish) -->
<div class="transition-all duration-300 ease-out">

<!-- Exit animations: 200-300ms, ease-in (slow start, fast exit) -->
<div class="transition-opacity duration-200 ease-in">
```

| Duration | Use for |
|----------|---------|
| `duration-150` | Button color changes, icon swaps |
| `duration-200` | Hover effects, focus rings |
| `duration-300` | Card hover lifts, panel slides |
| `duration-500` | Page-level entrance animations |

### Pattern 4: The Interaction Trinity — Hover + Active + Focus

```html
<button class="
  bg-emerald-600 text-white px-5 py-2.5 rounded-lg font-medium shadow-sm
  transition-all duration-200 ease-out
  hover:bg-emerald-500 hover:shadow-md hover:-translate-y-0.5
  active:bg-emerald-700 active:shadow-inner active:translate-y-0 active:scale-95
  focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-400 focus-visible:ring-offset-2
">
  Submit
</button>
```

- **hover**: Visual feedback — "this is interactive"
- **active**: Tactile feedback — "you're pressing it" (scale down, darken)
- **focus-visible**: Accessibility — "keyboard users can see where they are"

---

## Level 2: Focus Management and Accessibility (Intermediate)

### Pattern 1: focus-visible vs focus

| Variant | When it Fires | Use for |
|---------|--------------|---------|
| `focus:` | ANY focus (mouse click, keyboard, programmatic) | Text inputs (always need visible focus) |
| `focus-visible:` | Keyboard focus ONLY (Tab/Shift+Tab) | Buttons, links (hide ring on mouse click) |
| `focus-within:` | When ANY child has focus | Form containers, search bars |

```html
<!-- Buttons: focus-visible (keyboard only) -->
<button class="focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2">

<!-- Inputs: focus (always show) -->
<input class="focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none" />

<!-- Form container: highlight when child input is focused -->
<form class="border rounded-xl p-4 transition-all duration-200 focus-within:border-indigo-500 focus-within:ring-4 focus-within:ring-indigo-500/20">
  <input class="outline-none w-full" placeholder="Search..." />
</form>
```

### Pattern 2: Group and Peer State

```html
<!-- Group hover: parent state drives child styling -->
<a href="#" class="group block p-6 bg-white rounded-xl shadow-sm hover:bg-gray-50 transition-colors">
  <h3 class="font-semibold group-hover:text-blue-600 transition-colors">Title</h3>
  <p class="text-gray-500">Description</p>
  <svg class="mt-2 w-5 h-5 text-blue-600 transition-transform group-hover:translate-x-2">→</svg>
</a>
```

### Pattern 3: prefers-reduced-motion — MANDATORY

```html
<!-- Strategy A (Preferred): Opt-IN to motion -->
<!-- Animation only plays if user hasn't disabled motion -->
<div class="motion-safe:animate-slide-up-fade">Welcome back</div>

<!-- Strategy B: Opt-OUT of motion -->
<!-- Animation plays by default, disabled for sensitive users -->
<div class="animate-bounce motion-reduce:animate-none">↓ Scroll</div>

<!-- BEST: Degrade spatial motion to opacity fade -->
<div class="
  opacity-0
  motion-safe:translate-y-10
  motion-reduce:translate-y-0
  transition-all duration-500 ease-out
  data-[visible=true]:opacity-100
  data-[visible=true]:translate-y-0
">
  <!-- Standard users: slide up + fade in -->
  <!-- Reduced motion users: just fade in (no spatial movement) -->
</div>
```

**What's safe for reduced-motion users**: opacity fades, color transitions.
**What triggers vestibular distress**: scaling, translating, rotating, parallax, zooming.

---

## Level 3: Custom Animations and Scroll Reveals (Advanced)

### Pattern 1: Custom Keyframes in v4 @theme

```css
@import "tailwindcss";

@theme {
  --animate-wiggle: wiggle 0.6s ease-in-out infinite;
  --animate-slide-up-fade: slide-up-fade 0.5s cubic-bezier(0.16, 1, 0.3, 1) forwards;
  --animate-shimmer: shimmer 2s linear infinite;

  @keyframes wiggle {
    0%, 100% { transform: rotate(-3deg); }
    50% { transform: rotate(3deg); }
  }

  @keyframes slide-up-fade {
    0% { opacity: 0; transform: translateY(20px); }
    100% { opacity: 1; transform: translateY(0); }
  }

  @keyframes shimmer {
    0% { background-position: -1000px 0; }
    100% { background-position: 1000px 0; }
  }
}
```

```html
<button class="hover:animate-wiggle">Wiggle on hover</button>
<div class="motion-safe:animate-slide-up-fade">Entrance animation</div>
<div class="animate-shimmer bg-gradient-to-r from-gray-200 via-gray-100 to-gray-200 bg-[length:2000px_100%]">Skeleton</div>
```

### Pattern 2: Built-in Animations

| Utility | Effect | Use for |
|---------|--------|---------|
| `animate-spin` | 360° rotation, linear, infinite | Loading spinners |
| `animate-ping` | Scale out + fade, infinite | Notification dots |
| `animate-pulse` | Opacity 100%↔50%, infinite | Skeleton loaders |
| `animate-bounce` | Y-axis bounce, infinite | Scroll indicators |

Always wrap in `motion-safe:` — `motion-safe:animate-spin`.

### Pattern 3: Scroll-Triggered Entrance (IntersectionObserver)

```html
<!-- Start invisible and displaced -->
<section class="opacity-0 translate-y-12 transition-all duration-700 ease-out" data-reveal>
  <h2>Section Title</h2>
</section>
```

```js
const observer = new IntersectionObserver((entries) => {
  const prefersReduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      entry.target.classList.remove('opacity-0');
      if (!prefersReduced) entry.target.classList.remove('translate-y-12');
      observer.unobserve(entry.target);
    }
  });
}, { threshold: 0.1 });

document.querySelectorAll('[data-reveal]').forEach(el => observer.observe(el));
```

### Pattern 4: tailwindcss-animate (shadcn standard)

```html
<!-- Composable enter/exit animations -->
<div class="animate-in fade-in zoom-in-95 slide-in-from-bottom-2 duration-200">
  Tooltip appears
</div>

<div class="animate-out fade-out zoom-out-95 slide-out-to-top-2 duration-150">
  Tooltip disappears
</div>
```

---

## Performance: Make It Fast

### Perf 1: Only Animate transform and opacity
These run on the GPU compositor thread — 60fps guaranteed. Animating `width`, `height`, `margin`, or `top` triggers CPU layout recalculation = jank.

### Perf 2: Avoid transition-all
`transition-all` interpolates every CSS property. Use `transition-colors`, `transition-transform`, or `transition-opacity` for targeted, performant transitions.

### Perf 3: Keep Durations Short
Micro-interactions: 150-200ms. Entrances: 300-500ms. Anything over 400ms feels sluggish.

---

## Observability: Know It's Working

### Obs 1: Test with Reduced Motion Enabled
macOS: System Preferences → Accessibility → Display → Reduce motion. Verify all spatial animations gracefully degrade to fades or disappear.

### Obs 2: Verify Focus Rings on Keyboard Navigation
Tab through your entire page. Every button, link, and input should show a visible focus indicator. If any element "disappears" from tab order, focus-visible styling is missing.

### Obs 3: Check Animation Orchestration
Staggered entrance animations should have consistent delay increments (delay-100, delay-200, delay-300). Random delays look chaotic.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Ship Interactive Elements Without Transitions
**You will be tempted to:** Skip `transition-colors duration-200` on a button hover.
**Why that fails:** Instant color changes feel broken. Users question if the interface is responsive.
**The right way:** Every interactive element needs a transition on at least its color properties.

### Rule 2: Never Ignore prefers-reduced-motion
**You will be tempted to:** Add `animate-bounce` or `animate-spin` without `motion-safe:`.
**Why that fails:** Users with vestibular disorders experience nausea and dizziness. This is an accessibility violation.
**The right way:** `motion-safe:animate-bounce`. Always. No exceptions for spatial animations.

### Rule 3: Never Use focus:outline-none Without focus-visible Replacement
**You will be tempted to:** `focus:outline-none` to remove the "ugly" browser focus ring.
**Why that fails:** Keyboard users can no longer see where they are. WCAG 2.4.7 violation.
**The right way:** `focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2`.

### Rule 4: Never Animate Layout Properties
**You will be tempted to:** `transition-all` then change `width`, `height`, `margin`, or `top`.
**Why that fails:** Forces browser to recalculate layout on every frame. Drops to <30fps on mobile. Causes CLS.
**The right way:** Use `transform` (scale for size changes, translate for position changes) and `opacity`.

### Rule 5: Never Add Motion Without Purpose
**You will be tempted to:** Animate everything because it "looks cool."
**Why that fails:** Gratuitous motion is distracting, slows perceived performance, and annoys power users.
**The right way:** Motion should provide feedback (hover), spatial context (entrance), or status (loading). If it doesn't serve one of these, remove it.
