---
name: mx-tw-observability
description: "Tailwind CSS observability, any Tailwind CSS work, visual regression testing, Storybook integration, Chromatic snapshots, accessibility audit, axe-core, eslint-plugin-tailwindcss, design consistency, dark mode testing, prettier-plugin-tailwindcss, WCAG compliance"
---

# Tailwind CSS Observability — Design Consistency and QA for AI Coding Agents

**This skill co-loads with mx-tw-core for ANY Tailwind CSS work.** Ships without visual testing = ships blind. Design consistency requires tooling, not hope.

## When to also load
- `mx-tw-core` — v4 configuration, Prettier setup
- `mx-tw-design-system` — Dark mode testing, token auditing
- `mx-tw-components` — Storybook stories for all variant combinations
- `mx-tw-animation` — Motion accessibility verification

---

## Level 1: Linting and Class Ordering (Beginner)

### Pattern 1: prettier-plugin-tailwindcss

Auto-sorts utility classes in the canonical Tailwind order. Prevents merge conflicts, improves readability.

```json
// .prettierrc
{
  "plugins": ["prettier-plugin-tailwindcss"],
  "tailwindStylesheet": "./src/app.css",
  "tailwindFunctions": ["clsx", "cva", "cn", "twMerge"]
}
```

`tailwindFunctions` ensures classes inside `cn()`, `cva()`, etc. are also sorted.

### Pattern 2: eslint-plugin-tailwindcss

```bash
npm install -D eslint eslint-plugin-tailwindcss
```

```js
// eslint.config.js (flat config)
import tailwind from "eslint-plugin-tailwindcss";

export default [
  ...tailwind.configs["flat/recommended"],
  {
    settings: {
      tailwindcss: {
        callees: ["cn", "cva", "clsx"],
        config: "tailwind.config.ts",  // or CSS file for v4
      }
    },
    rules: {
      "tailwindcss/no-arbitrary-value": "error",     // Ban [#hex] and [17px]
      "tailwindcss/no-custom-classname": "error",    // Ban unrecognized classes
      "tailwindcss/enforces-shorthand": "warn",      // my-4 not mt-4 mb-4
      "tailwindcss/classnames-order": "off",         // Handled by Prettier
    }
  }
];
```

| Rule | What it catches |
|------|----------------|
| `no-arbitrary-value` | `bg-[#ff0033]`, `p-[17px]` — forces design tokens |
| `no-custom-classname` | Typos and non-existent classes |
| `enforces-shorthand` | `mt-4 mb-4` → `my-4`, `w-full h-full` → `size-full` |

---

## Level 2: Storybook and Accessibility Testing (Intermediate)

### Pattern 1: Storybook + Tailwind Integration

```ts
// .storybook/preview.ts
import '../src/styles/app.css';  // Import your Tailwind styles
import type { Preview } from '@storybook/react';

const preview: Preview = {
  parameters: {
    controls: { matchers: { color: /(background|color)$/i } },
  },
};
export default preview;
```

### Pattern 2: Stories for Every Variant

```tsx
// Button.stories.tsx
import type { Meta, StoryObj } from '@storybook/react';
import { Button } from './Button';

const meta: Meta<typeof Button> = {
  title: 'Components/Button',
  component: Button,
  tags: ['autodocs'],
  argTypes: {
    intent: { control: 'select', options: ['primary', 'secondary', 'destructive', 'ghost'] },
    size: { control: 'select', options: ['sm', 'md', 'lg'] },
    disabled: { control: 'boolean' },
  },
};
export default meta;

export const Primary: StoryObj = { args: { intent: 'primary', children: 'Submit' } };
export const Secondary: StoryObj = { args: { intent: 'secondary', children: 'Cancel' } };
export const Destructive: StoryObj = { args: { intent: 'destructive', children: 'Delete' } };
export const Disabled: StoryObj = { args: { disabled: true, children: 'Processing...' } };
export const Small: StoryObj = { args: { size: 'sm', children: 'Small' } };
export const Large: StoryObj = { args: { size: 'lg', children: 'Large' } };
```

### Pattern 3: Accessibility Addon (axe-core)

```bash
npx storybook add @storybook/addon-a11y
```

Automatically audits every story for WCAG violations:
- Color contrast (4.5:1 for normal text, 3:1 for large text)
- Missing ARIA attributes
- Form labels
- Focus management

Catches ~57% of accessibility issues automatically. The remaining 43% requires manual testing.

### Pattern 4: Dark Mode in Storybook

```bash
npm install -D @storybook/addon-themes
```

```ts
// .storybook/preview.ts
import { withThemeByClassName } from '@storybook/addon-themes';

export const decorators = [
  withThemeByClassName({
    themes: { light: 'light', dark: 'dark' },
    defaultTheme: 'light',
    parentSelector: 'html',
  }),
];
```

Every component now has a theme toggle in Storybook's toolbar. Both modes visible, both testable.

---

## Level 3: Visual Regression and CI Pipeline (Advanced)

### Pattern 1: Chromatic Visual Regression Testing

Chromatic captures pixel-perfect snapshots of every Storybook story. On every PR, it diffs against the baseline and flags visual changes.

```bash
npm install -D chromatic
```

### Pattern 2: Multi-Mode Snapshots

