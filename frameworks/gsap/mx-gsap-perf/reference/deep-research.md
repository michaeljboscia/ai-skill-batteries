# Advanced GreenSock Animation Platform (GSAP) Performance Optimization: A Comprehensive Technical Guide

**Key Points:**
*   Research suggests that managing GPU layer promotion via `force3D` and `will-change` is critical; excessive layers deplete VRAM and degrade performance.
*   It seems highly likely that leveraging `gsap.context()` in component-based frameworks (like React or Vue) is the most reliable method for preventing memory leaks and orphaned animations.
*   For high-frequency events (like mouse movement), bypassing standard tween parsing via `gsap.quickSetter()` or `gsap.quickTo()` can yield performance increases of 50% to 250%.
*   Evidence leans toward using `gsap.matchMedia()` as the optimal approach for accessible, responsive animations, particularly for accommodating `prefers-reduced-motion` settings.

**Understanding Animation Performance**
The GreenSock Animation Platform (GSAP) is a robust tool for web animation, but complex sequences can easily overtax a device's CPU and GPU. This report explores advanced techniques to ensure animations remain smooth at 60 frames per second (fps). It covers how the browser renders graphics, how to defer animations until they are actually visible, and how to properly clean up code to free up device memory. 

**The Need for Optimization**
Modern web applications often suffer from "jank" (stuttering visual updates) when developers rely on baseline animation techniques. While GSAP is heavily optimized out-of-the-box, it still operates within the constraints of the browser's main thread and compositing architecture. By strategically managing how and when calculations occur, developers can build rich, interactive experiences that do not compromise device battery life or accessibility.

---

## 1. Introduction

The GreenSock Animation Platform (GSAP) provides a highly performant, frame-based engine synchronized with the browser's refresh rate via `requestAnimationFrame` [cite: 1, 2]. While GSAP natively mitigates many layout-thrashing anti-patterns, the architectural complexities of modern web frameworks (e.g., React, Vue) and the constraints of mobile hardware require developers to adopt explicit optimization strategies. This comprehensive guide details advanced techniques for maximizing GSAP performance, focusing on graphics processing unit (GPU) layer management, lazy initialization, responsive memory handling, virtualization of large DOM arrays, and the circumvention of standard engine parsing for high-frequency updates.

---

## 2. GPU Layer Management and Compositing

To achieve 60fps, animations must ideally bypass the browser's "Layout" and "Paint" phases, operating entirely within the "Composite" phase. This requires hardware acceleration, which promotes an element to its own compositor layer on the GPU [cite: 3, 4].

### Transform vs. Layout Properties
Animating properties such as `width`, `height`, `top`, `left`, `margin`, or `padding` forces the CPU to recalculate the document layout and repaint pixels on every frame, which is computationally prohibitive [cite: 3, 5]. Conversely, animating `transform` (`x`, `y`, `scale`, `rotation`) and `opacity` allows the browser to utilize the GPU to manipulate an existing bitmap [cite: 1, 6]. GSAP defaults to using transforms for `x` and `y` coordinates [cite: 3].

### The `force3D` Directive: "auto" vs. `true`
GSAP's CSSPlugin includes a `force3D` property that governs hardware acceleration [cite: 4, 7]. By default, `force3D` is set to `"auto"`.

*   **`force3D: "auto"` (Default):** During an active tween, GSAP applies a 3D transform (e.g., `translate3d()` or `matrix3d()`) [cite: 8, 9]. This forces the browser to create a GPU texture (compositor layer) for the element, resulting in highly efficient manipulation [cite: 4, 10]. Once the animation completes, if no 3D properties remain, GSAP automatically reverts the element to a 2D transform (e.g., `translate()` or `matrix()`) [cite: 4, 10]. This frees up constrained Video RAM (VRAM).
*   **`force3D: true`:** This forces the element to remain in 3D mode permanently [cite: 7, 10]. While this eliminates the microscopic delay of transferring a texture to the GPU upon subsequent animations, overusing it leads to a "layer promotion budget" crisis [cite: 11]. Exceeding the GPU's memory limit causes aggressive texture thrashing, degrading performance severely [cite: 7, 12].

#### Code Example: Fine-Tuning `force3D`
```javascript
// Optimal for elements animated once or infrequently
gsap.to(".infrequent-item", {
  x: 100,
  force3D: "auto", // Default behavior, conserves VRAM
  duration: 1
});

// Optimal for a persistently animated element (e.g., a continuous spinner)
gsap.to(".persistent-spinner", {
  rotation: 360,
  force3D: true, // Prevents repeated GPU layer creation/destruction
  repeat: -1,
  ease: "none",
  duration: 2
});
```

### The `will-change` Strategy
The CSS `will-change: transform` property is a hint to the browser to preemptively promote an element to a compositor layer before the animation begins, preventing the initial startup lag [cite: 2, 3]. However, leaving `will-change` applied permanently exhausts VRAM in the same manner as `force3D: true` [cite: 13].

