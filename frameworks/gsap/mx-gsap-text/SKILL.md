---
name: mx-gsap-text
description: GSAP SplitText text animation patterns — character reveals, word stagger, line masking, autoSplit responsive re-splitting, onSplit callback, ScrollTrigger text combos, accessibility aria. Use when animating text, splitting text, SplitText, text reveal, stagger text, character animation, word animation, line animation.
---

# GSAP Text Animation Patterns for AI Coding Agents

**Loads when writing text animations with GSAP SplitText — character reveals, word staggers, line masking, responsive text splitting.**

## When to also load
- For SplitText API reference: see official **gsap-plugins** skill
- For React/Next.js integration: **mx-gsap-react**
- For scroll-triggered text: see official **gsap-scrolltrigger** skill
- For performance: **mx-gsap-perf**
- For debugging: **mx-gsap-observability**

---

## Level 1: Core Split Patterns (Beginner)

### Split Types — Only Parse What You Need

```javascript
// BAD: Splits everything (default), wastes DOM nodes
SplitText.create(".text", { type: "lines, words, chars" });

// GOOD: Only split what you'll animate
SplitText.create(".text", { type: "chars" });       // Character animation
SplitText.create(".text", { type: "words" });       // Word stagger
SplitText.create(".text", { type: "lines" });       // Line reveals
SplitText.create(".text", { type: "lines, chars" }); // Lines containing chars
```

### Recipe: Character-by-Character Reveal

```javascript
const split = SplitText.create(".hero-title", { type: "chars" });

gsap.from(split.chars, {
  duration: 0.8,
  autoAlpha: 0,
  y: 50,
  rotationX: -90,
  transformOrigin: "0% 50% -50",
  ease: "back.out(1.7)",
  stagger: 0.02
});
```

### Recipe: Word Stagger

```javascript
const split = SplitText.create(".subtitle", { type: "words" });

gsap.from(split.words, {
  duration: 1,
  autoAlpha: 0,
  scale: 0.8,
  ease: "power3.out",
  stagger: {
    amount: 1.5,
    from: "center",    // Ripples outward from middle
    ease: "power1.inOut"
  }
});
```

### Accessibility: aria is ON by default

SplitText v3.13+ automatically:
1. Adds `aria-label` with original text to the parent element
2. Adds `aria-hidden="true"` to all generated spans

This prevents screen readers from reading "H-e-l-l-o W-o-r-l-d" as individual tokens.

```javascript
// aria: "auto" is the default — don't disable it
SplitText.create(".text", { type: "chars", aria: "auto" });
```

---

## Level 2: Masking, Nesting, and Responsive Splits (Intermediate)

### Recipe: Masked Line Reveal (Standard Editorial Pattern)

`mask: "lines"` wraps each line in an `overflow: clip` container. Animate the inner line upward from below the mask.

```javascript
const split = SplitText.create(".editorial-heading", {
  type: "lines",
  mask: "lines"  // Creates overflow:clip wrappers
});

// Animate the lines (NOT the masks) — lines slide up into visible area
gsap.from(split.lines, {
  yPercent: 100,  // Start 100% below the mask
  duration: 1.2,
  ease: "expo.out",
  stagger: 0.1
});

// Access mask wrappers if needed: split.masks
```

### Recipe: Nested Split (Lines, then Chars Within)

```javascript
const split = SplitText.create(".nested-text", { type: "lines, chars" });
const masterTl = gsap.timeline();

split.lines.forEach((line, i) => {
  const charsInLine = line.querySelectorAll("div, span"); // chars inside this line
  masterTl.from(charsInLine, {
    autoAlpha: 0, x: 20, stagger: 0.02, duration: 0.6, ease: "power2.out"
  }, i * 0.1); // Offset each line's start
});
```

### Responsive: autoSplit + onSplit (MANDATORY PATTERN)

When viewport resizes or fonts load, line breaks change. `autoSplit: true` auto-reverts and re-splits. **Animations MUST be inside `onSplit()`** — otherwise they target destroyed DOM nodes.

```javascript
// GOOD: Animation inside onSplit, returned for auto-cleanup
SplitText.create(".responsive-heading", {
  type: "lines",
  mask: "lines",
  autoSplit: true,
  onSplit: (self) => {
    // Return the animation — SplitText tracks progress and restarts on resize
    return gsap.from(self.lines, {
      yPercent: 100,
      duration: 1,
      stagger: 0.1,
      ease: "power4.out"
    });
  }
});
```

```javascript
// BAD: Animation outside onSplit — breaks on resize
const split = SplitText.create(".text", { type: "lines", autoSplit: true });
gsap.from(split.lines, { yPercent: 100 }); // These DOM nodes get destroyed on resize!
```

| autoSplit | onSplit | Result |
|-----------|---------|--------|
| `false` | Not needed | Static split, no resize handling |
| `true` | **Required** | Auto re-split on resize/font load, animation recreated |
| `true` | Missing | **BUG** — animation targets destroyed nodes after resize |

---

## Level 3: ScrollTrigger Combos & Advanced Patterns (Advanced)

### Scroll-Triggered Text Reveal

