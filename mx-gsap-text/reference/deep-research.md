# GSAP SplitText Animation Patterns: A Comprehensive Guide

**Key Points:**
*   **API Evolution:** Research indicates that the GSAP SplitText plugin underwent a significant architectural rewrite in version 3.13.0, reducing file size while introducing critical features such as native masking, automated accessibility handles, and responsive re-splitting [cite: 1, 2].
*   **Accessibility:** It is highly recommended to utilize the built-in `aria` property, which automatically applies `aria-label` to parent elements and `aria-hidden` to split child elements, mitigating severe screen-reader degradation caused by DOM fragmentation [cite: 1, 3].
*   **Responsiveness:** The evidence suggests that utilizing the `autoSplit: true` property in conjunction with the `onSplit()` callback is the most effective pattern for managing layout reflows triggered by viewport resizing or asynchronous font loading [cite: 1, 2].
*   **Integration:** Complex animation sequences appear most stable when SplitText arrays (characters, words, lines) are seamlessly integrated into GSAP Timelines and triggered via ScrollTrigger, explicitly utilizing batching for performance optimization [cite: 4, 5].

**Understanding Text Splitting Mechanics**
Text splitting involves the programmatic extraction of contiguous text strings into isolated Document Object Model (DOM) nodes—typically `<span>` or `<div>` elements. This granular tokenization allows animation engines to manipulate CSS properties on a per-character, per-word, or per-line basis. The complexity arises from preserving typographic integrity, preventing layout collapse, and managing dynamic reflows.

**The Role of Advanced Masking**
Masking in text animations traditionally required manual DOM wrappers. Modern implementations automate this by wrapping tokenized elements in clipping containers (`overflow: clip`). This enables sophisticated reveal effects without bleeding outside the established bounding box of the typographic element.

**State Management and Reversion**
A critical aspect of text animation is state management. Because splitting text fundamentally alters the HTML structure, failing to revert these changes during component unmounting or spatial reconfiguration leads to memory leaks and visual corruption. Robust implementations always provide mechanisms to restore the original `innerHTML`.

---

## 1. Technical Reference: The `SplitText.create()` API

The `SplitText` plugin is an advanced GSAP utility designed to dissect HTML text nodes into individual, animatable DOM elements. By isolating characters, words, and lines, developers can sequence intricate staggered animations. The foundation of this functionality is the `SplitText.create()` method (or its equivalent constructor `new SplitText()`), which accepts a target selector and a comprehensive configuration object [cite: 1, 6].

### Core Splitting Mechanisms and Type Options

The `type` configuration property dictates the granularity of the text tokenization. By default, SplitText assumes `type: "lines, words, chars"`, but for optimal rendering performance, developers should restrict the engine to parse only the required elements [cite: 1].

*   **Characters (`chars`):** Isolates every single letter, number, and punctuation mark. Essential for high-energy, typewriter, or "Matrix-style" decryption reveals.
*   **Words (`words`):** Isolates contiguous blocks of characters separated by spaces. This is the optimal configuration for editorial pacing and readability [cite: 7].
*   **Lines (`lines`):** Isolates text based on the visual line breaks dictated by the browser's rendering engine and the container's width. This requires precise calculation of the typographic bounding box.
*   **Combinations:** Strings can be passed to combine types, such as `type: "lines, chars"`, which creates line wrappers that contain individually wrapped characters.

### Masking for Reveal Effects (`mask: true`)

The `mask` property is a powerful parameter introduced to facilitate hidden-to-visible transition effects, such as text sliding upward from an invisible baseline [cite: 1]. When `mask` is set to `"lines"`, `"words"`, or `"chars"`, the SplitText engine wraps each corresponding generated element within an additional `<div>` container styled natively with `overflow: clip` [cite: 8, 9]. 

Using `overflow: clip` is significantly more performant than `overflow: hidden` as it avoids establishing a completely new block formatting context while preventing the animated child from rendering outside the wrapper's boundaries [cite: 8, 9]. The newly created mask wrappers can be accessed via the `.masks` array property on the returned SplitText instance [cite: 8].

