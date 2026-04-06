---
name: mx-gsap-perf
description: GSAP animation performance optimization, any GSAP work — GPU layer management, force3D, will-change strategy, lazy ScrollTrigger, gsap.matchMedia responsive, memory leak prevention, gsap.quickTo, gsap.quickSetter, large list animation, prefers-reduced-motion. Co-loads with mx-gsap-core for ANY GSAP work.
---

# GSAP Performance Optimization for AI Coding Agents

**This skill co-loads with GSAP core for ANY GSAP work. Ensures every animation follows perf-aware patterns by default.**

## When to also load
- For basic perf rules (prefer transforms): see official **gsap-performance** skill
- For React/Next.js integration: **mx-gsap-react**
- For text animation patterns: **mx-gsap-text**
- For debugging perf issues: **mx-gsap-observability**

---

## Level 1: GPU Layer Management (Beginner)

### Transform vs Layout Properties

| Animate This | Not This | Why |
|-------------|----------|-----|
| `x`, `y` | `top`, `left` | Transforms stay on GPU compositor — no layout recalc |
| `scale`, `scaleX`, `scaleY` | `width`, `height` | Scale manipulates bitmap, width triggers reflow |
| `rotation` | `transform: rotate()` string | GSAP aliases are optimized, string parsing is not |
| `autoAlpha` | `opacity` + manual `visibility` | autoAlpha toggles visibility:hidden at 0, preventing ghost clicks |

### force3D: "auto" vs true

```javascript
// DEFAULT (force3D: "auto") — Use for most animations
// Promotes to GPU during animation, releases after
gsap.to(".card", { x: 100, duration: 1 }); // force3D: "auto" by default

// ONLY for continuously animated elements (spinners, looping particles)
gsap.to(".spinner", { rotation: 360, force3D: true, repeat: -1, ease: "none" });
```

| Scenario | force3D Setting |
|----------|----------------|
| One-shot animation (enters viewport, plays once) | `"auto"` (default) — releases VRAM after |
| Continuous loop (spinner, particles) | `true` — avoids repeated GPU alloc/dealloc |
| 100+ elements animating simultaneously | `"auto"` — `true` on all would exhaust VRAM |

### will-change: Apply Before, Remove After

```javascript
const animatePanel = (el) => {
  el.style.willChange = "transform, opacity"; // Hint browser BEFORE animation

  gsap.to(el, {
    x: 100, opacity: 0.8, duration: 0.5,
    onComplete: () => {
      el.style.willChange = "auto"; // Release GPU memory AFTER
    }
  });
};
```

**Never** set `will-change: transform` globally or on many elements. It's a budget — exceeding it causes texture thrashing and blurry text.

---

## Level 2: Lazy Initialization & Responsive Performance (Intermediate)

### Lazy ScrollTrigger: Initialize Near Viewport

```javascript
// BAD: Creates complex timeline on page load for below-fold section
const tl = gsap.timeline({ scrollTrigger: { trigger: ".heavy-section" } });
tl.to(".el-1", { x: 100 }).to(".el-2", { rotation: 180 });

// GOOD: Defer creation until element approaches viewport
ScrollTrigger.create({
  trigger: ".heavy-section",
  start: "top 150%", // 50% before it's visible
  once: true,
  onEnter: () => {
    const tl = gsap.timeline({ scrollTrigger: { trigger: ".heavy-section", scrub: true } });
    tl.to(".el-1", { x: 100 }).to(".el-2", { rotation: 180 });
  }
});
```

### ScrollTrigger.batch() for Many Elements

```javascript
// BAD: Individual ScrollTrigger per card (100 cards = 100 observers)
cards.forEach(card => {
  gsap.from(card, { opacity: 0, y: 50, scrollTrigger: { trigger: card } });
});

// GOOD: Single optimized observer for all cards
gsap.set(".card", { y: 50, opacity: 0 });

ScrollTrigger.batch(".card", {
  interval: 0.1,
  batchMax: 5,
  onEnter: (batch) => {
    gsap.to(batch, { opacity: 1, y: 0, stagger: 0.1, overwrite: true });
  }
});
```

### gsap.matchMedia() — Responsive + Accessibility

```javascript
const mm = gsap.matchMedia();

mm.add({
  isDesktop: "(min-width: 800px)",
  isMobile: "(max-width: 799px)",
  reduceMotion: "(prefers-reduced-motion: reduce)"
}, (ctx) => {
  const { isDesktop, isMobile, reduceMotion } = ctx.conditions;

  if (reduceMotion) {
    // Accessibility: opacity fade only, no spatial transforms
    gsap.from(".hero", { opacity: 0, duration: 1 });
    return;
  }

  if (isDesktop) {
    gsap.timeline({ scrollTrigger: { trigger: ".hero", scrub: true, pin: true } })
      .to(".hero-element", { scale: 2, rotation: 360 });
  }

  if (isMobile) {
    // Simplified: no pinning, fewer tweens, less GPU work
    gsap.to(".hero-element", { y: -50, opacity: 1 });
  }
  // Context auto-reverts animations when breakpoint changes
});
```

| User Environment | Strategy |
|-----------------|----------|
| Desktop, no motion preference | Full sequences, pinning, scrubbing |
| Mobile, no motion preference | Simplified transforms, no pinning |
| `prefers-reduced-motion: reduce` | Opacity fades only, zero spatial transforms |

---

## Level 3: Memory Management & High-Frequency Updates (Advanced)

