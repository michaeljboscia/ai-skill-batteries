---
name: mx-nextjs-seo
description: "Next.js SEO, Metadata API, generateMetadata, static metadata, title.template, metadataBase, sitemap.ts, robots.ts, dynamic OG images, ImageResponse, opengraph-image.tsx, JSON-LD structured data, canonical URLs, hreflang, alternates, schema-dts, rich results, E-E-A-T"
---

# Next.js SEO — Metadata, Structured Data, and Discoverability for AI Coding Agents

**Load this skill when configuring metadata, generating sitemaps/robots, creating OG images, adding structured data, or optimizing for search engines.**

## When to also load
- `mx-nextjs-core` — File conventions, route structure
- `mx-nextjs-rsc` — Metadata exports only work in Server Components
- `mx-nextjs-perf` — Core Web Vitals directly impact SEO rankings
- `mx-nextjs-deploy` — metadataBase depends on deployment URL

---

## Level 1: Metadata API Fundamentals (Beginner)

### Pattern 1: Static vs Dynamic Metadata
**Cannot have both** `metadata` object AND `generateMetadata` in the same route segment.

```tsx
// Static metadata — for pages with fixed content
// app/about/page.tsx
export const metadata = {
  title: 'About Us',
  description: 'Learn about our company and mission.',
};

// Dynamic metadata — for data-driven pages
// app/blog/[slug]/page.tsx
export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const post = await getPost(slug); // fetch auto-memoized

  return {
    title: post.title,
    description: post.excerpt,
    openGraph: {
      title: post.title,
      description: post.excerpt,
      images: [{ url: post.coverImage }],
    },
  };
}
```

### Pattern 2: Root Layout Metadata Setup
Every Next.js app needs these in the root layout:

```tsx
// app/layout.tsx
export const metadata = {
  metadataBase: new URL('https://yourdomain.com'), // REQUIRED for OG images
  title: {
    template: '%s | Brand Name',  // Auto-appends to all child titles
    default: 'Brand Name',        // Fallback when no child sets title
  },
  description: 'Default site description.',
  openGraph: {
    type: 'website',
    siteName: 'Brand Name',
    locale: 'en_US',
  },
  twitter: {
    card: 'summary_large_image',
  },
};
```

**`metadataBase` is critical** — without it, OG image URLs are relative and social platforms can't fetch them.

### Pattern 3: Metadata Inheritance
Child routes inherit parent metadata. Children override specific fields:

```
Root layout: title.template = "%s | Brand"
├── /about page: title = "About Us" → renders "About Us | Brand"
├── /blog layout: (inherits root)
│   └── /blog/[slug] page: title = post.title → renders "Post Title | Brand"
```

### Pattern 4: File-Based Metadata Conventions

| File | Location | Generates |
|------|----------|-----------|
| `favicon.ico` | `app/` | `<link rel="icon">` |
| `opengraph-image.tsx` | Any route | `<meta property="og:image">` |
| `twitter-image.tsx` | Any route | `<meta name="twitter:image">` |
| `sitemap.ts` | `app/` | `/sitemap.xml` |
| `robots.ts` | `app/` | `/robots.txt` |

---

## Level 2: Sitemaps, Robots, and OG Images (Intermediate)

### Pattern 1: Dynamic Sitemap

```tsx
// app/sitemap.ts
import type { MetadataRoute } from 'next';

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const posts = await db.post.findMany({ select: { slug: true, updatedAt: true } });

  const postUrls = posts.map((post) => ({
    url: `https://yourdomain.com/blog/${post.slug}`,
    lastModified: post.updatedAt,
    changeFrequency: 'weekly' as const,
    priority: 0.8,
  }));

  return [
    { url: 'https://yourdomain.com', lastModified: new Date(), priority: 1.0 },
    { url: 'https://yourdomain.com/about', lastModified: new Date(), priority: 0.5 },
    ...postUrls,
  ];
}
```

For large sites (50K+ URLs), use `generateSitemaps` to create a sitemap index:

```tsx
export async function generateSitemaps() {
  const count = await db.post.count();
  const pages = Math.ceil(count / 50000);
  return Array.from({ length: pages }, (_, i) => ({ id: i }));
}

export default async function sitemap({ id }: { id: number }) {
  const posts = await db.post.findMany({ skip: id * 50000, take: 50000 });
  return posts.map((post) => ({ url: `https://yourdomain.com/blog/${post.slug}` }));
}
```

### Pattern 2: robots.ts

```tsx
// app/robots.ts
import type { MetadataRoute } from 'next';

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: '*',
        allow: '/',
        disallow: ['/private/', '/admin/', '/api/'],
      },
    ],
    sitemap: 'https://yourdomain.com/sitemap.xml', // Always link sitemap
  };
}
```

**Never block `/_next/`** — crawlers need static assets to render pages correctly.

### Pattern 3: Dynamic OG Image Generation

```tsx
// app/blog/[slug]/opengraph-image.tsx
import { ImageResponse } from 'next/og';

export const runtime = 'edge';
export const alt = 'Blog post cover';
export const size = { width: 1200, height: 630 };
export const contentType = 'image/png';

