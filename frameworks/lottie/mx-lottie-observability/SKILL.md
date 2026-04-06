---
name: mx-lottie-observability
description: Lottie animation observability and debugging, any Lottie work — JSON validation before rendering, lottie-specs-js schema validation, reLottie AST parsing, Lottie expressions XSS security audit, error detection data_failed event, animation load time tracking Performance API, frame drop detection requestAnimationFrame, memory leak detection getRegisteredAnimations, DOM bloat monitoring, accessibility audit aria-label prefers-reduced-motion
---

# Lottie Observability — Know It's Working for AI Coding Agents

**This skill co-loads with mx-lottie-core for ANY Lottie work.**

## When to also load
- `mx-lottie-core` — library setup, SSR handling, lifecycle
- `mx-lottie-interaction` — scroll/hover/click patterns
- `mx-lottie-perf` — co-loads automatically on any Lottie work
- `mx-nextjs-observability` — Next.js-specific observability patterns

---

## Level 1: Pre-Rendering Validation (Beginner)

### Quick Heuristic Check

Before feeding any JSON to lottie-web, verify the minimum required properties:

```tsx
function isValidLottie(data: unknown): boolean {
  if (typeof data !== "object" || data === null) return false;
  const l = data as Record<string, unknown>;
  return (
    typeof l.v === "string" &&    // version
    typeof l.w === "number" &&    // width
    typeof l.h === "number" &&    // height
    typeof l.fr === "number" &&   // framerate
    Array.isArray(l.layers)       // layer array
  );
}

// Usage: validate BEFORE passing to loadAnimation
if (!isValidLottie(animationData)) {
  console.error("Invalid Lottie JSON — missing required properties");
  return <img src="/fallback.png" alt="Animation" />;
}
```

### Expression Detection (Security Check)

```tsx
function hasExpressions(data: object): boolean {
  return JSON.stringify(data).includes('"x"');
}

// If untrusted source + has expressions → BLOCK or use lottie_light
if (hasExpressions(untrustedData)) {
  console.warn("SECURITY: Lottie file contains expressions (potential XSS)");
  // Use lottie_light which strips eval(), or reject the file
}
```

### Error Event Listeners

Every lottie-web instance should have these listeners:

```tsx
const anim = lottie.loadAnimation({ /* config */ });

anim.addEventListener("data_ready", () => {
  console.log("[Lottie] Data parsed successfully");
});

anim.addEventListener("DOMLoaded", () => {
  console.log("[Lottie] DOM elements injected");
});

anim.addEventListener("data_failed", () => {
  console.error("[Lottie] Failed to parse animation data");
  // Trigger fallback UI
});

anim.addEventListener("error", (e) => {
  console.error("[Lottie] Runtime execution error", e);
});
```

---

## Level 2: Load Time & Frame Drop Tracking (Intermediate)

### Time-to-First-Frame (TTFF) Measurement

```tsx
useEffect(() => {
  const id = `lottie_${Date.now()}`;
  performance.mark(`${id}_start`);

  const anim = lottie.loadAnimation({
    container: containerRef.current,
    renderer: "svg",
    animationData,
  });

  anim.addEventListener("DOMLoaded", () => {
    requestAnimationFrame(() => {
      performance.mark(`${id}_painted`);
      const measure = performance.measure(`${id}_ttff`, `${id}_start`, `${id}_painted`);
      console.log(`[Lottie TTFF] ${measure.duration.toFixed(1)}ms`);

      if (measure.duration > 250) {
        console.warn("[Lottie TTFF] Slow first frame — consider lazy loading or .lottie format");
      }
    });
  });

  return () => anim.destroy();
}, [animationData]);
```

**TTFF Budgets:**

| Rating | Duration | Action |
|--------|----------|--------|
| Good | < 100ms | No action needed |
| Needs work | 100-250ms | Consider .lottie format or lazy loading |
| Critical | > 500ms | Mandatory: lazy load + .lottie + optimize file |

### Frame Drop Detection

```tsx
function useLottieFrameMonitor(animInstance, threshold = 33.34) {
  const rAF = useRef(0);
  const lastTime = useRef(0);
  const drops = useRef(0);

  useEffect(() => {
    if (!animInstance) return;

    const loop = (time) => {
      if (lastTime.current > 0) {
        const delta = time - lastTime.current;
        if (delta > threshold) {
          const dropped = Math.floor(delta / 16.67) - 1;
          drops.current += dropped;
          if (dropped > 2) {
            console.warn(`[Lottie Jank] Dropped ${dropped} frames (${delta.toFixed(1)}ms gap)`);
          }
        }
      }
      lastTime.current = time;
      rAF.current = requestAnimationFrame(loop);
    };

    rAF.current = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(rAF.current);
  }, [animInstance, threshold]);

  return drops;
}
```

**Frame drop thresholds:**
- Delta > 33ms = below 30fps (dropped 1+ frames)
- Delta > 50ms = below 20fps (dropped 2+ frames)
- Consistent drops = send animation back to design for optimization

---

## Level 3: Runtime Health & Schema Validation (Advanced)

### Memory Leak Detection

```tsx
function useLottieHealthAudit(intervalMs = 10000) {
  useEffect(() => {
    const check = setInterval(() => {
      const active = lottie.getRegisteredAnimations();
      if (active.length > 5) {
        console.warn(
          `[Lottie Health] ${active.length} active instances — potential memory leak. ` +
          `Expected ≤ 3 for typical SPA page.`
        );
      }
    }, intervalMs);
    return () => clearInterval(check);
  }, [intervalMs]);
}

// Place in _app.tsx or root layout to monitor globally
```

