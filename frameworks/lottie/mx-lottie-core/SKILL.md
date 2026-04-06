---
name: mx-lottie-core
description: Lottie animation loading and rendering in React and Next.js App Router — library selection (dotlottie-react, lottie-react, lottie-web), "use client" directive, dynamic import with ssr false, player setup, JSON vs dotLottie format, useRef container, useEffect lifecycle, destroy cleanup, error boundaries, static image fallback, prefers-reduced-motion, accessibility aria-label
---

# Lottie Core — Loading & Rendering in React/Next.js for AI Coding Agents

**Load this skill when writing any Lottie animation code in React or Next.js.**

## When to also load
- `mx-lottie-interaction` — scroll-triggered, hover, click, segment playback
- `mx-lottie-perf` — co-loads automatically on any Lottie work
- `mx-lottie-observability` — co-loads automatically on any Lottie work
- `mx-react-core` — React component patterns
- `mx-nextjs-rsc` — server/client component boundaries
- `mx-gsap-react` — when combining Lottie with GSAP ScrollTrigger

---

## Level 1: Patterns That Always Work (Beginner)

### Library Selection Decision Tree

| Scenario | Use This | Why |
|----------|----------|-----|
| New project, performance matters | `@lottiefiles/dotlottie-react` | WASM runtime, .lottie format (80% smaller files), ~14KB JS gzipped |
| Legacy codebase, .json animations | `lottie-react` | Declarative `<Lottie>` + `useLottie` hook, ~82KB gzipped with lottie-web |
| Extreme bundle constraints | `lottie-web/build/player/lottie_light` | Strips expression engine, halves payload, eliminates XSS vector |
| GSAP ScrollTrigger scroll-scrub | `lottie-web` directly | Need raw instance for `goToAndStop(frame, true)` in onUpdate |
| **NEVER use** | `react-lottie` | Abandoned, uses deprecated `componentWillUpdate`, breaks Next.js 13+ |

### Next.js App Router: The Client Component Wrapper

Lottie libraries access `window`/`document`. They MUST be client-side only.

**BAD — crashes with "ReferenceError: document is not defined":**
```tsx
// app/page.tsx (Server Component)
import Lottie from "lottie-react"; // CRASH: lottie-web touches document on import
```

**BAD — "use client" alone is NOT enough:**
```tsx
"use client";
import Lottie from "lottie-react"; // STILL CRASHES: Next.js pre-renders client components on server
```

**GOOD — Client Component Wrapper + dynamic import:**
```tsx
// components/LottieWrapper.tsx
"use client";
import Lottie from "lottie-react";

export default function LottieWrapper({ animationData, ...props }) {
  return <Lottie animationData={animationData} loop autoplay {...props} />;
}

// app/page.tsx (Server Component)
import dynamic from "next/dynamic";
const DynamicLottie = dynamic(() => import("@/components/LottieWrapper"), {
  ssr: false,
  loading: () => <div style={{ aspectRatio: "16/9" }} className="bg-gray-100 animate-pulse" />,
});
```

### Basic Setup with lottie-react

```tsx
"use client";
import Lottie from "lottie-react";
import animationData from "@/public/animations/hero.json";

export default function HeroAnimation() {
  return (
    <div style={{ width: 400, height: 300, aspectRatio: "4/3" }}>
      <Lottie
        animationData={animationData}
        loop={true}
        autoplay={true}
        style={{ width: "100%", height: "100%" }}
        aria-label="Animated hero illustration showing product features"
        role="img"
      />
    </div>
  );
}
```

---

## Level 2: Direct lottie-web Integration (Intermediate)

Use direct lottie-web when you need: renderer control (SVG/Canvas/HTML), GSAP integration, or programmatic playback.

### loadAnimation Options Reference

| Option | Type | Notes |
|--------|------|-------|
| `container` | HTMLElement | **Required.** Via `useRef`. |
| `renderer` | `'svg'` \| `'canvas'` \| `'html'` | Default: `'svg'`. See mx-lottie-perf for decision tree. |
| `loop` | boolean \| number | `true` = infinite, number = finite count |
| `autoplay` | boolean | Set `false` when GSAP or interaction controls playback |
| `animationData` | object | Inline JSON. **Mutually exclusive** with `path`. |
| `path` | string | URL to JSON. **Mutually exclusive** with `animationData`. |
| `name` | string | Optional identifier for global lottie commands |
| `initialSegment` | `[start, end]` | Play only specific frame range on init |
| `progressiveLoad` | boolean | Add DOM elements only when cursor reaches them |
| `rendererSettings` | object | `{ runExpressions: false }` to disable XSS vector |

### Strict-Mode Safe Lifecycle Pattern