### Accessibility Handling (`aria` property)

Fragmenting a single heading into 50 individual `<span>` tags severely disrupts assistive technologies like screen readers, which will attempt to read each token as an isolated semantic block. The SplitText API addresses this via the `aria` property [cite: 1].

When enabled (which is the default in modern versions like v3.13.0+), `aria: "auto"` performs two critical operations:
1.  It extracts the original `textContent` of the target element and applies it as an `aria-label` to the main parent container [cite: 1].
2.  It applies `aria-hidden="true"` to all freshly generated line, word, and character elements, effectively hiding the fragmented DOM soup from the accessibility tree while preserving the visual output [cite: 1].

### API Configuration Reference Table

The following table details the primary configuration parameters accepted by `SplitText.create()` [cite: 1]:

| Property | Type | Description |
| :--- | :--- | :--- |
| `type` | String | Defines tokenization level: `"chars"`, `"words"`, `"lines"`, or combinations like `"words, chars"`. |
| `mask` | Boolean/String | Set to `"lines"`, `"words"`, or `"chars"` to wrap elements in an `overflow: clip` container for reveal effects [cite: 8]. |
| `linesClass` | String | Appends a specific CSS class to all generated line elements. Supports auto-incrementing (e.g., `"line++"` becomes `line1`, `line2`) [cite: 1]. |
| `wordsClass` | String | Appends a CSS class to all word elements [cite: 10]. |
| `charsClass` | String | Appends a CSS class to all character elements [cite: 10]. |
| `aria` | String/Boolean | Manages accessibility. `"auto"` sets `aria-label` on parent and `aria-hidden` on children [cite: 1]. |
| `autoSplit` | Boolean | If `true`, enables internal `ResizeObserver` to automatically re-split text on container dimension changes or font loading [cite: 2]. |
| `onSplit` | Function | Callback executed immediately after text is split or re-split. Crucial for timeline reconstruction [cite: 1]. |

### Comprehensive API Usage Example

```javascript
// Register the plugin with the GSAP core
gsap.registerPlugin(SplitText);

// Create a highly configured SplitText instance
const splitInstance = SplitText.create(".hero-heading", {
  type: "lines, words, chars", // Split everything for maximum control
  mask: "lines",               // Wrap lines in overflow:clip for reveals
  linesClass: "line-wrapper",  // Custom class for styling
  wordsClass: "word-element++",// Auto-incrementing word classes (word-element1, etc.)
  charsClass: "char-element",  // Custom class for characters
  aria: "auto"                 // Ensure screen readers read the full string
});

// Accessing the generated arrays
console.log(splitInstance.lines); // Array of line wrapper DOM nodes
console.log(splitInstance.words); // Array of word DOM nodes
console.log(splitInstance.chars); // Array of character DOM nodes
console.log(splitInstance.masks); // Array of the overflow: clip mask elements
```

---

## 2. Animation Recipe Catalog

With the text successfully parsed into arrays of DOM nodes, GSAP can target these arrays to create staggered, sequenced motion. The following recipes demonstrate standard, highly effective typographic animation patterns.

### Recipe 1: Character-by-Character Reveals

This recipe produces a high-energy, fluid typing or fading effect where each letter materializes sequentially. It is particularly effective for short, impactful headings.

```javascript
const charSplit = SplitText.create(".title-chars", { type: "chars" });

gsap.from(charSplit.chars, {
  duration: 0.8,
  opacity: 0,
  y: 50,
  rotationX: -90,          // Adds a 3D flipping effect
  transformOrigin: "0% 50% -50", 
  ease: "back.out(1.7)",   // Gives a slight overshoot/bounce
  stagger: 0.02            // 20ms delay between each character's start time
});
```

### Recipe 2: Word Stagger with Configuration Objects

Splitting by word is often favored for paragraph text or longer subheadings, as character splitting on dense text can overwhelm the user's cognitive processing and cause rendering lag [cite: 7]. Utilizing GSAP's advanced `stagger` configuration object allows for multidirectional, mathematically spaced reveals.