### SVG DOM Bloat Monitor

```tsx
function auditLottieDOMBloat(container: HTMLElement | null): number {
  if (!container) return 0;
  const count = container.getElementsByTagName("*").length;
  if (count > 500) {
    console.warn(`[DOM Bloat] ${count} nodes — consider Canvas renderer`);
  }
  if (count > 1500) {
    console.error(`[DOM Bloat] ${count} nodes — MUST switch to Canvas renderer`);
  }
  return count;
}
```

### Full Schema Validation with lottie-specs-js

For CI/CD pipelines or API routes that accept uploaded animations:

```tsx
import { LottieValidator } from "lottie-specs-js";

function validateLottieSchema(data: object) {
  const validator = new LottieValidator(Ajv2020, lottieSchema, {
    name_paths: true,
    docs_url: "https://lottie.github.io/lottie-spec/latest",
  });

  const errors = validator.validate(data, false);
  if (errors?.length) {
    errors.forEach((e) => {
      console.error(`[Lottie Validation] ${e.type}: ${e.message} at ${e.path}`);
    });
    return { valid: false, errors };
  }
  return { valid: true, errors: [] };
}
```

### Structured Error Logging

When reporting to APM (Sentry, Datadog), include animation metadata:

```tsx
function logLottieError(error: Error, animationData: any) {
  const log = {
    event: "LOTTIE_RENDER_FAILURE",
    error: error.message,
    metadata: {
      version: animationData?.v || "unknown",
      framerate: animationData?.fr || 0,
      layers: Array.isArray(animationData?.layers) ? animationData.layers.length : 0,
      hasExpressions: JSON.stringify(animationData).includes('"x"'),
      width: animationData?.w,
      height: animationData?.h,
    },
  };
  // Sentry.captureException(error, { extra: log });
  console.error(JSON.stringify(log));
}
```

---

## Accessibility Audit Checklist

Every Lottie animation MUST pass these checks:

| # | Check | How to Verify |
|---|-------|---------------|
| 1 | `role="img"` on container | Inspect DOM |
| 2 | `aria-label` with descriptive text | Inspect DOM — must describe purpose, not "animation" |
| 3 | `prefers-reduced-motion` respected | Toggle in OS settings → animation stops or shows static |
| 4 | No flashing > 3 times/second | Visual inspection — seizure risk |
| 5 | Keyboard controls if interactive | Tab to element, Space/Enter to play/pause |
| 6 | Color contrast if text in animation | 3:1 minimum against background |
| 7 | Fallback exists for load failure | Kill network → static image appears |
| 8 | Information equivalency | If animation conveys info, same info in text somewhere |

---

## Performance: Make It Fast

- **Validate BEFORE rendering** — catch corrupt files at the gate, not in the user's browser
- **Heuristic check is < 1ms** — the isValidLottie function has zero performance cost
- **Frame monitor is passive** — rAF-based, adds negligible overhead
- **Health audit interval** — 10s default is fine; don't poll faster than 5s

## Observability: Know It's Working

- **TTFF > 250ms** = file needs optimization or lazy loading
- **Dropped frames** = animation too complex for renderer or main thread blocked
- **Active instances > page count** = memory leak from missing destroy()
- **DOM nodes > 1,500** = SVG renderer is the wrong choice
- **data_failed event** = corrupt file, network error, or malformed JSON
- **Expression detection** = potential XSS if from untrusted source

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Skip Pre-Rendering Validation
**You will be tempted to:** Pass any JSON object directly to `loadAnimation({ animationData })` assuming it's valid because it came from your design team.
**Why that fails:** Corrupted JSON during network transit, incomplete exports, or supply chain attacks produce files that crash lottie-web synchronously. Without an ErrorBoundary, the entire React component tree unmounts — white screen of death.
**The right way:** Run `isValidLottie()` at the component level (< 1ms cost). Run `lottie-specs-js` validation in CI/CD or API routes. Wrap in ErrorBoundary + data_failed listener.

### Rule 2: Never Ignore data_failed Events
**You will be tempted to:** Wrap `loadAnimation()` in a try/catch and assume initialization success means the animation is healthy.
**Why that fails:** try/catch only catches synchronous init errors. If the animation loads but has broken image links or invalid interpolation data deep in the timeline, it fails silently — frozen or blank SVG with no error in the console.
**The right way:** Bind to `data_failed` and `error` events. Set React state to trigger fallback UI. Log structured metadata to your APM for debugging.

### Rule 3: Never Hide Animations with CSS to Respect Reduced Motion
**You will be tempted to:** Use `display: none` or `animation: none !important` on the container when `prefers-reduced-motion` is active.
**Why that fails:** CSS hiding does nothing to stop the JavaScript engine. lottie-web continues its rAF loop, burning CPU/battery for an invisible animation. The `aria-label` also disappears from the accessibility tree.
**The right way:** Call `anim.pause()` or `anim.goToAndStop(0)` via JavaScript. Keep the container visible with the first frame as a static image. Or conditionally render a `<img>` fallback instead.

### Rule 4: Never Skip Memory Leak Monitoring in SPAs
**You will be tempted to:** Assume that React component unmounting automatically cleans up Lottie instances.
**Why that fails:** lottie-web maintains global internal arrays of all active animations. React's Virtual DOM cleanup doesn't reach these. After multiple route transitions, orphaned instances accumulate → rAF callbacks multiply → CPU spikes → eventual OOM crash.
**The right way:** Always call `destroy()` in useEffect cleanup. Periodically audit with `lottie.getRegisteredAnimations().length`. If count exceeds visible animations, you have a leak.
