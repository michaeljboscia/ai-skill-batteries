---
name: mx-wp-perf
description: Use when optimizing headless WordPress performance — WPGraphQL query optimization, caching strategies, WPGraphQL Smart Cache, Redis, persisted queries, cursor pagination, N+1 DataLoader, ISR rendering strategy, or any performance work on headless WP + Next.js. Also use when the user mentions 'Smart Cache', 'persisted queries', 'cursor pagination', 'N+1', 'DataLoader', 'posts_per_page', 'no_found_rows', or 'revalidate'.
---

# Headless WordPress Performance — Caching, Query Optimization, Rendering for AI Coding Agents

**Co-loads automatically on any headless WordPress work.**

## When to also load
- `mx-wp-core` — fetchGraphQL, architecture
- `mx-wp-auth` — revalidation webhooks
- `mx-nextjs-perf` — Next.js performance patterns

---

## Level 1: Query Optimization (Beginner)

### 1.1 Request Only What You Need

**BAD — Over-fetching (the "SELECT *" of GraphQL):**
```graphql
query { posts { nodes { id, databaseId, title, slug, content, excerpt, date, modified,
  author { node { name, email, avatar { url } } },
  categories { nodes { name, slug } },
  tags { nodes { name, slug } },
  featuredImage { node { sourceUrl, altText, mediaDetails { height, width } } }
} } }
```

**GOOD — Only fields needed for list page:**
```graphql
query GetPostCards {
  posts(first: 10, where: { status: PUBLISH }) {
    nodes {
      databaseId
      title
      slug
      excerpt(format: RENDERED)
      featuredImage { node { sourceUrl, altText, mediaDetails { height, width } } }
    }
  }
}
```

### 1.2 Cursor-Based Pagination (Relay-style)

**BAD — Offset pagination (O(n) database scan):**
```graphql
# WordPress scans and discards 500 rows to return 10
query { posts(where: { offsetPagination: { offset: 500, size: 10 } }) { nodes { title } } }
```

**GOOD — Cursor pagination (O(1) constant time):**
```graphql
query GetPosts($after: String) {
  posts(first: 10, after: $after) {
    pageInfo {
      hasNextPage
      endCursor       # Pass this as $after for next page
    }
    nodes { databaseId, title, slug }
  }
}
```

### 1.3 Essential WP_Query Optimization Flags

When writing custom WPGraphQL resolvers or filters:

| Flag | When to Use | Why |
|------|------------|-----|
| `no_found_rows => true` | No pagination needed | Skips `SQL_CALC_FOUND_ROWS` count query |
| `fields => 'ids'` | Only need post IDs | Reduces memory — no full post objects |
| `posts_per_page => 1` | Need one post | Don't load 10 by default |
| `update_post_meta_cache => false` | Only displaying titles | Skips meta preloading |
| `update_post_term_cache => false` | No taxonomy data needed | Skips term preloading |
| `posts_per_page => -1` | **NEVER** | Loads ALL posts into memory — OOM crash |

---

## Level 2: Multi-Layer Caching (Intermediate)

### 2.1 The 5-Layer Cache Architecture

```
Layer 1: Browser/Client    → Apollo InMemoryCache or Next.js router cache
Layer 2: CDN/Edge          → Vercel, Cloudflare, Varnish (GET requests only)
Layer 3: WPGraphQL Smart Cache → Tag-based invalidation via X-GraphQL-Keys header
Layer 4: WordPress Object Cache → Redis/Memcached for WP internal queries
Layer 5: MySQL Database    → InnoDB engine, query cache
```

### 2.2 WPGraphQL Smart Cache

The Smart Cache plugin provides network cache + object cache + tag-based invalidation.

**How it works:**
1. WPGraphQL resolves a query and tracks which entities (posts, users, terms) were accessed
2. Returns `X-GraphQL-Keys: list:post, post:123, category:4` header
3. CDN stores the response tagged with those keys
4. When post 123 is updated, Smart Cache purges only entries tagged `post:123`

**Requirements:**
- Queries must use HTTP **GET** for CDN caching (POST bypasses CDN)
- Hosting must support tag-based cache purging (WP Engine, Pressable)
- Install WPGraphQL Smart Cache plugin

### 2.3 Persisted Queries

Store queries server-side, reference by hash ID. Solves:
- URL length limits for GET requests
- Reduced network payload (only send hash, not full query)
- Security whitelist (prevent arbitrary query execution)
- Enhanced CDN cache hit rates

### 2.4 Redis Object Cache

```
maxmemory 256mb
maxmemory-policy allkeys-lru
```

Install Redis Object Cache plugin. Caches WP internal objects (posts, meta, options) in RAM. Reduces MySQL load by 60-80%.