The optimal strategy is to apply `will-change` immediately prior to an animation, and remove it upon completion.

#### Code Example: Lifecycle-Aware `will-change`
```javascript
const animatePanel = (element) => {
  // Preemptively hint the browser
  element.style.willChange = 'transform, opacity';
  
  gsap.to(element, {
    x: 100,
    opacity: 0.8,
    duration: 0.5,
    onComplete: () => {
      // Release GPU memory allocation
      element.style.willChange = 'auto';
    }
  });
};
```

### Decision Tree: GPU Layer Management

| Scenario | Recommended Strategy | Rationale |
| :--- | :--- | :--- |
| Element animates continuously (e.g., infinite loop). | `force3D: true` or persistent `will-change: transform`. | Avoids constant allocation and deallocation of GPU textures. |
| Element animates once, enters resting state. | `force3D: "auto"` (GSAP default). | Returns GPU memory once animation finishes to prevent VRAM overflow. |
| Complex element requires pre-computation to avoid start-up jank. | Apply `will-change` via JavaScript `onStart`, remove `onComplete`. | Pre-rasterizes the texture without permanently consuming the layer budget. |
| Animating `top`, `left`, `width`, or `height`. | Refactor to `y`, `x`, `scaleY`, `scaleX`. | Keeps calculations off the CPU layout thread entirely. |

---

## 3. Lazy ScrollTrigger Initialization and Batching

When developing scroll-driven web experiences, instantiating hundreds of independent `ScrollTrigger` animations on page load causes severe main-thread blocking and memory bloat. Performance is maximized through lazy initialization and batching [cite: 13].

### `ScrollTrigger.batch()`
For long lists of similar elements (e.g., product grids, article cards), `ScrollTrigger.batch()` creates a coordinated group of triggers that fire callbacks within a localized interval [cite: 14]. Instead of individual tweens fighting for execution time, `batch()` collects elements that enter the viewport simultaneously and passes them as an array, ideal for staggered animations [cite: 14, 15].

#### Code Example: Optimal Batching
```javascript
gsap.set('.card', { y: 50, opacity: 0 });

// Creates a single, highly-optimized observer interval for all cards
ScrollTrigger.batch('.card', {
  interval: 0.1, // Time window to group entering elements
  batchMax: 5,   // Maximum elements per staggered batch
  onEnter: (elements) => {
    gsap.to(elements, {
      opacity: 1,
      y: 0,
      stagger: 0.1,
      overwrite: true // Prevent conflict with leaving animations
    });
  },
  onLeave: (elements) => {
    gsap.to(elements, { opacity: 0, y: -50, overwrite: true });
  }
});
```

### Lazy Initialization of Complex Timelines
If an element contains a highly complex nested timeline, generating that timeline before the element is anywhere near the viewport wastes memory. Instead, instantiate the animation only when the user scrolls near the element.

#### Code Example: Just-In-Time Timeline Creation
```javascript
let isInitialized = false;

ScrollTrigger.create({
  trigger: ".heavy-section",
  start: "top 150%", // Trigger well before it enters the viewport
  once: true, // Dispose of the trigger once fired
  onEnter: () => {
    if (!isInitialized) {
      const tl = gsap.timeline();
      tl.to(".heavy-element-1", { x: 100 })
        .to(".heavy-element-2", { rotation: 180 }, "<");
      isInitialized = true;
    }
  }
});
```

### Decision Tree: ScrollTrigger Strategies

| DOM Structure / Need | Optimal Approach | Implementation |
| :--- | :--- | :--- |
| Dozens of identical cards in a grid. | `ScrollTrigger.batch()` | Pass elements array to a staggered `gsap.to()`. |
| Complex, multi-stage animation timeline. | Lazy Initialization | Use an independent ScrollTrigger to generate the timeline when `top 150%` is reached. |
| Single, one-off reveal animation. | Standard `ScrollTrigger` with `once: true`. | `gsap.from(el, { opacity: 0, scrollTrigger: { once: true } })` ensures garbage collection [cite: 16]. |

---

## 4. Responsive Performance and `gsap.matchMedia()`

Executing complex calculations on resource-constrained mobile devices degrades user experience. Furthermore, modern accessibility standards dictate that users with vestibular disorders must be able to opt out of motion via the operating system's `prefers-reduced-motion` flag [cite: 17].

GSAP 3.11+ introduced `gsap.matchMedia()`, which scopes animations to specific media queries and automatically manages the tedious cleanup process (`revert()`) when conditions change [cite: 18].

### Integrating `prefers-reduced-motion`
Instead of entirely stripping animations, which can remove vital context from a user interface, developers should provide simplified alternatives (like crossfades) [cite: 19]. `gsap.matchMedia()` acts identically to `window.matchMedia()` but tracks and stores all GSAP instances generated within its callback [cite: 18].