```tsx
"use client";
import { useEffect, useRef } from "react";
import lottie, { AnimationItem } from "lottie-web";

export function NativeLottie({ animationData }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const animRef = useRef<AnimationItem | null>(null);

  useEffect(() => {
    if (!containerRef.current) return;

    animRef.current = lottie.loadAnimation({
      container: containerRef.current,
      renderer: "svg",
      loop: true,
      autoplay: true,
      animationData,
    });

    // MANDATORY: destroy() in cleanup — prevents memory leaks + Strict Mode double-mount
    return () => {
      animRef.current?.destroy();
      animRef.current = null;
    };
  }, [animationData]);

  return <div ref={containerRef} role="img" aria-label="Animation" />;
}
```

### Error Boundary + Async Fallback (Two-Layer Defense)

```tsx
// Layer 1: ErrorBoundary catches sync render crashes
<LottieErrorBoundary fallback={<img src="/fallback.png" alt="Animation" />}>
  {/* Layer 2: Component catches async load failures via data_failed event */}
  <LottieWithFallback url="/hero.json" fallbackSrc="/fallback.png" />
</LottieErrorBoundary>
```

The async fallback listens for `data_failed` event on the lottie instance and sets error state to render the static image. ErrorBoundary catches synchronous crashes. Both are needed.

---

## Level 3: Security & Accessibility (Advanced)

### prefers-reduced-motion Hook

```tsx
function usePrefersReducedMotion() {
  const [reduced, setReduced] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    setReduced(mq.matches);
    const handler = (e) => setReduced(e.matches);
    mq.addEventListener("change", handler);
    return () => mq.removeEventListener("change", handler);
  }, []);
  return reduced;
}

// Usage: autoplay={!prefersReducedMotion} loop={!prefersReducedMotion}
// Or: render static <img> fallback when prefersReducedMotion is true
```

### Lottie Expression XSS Prevention

Lottie JSON `"x"` properties contain JavaScript strings evaluated via `eval()`. Malicious files can steal cookies, inject phishing overlays, or execute arbitrary code.

**Zero-trust for untrusted files:**
1. Use `lottie-web/build/player/lottie_light` — strips eval() engine entirely
2. Or pass `rendererSettings: { runExpressions: false }`
3. Never allow user-uploaded Lottie without validation (see mx-lottie-observability)

---

## Performance: Make It Fast

- **Dynamic import with `ssr: false`** — keeps 82KB+ off the critical rendering path
- **Reserve container space** with `aspect-ratio` CSS — prevents CLS
- **Use .lottie format** over .json — 80% smaller network payload
- **Remote host animations on CDN** — don't bundle JSON in your JS
- See `mx-lottie-perf` for renderer selection, lazy loading, and bundle optimization

## Observability: Know It's Working

- **Error boundary + data_failed listener** — two-layer defense against crashes
- **aria-label on every animation container** — screen readers need text alternatives
- **prefers-reduced-motion check** — legal requirement (WCAG 2.1)
- See `mx-lottie-observability` for JSON validation, load time tracking, and memory leak detection

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Use react-lottie
**You will be tempted to:** Install `react-lottie` because it has 300K+ weekly downloads and extensive StackOverflow answers.
**Why that fails:** Abandoned library using deprecated `componentWillUpdate`. Fails with Babel errors in Next.js 13+. No .lottie format support. No React 18 concurrent features.
**The right way:** Use `@lottiefiles/dotlottie-react` for new projects or `lottie-react` for legacy .json files.

### Rule 2: Never Import Lottie in Server Components
**You will be tempted to:** Import your Lottie component directly or assume `"use client"` alone makes it safe.
**Why that fails:** Next.js still pre-renders client components on the server. Lottie eagerly accesses `document` on import → `ReferenceError` crash in production.
**The right way:** Isolate Lottie in a dedicated client component file. Import it upstream via `dynamic(() => import(...), { ssr: false })`.

### Rule 3: Never Skip destroy() Cleanup
**You will be tempted to:** Skip the useEffect cleanup function, assuming React garbage-collects the DOM.
**Why that fails:** lottie-web maintains global internal references. Without destroy(), React 18 Strict Mode creates duplicate SVG nodes. SPAs accumulate orphaned instances → memory leaks → eventual OOM crash.
**The right way:** Always `return () => { anim.destroy(); anim = null; }` in useEffect cleanup.

### Rule 4: Never Trust Untrusted Lottie JSON
**You will be tempted to:** Accept user-uploaded .json files because "it's just animation data, not executable code."
**Why that fails:** Lottie expressions use `eval()` to execute JavaScript strings. CVE-2024-5060 demonstrated arbitrary code execution via crafted animation files. An attacker steals session cookies with a single uploaded .json.
**The right way:** Use `lottie_light` (strips eval engine), set `runExpressions: false`, or validate with lottie-specs-js before rendering.

### Rule 5: Never Ignore prefers-reduced-motion
**You will be tempted to:** Ship autoplay animations without checking the user's motion preference.
**Why that fails:** Users with vestibular disorders experience nausea and disorientation. It's a WCAG 2.1 requirement, not a nice-to-have.
**The right way:** Use `usePrefersReducedMotion` hook. Either render a static fallback image or set `autoplay={false}` + provide play/pause controls.