```ts
// .storybook/modes.ts
export const allModes = {
  'light mobile': { viewport: 'small', theme: 'light' },
  'light desktop': { viewport: 'large', theme: 'light' },
  'dark mobile': { viewport: 'small', theme: 'dark' },
  'dark desktop': { viewport: 'large', theme: 'dark' },
};

// .storybook/preview.ts
import { allModes } from './modes';
const preview = {
  parameters: {
    chromatic: {
      modes: {
        'light mobile': allModes['light mobile'],
        'dark desktop': allModes['dark desktop'],
      },
    },
  },
};
```

Every component snapshotted in light mobile + dark desktop. Dark mode can't break silently.

### Pattern 3: GitHub Actions CI Pipeline

```yaml
# .github/workflows/ui-qa.yml
name: UI Quality Assurance
on:
  push: { branches: [main] }
  pull_request: { branches: [main] }

jobs:
  lint-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: actions/setup-node@v4
        with: { node-version: '20' }
      - run: npm ci

      # Enforce class ordering + design token usage
      - run: npm run lint

      # Visual regression
      - uses: chromaui/action@latest
        with:
          projectToken: ${{ secrets.CHROMATIC_PROJECT_TOKEN }}
          buildScriptName: build-storybook
          autoAcceptChanges: ${{ github.ref == 'refs/heads/main' }}
          exitZeroOnChanges: false  # Block PR if visual changes unapproved
```

### Pattern 4: Automated Accessibility in CI

```ts
// .storybook/test-runner.ts
import type { TestRunnerConfig } from '@storybook/test-runner';
import { injectAxe, checkA11y } from 'axe-playwright';

const config: TestRunnerConfig = {
  async preVisit(page) { await injectAxe(page); },
  async postVisit(page) {
    await checkA11y(page, '#storybook-root', {
      detailedReport: true,
      detailedReportOptions: { html: true },
    });
  },
};
export default config;
```

```bash
# Run in CI: fails if any component violates WCAG
npx test-storybook
```

---

## Performance: Make It Fast

### Perf 1: Lint Catches Issues Before Build
ESLint `no-arbitrary-value` prevents ad-hoc values that bloat CSS. Catching them at lint time is cheaper than finding them in production bundle analysis.

### Perf 2: Chromatic Runs Fast with Turbosnap
Chromatic's Turbosnap only re-snapshots stories affected by changed files. On large projects, this cuts snapshot count by 80%+.

### Perf 3: Prettier Prevents Class Order Drift
Without automated ordering, developers argue about class order in PRs. Prettier ends the discussion — deterministic ordering, zero bike-shedding.

---

## Manual Accessibility Audit Checklist

Automated tools catch 57%. This checklist covers the rest.

### Keyboard Navigation
- [ ] Every interactive element reachable via Tab
- [ ] Focus ring visible on all focused elements
- [ ] Tab order matches visual layout (left→right, top→bottom)
- [ ] Escape closes modals/dropdowns
- [ ] No keyboard traps (can always Tab out)

### Screen Reader
- [ ] Buttons/links announce their action (not "Button" or SVG path)
- [ ] Icon-only buttons have `aria-label` or `.sr-only` text
- [ ] State changes announced (`aria-expanded`, `aria-checked`)
- [ ] Form errors use `aria-live` for dynamic announcements

### Color and Contrast
- [ ] Normal text: 4.5:1 contrast ratio (WCAG AA)
- [ ] Large text: 3:1 contrast ratio
- [ ] Both light AND dark mode pass contrast checks
- [ ] Information conveyed by more than color alone (icon + color for errors)
- [ ] Disabled states visible but distinct (>3:1 ratio)

### Zoom and Scaling
- [ ] Page works at 200% browser zoom
- [ ] No horizontal scrolling at standard widths
- [ ] Text doesn't overflow containers at large zoom levels

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Ship AI-Generated UI Without Visual Testing
**You will be tempted to:** Trust that AI-generated Tailwind classes render correctly.
**Why that fails:** AI hallucinate classes, miss dark mode, break spacing. Chromatic catches what eyes miss.
**The right way:** Every PR with visual changes requires approved Chromatic snapshots.

### Rule 2: Never Ship Inconsistent Spacing/Colors
**You will be tempted to:** "It looks close enough" with slightly different padding or a hardcoded hex.
**Why that fails:** Inconsistency compounds. 20 components with slightly different spacing = a site that looks amateur.
**The right way:** ESLint `no-arbitrary-value` enforces design tokens. `no-custom-classname` catches typos.

### Rule 3: Never Skip Accessibility Checks
**You will be tempted to:** "We'll add accessibility later."
**Why that fails:** Accessibility debt is exponentially harder to fix retroactively. Legal liability exists today.
**The right way:** axe-core addon runs on every Storybook story. `test-storybook` in CI blocks non-compliant PRs.

### Rule 4: Never Assume Dark Mode Works
**You will be tempted to:** Develop in light mode only. "Dark mode just inherits the tokens."
**Why that fails:** It doesn't. Brand colors vibrate on black. Gray text disappears. Shadows become invisible.
**The right way:** Every component snapshotted in both themes via Chromatic modes. Manual contrast check in both.

### Rule 5: Never Let Class Ordering Be a Team Decision
**You will be tempted to:** Establish a "team convention" for class order.
**Why that fails:** Conventions are forgotten, violated, and debated in code review. Wasted time.
**The right way:** `prettier-plugin-tailwindcss` — automated, deterministic, enforced on save.
