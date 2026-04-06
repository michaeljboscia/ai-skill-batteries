# Tailwind CSS v4 Fundamentals for AI Coding Agents: A Comprehensive Technical Reference

**Key Points**
*   **CSS-First Configuration**: Tailwind CSS v4 replaces the traditional `tailwind.config.js` with a CSS-native `@theme` directive, leveraging native CSS variables for design token management.
*   **Compiler Engine Shift**: The framework now utilizes an optimized Rust-based engine (Oxide) and Lightning CSS, dramatically reducing build times and eliminating the need for PostCSS and Autoprefixer dependencies.
*   **Dynamic Utilities**: The framework introduces dynamic utility value generation, resolving arbitrary values natively (e.g., `grid-cols-15` or `mt-29`) without requiring explicit arbitrary bracket syntax or configuration extension.
*   **Dark Mode Paradigm**: Dark mode now defaults to the `@media (prefers-color-scheme: dark)` standard. Class-based dark mode requires explicit orchestration via `@variant dark (&:where(.dark, .dark *));`.
*   **Tooling Updates**: Prettier integration via `prettier-plugin-tailwindcss` now necessitates explicitly defining the `tailwindStylesheet` entry point to correctly parse CSS-first theme configurations.

**Overview of the Paradigm Shift**
The release of Tailwind CSS v4 represents a fundamental architectural restructuring. Research suggests that this transition from a JavaScript-configured framework to a CSS-native build tool resolves long-standing friction points surrounding configuration fragmentation, build latency, and compatibility with modern CSS specifications (such as `@property`, `color-mix()`, and native cascade layers) [cite: 1, 2, 3]. For AI coding agents, this necessitates a hard recalibration of heuristic patterns. Models trained predominantly on Tailwind v2 and v3 data often hallucinate legacy JavaScript configuration structures, deprecated utility classes, and suboptimal component extractions. 

**Scope and Application**
This technical reference provides an exhaustive, instruction-dense guide engineered specifically for AI code generation systems. It outlines exact migration strategies, precise syntax rules, decision trees for architectural styling choices, and explicit **Anti-Rationalization Rules** designed to prevent autoregressive models from reverting to deprecated Tailwind v3 logic.

---

## 1. Architectural Paradigm Shift: CSS-First Configuration

### 1.1 The Deprecation of JavaScript Configuration
Historically, Tailwind CSS relied on a Node.js-based configuration paradigm (typically `tailwind.config.js`) to parse user-defined design tokens, plugins, and content paths. Tailwind CSS v4 entirely deprecates this requirement for greenfield projects, moving to a CSS-first configuration model [cite: 2, 4]. The framework acts as its own compiler, processing CSS files directly using the Oxide engine and Lightning CSS [cite: 2, 5].

AI agents must understand that the single source of truth for a Tailwind v4 project is the primary CSS entry file (e.g., `app.css` or `global.css`). 

#### 1.1.1 Legacy Implementation (Tailwind v3)
```javascript
// tailwind.config.js (Deprecated Pattern)
module.exports = {
  content: ["./src/**/*.{html,js,jsx,ts,tsx}"],
  theme: {
    extend: {
      colors: {
        brand: {
          500: '#3B82F6',
          600: '#2563EB'
        }
      },
      spacing: {
        '128': '32rem',
      }
    }
  },
  plugins: [
    require('@tailwindcss/typography')
  ]
}
```

#### 1.1.2 Modern Implementation (Tailwind v4)
In v4, the configuration is defined entirely via CSS custom properties wrapped inside a `@theme` directive. The engine automatically detects template files (eliminating the `content` array), and plugins are loaded via the `@plugin` directive [cite: 1, 2]. The `@tailwind` directives are replaced with a standard CSS `@import` [cite: 2, 6].

```css
/* src/app.css (Modern Pattern) */
@import "tailwindcss";
@plugin "@tailwindcss/typography";

@theme {
  /* Colors are defined natively as CSS variables */
  --color-brand-500: #3B82F6;
  --color-brand-600: #2563EB;
  
  /* Spacing scales are defined natively */
  --spacing-128: 32rem;

  /* Overriding default theme values (e.g., fonts) */
  --font-sans: "Inter", system-ui, sans-serif;
}
```