```javascript
SplitText.create(".scroll-text", {
  type: "lines",
  mask: "lines",
  autoSplit: true,
  onSplit: (self) => {
    return gsap.timeline({
      scrollTrigger: {
        trigger: self.elements[0], // The original text element
        start: "top 80%",
        toggleActions: "play none none reverse"
      }
    }).from(self.lines, {
      yPercent: 100, autoAlpha: 0, duration: 1, stagger: 0.1, ease: "power4.out"
    });
  }
});
```

### Scrub-Based Character Reveal (Tied to Scroll Position)

```javascript
SplitText.create(".scrub-text", {
  type: "chars",
  autoSplit: true,
  onSplit: (self) => {
    return gsap.timeline({
      scrollTrigger: {
        trigger: ".scrub-container",
        start: "top center",
        end: "bottom center",
        scrub: 0.5
      }
    }).from(self.chars, {
      autoAlpha: 0.1,
      stagger: 0.1
    });
  }
});
```

### Batch Multiple Text Elements

For many headings on a page, use `ScrollTrigger.batch()` instead of individual triggers.

```javascript
const headings = gsap.utils.toArray(".batch-heading");

// Pre-split and pre-hide all headings
const splits = headings.map(el => {
  const s = SplitText.create(el, { type: "words", mask: "words" });
  gsap.set(s.words, { autoAlpha: 0, yPercent: 100 });
  return { element: el, split: s };
});

ScrollTrigger.batch(headings, {
  interval: 0.1,
  onEnter: (batch) => {
    batch.forEach(el => {
      const match = splits.find(s => s.element === el);
      if (match) {
        gsap.to(match.split.words, {
          autoAlpha: 1, yPercent: 0, stagger: 0.05, duration: 0.8, ease: "power3.out"
        });
      }
    });
  },
  start: "top 85%"
});
```

### React Cleanup: useGSAP Handles SplitText

```tsx
"use client";
import { useRef } from "react";
import { gsap } from "gsap";
import { SplitText } from "gsap/SplitText";
import { useGSAP } from "@gsap/react";

gsap.registerPlugin(SplitText);

export default function AnimatedHeading() {
  const ref = useRef(null);

  useGSAP(() => {
    // SplitText created inside useGSAP is auto-reverted on unmount
    const split = SplitText.create(".heading", { type: "chars" });
    gsap.from(split.chars, { autoAlpha: 0, y: 50, stagger: 0.02, duration: 1 });
  }, { scope: ref });

  return <div ref={ref}><h1 className="heading">Animated Text</h1></div>;
}
```

---

## Performance: Make It Fast

- **Only split what you animate**: `type: "chars"` not `type: "lines, words, chars"` if you only need chars
- **Mask uses `overflow: clip`** (not `hidden`): SplitText's native masking is already optimized
- **Batch text elements**: `ScrollTrigger.batch()` for multiple headings instead of individual triggers
- **Limit stagger on long text**: 200+ characters with 0.02s stagger = 4 second animation. Cap at `amount: 1.5`

## Observability: Know It's Working

- **Font loading**: If text jumps after initial render, fonts loaded after split. Use `autoSplit: true` or wrap in `document.fonts.ready.then()`
- **Resize test**: Resize browser with text animation active — if text breaks, `autoSplit: true` is missing or `onSplit` not used
- **Cleanup test**: Navigate away and back — if text has doubled spans, `revert()` wasn't called

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never animate the parent container instead of split arrays
**You will be tempted to:** `gsap.to(".text", { opacity: 0, stagger: 0.1 })` after splitting.
**Why that fails:** `.text` is ONE element — stagger does nothing. The split arrays (`.chars`, `.words`, `.lines`) are what you animate.
**The right way:** `gsap.to(split.chars, { ... stagger: 0.1 })`.

### Rule 2: onSplit is MANDATORY when autoSplit is true
**You will be tempted to:** Enable `autoSplit: true` and write the animation right after the create call.
**Why that fails:** On resize, autoSplit destroys and recreates DOM nodes. Your animation still references the old, destroyed nodes.
**The right way:** All animations go inside `onSplit: (self) => { return gsap.from(self.lines, {...}) }`. RETURN the animation.

### Rule 3: Never use overflow:hidden for text masking manually
**You will be tempted to:** Wrap text in a `<div style="overflow: hidden">` for reveal effects.
**Why that fails:** `overflow: hidden` creates a new block formatting context and clips descenders (g, p, y). Text looks cut off.
**The right way:** Use `mask: "lines"` in SplitText config — it uses `overflow: clip` which handles typographic bounds correctly.

### Rule 4: Never skip cleanup in React components
**You will be tempted to:** Use `useEffect` with SplitText but leave cleanup empty.
**Why that fails:** React Strict Mode runs effects twice. Second run splits already-split spans, corrupting the DOM exponentially.
**The right way:** Use `useGSAP()` — it auto-reverts SplitText, tweens, and ScrollTriggers on unmount.

### Rule 5: Never initialize SplitText before fonts load
**You will be tempted to:** Call SplitText.create() in a top-level script or early useEffect.
**Why that fails:** Line breaks are calculated with fallback font metrics. When the real font loads, words jump out of their line wrappers.
**The right way:** Use `autoSplit: true` (listens to `document.fonts.ready`) or wrap in `document.fonts.ready.then(() => { ... })`.