```javascript
const wordSplit = SplitText.create(".paragraph-words", { type: "words" });

gsap.from(wordSplit.words, {
  duration: 1,
  opacity: 0,
  filter: "blur(10px)", // Requires careful use due to potential browser performance hits
  scale: 0.8,
  ease: "power3.out",
  stagger: {
    amount: 1.5,        // The total time distributed across all elements
    from: "center",     // Animation starts from the middle words and ripples outward
    ease: "power1.inOut"// Controls the timing of the stagger deployment itself
  }
});
```

### Recipe 3: Line-by-Line Reveals with Masking

A standard in modern web editorial design is the masked line reveal. Text appears to slide up out of an invisible floor. This effect relies explicitly on the `mask: "lines"` configuration [cite: 8, 10].

```javascript
// The mask parameter creates an overflow:clip wrapper around each line
const lineSplit = SplitText.create(".editorial-heading", { 
  type: "lines",
  mask: "lines" 
});

// We animate the inner line elements (split.lines), not the masks (split.masks)
// The masks stay stationary, hiding the inner lines until they move up into view
gsap.from(lineSplit.lines, {
  duration: 1.2,
  yPercent: 100, // Move the line 100% down, completely outside its mask
  opacity: 0,    // Optional: add opacity for a softer entry
  ease: "expo.out",
  stagger: 0.1
});
```

### Recipe 4: Nested Splits (Lines, then Characters Within)

For highly complex sequences, developers often need to reveal lines sequentially, but animate the characters *within* those lines in a staggered fashion. This requires splitting into lines and characters simultaneously.

```javascript
const nestedSplit = SplitText.create(".nested-text", { 
  type: "lines, chars",
  linesClass: "split-line" 
});

// Create a master timeline to coordinate the sequence
const masterTl = gsap.timeline();

// Iterate through each generated line
nestedSplit.lines.forEach((lineElement, index) => {
  // Query the characters exclusively within this specific line
  const lineChars = lineElement.querySelectorAll('.char-element'); // Assuming default or mapped classes
  
  // Alternatively, if you didn't set a charsClass, you can just query children
  const charsInLine = lineElement.children;

  masterTl.from(charsInLine, {
    duration: 0.6,
    opacity: 0,
    x: 20,
    ease: "power2.out",
    stagger: 0.02
  }, index * 0.1); // Delay each line's start time relative to its index
});
```

---

## 3. Responsive Handling and Automatic Re-splitting

One of the most complex challenges in DOM-based text animation is reflow. When an element is split into `lines`, the specific characters and words inside each line wrapper are hardcoded. If the viewport is resized, or if a custom web font finishes loading asynchronously, the natural text wrap points will change [cite: 1, 2]. Without intervention, the text will break erratically, resulting in "funky line breaks" and overlapping elements [cite: 2].

### The `autoSplit: true` Mechanism

To solve this, GSAP version 3.13.0 introduced `autoSplit: true` [cite: 1, 2]. Under the hood, this utilizes a `ResizeObserver` connected to the target element, alongside a `loadingdone` event listener on `document.fonts` [cite: 2]. When a reflow trigger is detected, the engine:
1.  Automatically reverts the text to its original innerHTML.
2.  Recalculates the typography.
3.  Re-applies the SplitText tokenization.

To maximize performance, the resizing events are internally debounced (typically waiting for a 200ms pause in window resizing) [cite: 2].

### The Mandatory `onSplit()` Callback Pattern

Using `autoSplit: true` introduces a programmatic paradox: if the engine destroys and recreates the `split.lines` array on resize, any GSAP animations previously bound to the *old* array nodes will break or manipulate detached DOM elements [cite: 1, 11]. 

Therefore, **it is mandatory** to construct your animations inside the `onSplit()` callback whenever `autoSplit: true` is utilized [cite: 1, 10]. 

Furthermore, if you **return the GSAP animation (Tween or Timeline)** from the `onSplit` function, SplitText's internal engine will automatically capture its `.totalTime()`, invoke `.revert()` to clean up the old animation, and synchronize the timing on the newly generated animation elements seamlessly [cite: 1, 11].

