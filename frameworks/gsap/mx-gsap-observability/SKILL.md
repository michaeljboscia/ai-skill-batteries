---
name: mx-gsap-observability
description: GSAP animation debugging and observability, any GSAP work — GSDevTools setup, ScrollTrigger markers, Chrome DevTools Performance profiling, timeline inspection, animation state verification, cleanup verification, memory leak detection. Co-loads with mx-gsap-core for ANY GSAP work.
---

# GSAP Debugging & Observability for AI Coding Agents

**This skill co-loads with GSAP core for ANY GSAP work. Ensures animations are debuggable and verifiable.**

## When to also load
- For performance optimization: **mx-gsap-perf**
- For React/Next.js patterns: **mx-gsap-react**
- For text animation patterns: **mx-gsap-text**

---

## Level 1: Development Markers & Visual Debugging (Beginner)

### ScrollTrigger Markers — Always On in Dev

```javascript
gsap.to(".section", {
  x: 100,
  scrollTrigger: {
    trigger: ".section",
    start: "top 80%",
    end: "bottom 20%",
    scrub: true,
    id: "SectionSlide",  // Shows on markers for identification
    markers: process.env.NODE_ENV === "development"  // Auto-strip in production
  }
});
```

For complex pages with overlapping markers, use custom colors and indentation:

```javascript
markers: process.env.NODE_ENV === "development" ? {
  startColor: "fuchsia",
  endColor: "white",
  fontSize: "14px",
  indent: 200  // Horizontal offset to prevent overlap
} : false
```

### Global TimeScale for Slow-Motion Review

```javascript
// Slow down ALL animations to 25% speed for visual inspection
gsap.globalTimeline.timeScale(0.25);

// Reset to normal
gsap.globalTimeline.timeScale(1);
```

### Assign IDs to Timelines and Tweens

IDs make animations identifiable in GSDevTools, console inspection, and ScrollTrigger.getById():

```javascript
const heroTl = gsap.timeline({ id: "HeroSequence" });

heroTl
  .to(".orange", { x: "100vw", duration: 1, id: "orange-entrance" })
  .to(".green", { y: 200, duration: 2, ease: "bounce", id: "green-bounce" });
```

---

## Level 2: GSDevTools & Chrome DevTools Workflow (Intermediate)

### GSDevTools Setup (Development Only)

GSDevTools is a Club plugin — visual timeline scrubber with play/pause/slow-motion.

```javascript
import { GSDevTools } from "gsap/GSDevTools";

gsap.registerPlugin(GSDevTools);

// Link to specific timeline (not global) for focused debugging
if (process.env.NODE_ENV === "development") {
  GSDevTools.create({
    animation: heroTl,      // Link to specific timeline
    globalSync: false,       // Don't sync with global timeline
    persist: true            // Keep in/out points across hot reloads
  });
}
```

**GSDevTools features:**
- Scrub playhead to any point in the timeline
- Set in/out points to loop a specific segment
- Dropdown to select animations by ID
- "H" key hides UI if it obscures the animation
- Slow-motion playback

### Chrome DevTools Performance Workflow

**Step 1: Record with throttling**
1. Open DevTools → Performance tab
2. Enable "Screenshots" checkbox
3. Set CPU Throttling to 4x (simulates mobile)
4. Click record, interact with the page, stop

**Step 2: Read the results**

| Chart Section | Color | Meaning |
|--------------|-------|---------|
| FPS bar | Green (tall) | 60fps — smooth |
| FPS bar | Red | Dropped frames — jank |
| CPU | Yellow | JavaScript execution |
| CPU | Purple | Style recalculation + Layout (BAD if during animation) |
| CPU | Green | Paint + Composite (expected for animations) |

**Step 3: Check rendering pipeline**
- **Rendering tab → Paint Flashing**: Green overlay = area being repainted. If GSAP-animated elements flash green, you're animating layout properties.
- **Rendering tab → Layer Borders**: Orange outlines = compositor layers. Animated elements should have their own layer.

### Decision Tree: Where's the Bottleneck?

| Symptom | Chrome DevTools Check | Likely Cause | Fix |
|---------|----------------------|-------------|-----|
| Animation stutters | Performance → FPS drops to red | Layout thrashing | Switch from `width`/`top` to `scaleX`/`x` |
| Entire page repaints | Paint Flashing → green everywhere | Animating layout property | Use transforms + opacity only |
| Element not hardware-accelerated | Layer Borders → no orange border | Missing GPU promotion | Check `force3D` setting |
| Memory grows on route changes | Memory → heap snapshot comparison | Orphaned tweens/ScrollTriggers | Add `ctx.revert()` to cleanup |

---

## Level 3: Timeline Inspection & Cleanup Verification (Advanced)

### Console: List All Active Animations

```javascript
// Count everything alive in the GSAP engine
function checkGlobalState() {
  const all = gsap.globalTimeline.getChildren(true, true, true);
  console.log(`Active animations: ${all.length}`);
}

// Find tweens targeting a specific element
function checkElement(el) {
  const tweens = gsap.getTweensOf(el);
  if (tweens.length > 0) {
    console.warn(`${tweens.length} active tweens on`, el);
    tweens.forEach(t => {
      console.table({
        isActive: t.isActive(),
        paused: t.paused(),
        progress: t.progress().toFixed(3),
        duration: t.duration()
      });
    });
  }
}
```

