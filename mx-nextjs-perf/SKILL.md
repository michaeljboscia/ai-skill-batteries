---
name: mx-nextjs-perf
description: "Next.js performance optimization, any Next.js work, next/image optimization, next/font self-hosting, next/script loading, next/dynamic lazy loading, Partial Prerendering PPR, bundle analysis, Turbopack, tree shaking, code splitting, Core Web Vitals LCP CLS FID INP, route segment config, streaming SSR, image optimization WebP AVIF"
---

# Next.js Performance — Optimization Patterns for AI Coding Agents

**This skill co-loads with mx-nextjs-core for ANY Next.js work.** Every component, every page, every route should follow perf-aware patterns by default.

## When to also load
- `mx-nextjs-core` — File conventions, streaming via loading.tsx
- `mx-nextjs-rsc` — Bundle size optimization via Server Components
- `mx-nextjs-data` — Caching, parallel fetching, waterfall prevention
- `mx-nextjs-deploy` — Runtime selection affects performance characteristics

---

## Level 1: Image, Font, and Script Optimization (Beginner)

### Pattern 1: Always Use next/image

```tsx
// ❌ BAD — Raw <img> tag: no optimization, CLS, no lazy loading
<img src="/hero.jpg" alt="Hero" />

// ✅ GOOD — next/image: auto WebP/AVIF, resizing, lazy loading, CLS prevention
import Image from 'next/image';

// Static import (auto width/height detection, blur placeholder)
import heroImage from '@/public/hero.jpg';
<Image src={heroImage} alt="Hero" placeholder="blur" priority />

// Remote image (must set width + height or use fill)
<Image
  src="https://cdn.example.com/photo.jpg"
  alt="Product photo"
  width={800}
  height={600}
  sizes="(max-width: 768px) 100vw, (max-width: 1200px) 50vw, 33vw"
/>
```

| Prop | When to use | Notes |
|------|------------|-------|
| `priority` | LCP hero image ONLY | Preloads. One per page max. |
| `placeholder="blur"` | Above-fold images | Auto for static imports. Improves perceived perf. |
| `sizes` | Responsive images | Specify actual viewport percentages, NOT `"100vw"` everywhere |
| `fill` | Unknown dimensions | Parent needs `position: relative` + defined size/aspect-ratio |
| `quality` | Hero (85-90), thumbnails (70) | Default 75. Higher = bigger file. |

**Remote images require `remotePatterns` in next.config.ts:**

```ts
// next.config.ts
const config = {
  images: {
    remotePatterns: [
      { protocol: 'https', hostname: 'cdn.example.com' },
    ],
  },
};
```

### Pattern 2: Always Use next/font

```tsx
// ❌ BAD — Google Fonts via <link> tag: third-party request, CLS, FOUT
<link href="https://fonts.googleapis.com/css2?family=Inter" rel="stylesheet" />

// ✅ GOOD — Self-hosted, zero CLS, zero external requests
import { Inter } from 'next/font/google';

const inter = Inter({
  subsets: ['latin'],
  display: 'swap',        // Show fallback immediately, swap when loaded
  variable: '--font-inter', // CSS variable for Tailwind integration
});

// app/layout.tsx
export default function RootLayout({ children }) {
  return (
    <html lang="en" className={inter.variable}>
      <body>{children}</body>
    </html>
  );
}
```

**How zero-CLS works**: next/font calculates `size-adjust`, `ascent-override`, `descent-override` for the fallback font so it matches the custom font's dimensions exactly. No layout shift on swap.

**For local fonts:**
```tsx
import localFont from 'next/font/local';
const customFont = localFont({ src: './fonts/CustomFont.woff2', display: 'swap' });
```

### Pattern 3: Optimize Third-Party Scripts

```tsx
import Script from 'next/script';

// Analytics — load after page is interactive
<Script src="https://analytics.example.com/script.js" strategy="afterInteractive" />

// Non-critical widget — load when browser is idle
<Script src="https://widget.example.com/embed.js" strategy="lazyOnload" />

// Critical inline script — load before hydration
<Script id="config" strategy="beforeInteractive">
  {`window.CONFIG = { apiUrl: '...' }`}
</Script>
```

