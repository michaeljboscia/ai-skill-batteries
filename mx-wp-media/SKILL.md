---
name: mx-wp-media
description: Use when working with images in headless WordPress — next/image configuration, WPGraphQL media queries, responsive images, CDN integration, image optimization pipeline, or WordPress media library with Next.js. Also use when the user mentions 'next/image', 'remotePatterns', 'featuredImage', 'sourceUrl', 'mediaDetails', 'Cloudinary', or 'image optimization'.
---

# Headless WordPress Media — Image Optimization Pipeline for AI Coding Agents

**Loads when working with images from WordPress in a Next.js frontend.**

## When to also load
- `mx-wp-core` — fetchGraphQL, codegen
- `mx-wp-content` — ACF image fields, gallery fields
- `mx-nextjs-perf` — next/image optimization, Core Web Vitals

---

## Level 1: WPGraphQL Media Queries (Beginner)

### 1.1 Always Query These Fields

Every image query must include `sourceUrl`, `altText`, and `mediaDetails { height, width }`.

**BAD — Missing dimensions and alt text:**
```graphql
query { post(id: "hello", idType: SLUG) {
  featuredImage { node { sourceUrl } }  # No altText, no dimensions
}}
```

**GOOD — Complete image data:**
```graphql
query GetPost($slug: ID!) {
  post(id: $slug, idType: SLUG) {
    title
    featuredImage {
      node {
        altText
        sourceUrl
        mediaDetails { height, width }
      }
    }
  }
}
```

### 1.2 Null Safety for Images

Featured images are not guaranteed. Always use optional chaining + nullish coalescing.

**BAD — Crashes when featuredImage is null:**
```tsx
<Image src={post.featuredImage.node.sourceUrl} alt="Post" width={800} height={600} />
```

**GOOD — Safe with fallbacks:**
```tsx
{post.featuredImage?.node && (
  <Image
    src={post.featuredImage.node.sourceUrl}
    alt={post.featuredImage.node.altText ?? post.title ?? ''}
    width={post.featuredImage.node.mediaDetails?.width ?? 800}
    height={post.featuredImage.node.mediaDetails?.height ?? 600}
  />
)}
```

---

## Level 2: next/image Configuration (Intermediate)

### 2.1 remotePatterns (Required)

Modern Next.js requires `remotePatterns` — the old `domains` array is deprecated.

**BAD — Deprecated and insecure:**
```typescript
// next.config.ts
images: {
  domains: ['mysite.com'],     // Deprecated
  unoptimized: true,           // Bypasses ALL optimization
}
```

**GOOD — Strict remotePatterns:**
```typescript
// next.config.ts
import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  images: {
    remotePatterns: [
      {
        protocol: 'https',
        hostname: 'your-wordpress-site.com',
        pathname: '/wp-content/uploads/**',
      },
      {
        protocol: 'https',
        hostname: '*.gravatar.com',
        pathname: '/avatar/**',
      },
    ],
  },
}
export default nextConfig
```

### 2.2 Priority for Above-the-Fold Images

Set `priority={true}` on hero/featured images to preload them (improves LCP).

```tsx
<Image
  src={heroImage.sourceUrl}
  alt={heroImage.altText ?? ''}
  width={heroImage.mediaDetails.width}
  height={heroImage.mediaDetails.height}
  priority={true}              // Preloads — no lazy loading
  sizes="(max-width: 768px) 100vw, (max-width: 1200px) 50vw, 33vw"
/>
```

### 2.3 Reusable WPImage Component

Centralize null safety and fallback logic in one component:

```tsx
import Image, { type ImageProps } from 'next/image'

interface WPImageNode {
  sourceUrl: string
  altText?: string | null
  mediaDetails?: { width?: number | null; height?: number | null } | null
}

interface WPImageProps extends Omit<ImageProps, 'src' | 'alt' | 'width' | 'height'> {
  imageNode?: WPImageNode | null
  fallbackAlt?: string
}

export function WPImage({ imageNode, fallbackAlt = '', priority, ...rest }: WPImageProps) {
  if (!imageNode?.sourceUrl) return null

  return (
    <Image
      src={imageNode.sourceUrl}
      alt={imageNode.altText ?? fallbackAlt}
      width={imageNode.mediaDetails?.width ?? 800}
      height={imageNode.mediaDetails?.height ?? 600}
      priority={priority}
      {...rest}
    />
  )
}
```