### kill() vs revert()

| Method | Stops Animation | Removes Inline Styles | Use When |
|--------|----------------|----------------------|----------|
| `tween.kill()` | Yes | **No** — styles stay | Mid-animation interrupt, keeping current state |
| `tween.revert()` | Yes | **Yes** — DOM restored | Component unmount, route change |
| `ctx.revert()` | All in context | All in context | **Always** use for React/SPA cleanup |

### gsap.context() — The Memory Leak Killer

```javascript
useEffect(() => {
  const ctx = gsap.context(() => {
    const split = SplitText.create(".title", { type: "chars" });
    gsap.from(split.chars, { opacity: 0, stagger: 0.05,
      scrollTrigger: { trigger: ".title", start: "top center" }
    });
  }, containerRef);

  return () => ctx.revert(); // Kills tweens, ScrollTriggers, reverts SplitText, strips inline styles
}, []);
```

### gsap.quickTo() — Mouse Followers Without GC Pressure

```javascript
// BAD: Creates new tween 60x/sec = garbage collection nightmare
document.addEventListener("mousemove", (e) => {
  gsap.to(".cursor", { x: e.clientX, y: e.clientY, duration: 0.4 });
});

// GOOD: Reuses single tween instance — up to 250% faster
gsap.set(".cursor", { xPercent: -50, yPercent: -50 });
const xTo = gsap.quickTo(".cursor", "x", { duration: 0.4, ease: "power3.out" });
const yTo = gsap.quickTo(".cursor", "y", { duration: 0.4, ease: "power3.out" });

document.addEventListener("mousemove", (e) => {
  xTo(e.clientX);
  yTo(e.clientY);
});
```

### gsap.quickSetter() — Raw Speed, No Easing

For direct value piping without interpolation (parallax math, raw scroll offsets):

```javascript
// 50-250% faster than gsap.set() — skips all parsing
const setX = gsap.quickSetter(".parallax", "x", "px");
const setY = gsap.quickSetter(".parallax", "y", "px");

window.addEventListener("scroll", () => {
  setX(window.scrollY * 0.5);
  setY(window.scrollY * 0.2);
});
```

| API | Easing | Use Case | Speed vs gsap.to() |
|-----|--------|----------|-------------------|
| `gsap.to()` | Full engine | Occasional state changes | Baseline |
| `gsap.quickTo()` | Reused tween | Mouse followers, smooth tracking | ~250% faster |
| `gsap.quickSetter()` | None (instant) | Raw parallax math, no smoothing | ~250% faster |

---

## Performance: Make It Fast

- **Transform + opacity only**: Everything else triggers layout/paint
- **force3D: "auto"** for most cases, `true` only for infinite loops
- **will-change lifecycle**: Apply onStart, remove onComplete
- **Batch, don't individualize**: `ScrollTrigger.batch()` for grids/lists
- **quickTo for mouse**: Never `gsap.to()` inside mousemove
- **matchMedia for mobile**: Disable heavy animations on weak devices
- **Lazy init**: Don't build complex timelines for below-fold content until near viewport

## Observability: Know It's Working

- **Chrome DevTools Performance tab**: Record with 4x CPU throttle. Green bars = 60fps. Red = jank
- **Paint Flashing**: Rendering tab → enable. Green flashes on GSAP targets = you're animating layout properties
- **Layer Borders**: Rendering tab → enable. Animated elements should show orange borders (own compositor layer)
- **Memory tab**: Take heap snapshot before/after route change. Growing `Detached HTMLDivElement` = leak

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never animate layout properties
**You will be tempted to:** Animate `width`, `height`, `top`, `left` for an expand/collapse effect.
**Why that fails:** Triggers CPU layout recalculation 60x/sec. Paint Flashing will light up green across the viewport.
**The right way:** Use `scaleX`/`scaleY` for size changes. Use GSAP Flip plugin for layout animations.

### Rule 2: Never apply will-change globally
**You will be tempted to:** Add `will-change: transform` to a `*` selector or to many elements "for performance".
**Why that fails:** Browser has a limited VRAM budget. Promoting hundreds of elements causes texture thrashing, blurry text, and worse performance than no will-change at all.
**The right way:** Apply dynamically via `onStart`, remove via `onComplete`. Or trust GSAP's `force3D: "auto"`.

### Rule 3: Never skip cleanup in SPAs
**You will be tempted to:** Not call `ctx.revert()` because "this component is always mounted".
**Why that fails:** Route changes, HMR, and React Strict Mode all unmount/remount components. Ghost tweens targeting detached DOM nodes accumulate, ballooning memory.
**The right way:** Every `gsap.context()` gets a matching `ctx.revert()` in cleanup. No exceptions.

### Rule 4: Never create tweens inside high-frequency event handlers
**You will be tempted to:** `gsap.to(".cursor", { x: e.clientX })` inside `mousemove`.
**Why that fails:** Creates a new tween object 60-120x/sec. Garbage collector pauses cause visible frame drops.
**The right way:** `gsap.quickTo()` for smooth following, `gsap.quickSetter()` for raw value piping.

### Rule 5: Never skip prefers-reduced-motion
**You will be tempted to:** Ship complex parallax/pinning without a reduced-motion path.
**Why that fails:** Users with vestibular disorders experience physical nausea. Also fails WCAG AAA compliance.
**The right way:** Wrap in `gsap.matchMedia()`. Provide opacity-only fallback for `(prefers-reduced-motion: reduce)`.