| Strategy | When | Use for |
|----------|------|---------|
| `beforeInteractive` | Before hydration | Critical config, polyfills |
| `afterInteractive` | After hydration (default) | Analytics, tag managers |
| `lazyOnload` | Browser idle | Chat widgets, social embeds |
| `worker` | Web Worker (experimental) | Heavy third-party scripts |

---

## Level 2: Code Splitting and Bundle Optimization (Intermediate)

### Pattern 1: next/dynamic for Lazy Loading

```tsx
import dynamic from 'next/dynamic';

// Lazy-load heavy component (only loads when rendered)
const HeavyChart = dynamic(() => import('@/components/HeavyChart'), {
  loading: () => <ChartSkeleton />,
});

// Skip SSR for browser-only components
const MapWidget = dynamic(() => import('@/components/MapWidget'), {
  ssr: false,
  loading: () => <MapPlaceholder />,
});
```

Use for: below-fold components, modals, tabs (load on interaction), browser-only libraries.

### Pattern 2: Import Specific Exports

```tsx
// ❌ BAD — Imports entire library (tree shaking may not catch everything)
import _ from 'lodash';
const sorted = _.sortBy(items, 'name');

// ✅ GOOD — Import only what you need
import sortBy from 'lodash/sortBy';
const sorted = sortBy(items, 'name');

// ✅ BEST — Use native JS when possible
const sorted = [...items].sort((a, b) => a.name.localeCompare(b.name));
```

### Pattern 3: Monitor Bundle Size

```bash
# Webpack bundle analyzer
ANALYZE=true next build

# Turbopack analyzer (v16.1+)
pnpm next experimental-analyze
```

**Check `next build` output**: "First Load JS" per route. Target: <100KB per route. If a route shows 200KB+, look for `"use client"` cascade or heavy imports.

### Pattern 4: Route Segment Config

```tsx
// app/blog/[slug]/page.tsx
export const dynamic = 'force-static';   // Force static generation
export const revalidate = 3600;          // ISR: revalidate hourly
export const fetchCache = 'force-cache'; // Cache all fetches in this segment

// app/dashboard/page.tsx
export const dynamic = 'force-dynamic';  // Always SSR (no caching)
```

| Config | Effect |
|--------|--------|
| `dynamic = 'auto'` | Default — Next.js decides |
| `dynamic = 'force-dynamic'` | Always SSR |
| `dynamic = 'force-static'` | Force static at build |
| `revalidate = N` | ISR with N seconds TTL |
| `runtime = 'edge'` | Run on Edge runtime |
| `runtime = 'nodejs'` | Run on Node.js runtime |

---

## Level 3: Partial Prerendering and Advanced Patterns (Advanced)

### Pattern 1: Partial Prerendering (PPR)

PPR = static HTML shell (CDN-cached) + dynamic content (streamed via Suspense). Same HTTP response. Near-instant TTFB with personalized content.

```tsx
// next.config.ts (Next.js 15 — experimental)
export default {
  experimental: {
    ppr: true,
  },
};

// app/product/[id]/page.tsx
import { Suspense } from 'react';

export default async function ProductPage({ params }) {
  const { id } = await params;
  const product = await getProduct(id); // Static — cached at build

  return (
    <div>
      {/* Static shell — served from CDN */}
      <h1>{product.name}</h1>
      <p>{product.description}</p>

      {/* Dynamic hole — streamed at request time */}
      <Suspense fallback={<PriceSkeleton />}>
        <LivePrice productId={id} />  {/* Real-time pricing */}
      </Suspense>
      <Suspense fallback={<InventorySkeleton />}>
        <InventoryStatus productId={id} /> {/* Live stock */}
      </Suspense>
    </div>
  );
}
```

**Mental model**: Everything outside `<Suspense>` = static. Everything inside = dynamic.

In Next.js 16: PPR evolves into `use cache` directive. All code dynamic by default, opt into static with `'use cache'`.