---

## Level 3: CDN Integration (Advanced)

### 3.1 CDN Decision Tree

| Need | Solution | Setup |
|------|----------|-------|
| Simplicity, Vercel hosting | Vercel Image Optimization | Zero config — just use next/image |
| Advanced transforms, WP storage relief | Cloudinary | WP plugin + custom Next.js loader |
| Proxy-based, S3/WP uploads | Imgix | Custom Next.js loader |
| Full control, no SaaS costs | Self-hosted (Thumbor) | High DevOps overhead |

### 3.2 Custom Loader for Cloudinary

```typescript
// lib/cloudinaryLoader.ts
export default function cloudinaryLoader({
  src, width, quality
}: { src: string; width: number; quality?: number }) {
  return `https://res.cloudinary.com/your-cloud/image/upload/w_${width},q_${quality || 75},f_auto/${src}`
}
```

```typescript
// next.config.ts
images: {
  loader: 'custom',
  loaderFile: './lib/cloudinaryLoader.ts',
}
```

### 3.3 Image Pipeline: WP → CDN → next/image → Browser

```
1. Upload to WP Media Library
2. WPGraphQL query returns sourceUrl + mediaDetails
3. next/image receives URL → applies remotePatterns check
4. Image Optimization API (Vercel or custom loader) resizes + converts to WebP/AVIF
5. Auto-generated srcset served to browser based on viewport
6. Browser selects optimal size from srcset
```

---

## Performance: Make It Fast

- Always include `width` and `height` from `mediaDetails` — prevents CLS
- Use `priority={true}` on LCP images (hero, featured above fold)
- Use `sizes` prop to guide srcset selection: `"(max-width: 768px) 100vw, 50vw"`
- Fetch `sourceUrl` (full size) — let next/image handle resizing. Never fetch WP thumbnail sizes.
- Add CDN domain to `remotePatterns` if using Cloudinary/Imgix

## Observability: Know It's Working

- Check Lighthouse LCP score — if poor, verify `priority` on hero images
- Monitor `Invalid src prop` errors in Next.js logs — means remotePatterns misconfigured
- Check Network tab for `_next/image?` requests — confirms optimization is active
- If images load slowly, verify CDN cache headers (`x-cache: HIT`)

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Fetch Full-Size Images Without Optimization
**You will be tempted to:** use WP `sourceUrl` in a raw `<img>` tag.
**Why that fails:** Original uploads can be 5MB+. Users download the full file on mobile. LCP and bandwidth destroyed.
**The right way:** Always wrap in `next/image` which auto-resizes and converts to WebP.

### Rule 2: Never Skip remotePatterns Configuration
**You will be tempted to:** add `unoptimized: true` or use the deprecated `domains` array to "just make it work."
**Why that fails:** `unoptimized` bypasses all optimization. `domains` is deprecated and overly permissive. Both are security risks.
**The right way:** Configure strict `remotePatterns` with protocol, hostname, and pathname.

### Rule 3: Never Hardcode Image Dimensions
**You will be tempted to:** write `width={800} height={600}` without querying actual dimensions.
**Why that fails:** Wrong aspect ratio causes CLS (layout shift) or stretched/squished images. The CMS holds the truth.
**The right way:** Always query `mediaDetails { width, height }` from GraphQL and pass those values.

### Rule 4: Never Use Raw img Tags
**You will be tempted to:** use `<img src={...}>` instead of `next/image`.
**Why that fails:** No automatic srcset, no lazy loading, no WebP conversion, no CLS prevention. Forfeits all Next.js image performance benefits.
**The right way:** Always `import Image from 'next/image'` and use the `<Image>` component.
