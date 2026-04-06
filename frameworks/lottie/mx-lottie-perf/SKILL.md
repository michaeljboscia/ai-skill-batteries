---
name: mx-lottie-perf
description: Lottie animation performance optimization, any Lottie work — bundle size reduction, lottie-web vs lottie-light, dotLottie .lottie format compression, SVG vs Canvas vs HTML renderer selection, lazy loading IntersectionObserver, dynamic import ssr false, CLS prevention aspect-ratio, prefers-reduced-motion, animation file optimization, frame drop detection
---

# Lottie Performance — Make It Fast for AI Coding Agents

**This skill co-loads with mx-lottie-core for ANY Lottie work.**

## When to also load
- `mx-lottie-core` — library setup, SSR handling
- `mx-lottie-interaction` — scroll/hover/click patterns
- `mx-lottie-observability` — co-loads automatically on any Lottie work
- `mx-nextjs-perf` — Next.js-specific performance patterns

---

## Level 1: Bundle & File Size (Beginner)

### Library Bundle Comparison

| Library | Minified + Gzipped | When to Use |
|---------|-------------------|-------------|
| `lottie-web` (full) | ~60KB | Need expressions + full renderer control |
| `lottie-web/build/player/lottie_light` | ~30KB | No expressions needed — **default choice** |
| `lottie-react` (wraps lottie-web) | ~82KB | Declarative React component for .json files |
| `@lottiefiles/dotlottie-react` | ~14KB JS + WASM | Best for .lottie format — lowest JS cost |

### .lottie Format vs .json

| Metric | .json | .lottie |
|--------|-------|---------|
| Compression | None (text) | ZIP/Deflate (80% smaller) |
| Bundled assets | No (external image refs) | Yes (images, fonts in archive) |
| Network requests | 1 per JSON + N per asset | 1 total |
| Theming | No | Yes (light/dark via slots) |
| State machines | No | Yes |

**Always prefer .lottie for production.** Convert with LottieFiles editor or `@dotlottie/dotlottie-js`.

### Dynamic Import (Keep Off Critical Path)

```tsx
// GOOD: 82KB loaded asynchronously after initial render
const DynamicLottie = dynamic(() => import("@/components/LottieWrapper"), {
  ssr: false,
  loading: () => <Skeleton />,
});
```

**Never** statically import Lottie libraries at the top of page components.

---

## Level 2: Renderer Selection (Intermediate)

### Decision Tree

| Condition | Renderer | Rationale |
|-----------|----------|-----------|
| Simple icons, < 100 DOM nodes | **SVG** | Crisp scaling, CSS-stylable, negligible overhead |
| Standard illustrations, 100-500 nodes | **SVG** | Good fidelity, acceptable DOM impact |
| Complex scenes, > 1,000 nodes | **Canvas** | Bypasses DOM entirely, maintains 60fps |
| Particle effects, > 2,000 objects | **Canvas** | Immediate-mode drawing, no GC pressure |
| Need off-main-thread rendering | **Canvas** | Supports OffscreenCanvas + Web Worker |
| Text-heavy, accessibility critical | **HTML** | Standard DOM, screen reader compatible |
| **Avoid** | **HTML** for graphics | Worst performance, highest DOM overhead |

### How to Check DOM Node Count

After loading with SVG renderer, check the container:
```tsx
const nodeCount = containerRef.current?.getElementsByTagName("*").length;
if (nodeCount > 500) {
  console.warn(`Lottie generated ${nodeCount} DOM nodes — consider Canvas renderer`);
}
```

**Threshold:** If Lighthouse flags "Excessive DOM Size" (>1,500 nodes total page), switch that animation to Canvas.

### Canvas Renderer Setup

```tsx
lottie.loadAnimation({
  container: containerRef.current,
  renderer: "canvas", // Not "svg"
  loop: true,
  autoplay: true,
  animationData,
});
```

Canvas tradeoffs: no CSS styling on elements, resolution-dependent (handle with `window.devicePixelRatio`), no blur filter support.

---

## Level 3: Lazy Loading & CLS Prevention (Advanced)

### IntersectionObserver + Dynamic Import

Only load the Lottie library AND animation data when the element approaches the viewport:

```tsx
"use client";
import { useRef, useState, useEffect, Suspense, lazy } from "react";

const LottieComponent = lazy(() => import("lottie-react"));

export function LazyLottie({ animationUrl, alt }) {
  const ref = useRef(null);
  const [isVisible, setIsVisible] = useState(false);
  const [data, setData] = useState(null);

  useEffect(() => {
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setIsVisible(true);
          observer.disconnect();
        }
      },
      { rootMargin: "200px" } // Pre-load 200px before viewport
    );
    if (ref.current) observer.observe(ref.current);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    if (isVisible && animationUrl) {
      fetch(animationUrl).then(r => r.json()).then(setData);
    }
  }, [isVisible, animationUrl]);

  return (
    <div ref={ref} style={{ aspectRatio: "16/9", minHeight: 300 }}>
      {isVisible && data ? (
        <Suspense fallback={<div className="animate-pulse bg-gray-100 w-full h-full" />}>
          <LottieComponent animationData={data} loop aria-label={alt} role="img" />
        </Suspense>
      ) : (
        <div className="animate-pulse bg-gray-100 w-full h-full" aria-label={alt} />
      )}
    </div>
  );
}
```

