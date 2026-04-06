---
name: mx-gsap-react
description: GSAP animation in React and Next.js App Router — "use client" boundary patterns, route transition animations, Tailwind CSS coexistence, FOUC prevention, dynamic imports, Server Component children pattern. Use when animating in React, Next.js, or integrating GSAP with Tailwind CSS or App Router.
---

# GSAP React & Next.js Integration for AI Coding Agents

**Loads when writing GSAP animations in React or Next.js App Router projects, or integrating GSAP with Tailwind CSS.**

## When to also load
- For core GSAP API (tweens, timelines, easing): see official **gsap-core** skill
- For useGSAP hook basics, refs, cleanup: see official **gsap-react** skill
- For ScrollTrigger patterns: see official **gsap-scrolltrigger** skill
- For text animations: **mx-gsap-text**
- For performance optimization: **mx-gsap-perf**
- For debugging: **mx-gsap-observability**

---

## Level 1: "use client" Boundaries (Beginner)

GSAP requires browser APIs. Every GSAP component needs `"use client"`. The goal: keep the boundary as small as possible.

### Pattern: Children Wrapper (Keep layout.tsx as Server Component)

```tsx
// BAD: Adding "use client" to layout.tsx
// Breaks metadata, forces entire tree into client bundle

// GOOD: Isolate GSAP into a wrapper component
// components/SmootherWrapper.tsx
"use client";
import { useRef } from "react";
import { gsap } from "gsap";
import { ScrollSmoother } from "gsap/ScrollSmoother";
import { useGSAP } from "@gsap/react";

if (typeof window !== "undefined") {
  gsap.registerPlugin(ScrollSmoother, useGSAP);
}

export default function SmootherWrapper({ children }: { children: React.ReactNode }) {
  const wrapperRef = useRef<HTMLDivElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);

  useGSAP(() => {
    ScrollSmoother.create({ wrapper: wrapperRef.current, content: contentRef.current, smooth: 1.5 });
  }, { scope: wrapperRef });

  return (
    <div ref={wrapperRef} id="smooth-wrapper">
      <div ref={contentRef} id="smooth-content">{children}</div>
    </div>
  );
}
```

```tsx
// app/layout.tsx — remains a Server Component
import SmootherWrapper from "@/components/SmootherWrapper";

export const metadata = { title: "My Site" }; // Works because layout is NOT "use client"

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html><body>
      <SmootherWrapper>{children}</SmootherWrapper>
    </body></html>
  );
}
```

### Decision Tree: Where to Place "use client"

| Need | Placement | Why |
|------|-----------|-----|
| Global layout animation (ScrollSmoother, transitions) | Dedicated `<ClientWrapper>` imported into layout.tsx | Preserves layout as Server Component for metadata + SEO |
| Single animated element (logo, button) | `"use client"` on that specific component file | Isolates JS to the leaf node only |
| Page entrance animation | `<PageTransitionWrapper>` wrapping page content | Keeps page.tsx as Server Component for data fetching |

### Centralized Plugin Registration

```tsx
// lib/gsapConfig.ts
"use client";
import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { useGSAP } from "@gsap/react";

if (typeof window !== "undefined") {
  gsap.registerPlugin(ScrollTrigger, useGSAP);
}

export { gsap, ScrollTrigger, useGSAP };
```

Import from `@/lib/gsapConfig` everywhere — prevents double-registration.

---

## Level 2: Route Transitions & Tailwind Coexistence (Intermediate)

### Pattern: TransitionProvider + TransitionLink

The App Router unmounts components instantly on navigation — no exit animation lifecycle. Solution: intercept navigation, run exit animation, THEN router.push().