### Code Example: Robust Responsive Pattern

```javascript
gsap.registerPlugin(SplitText);

let splitAnimationInstance;

SplitText.create(".responsive-text", {
  type: "lines, words",
  autoSplit: true, // Automatically reverts and recalculates on resize/font load
  onSplit: (self) => {
    // 'self' is the current SplitText instance containing the freshly minted DOM nodes
    
    // Create the animation targeting the NEW arrays
    const splitTween = gsap.from(self.words, {
      duration: 0.8,
      y: 30,
      opacity: 0,
      rotationZ: 5,
      stagger: 0.05,
      ease: "power2.out"
    });

    // IMPORTANT: Return the animation!
    // This allows GSAP to track the animation state, destroy it during a resize,
    // and seamlessly restart/resume it on the newly split text.
    return splitTween;
  }
});
```

---

## 4. ScrollTrigger + SplitText Combinations

Modern web experiences heavily rely on triggering typography animations as the element enters the viewport. Integrating SplitText with GSAP's `ScrollTrigger` requires careful scoping, especially when handling responsive re-splitting.

### Scroll-Triggered Text Reveals

When combining ScrollTrigger with SplitText, the trigger is typically the parent container, and the targets are the split nodes.

```javascript
SplitText.create(".scroll-reveal-text", {
  type: "lines",
  mask: "lines",
  autoSplit: true,
  onSplit: (self) => {
    // Return the timeline to ensure resize cleanup
    return gsap.timeline({
      scrollTrigger: {
        trigger: ".scroll-reveal-text", // The parent container
        start: "top 80%",               // Starts when top of text hits 80% of viewport
        end: "bottom 20%",
        toggleActions: "play none none reverse" // Play on enter, reverse on leave
      }
    })
    .from(self.lines, {
      yPercent: 100,
      opacity: 0,
      duration: 1,
      stagger: 0.1,
      ease: "power4.out"
    });
  }
});
```

### Scrub-Based Text Animations

For interactive storytelling, tying the text reveal directly to the scrollbar position (`scrub: true`) creates a highly engaging effect.

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
        scrub: 0.5 // Smooth scrubbing with 0.5s catch-up lag
      }
    })
    .from(self.chars, {
      opacity: 0.1, // Fade from barely visible
      scale: 0.5,
      stagger: 0.1,
      color: "#ff0000" // Transition color during scroll
    });
  }
});
```

### Batching Text Elements

When animating multiple identical elements across a page (e.g., all `<h2>` tags), instantiating individual ScrollTriggers can cause performance issues and synchronized overlapping if multiple headers enter the viewport simultaneously. `ScrollTrigger.batch()` solves this by grouping targets that cross the trigger threshold within the same interval [cite: 4, 5].

```javascript
// Step 1: Query all target elements
const headings = gsap.utils.toArray(".batch-heading");

// Step 2: Split each element and hide them initially
const splits = headings.map(heading => {
  const split = SplitText.create(heading, { type: "lines, words", mask: "lines" });
  gsap.set(split.words, { opacity: 0, yPercent: 100 }); // Pre-hide
  return split;
});

// Step 3: Batch process the animations
ScrollTrigger.batch(headings, {
  interval: 0.1, // Time interval to group elements
  batchMax: 3,   // Max elements to animate in a single batch
  onEnter: (batchElements) => {
    // batchElements is an array of the .batch-heading DOM nodes that entered.
    // We must find their corresponding SplitText arrays to animate.
    
    batchElements.forEach(el => {
      // Logic to retrieve the specific split array for this element
      // (Usually mapped via a data attribute or WeakMap in complex architectures)
      const specificSplit = splits.find(s => s.elements === el);
      
      gsap.to(specificSplit.words, {
        opacity: 1,
        yPercent: 0,
        duration: 0.8,
        stagger: 0.05,
        ease: "power3.out"
      });
    });
  },
  start: "top 85%"
});
```

---

## 5. Cleanup and Revert Strategies

Memory leaks and visual tearing are the most common bugs in Single Page Applications (SPAs) utilizing SplitText. If a React component unmounts, but the SplitText instance is not destroyed, the DOM retains the fragmented spans, and lingering ScrollTriggers will throw null reference errors when they attempt to query the detached DOM.

### Manual Reversion: `splitInstance.revert()`

Every SplitText instance exposes a `.revert()` method [cite: 6]. Calling this method instantaneously strips all generated `<span>` and `<div>` tags, restoring the target element's `innerHTML` to its exact pre-split state, and clears internal memory caches.

```javascript
const mySplit = SplitText.create("#target", { type: "chars" });