#### Code Example: Responsive and Accessible `matchMedia`
```javascript
let mm = gsap.matchMedia();

// Define breakpoints and accessibility queries
mm.add({
  isDesktop: "(min-width: 800px)",
  isMobile: "(max-width: 799px)",
  reduceMotion: "(prefers-reduced-motion: reduce)"
}, (context) => {
  let { isDesktop, isMobile, reduceMotion } = context.conditions;

  // 1. If user prefers reduced motion, provide an opacity fade
  if (reduceMotion) {
    gsap.from(".hero-element", { opacity: 0, duration: 1 });
    return; // Exit early, skipping complex motion
  }

  // 2. Complex desktop animation
  if (isDesktop) {
    gsap.timeline({
      scrollTrigger: { trigger: ".hero", scrub: true, pin: true }
    }).to(".hero-element", { scale: 2, rotation: 360 });
  }

  // 3. Simplified mobile animation (saves CPU/GPU on weak devices)
  if (isMobile) {
    gsap.to(".hero-element", { y: -50, opacity: 1 });
  }

  // Context automatically reverts these animations when the breakpoint shifts
});
```

### Decision Tree: Responsive Animation Design

| User Environment | Motion Strategy | Performance Implication |
| :--- | :--- | :--- |
| Desktop & `no-preference` | Full complex sequences, pinning, scrubbing. | High CPU/GPU utilization; optimal for capable hardware. |
| Mobile & `no-preference` | Simplified transforms (no pinning, fewer tweens). | Reduces thermal throttling and battery drain on mobile CPUs. |
| `prefers-reduced-motion` | Opacity fades only, no spatial transforms. | Meets WCAG AAA compliance, minimal processing required [cite: 19]. |

---

## 5. Memory Leak Prevention and Garbage Collection

The most prevalent performance failure in Single Page Applications (SPAs) built with React, Vue, or Nuxt occurs when components unmount, but GSAP instances continue running in memory [cite: 20, 21]. 

### The Difference Between `kill()` and `revert()`
To eliminate memory leaks, developers must grasp the distinction between these two methods [cite: 22]:
*   **`kill()`:** Stops the animation in its tracks and makes the tween eligible for garbage collection. However, any inline styles applied by GSAP (e.g., `style="transform: translate(50px)"`) remain permanently attached to the DOM node [cite: 22].
*   **`revert()`:** Stops the animation, deletes the instance, and strips all inline CSS injected by GSAP, restoring the element to its pristine pre-animation state [cite: 22, 23]. This is essential for component re-mounting.

### `gsap.context()` for Component Cleanup
`gsap.context()` collects all animations, ScrollTriggers, and `SplitText` instances created within its callback. Calling `ctx.revert()` during a component's teardown lifecycle immediately destroys all grouped instances [cite: 20, 23]. In React, the `@gsap/react` package exposes `useGSAP()`, which wraps `gsap.context()` to automate this [cite: 20, 24].

#### Code Example: Robust Cleanup in React (Using Context)
```jsx
import { useRef, useEffect } from 'react';
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import { SplitText } from 'gsap/SplitText';

gsap.registerPlugin(ScrollTrigger, SplitText);

export default function AnimatedComponent() {
  const containerRef = useRef(null);

  useEffect(() => {
    // Wrap all creation logic in a context
    let ctx = gsap.context(() => {
      // 1. SplitText instances are inherently tracked by context in newer GSAP versions
      const textSplit = new SplitText(".title", { type: "words,chars" });
      
      // 2. Tweens and ScrollTriggers are tracked automatically
      gsap.from(textSplit.chars, {
        opacity: 0,
        y: 20,
        stagger: 0.05,
        scrollTrigger: {
          trigger: ".title",
          start: "top center"
        }
      });
      
      // 3. Manual event listeners must be tracked and cleaned up independently 
      // or added via ctx.add() if triggering animations
      const btn = document.querySelector(".btn");
      const onClick = () => gsap.to(".box", { x: 100 });
      btn.addEventListener("click", onClick);
      
      // Add custom cleanup to the context
      return () => btn.removeEventListener("click", onClick);

    }, containerRef); // Scope selector text to this component

    // Teardown: Reverts SplitText, kills ScrollTrigger, reverts Tweens, removes listeners
    return () => ctx.revert(); 
  }, []);

  return (
    <div ref={containerRef}>
      <h1 className="title">Hello World</h1>
      <div className="box"></div>
      <button className="btn">Move Box</button>
    </div>
  );
}
```

### Handling `SplitText` Complexities
`SplitText` modifies the DOM structure by injecting nested `div` elements. If the containing component unmounts or routes change (e.g., via SWUP or Next.js router) without reverting `SplitText`, the DOM becomes bloated with fragmented nodes [cite: 25]. Furthermore, using `autoSplit: true` (which reflows text on window resize or font load) without wrapping animations inside the `onSplit` callback causes the engine to animate "ghost" elements that have already been replaced [cite: 26, 27].