### 1.2 The `@theme` Directive and Token Mapping
The `@theme` directive maps CSS custom properties directly to Tailwind's internal namespaces. This exposes all design tokens to the CSS cascade, allowing developers to utilize `var(--color-brand-500)` natively in inline styles or external stylesheets without invoking the legacy `theme()` function [cite: 1, 7].

Namespace mappings follow a strict nomenclature:
*   **Colors**: `--color-*` generates `bg-*`, `text-*`, `border-*`, `ring-*`, etc. [cite: 8].
*   **Spacing**: `--spacing-*` generates `p-*`, `m-*`, `w-*`, `h-*`, `gap-*`, etc. [cite: 9].
*   **Typography**: `--font-*` generates `font-*` utility classes. `--text-*` controls font sizes.
*   **Breakpoints**: `--breakpoint-*` generates responsive variants (e.g., `md:`, `lg:`).

#### AI Anti-Rationalization Rule: Configuration Context
**Rule:** NEVER generate a `tailwind.config.js` or `tailwind.config.ts` file when instructed to initialize or configure a Tailwind CSS v4 project. 
**Rationale:** Generating JavaScript configuration files reintroduces unnecessary Node.js dependencies, disables the automated file-watching zero-config mechanics of the Oxide engine, and violates the v4 CSS-native architecture [cite: 2, 10]. All customizations MUST be written as CSS custom properties inside the `@theme` directive within the root stylesheet.

---

## 2. Utility Class Philosophy and Component Architecture

### 2.1 The `@apply` Directive: Deprecation and Alternatives
The `@apply` directive was introduced in early versions of Tailwind to appease developers migrating from traditional BEM-based CSS methodologies, allowing them to compose utility classes within custom CSS selectors. However, the use of `@apply` is widely considered an anti-pattern in modern Tailwind architecture [cite: 11, 12]. 

In Tailwind CSS v4, utilizing `@apply` is heavily restricted, specifically within scoped frameworks like Vue, Svelte, or CSS Modules [cite: 13]. Since the framework processes standard CSS, scoped blocks do not inherently possess access to the global `@theme` context unless explicitly referenced [cite: 14, 15].

#### 2.1.1 The `@reference` Directive
If an AI agent absolutely must utilize `@apply` in a scoped Vue or Svelte component, or a CSS Module, it must import the root stylesheet as a reference using the `@reference` directive. This instructs Tailwind to expose the design tokens and utility definitions without duplicating the CSS output [cite: 13, 15].

```html
<!-- Vue Component / Svelte Component -->
<style lang="postcss">
  /* Requires relative path to the root stylesheet */
  @reference "../../assets/css/app.css";

  .btn-primary {
    @apply rounded-md bg-brand-500 px-4 py-2 text-white hover:bg-brand-600;
  }
</style>
```

However, the preferred paradigm is to eliminate `@apply` entirely and leverage native component composition (e.g., React/Vue components) or native CSS variables [cite: 15].

### 2.2 Decision Tree: Utilities vs Components vs `@apply`

When an AI agent is tasked with styling a repeated element, it must traverse the following decision matrix:

| Scenario | Recommended Approach | Justification |
| :--- | :--- | :--- |
| **Highly dynamic element with specific framework state (React/Vue)** | Extract to a Framework Component (e.g., `<Button variant="primary">`) | Single source of truth is maintained in the markup. Classes remain atomic, maximizing tree-shaking and preventing CSS bloat. |
| **Simple, repeated HTML string without framework logic (e.g., CMS content)** | Use Tailwind Plugins via `@utility` or native CSS variables. | Framework extraction is impossible. Applying native CSS ensures consistency. |
| **Integrating with a 3rd party library requiring specific class names (e.g., Select2)** | Use `@apply` inside `@layer components` or custom CSS. | Third-party libraries enforce their own DOM structure, meaning markup cannot be modified to accept atomic utility classes [cite: 16]. |

#### 2.2.1 Custom Utilities via `@utility`
To define new custom utility classes in v4 without using `@apply`, developers should use the `@utility` directive. This natively registers the utility within Tailwind's internal state, ensuring it correctly interacts with variants like `hover:`, `md:`, or `dark:` [cite: 16].

```css
@import "tailwindcss";

@utility flex-center {
  display: flex;
  align-items: center;
  justify-content: center;
}
```