### Console: Read Current Property Values

```javascript
// gsap.getProperty() returns GSAP's internal tracked value — not computed style
const x = gsap.getProperty(".box", "x");           // Number: 200
const xPx = gsap.getProperty(".box", "x", "px");   // String: "200px"
const bg = gsap.getProperty(".box", "backgroundColor"); // "rgb(255, 0, 0)"
```

### ScrollTrigger: Detect Orphans

```javascript
function checkScrollTriggers() {
  const all = ScrollTrigger.getAll();
  console.log(`Active ScrollTriggers: ${all.length}`);

  all.forEach(st => {
    console.log({
      id: st.vars.id,
      trigger: st.trigger,
      isActive: st.isActive,
      progress: st.progress.toFixed(3),
      // Check if trigger element is still in DOM
      inDOM: document.contains(st.trigger)
    });
  });
}

// Get specific trigger by ID
const st = ScrollTrigger.getById("HeroTrigger");
if (st) console.log("Velocity:", st.getVelocity());
```

### Cleanup Verification Checklist (SPA/React)

Run after every route change during development:

```javascript
// In React useEffect cleanup or route change handler:
return () => {
  ctx.revert();

  // VERIFICATION
  const orphanedTriggers = ScrollTrigger.getAll();
  if (orphanedTriggers.length > 0) {
    console.error(`LEAK: ${orphanedTriggers.length} ScrollTriggers survived cleanup`);
    orphanedTriggers.forEach(st => console.error("  -", st.vars.id, st.trigger));
  }

  const orphanedTweens = gsap.globalTimeline.getChildren(true, true, false);
  if (orphanedTweens.length > 0) {
    console.warn(`${orphanedTweens.length} tweens still in global timeline`);
  }
};
```

### Custom Logging via Callbacks

```javascript
gsap.to(".box", {
  x: 500,
  duration: 2,
  onStart: () => console.timeStamp("Animation Started"),
  onUpdate: function () {
    // Log at 50% progress (not every frame)
    if (this.progress() > 0.5 && !this._halfLogged) {
      console.log(`50% complete. X: ${gsap.getProperty(".box", "x")}`);
      this._halfLogged = true;
    }
  },
  onComplete: () => {
    console.log("Complete. Final X:", gsap.getProperty(".box", "x"));
    console.assert(gsap.getProperty(".box", "x") === 500, "X mismatch!");
  }
});
```

---

## Performance: Make It Fast

- **Strip markers in production**: `markers: process.env.NODE_ENV === "development"` — markers inject DOM nodes that affect layout
- **Exclude GSDevTools from production bundle**: Use dynamic import or build-tool tree shaking
- **Don't log inside onUpdate without gating**: `onUpdate` fires 60x/sec — ungated console.log kills performance
- **Profile in Incognito Mode**: Browser extensions skew Performance tab results

## Observability: Know It's Working

- **Pre-deploy checklist**: Search codebase for `markers: true` (should be 0 in prod), verify GSDevTools is excluded
- **Route change audit**: `ScrollTrigger.getAll().length` should drop to 0 after navigating away from animated routes
- **Inline style audit**: After `ctx.revert()`, inspect DOM elements — no lingering `style="transform: ..."` attributes
- **ScrollTrigger.refresh()**: Call after any async DOM change (API data load, image load, font load)

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never ship GSDevTools to production
**You will be tempted to:** Leave GSDevTools imported because "it won't render without .create()".
**Why that fails:** Ships unnecessary JS payload, violates Club license, and if `.create()` is accidentally called, exposes a full animation debugger to end users.
**The right way:** Conditional import behind `process.env.NODE_ENV === "development"` or exclude via build config.

### Rule 2: Never leave markers: true in production
**You will be tempted to:** Hide markers with CSS instead of removing them.
**Why that fails:** Markers inject actual `<div>` nodes into the DOM. They participate in layout calculations, subtly shifting viewport height and trigger positions.
**The right way:** `markers: process.env.NODE_ENV === "development"` — compile-time stripping.

### Rule 3: Never skip ScrollTrigger.refresh() after async DOM changes
**You will be tempted to:** Assume ScrollTrigger auto-recalculates when content loads.
**Why that fails:** Async events (API fetch, font load, lazy image) push content down AFTER ScrollTrigger calculated coordinates. Triggers fire early or late.
**The right way:** Call `ScrollTrigger.refresh()` in the resolution callback of any async DOM-altering event.

### Rule 4: Never use gsap.context().kill() instead of .revert()
**You will be tempted to:** Call `.kill()` on cleanup because it sounds sufficient.
**Why that fails:** `.kill()` stops animations but leaves all inline styles on the DOM. Elements keep their mid-animation `transform` values permanently.
**The right way:** Always `.revert()` — stops animations AND strips all GSAP-injected inline styles.

### Rule 5: Never debug animations without Chrome CPU throttling
**You will be tempted to:** Test animations only on your development machine (fast CPU/GPU).
**Why that fails:** Your M-series MacBook runs animations at 60fps that will stutter at 15fps on a 3-year-old Android phone. You'll ship jank to most users.
**The right way:** Always profile with 4x CPU throttle in Chrome DevTools Performance tab. If it's smooth at 4x, it's smooth everywhere.