### CLS Prevention Techniques

| Technique | Browser Support | Code |
|-----------|----------------|------|
| `aspect-ratio` CSS | Modern (95%+) | `aspect-ratio: 16 / 9;` |
| Padding-bottom hack | Universal | `padding-bottom: 56.25%; height: 0; position: relative;` |
| Fixed dimensions | Universal | `width: 400px; height: 300px;` |

**Always set dimensions on the container BEFORE the animation loads.** Get the ratio from the Lottie JSON's `w` and `h` properties.

```css
.lottie-container {
  width: 100%;
  max-width: 500px;
  aspect-ratio: attr(data-w) / attr(data-h); /* Or hardcode: 16 / 9 */
  background-color: #f3f4f6;
  overflow: hidden;
}
```

### Animation File Optimization Checklist

Before any Lottie file goes to production:

| Check | Action | Impact |
|-------|--------|--------|
| Decimal precision | Reduce to 2-3 places | 10-30% size reduction |
| Hidden layers | Delete layers with opacity 0 | Dead weight removal |
| Expressions | Bake to keyframes, use lottie_light | 50% bundle reduction + XSS prevention |
| Raster images | Convert to vectors or externalize | Prevent Base64 bloat in JSON |
| Path complexity | Simplify anchor points in Illustrator | Fewer vertices = less math per frame |
| Layer count | Merge overlapping shapes | Each layer = memory + compute |
| Frame rate | Cap at 30fps for web (60fps only if essential) | 50% fewer frames to compute |

---

## Performance: Make It Fast

### Performance Budget Table

| Metric | Target | Warning | Critical | Fix |
|--------|--------|---------|----------|-----|
| JSON file size | < 50KB | 100KB | > 250KB | Optimize in LottieFiles, reduce decimals |
| .lottie file size | < 15KB | 30KB | > 75KB | Deduplicate assets, compress |
| DOM nodes (SVG) | < 300 | 800 | > 1,500 | Switch to Canvas renderer |
| Library bundle (gzip) | < 15KB | 30KB | > 60KB | Use dotlottie-react or lottie_light |
| Frame rate target | 60fps | < 45fps | < 30fps | Remove blend modes, reduce alpha layers |
| Time-to-first-frame | < 100ms | 250ms | > 500ms | Lazy load, use .lottie, preload critical |

## Observability: Know It's Working

- **Lighthouse DOM size audit** — if >1,500 nodes, SVG renderer is the culprit
- **Chrome DevTools Performance tab** — look for long rAF callbacks during animation
- **`performance.measure()`** around loadAnimation → DOMLoaded event for TTFF
- **Check `lottie.getRegisteredAnimations().length`** — orphans after route change = leak

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Ship Full lottie-web in Main Bundle
**You will be tempted to:** `import lottie from "lottie-web"` at the top of a page component because it's simpler than setting up dynamic imports.
**Why that fails:** 60KB gzipped of synchronous JavaScript blocks hydration. Every user pays the cost even if the animation is below the fold. Lighthouse TTI tanks.
**The right way:** Dynamic import with `ssr: false` for the component. Use `lottie_light` if you need direct lottie-web. Use `dotlottie-react` (14KB JS) for new projects.

### Rule 2: Never Use SVG Renderer for Complex Animations
**You will be tempted to:** Keep the default SVG renderer for a 15-second multi-character scene because "SVG is vector, it scales."
**Why that fails:** SVG creates a DOM node per path/layer/mask. Complex animations inject 1,500+ nodes → catastrophic reflow → single-digit FPS → "Excessive DOM Size" Lighthouse failure.
**The right way:** Check node count after load. If > 500, switch to Canvas. If > 1,000, Canvas is mandatory. Use OffscreenCanvas + Web Worker for heavy animations.

### Rule 3: Never Skip CLS Reservation
**You will be tempted to:** Let the Lottie animation define its own size after loading, skipping the `aspect-ratio` or fixed dimensions on the container.
**Why that fails:** Async-loaded content without reserved space causes layout shift. CLS score degrades. Users see content jump as the animation materializes.
**The right way:** Always set `aspect-ratio`, `width`/`height`, or the padding-bottom hack on the container div BEFORE the animation loads. Match the Lottie file's `w`/`h` ratio.

### Rule 4: Never Ship .json When .lottie Is Available
**You will be tempted to:** Push `.json` files to production because "Gzip on the server handles compression anyway."
**Why that fails:** Server Gzip reduces transfer but the browser still JSON.parses the massive string on the main thread. .json files can't bundle external image assets (forced Base64 inline = huge strings). Multiple network requests for external assets.
**The right way:** Convert all production Lottie files to `.lottie` format. 80% smaller network payload, bundled assets, single request. Use LottieFiles editor or `@dotlottie/dotlottie-js` for conversion.
