---
name: mx-lottie-interaction
description: Lottie animation interactivity in React — scroll-triggered playback with GSAP ScrollTrigger, hover play pause on mouseenter mouseleave, click toggle, segment playback with playSegments, named markers goToAndPlay, cursor-follow, lottie-interactivity conflicts, useGSAP hook cleanup
---

# Lottie Interaction — Scroll, Hover, Click & Segments for AI Coding Agents

**Load this skill when adding interactivity to Lottie animations — scroll-driven, hover, click, or segment-based playback.**

## When to also load
- `mx-lottie-core` — library setup, SSR handling, lifecycle management
- `mx-lottie-perf` — co-loads automatically on any Lottie work
- `mx-lottie-observability` — co-loads automatically on any Lottie work
- `mx-gsap-react` — GSAP + React patterns (useGSAP, ScrollTrigger cleanup)

---

## Level 1: Hover & Click Interactions (Beginner)

### Hover: Play on Enter, Pause on Leave

```tsx
"use client";
import { useLottie } from "lottie-react";
import animationData from "./icon-animation.json";

export function HoverIcon() {
  const { View, play, pause } = useLottie({
    animationData,
    loop: true,
    autoplay: false, // MUST be false for interaction control
  });

  return (
    <div
      onMouseEnter={() => play()}
      onMouseLeave={() => pause()}
      style={{ width: 80, cursor: "pointer" }}
    >
      {View}
    </div>
  );
}
```

### Click Toggle: Play/Pause

```tsx
"use client";
import { useState } from "react";
import { useLottie } from "lottie-react";

export function ClickToggle({ animationData }) {
  const [isPlaying, setIsPlaying] = useState(false);
  const { View, play, pause } = useLottie({
    animationData,
    loop: false,
    autoplay: false,
  });

  const handleClick = () => {
    if (isPlaying) { pause(); } else { play(); }
    setIsPlaying(!isPlaying);
  };

  return (
    <button onClick={handleClick} aria-pressed={isPlaying}>
      {View}
    </button>
  );
}
```

### Segment Playback with playSegments

```tsx
const { View, playSegments } = useLottie({ animationData, loop: false, autoplay: false });

// Play frames 0-50 immediately (forceFlag = true)
const playIntro = () => playSegments([0, 50], true);
// Play frames 51-100 immediately
const playOutro = () => playSegments([51, 100], true);
```

`playSegments([start, end], forceFlag)`:
- `true` = interrupt current playback, jump immediately
- `false` = queue after current segment finishes

---

## Level 2: Named Markers (Intermediate)

### Why Markers Beat Frame Numbers

| Approach | Survives Re-export? | Maintainable? | Example |
|----------|-------------------|---------------|---------|
| `playSegments([15, 45], true)` | No — frames shift when designer edits | No — magic numbers | Fragile |
| `goToAndPlay('introLoop')` | Yes — marker stays attached to keyframes | Yes — self-documenting | Resilient |

### After Effects Marker Setup

Designer creates markers in After Effects with:
- Comment: `{"name":"segmentName"}`
- Duration: length of the segment (optional)

### Using Named Markers in Code

```tsx
// With duration marker: plays segment and stops
animRef.current.goToAndPlay("introLoop");

// Without duration: plays from marker to end of composition
animRef.current.goToAndPlay("explosion");

// Jump to marker and freeze
animRef.current.goToAndStop("idleFrame");
```

**Note:** `playSegments()` does NOT accept named markers — only frame number arrays. For named segments, always use `goToAndPlay()`.

### Defensive Marker Usage

```tsx
// Check marker existence before playing (for untrusted animation files)
const markers = animRef.current?.renderer?.elements?.[0]?.data?.markers;
if (markers?.some(m => m.cm === "introLoop")) {
  animRef.current.goToAndPlay("introLoop");
}
```

---

## Level 3: GSAP ScrollTrigger Scroll-Scrub (Advanced)

### The Pattern: useGSAP + lottie-web + ScrollTrigger

This is the canonical pattern for scroll-driven Lottie in React. Use `lottie-web` directly (not lottie-react) because you need the raw instance.