#### AI Anti-Rationalization Rule: `@apply` Abuse
**Rule:** DO NOT extract utility classes into custom CSS classes using `@apply` simply to "clean up HTML markup." 
**Rationale:** This breaks the fundamental epistemological premise of utility-first CSS. It leads to stylesheet bloat, cache invalidation issues, and naming fatigue. If a block of HTML is overly verbose, abstract the *HTML itself* into a reusable component (e.g., a React component), keeping the utility classes inline [cite: 11, 12].

---

## 3. The Variant System and State Management

Tailwind CSS v4 introduces a more robust variant system, natively supporting pseudo-classes, attribute selectors, and media queries without requiring external plugins. 

### 3.1 Dark Mode Mechanics
In Tailwind v3, dark mode was frequently orchestrated using the `class` strategy, appending a `.dark` class to the HTML root via JavaScript. In Tailwind v4, the default behavior relies strictly on the `@media (prefers-color-scheme: dark)` standard [cite: 10]. 

If an application requires manual dark mode toggling (e.g., a user overriding the system preference), the AI agent must manually construct the dark variant using the `@variant` or `@custom-variant` directive [cite: 10, 17, 18].

#### 3.1.1 Implementing Class-Based Dark Mode
To implement class-based dark mode, append the following directive immediately after `@import "tailwindcss";` in the main stylesheet:

```css
@import "tailwindcss";

/* Orchestrating class-based dark mode */
@variant dark (&:where(.dark, .dark *));

/* Alternatively, for data attributes */
@variant dark (&:where([data-theme="dark"], [data-theme="dark"] *));
```
*Note: This specific syntax ensures that any element possessing the `.dark` class, and all of its nested children, will trigger `dark:*` utility classes [cite: 18, 19].*

#### 3.1.2 Theming with CSS Variables in Dark Mode
A superior architectural pattern for dark mode in v4 involves utilizing the `@theme` directive in combination with standard CSS `@layer theme` pseudo-selectors, entirely bypassing the need to litter the DOM with `dark:bg-slate-900` prefixes.

```css
@import "tailwindcss";

@theme {
  --color-background: var(--bg-color);
  --color-foreground: var(--text-color);
}

@layer theme {
  :root {
    --bg-color: #ffffff;
    --text-color: #000000;
  }
  
  /* Adapts automatically based on the class strategy defined above */
  :root.dark {
    --bg-color: #0f172a;
    --text-color: #ffffff;
  }
}
```
With this configuration, the AI agent only needs to apply `bg-background text-foreground`. The colors will swap dynamically based on the presence of the `.dark` class on the root element [cite: 20, 21].

### 3.2 New Modern Variants
Tailwind v4 incorporates native support for modern CSS states [cite: 1, 3, 22]:
*   **`starting:`** Targets the `@starting-style` rule for entry animations natively in CSS.
*   **`not-*:`** Implements the `:not()` pseudo-class (e.g., `not-hover:opacity-50`).
*   **`inert:`** Targets elements carrying the `inert` HTML attribute.
*   **`descendant:`** A highly powerful, albeit dangerous, variant for styling all nested descendants. (AI Agents should use this sparingly to avoid specificity wars).
*   **`nth-*:`** Native support for `:nth-child()`.

#### AI Anti-Rationalization Rule: Dark Mode Strategy
**Rule:** When implementing dark mode, DO NOT attempt to write `darkMode: 'class'` inside a JavaScript configuration file.
**Rationale:** This configuration parameter has been entirely deprecated. Class-based dark mode is now purely orchestrated within the CSS cascade via `@variant dark (&:where(.dark, .dark *));`. Attempting to pass this to a JS config will result in silent failures and unpurged dark variants [cite: 2, 10].

---

## 4. Arbitrary Values vs. Design Tokens

### 4.1 Dynamic Utilities
One of the most profound innovations in Tailwind v4 is the introduction of **Dynamic Utilities**. In previous versions, if a developer required a value slightly outside the predefined spacing or sizing scale, they were forced to use arbitrary value bracket syntax (e.g., `w-[17rem]`) or extend the `tailwind.config.js` file.