export default async function Image({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const post = await getPost(slug);

  return new ImageResponse(
    (
      <div style={{
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'center',
        alignItems: 'center',
        width: '100%',
        height: '100%',
        backgroundColor: '#1a1a2e',
        color: 'white',
        padding: 60,
      }}>
        <h1 style={{ fontSize: 64, fontWeight: 'bold', textAlign: 'center' }}>
          {post.title}
        </h1>
        <p style={{ fontSize: 28, opacity: 0.8 }}>yourdomain.com</p>
      </div>
    ),
    { ...size }
  );
}
```

**Auto-generates `<meta og:image>` per route** — no manual meta tags needed. Supports Flexbox (not Grid), custom fonts, emojis. 500KB bundle limit.

### Pattern 4: Pre-generate OG Images at Build Time

```tsx
// Add to the same opengraph-image.tsx file
export async function generateStaticParams() {
  const posts = await db.post.findMany({ select: { slug: true } });
  return posts.map((post) => ({ slug: post.slug }));
}
```

---

## Level 3: Structured Data and Advanced SEO (Advanced)

### Pattern 1: JSON-LD Structured Data

```tsx
// app/blog/[slug]/page.tsx
import type { Article, WithContext } from 'schema-dts'; // TypeScript types for Schema.org

export default async function BlogPost({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const post = await getPost(slug);

  const jsonLd: WithContext<Article> = {
    '@context': 'https://schema.org',
    '@type': 'Article',
    headline: post.title,
    datePublished: post.publishedAt,
    dateModified: post.updatedAt,
    author: { '@type': 'Person', name: post.author.name },
    publisher: { '@type': 'Organization', name: 'Brand Name' },
    image: post.coverImage,
    description: post.excerpt,
  };

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify(jsonLd).replace(/</g, '\\u003c'), // XSS prevention
        }}
      />
      <article>{/* ... */}</article>
    </>
  );
}
```

**Always sanitize** with `.replace(/</g, '\\u003c')` to prevent script injection via user-controlled data.

### Pattern 2: Common Schema Types

| Page Type | Schema | Key Properties |
|-----------|--------|---------------|
| Blog post | `Article` | headline, datePublished, author, publisher |
| Product | `Product` | name, offers, aggregateRating, brand |
| Organization | `Organization` | name, url, logo, sameAs (social links) |
| FAQ | `FAQPage` | mainEntity (Question/Answer pairs) |
| Breadcrumbs | `BreadcrumbList` | itemListElement (ordered) |
| Recipe | `Recipe` | cookTime, recipeIngredient, nutrition |

Place Organization/WebSite schemas in `layout.tsx` (sitewide). Page-specific schemas in `page.tsx`.

### Pattern 3: Canonical URLs and Alternates

```tsx
// app/blog/[slug]/page.tsx
export async function generateMetadata({ params }) {
  const { slug } = await params;
  return {
    alternates: {
      canonical: `/blog/${slug}`,           // Resolves against metadataBase
      languages: {
        'en-US': `/en/blog/${slug}`,
        'fr-FR': `/fr/blog/${slug}`,
        'x-default': `/blog/${slug}`,       // Always include x-default
      },
    },
  };
}
```

Canonicals prevent duplicate content penalties from trailing slashes, www/non-www, query params, and pagination.

---

## Performance: Make It Fast

### Perf 1: generateMetadata fetch Requests Are Auto-Memoized
If your `page.tsx` and `generateMetadata` both call `getPost(slug)`, React deduplicates — only one fetch fires. No need to cache manually between them.

### Perf 2: Pre-generate OG Images
Dynamic OG generation on every request is expensive. Use `generateStaticParams` in `opengraph-image.tsx` to pre-render at build time.

### Perf 3: Don't Block Rendering for Metadata
`generateMetadata` resolves before the page streams. Keep data fetches minimal — only what's needed for meta tags.

---

## Observability: Know It's Working

### Obs 1: Validate with Testing Tools
- Google Rich Results Test: validates JSON-LD structured data
- Facebook Sharing Debugger: validates OG tags and images
- Twitter Card Validator: validates Twitter card rendering
- metatags.io: preview across platforms

### Obs 2: Monitor 404s and Crawl Errors
Use Google Search Console + your `not-found.tsx` logging to detect broken links. High 404 rates damage crawl budget.

### Obs 3: Track Missing metadataBase
Without `metadataBase`, all OG image URLs become relative — social platforms return blank images. Monitor social share previews after deployment.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Use next/head
**You will be tempted to:** `import Head from 'next/head'` and add `<title>` tags.
**Why that fails:** `next/head` does not exist in App Router. Import fails or metadata is silently ignored.
**The right way:** Export `metadata` object or `generateMetadata` function from `page.tsx` or `layout.tsx`.

### Rule 2: Never Skip metadataBase
**You will be tempted to:** Set OG images with relative paths: `images: ['/images/og.png']`.
**Why that fails:** Social platforms receive relative URLs they can't fetch. Preview images are blank on Twitter, Facebook, LinkedIn, Slack.
**The right way:** Set `metadataBase: new URL('https://yourdomain.com')` in root layout. All relative URLs resolve against it.

### Rule 3: Never Hardcode Identical Metadata Across Pages
**You will be tempted to:** Copy-paste the same title and description to every page.
**Why that fails:** Duplicate metadata across pages signals low quality to search engines. Rankings drop.
**The right way:** Use `title.template` in root layout. Set unique titles and descriptions per page via `generateMetadata`.

### Rule 4: Never Skip JSON-LD Sanitization
**You will be tempted to:** `JSON.stringify(jsonLd)` without escaping.
**Why that fails:** If user-controlled data contains `</script>`, it breaks out of the JSON-LD block — XSS vulnerability.
**The right way:** Always `.replace(/</g, '\\u003c')` on the stringified JSON before passing to `dangerouslySetInnerHTML`.

### Rule 5: Never Block /_next/ in robots.txt
**You will be tempted to:** Disallow `/_next/` thinking it's internal.
**Why that fails:** Crawlers need static JS/CSS assets to render your pages. Blocking them makes your site appear blank to Google.
**The right way:** Only disallow `/private/`, `/admin/`, `/api/` — never internal framework routes.