#### Code Example: Proper `autoSplit` Management
```javascript
// Correct implementation for reflowing text
SplitText.create(".responsive-text", {
  type: "lines",
  autoSplit: true,
  onSplit: (self) => {
    // Returning the tween allows SplitText to automatically 
    // kill and restart the animation cleanly upon resize reflow.
    return gsap.from(self.lines, {
      y: 100,
      opacity: 0,
      stagger: 0.05
    });
  }
});
```

### Decision Tree: Memory Management

| Lifecycle Event | Action Required | GSAP Mechanism |
| :--- | :--- | :--- |
| Component Unmount (React/Vue) | Strip inline styles and kill loops. | `ctx.revert()` via `useGSAP()` or `onUnmounted`. |
| Window Resize (Text Reflow) | Re-calculate text splits, preserve animation progress. | `SplitText` with `autoSplit: true` and returning tweens in `onSplit` [cite: 26]. |
| Interactive Event (Mouse, Click) | Ensure accumulating listeners are destroyed. | Return removal functions inside `gsap.context()` [cite: 28]. |

---

## 6. Large List Animation Strategies

Rendering large sets of data (e.g., 1000+ rows) fundamentally breaks performance paradigms. While GSAP handles mathematical interpolation efficiently, the browser's rendering engine cannot manage thousands of concurrent DOM node repaints [cite: 29]. 