Tailwind v4 leverages native CSS math to resolve spacing dynamically. Spacing classes (`w-*`, `h-*`, `p-*`, `m-*`, etc.) reference a single core spacing variable, usually `var(--spacing)` [cite: 9, 23]. 

This allows an AI agent to write `mt-29` (which equals 29 units of the base spacing scale) natively, without arbitrary brackets. Similarly, grids natively accept any numeric value (e.g., `grid-cols-15`) [cite: 1, 9].

### 4.2 Arbitrary Bracket Syntax `[...]` Limits
Arbitrary values should be strictly reserved for absolute magic numbers that hold no semantic relationship to the design system (e.g., an exact pixel offset for a third-party iframe: `top-[113px]`). 

#### 4.2.1 Strict Syntax Formatting
In Tailwind v3, commas inside arbitrary values were sometimes heuristically converted to spaces for backward compatibility with v2 grids. Tailwind v4 removes this compatibility layer. CSS properties that require spaces must use underscores `_` [cite: 13].

*   **Incorrect (v3 hangover):** `grid-cols-[1fr,500px,2fr]`
*   **Correct (v4 standard):** `grid-cols-[1fr_500px_2fr]`

#### 4.2.2 Using Theme Variables inside Arbitrary Values
In v3, developers used the `theme()` function inside brackets (e.g., `w-[theme(spacing.128)]`). In v4, because all tokens are native CSS variables, this is replaced entirely by the `var()` function [cite: 10].

*   **Correct:** `h-[calc(100vh-var(--spacing-16))]`

### 4.3 Decision Tree: Value Assignment

| Value Requirement | Recommended Syntax | Example |
| :--- | :--- | :--- |
| **On-Scale Numeric Value** (e.g., 17 units of padding) | Dynamic Utility (No brackets) | `p-17`, `w-120` |
| **Grid Column/Row count** | Dynamic Utility (No brackets) | `grid-cols-15` |
| **One-off specific hex color** | Arbitrary Bracket | `bg-[#ff0033]` |
| **Frequently reused specific hex color** | `@theme` Extension | Add `--color-brand: #ff0033;` in CSS. Use `bg-brand`. |
| **Complex CSS function** (e.g., calc) | Arbitrary Bracket with `var()` | `w-[calc(100%-var(--spacing-4))]` |

#### AI Anti-Rationalization Rule: Arbitrary Abstraction
**Rule:** DO NOT overuse arbitrary values like `w-[32px]` or `text-[16px]` when semantic scale equivalents exist (`w-8`, `text-base`).
**Rationale:** Excessive use of arbitrary pixel values destroys the cohesiveness of the design system. AI agents are prone to reading pixel values from Figma/design files and injecting them directly as brackets. In v4, the agent must map pixel requirements to the dynamic `--spacing` scale (where 1 unit = 0.25rem = 4px). 32px equals 8 units.

---

## 5. Class Ordering, Code Formatting, and Tooling

### 5.1 `prettier-plugin-tailwindcss`
Consistent class ordering is vital for team collaboration, avoiding Git merge conflicts, and maintaining predictable CSS cascade behavior (where utilities are prioritized correctly). The official `prettier-plugin-tailwindcss` automatically organizes classes according to Tailwind's internal dependency graphs: base layers first, components second, utilities third, and high-specificity variants last [cite: 24, 25].

### 5.2 Configuring Prettier for Tailwind v4
Because Tailwind v4 derives its configuration from the CSS entry point (via `@theme` directives) rather than a JavaScript file, the Prettier plugin must be explicitly instructed on where to locate this stylesheet. If it is not configured, Prettier will fail to recognize custom dynamic utilities, custom colors, and custom variants [cite: 26, 27].

To configure the plugin, the AI agent must update the `.prettierrc` (or equivalent configuration file) with the `tailwindStylesheet` property pointing to the CSS file containing the `@import "tailwindcss";` directive.

#### 5.2.1 Configuration Example
```json
// .prettierrc
{
  "plugins": ["prettier-plugin-tailwindcss"],
  "tailwindStylesheet": "./src/app.css"
}
```

If the project uses JavaScript-based configuration for Prettier (e.g., `prettier.config.js`), it is configured similarly:
```javascript
// prettier.config.js
export default {
  plugins: ["prettier-plugin-tailwindcss"],
  tailwindStylesheet: "./src/styles/global.css",
};
```