```tsx
"use client";
import { useRef } from "react";
import lottie from "lottie-web";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { useGSAP } from "@gsap/react";

gsap.registerPlugin(ScrollTrigger);

export function LottieScrollSection({ animationData }) {
  const sectionRef = useRef(null);
  const lottieRef = useRef(null);
  const animInstance = useRef(null);

  useGSAP(() => {
    // 1. Init Lottie — autoplay MUST be false
    animInstance.current = lottie.loadAnimation({
      container: lottieRef.current,
      renderer: "svg",
      loop: false,
      autoplay: false,
      animationData,
    });

    // 2. Wait for data_ready — totalFrames not available until then
    animInstance.current.addEventListener("data_ready", () => {
      const totalFrames = animInstance.current.totalFrames;

      // 3. Create ScrollTrigger
      ScrollTrigger.create({
        trigger: sectionRef.current,
        pin: true,
        start: "top top",
        end: "+=200%",
        scrub: 1,
        onUpdate: (self) => {
          // Map scroll progress (0-1) to frame index
          const frame = Math.round(self.progress * (totalFrames - 1));
          animInstance.current.goToAndStop(frame, true);
        },
      });
    });

    // 4. Cleanup BOTH lottie AND ScrollTrigger
    return () => {
      animInstance.current?.destroy();
      ScrollTrigger.getAll().forEach((t) => t.kill());
    };
  }, { scope: sectionRef });

  return (
    <div ref={sectionRef} style={{ height: "100vh" }}>
      <div ref={lottieRef} style={{ width: "100%", height: "100%" }} />
    </div>
  );
}
```

### Key Details

| Setting | Value | Why |
|---------|-------|-----|
| `autoplay` | `false` | GSAP controls playback — autoplay causes visual stutter |
| `loop` | `false` | Scroll scrub handles direction — looping creates jumps |
| `scrub` | `1` or `true` | `1` = 1s smooth delay. `true` = instant (can feel jerky) |
| `pin` | `true` | Section stays visible during scroll-through |
| `goToAndStop(frame, true)` | `true` = isFrame | Second arg means "frame index" not "time in seconds" |

### Segment Scroll-Scrub

Map scroll progress to a sub-range instead of the full timeline:

```tsx
onUpdate: (self) => {
  const startFrame = 30;
  const endFrame = 120;
  const frame = startFrame + Math.round(self.progress * (endFrame - startFrame));
  animInstance.current.goToAndStop(frame, true);
}
```

---

## Performance: Make It Fast

- **Hover icons:** Use `lottie-react` wrapper (lighter setup) — GSAP is overkill
- **Scroll-scrub:** Use `lottie-web` directly — wrapper abstracts too much
- **Viewport-triggered play (no scrub):** Use IntersectionObserver + `play()` — cheaper than GSAP
- **Multiple hover icons:** Share one `animationData` import — each instance gets its own player

## Observability: Know It's Working

- **Verify data_ready fires** before creating ScrollTrigger — if it doesn't, totalFrames is undefined
- **Check `lottie.getRegisteredAnimations().length`** after route changes — orphans = memory leak
- **Use ScrollTrigger `markers: true`** during development to visualize start/end/trigger positions
- **Monitor `self.progress`** in onUpdate — should move smoothly from 0 to 1

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Hardcode Frame Numbers
**You will be tempted to:** Use `playSegments([15, 45], true)` because inspecting the JSON is faster than asking the designer for named markers.
**Why that fails:** Motion design is iterative. When the designer adds 5 frames of easing, every hardcoded index breaks. Animations play wrong segments, start mid-action, or crash if the frame exceeds totalFrames.
**The right way:** Require named markers in the After Effects export. Use `goToAndPlay('markerName')` exclusively.

### Rule 2: Never Combine lottie-interactivity with GSAP ScrollTrigger
**You will be tempted to:** Import `@lottiefiles/lottie-interactivity` alongside GSAP ScrollTrigger for scroll animations because both appear in search results.
**Why that fails:** They fight for scroll control. `lottie-interactivity` tracks element bounding rect. GSAP `pin: true` locks the element position. `lottie-interactivity` sees no movement → animation freezes permanently.
**The right way:** Pick one. If GSAP is in the project, use GSAP's `onUpdate` + `goToAndStop()`. Never mix scroll controllers.

### Rule 3: Never Forget Dual Cleanup
**You will be tempted to:** Rely on `useGSAP` to clean up everything, skipping the explicit `lottie.destroy()` call.
**Why that fails:** `useGSAP` cleans GSAP timelines and ScrollTriggers. It does NOT know about lottie-web instances. Without `destroy()`, the lottie instance runs its rAF loop forever in the background.
**The right way:** In the useGSAP return function, destroy BOTH: `animInstance.current?.destroy()` AND `ScrollTrigger.getAll().forEach(t => t.kill())`.

### Rule 4: Never Set autoplay:true When GSAP Controls Playback
**You will be tempted to:** Leave `autoplay: true` (the default) when setting up a scroll-scrub animation.
**Why that fails:** The animation immediately plays linearly on load. When GSAP's `onUpdate` fires, it yanks the playhead to the scroll position. This creates severe visual stuttering — the animation fights between its own timeline and GSAP's.
**The right way:** Explicitly set `autoplay: false` and `loop: false` for any animation controlled by GSAP or interaction events.
