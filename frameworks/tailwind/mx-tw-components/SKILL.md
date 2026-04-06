---
name: mx-tw-components
description: "Tailwind CSS component patterns, class-variance-authority CVA, cn utility, clsx, tailwind-merge, shadcn/ui, Radix UI, compound variants, component extraction, variant management, data attributes, copy-to-own"
---

# Tailwind CSS Components — CVA, cn(), and shadcn/ui for AI Coding Agents

**Load this skill when building reusable components with Tailwind, managing variant styles, or integrating shadcn/ui and Radix UI.**

## When to also load
- `mx-tw-core` — v4 configuration, utility classes
- `mx-tw-design-system` — Semantic tokens consumed by variants
- `mx-tw-animation` — Transition classes on interactive components
- `mx-react-core` — React composition patterns (compound components)

---

## Level 1: The cn() Utility and Component Basics (Beginner)

### Pattern 1: Why cn() Exists

Tailwind applies styles based on stylesheet order, not class attribute order. `bg-red-500 bg-blue-500` doesn't guarantee blue wins — the last rule in the CSS file wins.

```tsx
// lib/utils.ts — THE standard implementation
import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

**How it works**:
1. `clsx()` — handles conditional classes, filters out falsy values
2. `twMerge()` — detects Tailwind conflicts, keeps the LAST class for each property

```tsx
cn("px-4 py-2", "p-8")           // → "p-8" (p-8 overrides px-4 py-2)
cn("bg-red-500", "bg-blue-500")  // → "bg-blue-500" (last wins)
cn("text-sm", { "text-lg": true }) // → "text-lg" (conditional evaluated, last wins)
cn("rounded-lg", undefined, false) // → "rounded-lg" (falsy values stripped)
```

### Pattern 2: Component with className Override

Every component should accept `className` and merge it with cn():

```tsx
interface CardProps extends React.HTMLAttributes<HTMLDivElement> {
  children: React.ReactNode;
}

function Card({ className, children, ...props }: CardProps) {
  return (
    <div
      className={cn(
        "rounded-xl border bg-surface p-6 shadow-sm",  // defaults
        className  // consumer overrides — always wins
      )}
      {...props}
    >
      {children}
    </div>
  );
}

// Consumer can safely override any property:
<Card className="p-8 shadow-lg">Custom padding and shadow</Card>
```

### Pattern 3: When to Extract a Component

| Situation | Action |
|-----------|--------|
| Same 15+ utility classes used in 2+ places | Extract to a component |
| Complex element with HTML structure + ARIA + state | Extract to a component |
| One-off complex layout | Keep inline — avoid premature abstraction |
| Repeated styling on DIFFERENT HTML elements | Consider `@utility` in CSS |

**The @apply question**: Don't use `@apply` to "clean up HTML." If you're extracting, extract the HTML into a component, not the classes into CSS.

---

## Level 2: CVA — Class Variance Authority (Intermediate)

### Pattern 1: Base + Variants + Defaults

```tsx
import { cva, type VariantProps } from "class-variance-authority";

const buttonVariants = cva(
  // Base: always applied
  "inline-flex items-center justify-center font-medium rounded-lg transition-colors duration-200 focus-visible:ring-2 focus-visible:ring-offset-2",
  {
    variants: {
      intent: {
        primary: "bg-primary text-white hover:bg-primary-hover focus-visible:ring-primary",
        secondary: "bg-surface border border-border text-text hover:bg-surface-muted",
        destructive: "bg-destructive text-white hover:bg-destructive/90 focus-visible:ring-destructive",
        ghost: "hover:bg-surface-muted text-text",
      },
      size: {
        sm: "text-sm px-3 py-1.5",
        md: "text-base px-4 py-2",
        lg: "text-lg px-6 py-3",
      },
    },
    defaultVariants: {
      intent: "primary",
      size: "md",
    },
  }
);
```

### Pattern 2: Compound Variants

Compound variants apply styles when MULTIPLE conditions are true:

```tsx
const buttonVariants = cva("...", {
  variants: { intent: { ... }, size: { ... }, disabled: { true: "opacity-50 cursor-not-allowed" } },
  compoundVariants: [
    {
      intent: "primary",
      disabled: true,
      class: "bg-primary/50 hover:bg-primary/50",  // Override hover for disabled primary
    },
    {
      intent: ["secondary", "ghost"],  // Array: applies to multiple intents
      size: "lg",
      class: "uppercase tracking-wide",
    },
  ],
  defaultVariants: { intent: "primary", size: "md" },
});
```

### Pattern 3: TypeScript Integration with VariantProps

```tsx
import { type VariantProps } from "class-variance-authority";

type ButtonVariants = VariantProps<typeof buttonVariants>;

interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    ButtonVariants {}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, intent, size, disabled, ...props }, ref) => (
    <button
      ref={ref}
      className={cn(buttonVariants({ intent, size, disabled }), className)}
      disabled={disabled}
      {...props}
    />
  )
);
Button.displayName = "Button";
```

`VariantProps` extracts exact types from CVA config — consumers get autocomplete and compile-time validation for `intent`, `size`, etc.

---

## Level 3: shadcn/ui and Radix UI Integration (Advanced)

### Pattern 1: shadcn/ui Philosophy — Copy-to-Own

shadcn/ui is NOT an npm package. Components are copied into your project as source code.

```bash
# Adds Button component source to components/ui/button.tsx
npx shadcn@latest add button
```

**Key principles**:
- You OWN the code. Modify freely.
- Built on Radix UI primitives (accessibility handled)
- Uses CVA for variants + cn() for class merging
- Theming via CSS variables (not JS theme objects)
- No `shadcn-ui` in package.json = no breaking updates

### Pattern 2: Radix UI — Headless Accessibility Primitives

Radix provides behavior + accessibility. You provide styling.

```tsx
import * as Dialog from "@radix-ui/react-dialog";

// Radix handles: focus trapping, Escape key, ARIA attributes, scroll lock
// You handle: how it LOOKS

<Dialog.Root>
  <Dialog.Trigger className="bg-primary text-white px-4 py-2 rounded-lg">
    Open Modal
  </Dialog.Trigger>
  <Dialog.Portal>
    <Dialog.Overlay className="fixed inset-0 bg-black/50 data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0" />
    <Dialog.Content className="fixed left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 bg-surface p-6 rounded-xl shadow-lg w-full max-w-md">
      <Dialog.Title className="text-lg font-semibold">Modal Title</Dialog.Title>
      <Dialog.Description className="text-text-muted mt-2">Description text.</Dialog.Description>
      <Dialog.Close className="absolute top-4 right-4">✕</Dialog.Close>
    </Dialog.Content>
  </Dialog.Portal>
</Dialog.Root>
```

**Key**: Radix exposes `data-[state=open]` and `data-[state=closed]` attributes — Tailwind can style these without React state management.

### Pattern 3: Product-Level Wrappers Over Base Components

```tsx
// components/ui/button.tsx — shadcn base (you own this)
// components/app/submit-button.tsx — your product wrapper

import { Button } from "@/components/ui/button";
import { Loader2 } from "lucide-react";

export function SubmitButton({ loading, children, ...props }) {
  return (
    <Button disabled={loading} {...props}>
      {loading && <Loader2 className="mr-2 size-4 animate-spin" />}
      {children}
    </Button>
  );
}
```

Don't scatter shadcn base components everywhere. Build product-specific wrappers.

---

## Performance: Make It Fast

### Perf 1: CVA Pre-computes Class Strings
CVA resolves variant combinations at call time, not render time. No runtime overhead from conditional string building.

### Perf 2: tailwind-merge Has a Cost
`twMerge` parses every class string. For hot render paths, cache the cn() result or move it outside the render function when the inputs don't change.

### Perf 3: Component Extraction Reduces Duplicate DOM
Extracting a `<Card>` component means one source of truth for 15 utility classes instead of copy-pasting them across 20 files.

---

## Observability: Know It's Working

### Obs 1: Document Components in Storybook
Every variant combination should have a Story. Primary/sm, Primary/md, Primary/lg, Secondary/sm, Destructive/disabled — all visible in one place.

### Obs 2: TypeScript Catches Invalid Variants
If a consumer passes `intent="warning"` but only `primary|secondary|destructive` exist, TypeScript errors at compile time. This IS your observability for design system compliance.

### Obs 3: Visual Regression Catches Unintended Overrides
A className override via cn() can accidentally change a component's look. Chromatic snapshots catch these before they ship.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Copy 20 Utility Classes Instead of Extracting
**You will be tempted to:** Duplicate `px-4 py-2 bg-blue-500 text-white rounded-lg shadow hover:bg-blue-600 transition` across 5 files.
**Why that fails:** Change the border-radius once? Edit 5 files. Miss one? Inconsistency.
**The right way:** Extract to a component. The utilities stay inline, but the HTML structure is shared.

### Rule 2: Never Use Ternary Chains for Multi-Variant Components
**You will be tempted to:** `className={size === 'sm' ? 'text-sm px-2' : size === 'md' ? 'text-base px-4' : 'text-lg px-6'}`
**Why that fails:** Add a fourth size or an `intent` dimension and this becomes unreadable. No compound variant support.
**The right way:** CVA with typed variants. Clean, declarative, type-safe.

### Rule 3: Never Over-Engineer Variants
**You will be tempted to:** Create variant props for `hasPadding`, `customMargin`, `borderStyle`.
**Why that fails:** Re-inventing CSS through React props. Bloats the API. Defeats utility-first.
**The right way:** Restrict CVA variants to semantic intents (`size`, `intent`, `state`). Use `className` prop for one-off spatial adjustments.

### Rule 4: Never Skip cn() for className Overrides
**You will be tempted to:** `className={`${baseClasses} ${props.className}`}` with template literals.
**Why that fails:** Tailwind specificity conflicts. `p-4` from base and `p-8` from consumer both stay — unpredictable result.
**The right way:** `className={cn(baseClasses, props.className)}` — twMerge resolves conflicts, consumer wins.

### Rule 5: Never Directly Modify shadcn Base Components
**You will be tempted to:** Edit `components/ui/button.tsx` to add your app-specific loading state.
**Why that fails:** When you pull in a new shadcn component, the patterns won't match. Base should stay generic.
**The right way:** Create product wrappers (`components/app/submit-button.tsx`) that compose the base component.