#### AI Anti-Rationalization Rule: Prettier Configuration
**Rule:** When setting up a v4 project with Prettier, DO NOT rely on the `tailwindConfig: "./tailwind.config.js"` parameter. 
**Rationale:** The Prettier plugin for v4 relies on the CSS Abstract Syntax Tree (AST) to discern custom values. Pointing it to a non-existent or ignored JavaScript config will break formatting. The agent must strictly use `tailwindStylesheet` [cite: 26].

---

## 6. Legacy Migration and Renamed Utilities Reference

For AI agents refactoring a Tailwind v3 project to v4, several fundamental utility classes have been canonically renamed to align more strictly with CSS standards. 

### 6.1 Critical Renamed Utilities Matrix
When refactoring legacy code, the agent must execute the following syntax swaps [cite: 6, 13, 28]:

| Tailwind v3 Utility | Tailwind v4 Utility | Rationale for Change |
| :--- | :--- | :--- |
| `outline-none` | `outline-hidden` | In v3, `outline-none` created a transparent 2px outline for accessibility. `outline-hidden` maintains this behavior. v4 adds a true `outline-none` which maps to `outline-style: none` [cite: 6, 28]. |
| `bg-gradient-to-[dir]` | `bg-linear-to-[dir]` | Aligns with the CSS standard `linear-gradient()`. Also introduces `bg-radial` and `bg-conic` [cite: 9, 10]. |
| `flex-shrink-*` | `shrink-*` | Streamlined syntax for flexbox logic [cite: 10]. |
| `flex-grow-*` | `grow-*` | Streamlined syntax [cite: 29]. |
| `shadow-sm` | `shadow-xs` | Shadow scale was recalibrated for finer granularity [cite: 6, 30]. |
| `shadow` | `shadow-sm` | Default shadow mapped to `sm` to accommodate new base shadow [cite: 6, 30]. |
| `drop-shadow-sm` | `drop-shadow-xs` | Matches the `box-shadow` scale calibration [cite: 13]. |
| `blur-sm` | `blur-xs` | Recalibrated for finer granularity [cite: 13, 30]. |
| `ring` | `ring-3` | The default `ring` size in v3 was 3px. In v4, `ring` defaults to 1px. To achieve the old default look, use `ring-3` [cite: 6, 13]. |

### 6.2 Structural Migration Checklists
To successfully execute a v3 to v4 migration, the AI agent must orchestrate the following workflow [cite: 2, 30]:

1.  **Dependency Upgrade**: Replace `tailwindcss` (v3) with `tailwindcss@latest` and the appropriate bundler plugin (e.g., `@tailwindcss/vite` or `@tailwindcss/postcss`) [cite: 2].
2.  **Strip Legacy Processors**: Remove `autoprefixer`. Tailwind v4 Lightning CSS engine natively handles vendor prefixing [cite: 30].
3.  **Refactor CSS Directives**: Replace `@tailwind base; @tailwind components; @tailwind utilities;` with the singular `@import "tailwindcss";` [cite: 2, 4].
4.  **Transpile JS Config to CSS**: Migrate the contents of `theme.extend` inside `tailwind.config.js` to CSS custom properties inside `@theme` in the main stylesheet [cite: 2, 10].
5.  **Refactor Utilities**: Scan and replace renamed utilities (e.g., `outline-none` to `outline-hidden`) [cite: 6].

### AI Anti-Rationalization Rule: Default Borders and Rings
**Rule:** Do not assume `border` or `ring` inherits the `gray-200` or `blue-500` color respectively. 
**Rationale:** In Tailwind v3, adding the `border` class defaulted to `border-gray-200`. In v4, Tailwind is strictly unopinionated—the default border color has been changed to `currentColor` to match native browser rendering [cite: 13]. If an explicit color is required, the AI must append it (e.g., `border border-gray-200`). Similarly, `ring` defaults to `currentColor` rather than the old `blue-500` [cite: 13].