```tsx
// context/TransitionContext.tsx
"use client";
import { createContext, useRef, useLayoutEffect } from "react";
import { useRouter, usePathname } from "next/navigation";
import { gsap } from "gsap";

export const TransitionContext = createContext<{ navigate: (href: string) => void }>({
  navigate: () => {}
});

export function TransitionProvider({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const overlayRef = useRef<HTMLDivElement>(null);
  const isAnimating = useRef(false);

  // Entrance: overlay slides away when new route loads
  useLayoutEffect(() => {
    if (!overlayRef.current) return;
    gsap.to(overlayRef.current, { yPercent: -100, duration: 0.8, ease: "power3.inOut",
      onComplete: () => { isAnimating.current = false; }
    });
  }, [pathname]);

  const navigate = (href: string) => {
    if (isAnimating.current || pathname === href) return;
    isAnimating.current = true;
    gsap.set(overlayRef.current, { yPercent: 100 });
    gsap.to(overlayRef.current, { yPercent: 0, duration: 0.8, ease: "power3.inOut",
      onComplete: () => router.push(href)
    });
  };

  return (
    <TransitionContext.Provider value={{ navigate }}>
      <div ref={overlayRef} className="fixed inset-0 z-50 bg-black pointer-events-none translate-y-full" />
      {children}
    </TransitionContext.Provider>
  );
}
```

```tsx
// components/TransitionLink.tsx
"use client";
import { useContext } from "react";
import Link from "next/link";
import { TransitionContext } from "@/context/TransitionContext";

export function TransitionLink({ href, children, className }: { href: string; children: React.ReactNode; className?: string }) {
  const { navigate } = useContext(TransitionContext);
  return (
    <Link href={href} onClick={(e) => { e.preventDefault(); navigate(href); }} className={className}>
      {children}
    </Link>
  );
}
```

### Tailwind CSS + GSAP: Separation Rules

| Property Type | Owner | Rule |
|--------------|-------|------|
| Transforms (`x`, `y`, `scale`, `rotation`) | **GSAP** | Remove Tailwind `transition-all`/`transition-transform` from GSAP targets |
| Visibility/Fade | **GSAP** | Use `autoAlpha`, never Tailwind `hidden` (display:none breaks GSAP) |
| Hover colors, backgrounds | **Tailwind** | `transition-colors hover:bg-gray-200` is fine — no transform conflict |
| Layout (flex, grid, spacing) | **Tailwind** | GSAP handles motion, Tailwind handles structure |

```tsx
// BAD: Tailwind transition fights GSAP
<div className="transition-all duration-500" ref={boxRef}>

// GOOD: Only transition colors via CSS, let GSAP handle transforms
<div className="transition-colors duration-500 hover:bg-blue-500" ref={boxRef}>
```

**Initial state**: Use `gsap.set()` instead of Tailwind transform classes.
**After animation**: Use `clearProps: "all"` to hand control back to CSS if needed.

---

## Level 3: FOUC Prevention & Dynamic Imports (Advanced)

### FOUC Prevention: CSS-First Hiding

The problem: Server renders HTML → browser paints it visible → JS loads → GSAP sets opacity:0 → user sees a flash.

**Solution**: Hide with CSS (inline `visibility: hidden`), reveal with `autoAlpha`.

```tsx
"use client";
import { useRef } from "react";
import { gsap } from "gsap";
import { SplitText } from "gsap/SplitText";
import { useGSAP } from "@gsap/react";

gsap.registerPlugin(SplitText);

export default function HeroAnimation() {
  const containerRef = useRef<HTMLDivElement>(null);

  useGSAP(() => {
    const split = SplitText.create(".hero-text", { type: "chars" });
    gsap.fromTo(split.chars,
      { autoAlpha: 0, y: 50 },
      { autoAlpha: 1, y: 0, stagger: 0.05, duration: 1, ease: "back.out(1.7)" }
    );
    gsap.set(containerRef.current, { autoAlpha: 1 });
  }, { scope: containerRef });

  return (
    // visibility:hidden in CSS — browser never paints it visible before GSAP loads
    <div ref={containerRef} style={{ visibility: "hidden" }}>
      <h1 className="hero-text">Immersive Experience</h1>
    </div>
  );
}
```