// Later in the lifecycle, or prior to a routing transition:
mySplit.revert();
```

### React Cleanup with `useGSAP`

In React, the standard `useEffect` hook requires manual teardown. However, GSAP provides the `@gsap/react` package with the `useGSAP` hook, which establishes a `gsap.context()` that automatically reverts all Tweens, Timelines, ScrollTriggers, and SplitText instances created within its scope when the component unmounts.

```jsx
import { useRef } from "react";
import gsap from "gsap";
import { SplitText } from "gsap/SplitText";
import { useGSAP } from "@gsap/react";

gsap.registerPlugin(SplitText);

export default function AnimatedHeading() {
  const containerRef = useRef(null);

  useGSAP(() => {
    // Everything created here is automatically context-aware.
    // No manual revert() needed on unmount!
    const split = SplitText.create(".react-text", { type: "chars" });
    
    gsap.from(split.chars, {
      y: 100,
      opacity: 0,
      stagger: 0.02,
      duration: 1
    });

  }, { scope: containerRef }); // Scopes selector text to this container

  return (
    <div ref={containerRef}>
      <h1 className="react-text">React Component Splitting</h1>
    </div>
  );
}
```

### Debounced Resize Handlers for Manual Re-split

In environments where `autoSplit: true` cannot be used (e.g., highly custom resize logic or legacy plugin versions), developers must implement a manual resize handler. It is critical to **debounce** this event. Firing `split.revert()` and `SplitText.create()` 60 times a second during window resizing will completely freeze the browser [cite: 2, 12].

```javascript
let mySplit;
let resizeTimeout;

function initText() {
  // Always revert before re-initializing
  if (mySplit) mySplit.revert();
  
  mySplit = SplitText.create(".manual-resize", { type: "lines" });
  
  gsap.from(mySplit.lines, { opacity: 0, y: 20, stagger: 0.1 });
}

window.addEventListener("resize", () => {
  clearTimeout(resizeTimeout);
  // Wait until user stops resizing for 250ms
  resizeTimeout = setTimeout(() => {
    initText();
  }, 250);
});