---

## Level 3: DataLoader + Rendering Strategy (Advanced)

### 3.1 The N+1 Problem

Querying 10 posts with authors = 1 query for posts + 10 queries for authors = 11 total.

**WPGraphQL's built-in DataLoader:**
- Collects all author IDs during a single execution frame
- Deduplicates (3 posts by same author = 1 author query)
- Batches into single query: `SELECT * FROM wp_users WHERE ID IN (1, 2, 5)`
- **New DataLoader instance per request** — prevents data leakage between users

### 3.2 Next.js Rendering Strategy Decision Tree

| Strategy | Implementation | Best For | Risk |
|----------|---------------|----------|------|
| SSG | `generateStaticParams` at build | Static pages (Home, About) | **SSG DoS** if generating 10K+ pages |
| ISR | `revalidate: 3600` or on-demand `revalidateTag` | Blog posts, case studies | Stale content if webhooks fail |
| SSR | Dynamic rendering (Next.js 16 default) | Search results, dashboards | Slower TTFB, depends on WP server speed |
| `use cache` (Next.js 16) | Explicit component-level caching | Hybrid layouts mixing static + dynamic | Requires React 19 + Next.js 16 |

### 3.3 Avoiding SSG DoS

**BAD — Generate all 10,000 posts at build:**
```typescript
// generateStaticParams fetches ALL posts — overwhelms WP server
export async function generateStaticParams() {
  const posts = await getAllPosts()  // 10,000 posts = 10,000 GraphQL requests during build
  return posts.map(p => ({ slug: p.slug }))
}
```

**GOOD — Generate top 50, ISR the rest:**
```typescript
export async function generateStaticParams() {
  const posts = await getRecentPosts(50)  // Only most-trafficked pages
  return posts.map(p => ({ slug: p.slug }))
}
// Remaining 9,950 posts built on first request via ISR
```

---

## Performance: Make It Fast (Checklist)

- [ ] Request only needed fields in every query
- [ ] Use cursor pagination, never offset
- [ ] Never use `posts_per_page: -1`
- [ ] Include `id` + `databaseId` for client cache normalization
- [ ] Use `revalidateTag` for on-demand ISR (not time-based)
- [ ] Enable WPGraphQL Smart Cache with GET requests
- [ ] Configure Redis Object Cache on WP host
- [ ] Generate only top 50-100 pages at build time, ISR the rest
- [ ] Use Next.js 16 `use cache` for component-level caching

## Observability: Know It's Working

- Monitor `X-GraphQL-Keys` header — confirms Smart Cache is active
- Check CDN `x-cache: HIT/MISS` ratio — target 90%+ hits
- Track ISR revalidation webhook success rate
- Monitor WP Query Monitor for N+1 patterns during development
- Track Redis `hit_rate` — should be > 80%

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Use posts_per_page -1
**You will be tempted to:** fetch "all posts" with `posts_per_page: -1` or `first: 99999`.
**Why that fails:** Loads entire database into PHP memory. Fatal OOM on any non-trivial site. One query can crash the server.
**The right way:** Always paginate. Use `first: 10` with cursor-based `after` parameter.

### Rule 2: Never Use Offset Pagination
**You will be tempted to:** use `offset: 500` for "simple" pagination.
**Why that fails:** MySQL scans and discards all rows up to the offset. Page 50 requires scanning 500 rows to return 10. O(n) performance degradation.
**The right way:** Cursor-based pagination with `first`/`after`. Constant O(1) performance.

### Rule 3: Never Skip Caching
**You will be tempted to:** skip cache configuration because "the site is small."
**Why that fails:** Without caching, every page view hits WordPress PHP + MySQL. Even a moderate traffic spike causes timeouts.
**The right way:** Implement at minimum: Next.js ISR + Redis Object Cache + CDN for static assets.

### Rule 4: Never Generate All Pages at Build Time
**You will be tempted to:** use `generateStaticParams` to SSG every page for "maximum performance."
**Why that fails:** Building 5,000+ pages fires 5,000 GraphQL requests during CI/CD build. WP server crashes. Build takes 45+ minutes. Self-inflicted DoS.
**The right way:** SSG top 50-100 pages. ISR everything else. On-demand revalidation via webhooks.

### Rule 5: Never Nest Connections Deeply Without DataLoader
**You will be tempted to:** query `posts → categories → posts in category → authors` in one query.
**Why that fails:** Each nesting level multiplies database queries exponentially. Without DataLoader batching, this triggers hundreds of individual SQL queries.
**The right way:** Keep nesting shallow. Split into multiple flat queries if deep relations needed. Rely on WPGraphQL's built-in DataLoader.