### Pattern 2: Streaming Architecture
Structure pages for maximum streaming benefit:

```
┌─────────────────────────────────────┐
│ Static Shell (instant from CDN)      │
│ ┌─────────────────────────────────┐ │
│ │ Nav, Header, Layout             │ │
│ └─────────────────────────────────┘ │
│ ┌──────────┐  ┌──────────────────┐ │
│ │ Suspense  │  │ Suspense         │ │
│ │ ┌──────┐  │  │ ┌──────────────┐│ │
│ │ │ Data │  │  │ │ Heavy Data   ││ │
│ │ │ ~200ms│ │  │ │ ~800ms       ││ │
│ │ └──────┘  │  │ └──────────────┘│ │
│ └──────────┘  └──────────────────┘ │
│ ┌─────────────────────────────────┐ │
│ │ Suspense: Analytics (non-crit)  │ │
│ │ Streams last                    │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

### Pattern 3: Core Web Vitals Optimization Checklist

| Metric | Target | Key Lever |
|--------|--------|-----------|
| LCP | <2.5s | `priority` on hero image, streaming SSR, CDN |
| CLS | <0.1 | next/font (zero CLS), next/image (width/height), no dynamic content above fold |
| INP | <200ms | Minimize client JS, debounce handlers, `startTransition` for heavy updates |
| TTFB | <800ms | Edge runtime, static generation, CDN caching |

---

## Observability: Know It's Working

### Obs 1: Monitor Core Web Vitals in Production
Use `web-vitals` library or Vercel Analytics to track real-user CWV:

```tsx
// app/components/WebVitals.tsx
'use client';
import { useReportWebVitals } from 'next/web-vitals';

export function WebVitals() {
  useReportWebVitals((metric) => {
    // Send to your analytics/monitoring system
    console.log(metric.name, metric.value);
  });
  return null;
}
```

### Obs 2: Track Build Size Trends
Run `next build` in CI and track "First Load JS" per route over time. Alert when any route exceeds 150KB.

### Obs 3: Monitor Image Optimization Cache
On self-hosted deployments, `.next/cache/images/` grows unbounded. Monitor disk usage. Set `minimumCacheTTL` in next.config.ts for cache retention.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Use Raw `<img>` Tags
**You will be tempted to:** Write `<img src="/photo.jpg">` because it's simpler.
**Why that fails:** No WebP/AVIF conversion (40-70% larger files), no lazy loading, no responsive sizing, CLS from missing dimensions.
**The right way:** Always `import Image from 'next/image'`. Set `width`+`height` or `fill`. Configure `remotePatterns` for external images.

### Rule 2: Never Use External Font Links
**You will be tempted to:** Add `<link href="fonts.googleapis.com/...">` in the head.
**Why that fails:** Third-party request blocks rendering, causes FOUT/FOIT, layout shift when font swaps.
**The right way:** `import { FontName } from 'next/font/google'`. Self-hosted, zero CLS, zero external requests.

### Rule 3: Never Set sizes="100vw" on All Images
**You will be tempted to:** Use `sizes="100vw"` as a default for responsive images.
**Why that fails:** Browser downloads the largest available image for every viewport. A sidebar thumbnail gets a 1200px image on desktop.
**The right way:** Specify actual viewport percentages: `sizes="(max-width: 768px) 100vw, 50vw"`.

### Rule 4: Never Import Entire Libraries Client-Side
**You will be tempted to:** `import moment from 'moment'` or `import _ from 'lodash'` in client components.
**Why that fails:** Ships 70-300KB of JavaScript to every user. Tree shaking doesn't always catch barrel exports.
**The right way:** Import specific functions, or move processing to Server Components where bundle size doesn't matter.

### Rule 5: Never Force Dynamic When Static Works
**You will be tempted to:** Add `export const dynamic = 'force-dynamic'` to silence build warnings about `searchParams`.
**Why that fails:** Opts the entire route out of static generation. Every request triggers SSR — slower TTFB, higher server costs.
**The right way:** Isolate dynamic data (searchParams, cookies) in `<Suspense>` boundaries. Let the rest of the page be static.