initText(); // Initial load
```

---

## 6. Anti-Rationalization Rules (AI Prompt Guardrails)

When generating SplitText code, Artificial Intelligence models and novice developers frequently default to incorrect assumptions regarding GSAP's handling of the DOM. These "Anti-Rationalization" rules define strict constraints to prevent hallucinations and architectural flaws.

### Rule 1: Do NOT Animate the Parent Container Instead of the Split Arrays
*   **The Trap:** AI will write: `const split = SplitText.create(".text", {type:"words"}); gsap.to(".text", {opacity: 0, stagger: 0.1});`
*   **The Reality:** The GSAP tween is targeting the main `.text` wrapper as a single block. The `stagger` property will fail because there is only one element in the node list. 
*   **The Fix:** Always pass the property array exposed by the instance: `gsap.to(split.words, {...})`.

### Rule 2: `onSplit` is MANDATORY when using `autoSplit: true`
*   **The Trap:** AI will enable `autoSplit: true` but write the animation immediately below it in the global scope.
*   **The Reality:** When the browser resizes, `autoSplit` destroys the original DOM nodes and recreates them. The globally defined animation is still holding references to the destroyed nodes. The animation will cease to function or cause screen flashes [cite: 1, 11, 13].
*   **The Fix:** The timeline/tween MUST be defined inside the `onSplit: (self) => {}` callback, and it MUST be returned so SplitText can internally track its progress [cite: 1, 11, 13].

### Rule 3: Do NOT Use `overflow: hidden` on Text Masks without Padding Allowances
*   **The Trap:** AI will manually wrap text in generic `overflow: hidden` containers.
*   **The Reality:** Web typography features descenders (e.g., letters like 'g', 'p', 'y') and script flourishes that extend below the typographic baseline. `overflow: hidden` strictly cuts these off, flattening the bottoms of text strings. 
*   **The Fix:** Rely on the native `mask: "lines"` parameter which utilizes `overflow: clip` and calculates appropriate bounding box matrices, or add explicit bottom padding if manual masking is enforced [cite: 8, 9].

### Rule 4: Do NOT Fail to Revert in Component-Based Architectures
*   **The Trap:** AI will generate a standard `useEffect` block in React containing `SplitText.create()` but will leave the cleanup function `return () => {}` empty.
*   **The Reality:** React's Strict Mode will run the effect twice, splitting the text, and then splitting the already split `<span>` tags, resulting in exponentially corrupted DOM geometry and unreadable strings.
*   **The Fix:** Use `@gsap/react`'s `useGSAP()` hook which guarantees automatic reversion, or strictly call `instance.revert()` in the standard `useEffect` unmount return.

### Rule 5: Acknowledge that Fonts Destroy Calculations
*   **The Trap:** AI will initialize SplitText in the standard global script execution phase.
*   **The Reality:** If SplitText calculates line breaks before a web font (e.g., a Google Font) finishes rendering, it uses the fallback font's metrics. When the real font applies, words will jump out of their generated line wrappers [cite: 14].
*   **The Fix:** Either use `autoSplit: true` (which listens to `document.fonts.ready` [cite: 2]), or wrap the initial instantiation in `document.fonts.ready.then(() => { ... })` [cite: 11].

**Sources:**
1. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFJxoKifLd9jzL1TT4CciY5X1Kznb23RwB67dGGFbM7K2oQZ0vvq4C7zP5HySyaFwg0KqaECQj3laWz6bCy9u3SL9_jgICVs68rRBTd1Pt-k0TNEO9Eb1c8OUFvHuaYCqs0)
2. [webflow.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGMwgLXQF7sCLJBcOGplGM46aAEtnE3CLIu_DannsLvIvZzbxj3sfjICQ-kaoMMfodUnhDMI9CW0KhLlYCT-jufY87wWuuien1lUQ6r7fyj8rU5ISkClBxwyw6eIQubGI_rSGuWBg==)
3. [mintlify.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHUcQwsuCS1pppO2lwA69As08hLqLE568mnFVraf5qSR-8s9XUpQcEPb-Z-pBgF8V4EX8gUA5AFbGYSbuh73O39M_IPTpAWTAXBsNhfXzjon21bMlrACWwmhMadDN-7jvdaBOKQ8QHyX2bW3XUxzQkm)
4. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEb4tW62pXcaw9UWGQD8K2j_57vQVcyOZewdUTAKtXwqIJBpP-K6IU7vdggZQPD142SZjlZghAUBhKV7P0T_ZucIgaPk7BC4riAWihwjkPUPM2GZmsnqr58wp9GZVcBQQsIj9IXdk7UqCYwSrk0EAewAC6l3A==)
5. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQH_WEYlUUKy5u58plFVcLNlizMn1RtEASvztHr4NyGzMDTSwq1qi4St4P7TTSbl5ztuY449tVLyMNMCNDAM2Vm9FheIDtIPtN2LFz4VAQsz2lDC8LaDDGObehfDGyizQaw4Dls2vdY9cmMgrdZpeyqStOXubkwVq4dSLM2bVh0PMPpvY5ZDJ0aGjrhrrf-6veyYvDhzWXc=)
6. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFOqdP0EbmQUiWdDh45hpLFEac08owrZcotEHlknscvESLtqnmGWxjgTl-MopW6tE7dI2EKw0G5vW69pcezgHP1tIjoP-wqLY_t7Sk8cJOlw3JIO2uv9j0tvDEhEe7XJ-UukFKRG01KdHk=)
7. [yar.website](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHb1bBs2Ob6Dyc6M6TRmp5_7aXsLW_etz6wfEtKx91uhEbeyZ5t1nTLbjjcEgNfqT1a4x_TsW1eoZW1CRhQkBZ-FjQCp9AZg1RfMgN2iPnjmHWcMnK03O-PDEJdaR2CFvsnV91zg0zqsTfAuziU29eLyeEONLrBFmnMozKAVeDDk3RnmtlGkdV4JWliTTakqrCUk5vAVrVU9gUK_YDjCc_Aghu7v5S6g5Mg9UuOaeUseA==)
8. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEm8FmO0ZKrvjz161wJmbQcYd7tNrYpKOIUZwA5zwSmZ5mNKprW1K9cPZgLy1aV7DuLyLykwFCH_Fn0XIgxGHCzVq9zMr3ACCRb994QggWTficN2EyVuplHpkcGWBj-qclRD1Xqjzpb)
9. [html-plus.in.ua](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHDwnkEHrA-8puQIMPPXUPYYRf0XA3aypT717craZ2wN_Xi0W6gVuZFwEWozNm_oVSAwjT_MhYuHXeM8c9ZVU54Lfu-TyDGi9x_TEhPVmLIkIjzvwqLcCgBg1Tnd6QtOFHHCWy0)
10. [tympanus.net](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE8pYjwjVJ2G_-CugJG9doHnXTtDFhRhakSKI_aCSMw6Xl-RXys9RrgU4wBbeOVf0UsEVhtJ8H9VpmlWSiL22biUgqH2k7JEaaE1LKB0gmIUr-Kogqa_Mg9VZsZOSOARZ9pcOnyeDCeAP18TWfB2CZUq1D1Y2XPHrLTl9pmbYiJowpyxa3_Tgu8G1Qy6yX_O1P4TjRYgYVlxi2scGFCwPPgxhI=)
11. [clcreative.co](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQG7m6yx70qctWMB0CSibZqNxdw6m2Op-nuBrH-BuCE8S9DySHdPAqDdot-RaTq5N7J7zFPAl2sTW8jNJpbUSaYdcGHRF2TvMGYD9eJ4YBnGiNZjeJ5cwDFvcbbGP3e7zlF2rZJgapr6-MTJolgNnJ5is2-uOw7uFAYGM7DB)
12. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHhx_L79potmOs8j2rGZgjLNTR0R5xED8IhE6GT5l047JRu1GN5HWba6mPz5-I-mVJl-8e1bjOXT23otlU5LIoHkA-1OjvJjwjW8_cguOqKFFu5sBUNZ_Pa8En9NEqGZaRj5LMi29wvHyIIjZ_hvDNUNu273FiejFhyKUMk0xIi9DJWJDTKVg==)
13. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFgbG2sx_4yP-l-RVxAwHaMElvLiWS-MBpzSCRes4QZqh4Yp0jRLi3Q21P_sLycl3JVjJqAUQqZ_vL2Ac8kVLslH7fi_qxvmZJ1fmKuzSiZzCj52cizKKIKMj-jR7pVdZt640NqIzZR26rb4-tKai40alKdiVuI7b1YBx1pKNwh7L4MnsiwTL7MM5pfTOrp5CnN7iN7L8MJ0oKgXZPUOVAyI1yBxSVKLLrv)
14. [gsap.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQG-bsWjex0GRLlbyk7sTA_HjwFeMGBJ9lxaS85k9MDWPwUasfcNigTwwlcWMwwZ9CmM5p15f8PhMDyDNr-h0qx42TeVS095sekpcif1cKmPrGnmibhAf7NiWA-u_tQsTMrntMm3ub-jWMWZ6hcjp-k4-_MaRSCofPpLNUb1iGQmP3K7Ph-FY_3yvu1xUW0qBlsfwXAcCDPQhEBVNAiNnSSknWmQys0boyDdLyffzeIbDEULb0yyMOnv_F-qadkQG0ui)