| Scenario | Anti-FOUC Strategy |
|----------|-------------------|
| Above-the-fold hero | `style={{ visibility: "hidden" }}` + `autoAlpha: 1` |
| Below-the-fold (ScrollTrigger) | Not needed — element is off-screen during hydration |

### Dynamic Imports for Heavy Components

```tsx
// app/page.tsx (Server Component)
import dynamic from "next/dynamic";
import HeroSection from "@/components/HeroSection"; // Normal import — above fold

const HeavyAnimation = dynamic(
  () => import("@/components/HeavyAnimation"),
  { ssr: false, loading: () => <div className="min-h-screen animate-pulse bg-gray-100" /> }
);

export default function Page() {
  return (
    <main>
      <HeroSection />
      <HeavyAnimation /> {/* Only loads on client, after hydration */}
    </main>
  );
}
```

| Component Type | Import Method |
|---------------|--------------|
| Above-fold critical animation | Standard `import` — must be in initial payload |
| Below-fold heavy animation | `next/dynamic` with `ssr: false` |
| WebGL / Canvas / window-dependent | `next/dynamic` with `{ ssr: false }` — prevents hydration errors |

---

## Performance: Make It Fast

- **Isolate client boundaries**: Fewer Client Components = smaller JS bundle = faster TTI
- **Centralize plugin registration**: One `gsapConfig.ts` prevents duplicate imports
- **Dynamic import below-fold**: Defer heavy GSAP components with `next/dynamic({ ssr: false })`
- **Remove Tailwind transition classes**: `transition-all` on GSAP targets causes 60x/sec CSS-vs-JS fighting

## Observability: Know It's Working

- **Route cleanup**: After navigation, check `ScrollTrigger.getAll().length` — should be 0 for unmounted routes
- **FOUC test**: Throttle network to Slow 3G, reload — hero should NOT flash visible then disappear
- **Tailwind conflict test**: If animation stutters, check element for Tailwind `transition` classes

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never add "use client" to layout.tsx
**You will be tempted to:** Fix a hook error by adding `"use client"` to `app/layout.tsx`.
**Why that fails:** Breaks `export const metadata`, forces entire app tree into client bundle, destroys SSR benefits.
**The right way:** Create a dedicated Client Component wrapper, import it into layout.tsx, pass children.

### Rule 2: Never use standard Link for animated transitions
**You will be tempted to:** Use `<Link>` and animate on unmount with useEffect cleanup.
**Why that fails:** App Router destroys DOM instantly on navigation — cleanup fires but elements are already gone.
**The right way:** Custom `TransitionLink` that intercepts click → exit animation → `router.push()` on completion.

### Rule 3: Never use Tailwind `hidden` class on GSAP targets
**You will be tempted to:** Use `className="hidden"` to hide elements before animation.
**Why that fails:** `display: none` removes element from layout — GSAP can't calculate bounding boxes, autoAlpha fails.
**The right way:** `style={{ visibility: "hidden" }}` + `autoAlpha` for FOUC prevention.

### Rule 4: Never use gsap.set() for FOUC prevention
**You will be tempted to:** Call `gsap.set('.hero', { autoAlpha: 0 })` to hide before animation.
**Why that fails:** gsap.set() is JavaScript — runs AFTER browser paints the SSR HTML. The flash already happened.
**The right way:** Inline `style={{ visibility: "hidden" }}` in JSX — browser never paints it visible.

### Rule 5: Never put transition-all on GSAP-animated elements
**You will be tempted to:** Add `className="transition-all duration-300"` for hover effects alongside GSAP.
**Why that fails:** CSS transition intercepts every GSAP frame update, applying its own 300ms interpolation. Result: severe jitter.
**The right way:** Use `transition-colors` or `transition-opacity` for CSS-only properties. GSAP owns transforms.