**Sources:**
1. [tailwindcss.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGQNc795MMewM0MhqBwMbQgcjSEXVg4gLxfGr2q5Z4I-xnPwH1I2PmFv5t9nBP7C9CPzmSlF65fkNKs_eO2AUIqHfdud4UeRSBhyLcZQnDGsWrXnv31fCiC9pojpwUVSuP0)
2. [dev.to](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHtGdw2--te2rUHLR9QOCXEjcdsnmdPgZTPmHcmMsEqvQooFADXuQDkzTz6IG842OCLquUy0mKHWiM2M96kc_UbGUwj3Diu91Getbg-N21jzN5_g-NlPVc0fE6Qj8dO7KQUPou__GTDl7nyaxVdm2K2d62eNsnyq4mnMVvpFfdytjlgR6IHmqHIDhyhyzp3GuGlBn3eyehYe3EzqlH13pn1IyjcM1U=)
3. [youtube.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFE75bYDDtFCcPjc5p3Ts9GvuYnelMS2X7BhtQwLAE0l6vCTfw9oF7de_AmvYbqVCutU7-7Bt3RLNyeula9CJYtfD5td0zlxSaI4q57-IBnPZ9AckuKhhewDz9qspFfXS8p)
4. [logrocket.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHtqJhoCZzjQ_WZHHAYwWp4LpR4mxWvA8ibDU5smQIIU2YxeYeWWW-6z7QDcTInI5RJtudLXQq0XVT3f0AGz_a8Nu75PCL8H_nWStuJG7VFDAcBfq-oSlttfuNn9FAqZDE92iCT)
5. [typescript.tv](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQG6p2pAdh2EWDC1LUgELejoiGw8Vy8SsY7LO4pHbRdsrporf6r8DguNrie3-svcvk81xL9gOT7nbASeLL1sbvKUbjgqsN0VdClc5VFVJFa1LVq2V8MLh5g3d_o8_s7XhYbs7YzWjlXTW-4DHwxe7E3w4DSyqCtleXcgK1ugrfJpt1j2Rzg=)
6. [zippystarter.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGK22h4lgmyP4VLNFum4IL7ct29kd9CP2LQ6rUXECwj6dw3Bo0S9j_s9adWyWfduC8LkDS-9sq4NKLtonrWmVqQEy15O4bQWVKQJMMFwMcxpzTS7vMhIC5SO_D_CXVcidzoiO0DarahPvAVtDFj1UFL3a2rDUuZNQaTQHDYWdF2ZMNdV43Ldwc=)
7. [mintlify.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGgCF8J7fJvPoXEdfvScszzjHdEdPzMsq5jd4TbYXkNc9CTBsEoK4Et9qccgPK4cVKpa6mp6alwOmyJ0PUyM_WzUBO9ByHLhtYv1tUhmjYWYXfRRv-6p-xd0jY4PZIAclmddtdHUFeVx8aj-Zf8_rgqw3uURdQ-Sg==)
8. [bryananthonio.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEuVdbqfwfi8HlAdmKv1m8VK9hD3ND5NPHwEOoBqH5sv5xwEt2v01MH2g9TuWMud8wDaOUXAJJWeM8aZmbNP9p0t9uKM8OZL9IBJc7ILDOuwNd3whWkXM8cznUK6pDKDMS2pt8yKauqBuhTkxR_xvo6aw==)
9. [plainenglish.io](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQF4tj0MlUrdkCA7czpq0h1g6aZc0G8p08JibnQrRQuTEuj96-kHNMRakD3ccuX2337Q33-lyr-WDU9hOZ3NOQd8_7sq0lBJ9uM4IMEBhWHv3tiYoV5ZoOMpwdEc4kSTXur9Ll7mWRNpEHHcjOIdRsPW_NvH-7tyC29d338vEtMYIcBXPzlFR1TePaHTY6cQwooY_WBUqkWyF1790lMUljSh2A7xiEyv1C3hSIj45w==)
10. [digitalapplied.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE71xpgCgCLGYHa7248tQ6kH3uDzqnYMPwLGixknjN4hZ2F6SsqoT8G0ffVodQFNA6hWBzsceuxVfVdb2lfoR5eVCIJjXsfLT7faLNc4JHgVBZBdJdOfsOOVnmw4zKPAcuU-5kVXOnaYYFHfW39wsOqJ7trGLP0_075FET5_7SM7okt045Zjg==)
11. [kolja-nolte.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQG_2rmmb5mDKwHyEmGOwNZphof3pHihCdPbzsW49-Y8HxE7HMyz30Pg3U5lmR-qRXhHWhj_lr3FR_SJ3shNMHbTtJpa3rJ-a6y9kP9tsPLCzXrztH8VqzlShcqbFAW2CTB23LutTGoqldhLq5u7Od0DJ9x56Je-eoqKaJN3qY8a2kVn1Q==)
12. [stackoverflow.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQG1llSKkulDsqq2lvug2jZzXHIuWCv_vRICtwp9qm1RlmfG_b3HVy4VsWjeA1IFuCj7_Jxy6P-5NvtL3b03K4mrpySjNU5s9FrU1W-XJH8T9Q9bzFQJVbilUEUPZX8gPG8hDSSXcMkkiFmCe1aogOSWvC9nT1E8F3CQXIfmmoV_Of9l)
13. [tailwindcss.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHpn_28ff98ipdJMn7GBdNZ2yIH__mSSIDKiGeHVjSmyvqtLbZMxQtXBG2MlQrjI6-rUA0G4X3csKtnuWn8TNEfL9bigTrYuymDZy5C_tPFxhtBoIe92KmN_D9JgDSWXjI=)
14. [okaryo.studio](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGEcdKhmiAR-4AgeDHu_XMnzUpCyu2KUwmbwjv6IPvDyH0wzkoyLSKnF0-S4LLCU1HDSDc09l3TAaxfxVFvaEVEy7YY4BOA2t6ccGNk5NI241S-s2GxFAr4Dzxrmqjye31sYPrOwLcjU1-URAscEJLUlDg-Ow4KNwAOczizyA==)
15. [tailwindcss.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFNk-LjmH35y0eHEcNAFcNueDrcHIiNvlTKlvr6eiFqRZk4Dichf-6700fEpDA2nUoLcMP27aGi3fH5-3PA63HhdRbUPNeWaful9MDQOswp5h4jiCxcP-fC-XFJILYna0c=)
16. [tailwindcss.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFh5t0wxoVIAIIcU8hur5TE7x7-9thwhBMDiQe27Db_xVP-6Le4oQLx6glMYB28ypD9zsADMn6fO1LmSRtV-dXJ1DtrwH84HIy1Kfj6gEVBLOBACE-jsvlTlGq_LaxhqlabEkMdiILNDXDKXw==)
17. [dev.to](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEO_2GlOQmo43OMX1heK2chRQl5nvmD8DtMdsPtoY-wTil3aV1cSwk0kJLjivCZzIpfE-5dDn22P6M5XMhzFrBsCSLAMxQfIHkt8TjZKuYZimQhu_R6K0LxwDITFC_Ppu4D4KyUBx_PDYUIvnVfZg==)
18. [tailadmin.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE9go1hFB-ei-ZErGD2IzLWFnB62_chG1Fe_ZulSL6SOIQFVeEFaoaccOGer81wfmofZsO-sgONjebAKDa5Ix7SX525sTxJffgcNoyGFRn2iNqs_--ZpJhU0hJFNC7Iw5t4DstklwxFoEw=)
19. [github.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE4zwWi04C34zZEvHqhLntJSf1wOgzJqjJXgdIcreZAPIxKlqzN2zqItwXvENUS6__0q3T2DihzRMHXBbck95KOU806eJW4qT_3ljwnvKUUDsG6Qjq4IntrQf_5JUz7xGxnvtnpGT0LrUeEDYYP42p0nwcH)
20. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE_88vQGPQXXVLY78vjE4P49SGLu-SqKCaW97Anixh3g_sAYTPwFgvcadHSYfLVuKoUp5cvifOAMJMlWMpsPNwpF6JcThFzwEOMHObdv5W5Pwvaw5lczy9cFPVLPU1kMSJdynbc-lwNyYH1IJbbLHNpMEAI4JXmRHi90cedWbgxnmSzoyFe5h_L3tBw3CcAOpHznz6bDOQ5fODc4LnAOWnIWCZu)
21. [reddit.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFuSjPpaZCB-fWGySrijx1w55n3g9XOzoerf_c9d-4cXEs6PBbaPRoopQBjD-mRUZybL3751ZrEJrhJ9SHgDrNASd1Bmw3-kvvmjZBQZHp8HoSnEc_UPctCt7ABSafC2Ur48twwl4JzdAnUtbTtGIIpFvgaZhREnke9hQv3oMbSo8SUEFZPcKvVeeaCIMmGlMpSRDM22ucbSkDK-N0=)
22. [stackademic.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQH0cvXCs87jcdzWtQbuHCN3XItnrhg_qZ1dgibkJlt50g2Az0mhC7_Q1WlT9NPl7lOYq_oCFYBLpUroqByJD7hYPnb2n0XByLnDukclEDvRuYKy-G5MhTWn0a5Uqqs26ubOdl35Dynfk1vZYlCMyq_-IgXW-IjafVEnF50dqVr0Fp267G30l10mLq0A7IJxPuQ6BmmXQsYOR5pna5x6o4wa-gJW5g==)
23. [eagerworks.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQF8rQNn1FqH-Xxy1yP1hUIIMHKYGjMJpPLnPujULtfLOgvQ7kdzS4NQ0tyuqFnqnhOS-UDIlAs0xhUdcJSpw8BXbtT9RazNAmdQFMIi5rtEMNxzOVsK_diw3C9fgwA5GXLr)
24. [medium.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE8ABbi-ReuG1yX3oYCrNepZ0Jp17DT8HVMHrspFg2Sv181JEAZqsyAK0N57dXYKCGX3YNPL-a5qschUlKunN5tT5oqf5vhPzjgA6gCylRE7qCh4VFCffPxl-WgcKhgwBglvzSbbp84Wq0Mb3zlX2djL-eZmsLe6QKlk2pvAhuvxTVOkDTOYr5p64wetlamLV6p--xDry9NInutvJo-kb2CUzRo)
25. [yarnpkg.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQF_iGFNb_v1slb1ZU1A5li4yxTr6Zsa2ObjWsFRCDVhMidzjp95aLHg24n64nys-zBlgUfyoxo2QYqIL7vhJIfw56lpSDjk7D0rThKKKtLl2Yc0jlaSrvClzWgG24FHd1hdVWeG7elAJmxyXo2Qv-Gomruhs3gOE3aTtZXIHqoArGS9cgeSTEg=)
26. [github.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHtcPrIJjCOrAwOsRMo9r2da8seJJH1boKSQdzuyiHuYRrj6gIo-zNUFOof6L_Y_z-JfHQFACT4t3xwJ5jZbr-ONSzvc3wTWRS2aZlAcRGYMaZ_Q3lf40Q4SKwMrfD8W-OmOgtQ57g5jbPgAjRwGSJhfQ==)
27. [github.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFsTysjv2ncrkh3hRgpSOJDXlJKhSZWR_fJ3JUJuAbfN8YxteEWFujC8p4fVuIe7mvP89IxonslRMwro1s6Ae7J8ck_teqmLaWGQw6BTTK6l__qPphSRCZU-4jCSag2fsHudmCVk03tgogZv__dvoh7CRoz)
28. [github.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHFl58g9zU9Yh71OChnpAeJlgKrOtI0xPDFYbqpjqxLov0fUaSNPEdDlxSRuihGTcV_fz8XaK72Zlu-EWdhxWkeUNn9C6b_XJIrTq4XmwfImaapqs00BV6OQh4NzfNRSrN3uofvh3Zs3F_-ngGcTA==)
29. [saasrock.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHH0-jflZDaCKxvHOdlseO_ZnYHm9vCM8l-rpbmEFTCduMaNf-fcrymWl8bd6su7v7oKIkoUzUwsDRQqJ3_7aQn7RJaqqv_LBGPCmhKSrAo6EqhvJsDkJsNDSE_uF-c_uX0oeDShKA2Uo9S68qwLY6Lz8rR7XL3EZc1BfoVq-XP3og6Ce-nC0IqI0T3r29uwD4HyDsYpls4CDOmDoY=)
30. [mintlify.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFz_a8ZLbwXwkpLUQ5bk4WdBs3Nw-zasQXTe6Rdb6cDzR38clPODK6hVQkwrkmgIKQU8uPeHqpq__MJrOrrEQsfrpSjneJ685UgDAPyBzPXB1JwT5dGXE9deNAB0TfEkn-UKUm-Gyyvduy6I2VddTazUnCwdleb)