### DOM Virtualization First
Before implementing GSAP on a massive array, developers must utilize list virtualization (e.g., `react-window` or Vue's dynamic rendering) [cite: 29]. Virtualization ensures that only the nodes visible in the viewport (plus a small buffer) exist in the DOM [cite: 29].

### Staggered Reveal with Visibility Checks
Even with virtualization, creating tweens for hundreds of list items simultaneously overburdens the CPU. As established, `ScrollTrigger.batch()` should be used to compartmentalize logic [cite: 14]. 

If batching is unfeasible, implement visibility checks to prevent GSAP from initializing timelines for off-screen items [cite: 30].

#### Code Example: Virtualized / Paged Staggering
```javascript
const items = document.querySelectorAll(".virtual-list-item");

// Poor Performance: gsap.to(items, { stagger: 0.1, x: 100 }); 
// Creates X tweens instantly.

// High Performance: Use Batching to stagger ONLY what enters the screen
ScrollTrigger.batch(items, {
  interval: 0.15,
  onEnter: (batch) => {
    gsap.to(batch, {
      opacity: 1,
      x: 0,
      stagger: 0.1,
      // overwrite ensures no conflict if scrolling rapidly
      overwrite: "auto" 
    });
  }
});
```

---

## 7. High-Frequency Updates: `gsap.quickTo()` and `gsap.quickSetter()`

Binding standard `gsap.to()` calls to high-frequency browser events—such as `mousemove`, `touchmove`, `requestAnimationFrame`, or device accelerometers—is a primary source of memory bloat. Every time `gsap.to()` is called, the engine performs heavy background logic: unit conversion, relative value string parsing, function-based value evaluation, and plugin routing [cite: 31]. Running this logic 60 times a second creates severe garbage collection pressure.

To circumvent this, GSAP provides hyper-optimized data pipes.

### `gsap.quickSetter()`: Instant Value Setting
If an animation requires immediate mathematical updates without smoothing or easing, `quickSetter()` provides a 50% to 250% performance increase over `gsap.set()` [cite: 32, 33]. It wires directly to a specific property of an element, skipping all safety checks and parsing logic [cite: 33].

### `gsap.quickTo()`: Interpolated Following
If the object needs to smoothly follow a moving target (like a custom cursor), `quickTo()` creates a reusable tween. Instead of generating a new tween object per frame, `quickTo()` re-routes the endpoint of an existing tween, conserving massive amounts of memory [cite: 31, 34].

#### Code Example: High-Performance Custom Cursor
```javascript
// Initialize target element center
gsap.set(".cursor", { xPercent: -50, yPercent: -50 });

// Initialize reusable, highly-optimized tweens
// Skipping unit conversions by passing raw numbers later
const xTo = gsap.quickTo(".cursor", "x", { duration: 0.4, ease: "power3.out" });
const yTo = gsap.quickTo(".cursor", "y", { duration: 0.4, ease: "power3.out" });

// Bind to high-frequency event
document.addEventListener("mousemove", (e) => {
  // Pipes values directly into the tween's inner registry
  xTo(e.clientX);
  yTo(e.clientY);
});
```

### Decision Tree: High-Frequency Updates

| Scenario | Recommended API | Performance Implication |
| :--- | :--- | :--- |
| Custom cursor that smoothly trails behind the mouse. | `gsap.quickTo()` | Reuses a single tween instance; prevents garbage collection pauses [cite: 31]. |
| Parallax element directly tied to raw scroll math (no easing). | `gsap.quickSetter()` | Bypasses core engine parsing entirely; fastest possible execution [cite: 33, 35]. |
| Occasional state change based on click. | standard `gsap.to()` | Negligible performance overhead; benefits from standard engine safety checks [cite: 33]. |

---

## 8. Performance Benchmarks

*Note: The following benchmarks are based on documented optimization metrics [cite: 33] and established browser rendering mechanics. Absolute frame rates depend heavily on device hardware.*

| Optimization Technique | Baseline Approach | Optimized Approach | Estimated Performance Gain / Metric |
| :--- | :--- | :--- | :--- |
| **Mouse Follower (60Hz event)** | `gsap.to()` on every `mousemove` (High GC pressure) | `gsap.quickTo()` (Reused tween instance) | **Up to 250% CPU reduction**; prevents dropped frames [cite: 33]. |
| **List of 500 Elements** | Independent `ScrollTrigger` per item | `ScrollTrigger.batch()` | **Significant memory reduction**; groups rendering intervals [cite: 14]. |
| **Component Teardown** | Component unmounts, tweens keep running | `ctx.revert()` on unmount | **Eliminates memory leaks**; restores pristine DOM state [cite: 22]. |
| **Translating Elements** | Animating `top` / `left` (CPU Layout) | Animating `x` / `y` (GPU Composite) | **Bypasses layout thrashing**; shifts load to GPU [cite: 3, 5]. |
| **Layer Management** | `force3D: true` on 1000 items | `force3D: "auto"` | **Prevents VRAM exhaustion**; avoids texture thrashing [cite: 4, 7]. |

---

## 9. Anti-Rationalization Rules (The Developer/AI Temptation Checklist)

When building complex logic, it is exceptionally easy to rationalize "quick fixes" that severely degrade animation performance over time. Adhere to the following strict rules:

1.  **Never rationalise animating layout properties.**
    *   *Temptation:* "I need this box to expand, so I will animate `width` and `height`. It's just one box."
    *   *Reality:* Animating `width`/`height` triggers global document layout recalculations [cite: 3]. 
    *   *Rule:* Always substitute with `scaleX` and `scaleY`. If the child contents distort, counter-scale them, or use the GSAP Flip plugin.

2.  **Never rationalise indiscriminate `will-change` usage.**
    *   *Temptation:* "I want all my animations to be hardware-accelerated, so I will put `will-change: transform` or `force3D: true` on the `*` universal selector."
    *   *Reality:* The browser has a strictly limited VRAM budget. Forcing layers globally will crash the browser or cause severe visual artifacts (blurry text, flickering) [cite: 8, 12].
    *   *Rule:* Only apply `will-change` dynamically via JavaScript before the tween begins, and remove it in the `onComplete` callback, or rely on GSAP's default `force3D: "auto"` [cite: 11, 13].

3.  **Never rationalise skipping cleanup in SPAs.**
    *   *Temptation:* "This specific component is heavily used, so I don't need to revert the GSAP context on unmount. It's fine if the `SplitText` DOM nodes stay."
    *   *Reality:* Every unmounted component leaves ghost tweens running in the background and detached DOM elements. The memory footprint will balloon over a user session [cite: 20, 21, 23].
    *   *Rule:* All animations within React, Vue, or dynamic routing systems *must* be encased in `gsap.context()` (or `useGSAP`) and cleanly reverted via `ctx.revert()` [cite: 20, 28].

4.  **Never rationalise creating new tweens inside high-frequency event loops.**
    *   *Temptation:* "It's just a 3-line `gsap.to()` call inside my `requestAnimationFrame` loop. V8 engine garbage collection is fast enough."
    *   *Reality:* Creating object instances 60 to 120 times per second guarantees garbage collection spikes, which freeze the main thread momentarily (jank) [cite: 34, 36].
    *   *Rule:* Strictly use `gsap.quickTo()` or `gsap.quickSetter()` for continuous inputs like `mousemove` or scroll-driven mathematical calculations [cite: 31, 36].

5.  **Never rationalise ignoring `prefers-reduced-motion`.**
    *   *Temptation:* "My site's identity relies on these massive parallax sweeps. I'll just skip the media query for this one project."
    *   *Reality:* Motion sickness from vestibular disorders is a physical accessibility barrier [cite: 17]. Non-compliance harms users and degrades performance on low-end devices.
    *   *Rule:* Wrap primary sequences in `gsap.matchMedia()`. Provide a seamless fallback (e.g., opacity fades) for the `reduce` state [cite: 17, 19].

**Sources:**
1. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQH_I0QqG3aR-h4nCxYx_8kQ87Q83RCS6K8tUBRYUwFdinO9LcNam7T2z8DmOXZINkx8Yo07wL_ZZ2zhK9lV36mvXak5qv5KbuiBIOy3pPS0k6iSaqQxOgmR6tYkqp1XFKold2D41fZ2grA8J4cUar5n93ewFsbt5RMXIDQ-O1nB-MJ2T5FY-TTI)
2. [augustinfotech.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGkOoxlnpnzA9EIqYtwUEFOhXs2TUek0XVrv6CIOq9ZOzAu2Xne4xYhB6sISqOyAzLjKhR93GZdw4fjrCxiHjkRCyoBC8XKGCyMJvFKJD0Z1wpzwZzEqnkSWTPE2AziGa_JjF0hk3N2_ml5NzhNSstA6n7nAohxsDUxPdm3P1YnoP2mS5Ps1OufBu4QpaJ-NT2OEpBspGKiD894P-m-i8kWQnE=)
3. [lobehub.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEAMkPG7QS9ivwXRryGYSnLkz_tlCuYexzH02JPlv02pAOfac2ezMVNToJ40BxBR8ehEsFHYpk-Z3MR1CkcTbmctw-yCMJSjypHB5jhj6IewCH8amDVDlEwTxLmwnPf03RiMVT_Omd724Zgkwbusy9bi-AbJCbZ)
4. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGfOHD-QV7Zec4KyhGUAsSoXDgH9gOLU6vtUMtQwlYmgqWqPmDdxSKJcyIzu81eNq6at25tukNGSu04tnbyMg1wWsKhl0WuqeNFSF3GLV5UVQUfbTyMz-S8-5y78HkMRrW5nbs=)
5. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHdXxmcVgRGctlSkEdU0ese-SK9xaCTAWcAWcgkgu-aa9TktZGGfzf9fsetnQS4icwRPse2FgxS31CEowqiIhBt-pWKJNYME7kcHS5ezlU_JWLv0qI--fRdo_tHtkbFmDIaxkA93aWwMEAvguLXsf1lvjXgCbkdj3Xd6-axlb8IZdsT6dVb7zE=)
6. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFX3J6Xw-UaAg0QP2h9R1EnU84bDFKlb04E1DByxESnAFcjkjLfrOehwlSBa7BDluiY9BaPTPdQ81OrnAjnZguRZBBUP89usWCsqoyROHi3OozTggSgdC0N6gPSgFfHfUOlUpPVeLt7ZZXkH7Ff7cp31sN0H4nmzcPnO3nq5qsWqT7FNZ7RI6-Mz4Laio-ZuJdCbxFX211BglPL1ufKMgMo1skQPG8u-tGnc_uOVPqtN9lnCtwrhjE=)
7. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGdR9PImsWLZaVPPV_Wi7QS4W2_q-kodzpolJZfuj8hGRKYHIwLFAomYCmm287b3epHpMCHHmg-YyJac56o_TpR6eUoi41z89uiyecfrLablb7FmUYz06HpkMmaRT9mfONThA5drSGvVg6ujDkKlP6Tjollok579xUOmQbanQDJ_0q94cV_kd_dTgWlmjlzIYdAqFxBuh9sLmwqtrM=)
8. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGdRbByf921I0mc2mm7A903GzbR8n1cuU8J-u-AgB1zEZyN9SfBdVFJatQWBfFAorTjxybhpYtVWEhLeQvUW9s_grRUPibdelAOCSbx7Ii1089OuletVOUpsXByfOBVdoWXeAK37L-eSUf7TcLI4OCALFGxsw2VU4ptfEBU0KmonR8f7MJI9m9G7wh1Vzk23QeL-Q6pKrA=)
9. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQETeb3S-o5GMxKjwwcdj7Q_kfXtVtDl-36TddxOcY2VucWPFgfTjdQW3nMb6OQjP7eBfEbhzn8hFZIJmt8SW7Q5hxwSsqQsDZEDHMHq6ztdQl31Mb66rfKCLE-iU_pwyONWhzyhkch0EXwyrIcN6-M3OTRgiuu0lIKpiFdULy7M0JvkGtOaxa132OKReDnNmBqcnuPrrQ==)
10. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHrMJyKPb79bfiAt8L8NXK8NrtcGIaz8XOeIVUp8XttWaHXQ6qfMHcVgakPyC0CGLiBKU99UjDGPWtu7wD7sx20ivz4JxXTdM-uGpLSqlEnm5vsoZ_RyiD7D592aKN-HVMK)
11. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFKMxLMou38KMv5kDeF5kn-lR6CB9zBMR83wAF4TsX58AJePiTY57M5_IekPjCumMTqhsQ20C3xStlUEoI2oRjBB1NngCnjrLGgjkLsF2zP3k0ngbWDtaYOlm8Tnqj7ZHxwXQK0RT7rI__itL2pYWHJ2A4KtYY=)
12. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEVJ3z3PXOOrlFL0eSvMKNT41urRR5aMJ-5ipe1d6YPT7fi95o7BRPwcpL8rF9nWmUANC-Q8rojwEzm3yDne3k9dtV5ZNhRG5_3hSkTKfm3PAXmt11wbob-49eWX43VGnYDcx67GU7LpY-pQSjfGPNX-Uk1xsnMWHErdFOi6-PfEWPSS_69EYiJI9ojKUM=)
13. [smithery.ai](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEsc2fJmRRxl4cIaAacaxrINDpZmmau3xgfY4jHjrp3lrQ0jSCUIhlr5ZZoNOgSuqNbepaMTFJEG3REhWHZ3bFx-pREtxovNb4-MhLpeFegTTOAhKxIxbiL6NGH4RNf3lL6Sh4=)
14. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGsLqF9iWcGAuV07CRISRqYlSjRqB7sWr2p7SHfMDnV738_MGoZtlsn6D-kVXw5KzqcE32wWKpDx87Hsk5WI05bsqd7-p5tO-7WJVdG3zwPavuMePo6sNDj9mD9-z1nkIq869WP1mx2E7jqiyWgsmYzyS4p)
15. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGjffGKy1et9h_99nCamFfhHy5Ex726a9HFrxaaXU1J8oSQRjeZAFiZgXPUAEtKB-LGTnM-qtsqj9cDIWhaO4tEwl_BF0YplLpNEF6ZLlS2JrfMb_Un4o2PrLJ1DJ-JIMP17ryv2kplDmnjlU--v674n2cLAIxcxXVcZ1QFD1HxFE74nAmdzim_YOmXvQ==)
16. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFXkUjUKJsLcNKYPQf_CVrStgEhQXMsTz3TaouGu0uzeMna7xFXls2yLMyyHk61RAKgAmyyl1eHgCl5JSDD4yKiNs1hvflfKGMK6Nkt04_AEBVwFS_DPhD7Sa6EkXLOexgF5xzd)
17. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHDxx5dQxJX378leNiOeekbHWG3fPF9Elx0Ea409bdRt50QpE3zZbsrrKzTHZ1pAIwamF52ZA1Ed6GisvLTi3XTmmtjYajvVnyILHMU4sQHudEJgvNy)
18. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGIKcEBKo2FkxJ8cezO63mVECwwxW69O1ALtrVG2EPazCJXxIw6uiZKOwtm2FgBY0e8Zd4w2poqyHkU0uGfmGigoPlfxcts5ovD0jDTvvFNwcVEVlr2U9iKIbrhrxHwIRhRXRQh-Q==)
19. [youtube.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFX-H7WyKaRRAB55lGwLUszTBnGj9BpEYL7L3Hp-N_XhMW9KR5MOEBCJLqmbUG-1mDGGQY_5vca3__3oKPz-1BhtoUTkK3Ftp6A6fUyQdbQ_Nt4sRCSzchRYnPEoKU8j-I=)
20. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEX68FR0ecFoB73AWCtFQEScazqOq2AKheFef5NtSerTU0oC1Z8o02uOKSq7hC81aU4KQE2M_AnY3kIt3LQL4P13FVRz8Gqfgpy1bjZdZac3F_S-Hrj7ejqEE7Fwr6anHHs3JqF8A88-tzj0vbwD2d1XUXNzow6W8wArhOD-tTXSKt9TTicsAvwDm2oLVtFWEJ-C6RCAFw=)
21. [zigpoll.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEX1KnBTPNbTfPRSb5-gaxJMDcrc23dXfQX3TkkegsKW39qiFJk4xl0P0YL4_8zJjVmXWgWjAA8kqVaVBfmJOTYsTfb7UsDO88_vMpMQEatYii1xpZwLIeUplaqTmuZc9LIdUyv-FFVoWPwpuwKtJCHwcKbqeH8xNp13vZo2xfEt_Ae3f7jdYhIRiDPXxDWB3SXvoT-gaT1RvA94hJ7rMdf7FurqfGpMxW_9GxhRzbc8GmxynmoPi1n1mESIlngRyb6dXItvw==)
22. [youtube.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGVoCtmKRvKJggvnixEy2UdC1OU9TccUQG3M-D52kuQk9oWerQwFmlIwrVQOTlt5MWUGzeJYEuM1QH0ifFmf4NCnjT-GmrzzediwlCegeIy6WORmcvMyCkQWdf5eoDjKXg=)
23. [scribd.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGuizBKSAcVbFCd9jZU8rv_TCQZQaDh6os72aY7v1qyAwJm1V34X36I-ig0RkkQ1kWbmhQKe_upJlCqlKw9Dot3SDi7krajVzOFEsx6OUYlEn68wfuId6QLVm159NO3vVIPmXQ=)
24. [stackoverflow.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFcy7JHoSPf3Jv1icu8fUQ7_hJZ2fQZYLudu0rsuXy8vAAupK1qXjoY_XW6gs4qUWTT3LJk4hKinbyzOe3datqPWd8APBuhSspy70tM_tS2rMCqlOxYES-Tpb73cPmQAhhI71Bu0IH9qHck_z69iYFbemaHj33_v3BDKoUVo3eiwhMpksOyAmMYVWBhnSCjK__k6c8wJBSrW9csVwo_UZDbqWKko-OLIuDWAA_PjRnGuA==)
25. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHDqiKGupS9lcyaHtLSCybBb9LFeQw74MBzIbpt_fQFfAeC-kNF6yFqycF2azkae3R5rkbi30FssarJi1OAGjp9MljGaZkYmG9__rXN5aYvErWf1PGkHKLytL1FzQx2KtOfC3iijsP0wE-PCNQ68qDjqttkgVEkOkSfMspDOdo1zEDwCEh81wG8jN1fqQmzlPw=)
26. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHdJGAORbYWkj_GSnSoMqn3rDcbHlynZm0-xydgbzTZocU4hcTk2jBstjau0D763INJtikEHppKT3Qcw_mvRFo6Yvr2nCAnjfkRjiFInacUPAJ_RccM9wntNARMC4Z8W3Y=)
27. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFFtxNIUxPIuwR5ceaoZrUP3c82D6YGN27tCKOEq1sGmZh6mz4AjQtvoztjW4mkYEgaJwLwq8SxjVdgOHBEI4uoS-P3Up2mvoxeLbjeWcqc7v3V5hsCaZS4FRRq87FLLaSebmxp4MExZt2CO8x_zxYxenqFCvMcZZaQFfRIEVU5qII=)
28. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFInB9eBjPR-GB9Ps1ZnmI3DIPnW2z4I2c2FrhSJVKT6BP4mdTSRVI3wJoOkhnr9RdvT_YR4ALf5xxXHEHB59cm9-weEea8D2paRRi3FCCI4ZEtRKxvFW6zk2HBh-VSCFpsOA2V71NkLgu3yE-bRiJjRhE0xEF8oiuAH2RCRg7pJwbOm-8OWemzBsTuf6yRxqorQ3fuoMTuEJFwfTIwug==)
29. [studylib.net](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFtWdtvOJEDFESpu3NvFIE9YGgApCYlOum074D7FAH2JlxO9QWsRXcCMLQhGdPTMckL8IUb9S7PmLHFImMLFtM0wNtj3CiNCnjrf6bJKHgs_p-hBNQ_MfhavZ0fglCJD_oPtyidPaW7orZK_Xz_TH9duUQjR5b6xnCT2RLYRQKzdg0=)
30. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGGPw-5g20zJYy3wGolHkZ7541HQvGZfDxt_jATbEIo2yKjBmxjMvr0fkaCC50quNtBSRQYamY29mjqAO7DcD_rL-jLIyQ94Q6WWV1NtOJ2FCug3eBNByxAa9PKI534RbPF5uFC3y74vcYXImaYzrTxNCWkL-hPjz2O_Sj0McReMH_r62w=)
31. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHp7AteyoLs6mFu45tSxv9zUr3PIq7q3dyEqdijLVkS9g186d9tdSH77n7cjUCl4sFc0grdJAIYzwWaCtOC9y-zA8LxVSJXBDs99jBp6_-uPbMT2Svrbri78KfIVerLVpt4PA==)
32. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQG1nGDRGPmx2MyDhzpbdNr2Gt8Ty3XDR1-1MHvVRUcXuFj3SCDqbXj8m7jpAPFlwfkbCWY0XAjaR96-KJ0WyNqNWKnAc_VxH_emkpcxbDYN_OddBF0wn__dzxzZiK2O2k8GPmHZunW3ajrZCad8NdUvWFryFwG0NO0LRZMeZ8InFUquW0vYPIqq39q4E7uPLcSB)
33. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGBNX80xbu3jrX1tsBHqWwe5ZgVMsptpyjosMwxRU4JmjTpOcTKCPsvm_B_idClJ4_qyiq0WgIGzhP_9AFqu6PizW02Ya5OfnudyNx0jxZen9nQre6QO1J4w9d0DiH-wrr5TO_24uI=)
34. [tympanus.net](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFggzXYi0tqbYX4kw0RB3re-VyaUW9v_R2VkF164eK1fvWFPt_yqyjigUrXR2-35HxCN54PWxXWRp7wMyL2jH_HPyJ7r4yt6P4Fq_PMwSL4wKe10NaqzunFWO8eoMzOdVrJdBxp4QPnmyn1XxSxEjoJzM9unYnoQXf9pAb5aFuJd3GIMDNq9FgLtbvtk98cjsvWMZ9UDGRnCm0=)
35. [dev.to](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGQnHzEeSngPEs_cqvUyup1l7L804hWAAWftD-BHjGaYkLAIETpb6f-BxzweteJWWPeFCgCOhskkhdck4JlaVfLCTn3XnGmR-NnUGWQd7WkOP99VxZ7-wOs5FFSqBmeEbdi3ilrMW7eIP0x61yqi7oT4wK86aLBG3RvbE0jsH3RZJM9clMLuJkZ8pM10u-7GRakv7Gx)
36. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGxtsOIZBfUkB0XZoV3BvZ6q-TCSXpOXcnJVkq1G9I2dxVv6caQNJ5E-tkT-_Ea3P-Y2_gklF9B6iteCzEqHp8XFZCrQlF_4WTnOruYN7m7qx-y5EcAI_8eUmCVMx4AiJl0Gi6JOEN8GvWq14OJltu8X8saauB8NBdTqlo4RUy09OiahA4n_ohzIVDLNtcc72JC8Xo7tCZIABI=)
