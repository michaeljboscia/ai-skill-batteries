---
name: mx-wp-core
description: Use when setting up headless WordPress with WPGraphQL, registering custom post types for GraphQL, configuring graphql-codegen, writing fetchGraphQL functions, or any headless WP + Next.js architecture work. Also use when the user mentions 'WPGraphQL', 'headless WordPress', 'show_in_graphql', 'graphql-codegen', or 'fetchGraphQL'.
---

# Headless WordPress Core — WPGraphQL + Next.js Architecture for AI Coding Agents

**Loads when writing any headless WordPress code with WPGraphQL and Next.js.**

## When to also load
- `mx-wp-content` — ACF fields, Flexible Content, Gutenberg blocks
- `mx-wp-auth` — JWT auth, preview mode, draft content
- `mx-wp-perf` — co-loads automatically (query optimization, caching)
- `mx-wp-observability` — co-loads automatically (monitoring, health checks)
- `mx-nextjs-core` — Next.js App Router patterns
- `mx-ts-core` — TypeScript patterns

---

## Level 1: Patterns That Always Work (Beginner)

### 1.1 Custom Post Type Registration for GraphQL

Every CPT must explicitly opt into the GraphQL schema. Without these three flags, the CPT is invisible to WPGraphQL.

**BAD:**
```php
// CPT exists in WordPress but is INVISIBLE to GraphQL
register_post_type('case_study', [
    'public' => true,
    'label'  => 'Case Studies',
]);
```

**GOOD:**
```php
register_post_type('case_study', [
    'public'              => true,
    'publicly_queryable'  => true,
    'label'               => 'Case Studies',
    'supports'            => ['title', 'editor', 'thumbnail'],
    'show_in_graphql'     => true,              // REQUIRED
    'graphql_single_name' => 'caseStudy',       // camelCase, unique
    'graphql_plural_name' => 'caseStudies',     // camelCase, unique
]);
```

Same pattern for taxonomies — all three flags required.

### 1.2 GraphQL Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Types | PascalCase | `Post`, `CaseStudy`, `MenuItem` |
| Fields | camelCase | `databaseId`, `featuredImage`, `estimatedReadingTime` |
| Arguments | camelCase | `where`, `first`, `after` |
| Enum values | ALL_CAPS | `PUBLISH`, `DRAFT`, `ASC` |

### 1.3 fetchGraphQL Reference Implementation

Never throw exceptions from fetchGraphQL — return `{data, errors}` for graceful degradation.

**BAD:**
```typescript
// Throwing destroys the entire React render tree
async function fetchGraphQL(query: string) {
  const res = await fetch(process.env.NEXT_PUBLIC_WORDPRESS_GRAPHQL_URL!, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  })
  const json = await res.json()
  if (json.errors) throw new Error(json.errors[0].message) // BAD
  return json.data
}
```

**GOOD:**
```typescript
interface GraphQLResponse<T> {
  data?: T
  errors?: Array<{ message: string }>
}

export async function fetchGraphQL<T = any>(
  query: string,
  variables: Record<string, any> = {},
  tags: string[] = ['wordpress']
): Promise<GraphQLResponse<T>> {
  try {
    const res = await fetch(process.env.NEXT_PUBLIC_WORDPRESS_GRAPHQL_URL!, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ query, variables }),
      next: { tags },  // Next.js cache tags for on-demand revalidation
    })
    if (!res.ok) {
      return { data: undefined, errors: [{ message: `Network: ${res.statusText}` }] }
    }
    const json = await res.json()
    if (json.errors) {
      return { data: undefined, errors: json.errors }
    }
    return { data: json.data }
  } catch (error) {
    return { data: undefined, errors: [{ message: error instanceof Error ? error.message : 'Unknown error' }] }
  }
}
```

### 1.4 Query Function Pattern

One file per query in `lib/queries/`. Always null-check before returning.

```typescript
import { fetchGraphQL } from '@/lib/functions'
import type { Post } from '@/lib/generated'

export default async function getAllPosts(): Promise<Post[]> {
  const query = `
    query GetAllPosts {
      posts(where: {status: PUBLISH}) {
        nodes {
          databaseId
          title
          slug
          excerpt(format: RENDERED)
          featuredImage {
            node { altText, sourceUrl, mediaDetails { height, width } }
          }
        }
      }
    }
  `
  const response = await fetchGraphQL(query)
  if (!response?.data?.posts?.nodes) return []
  return response.data.posts.nodes as Post[]
}
```

---

## Level 2: Type Safety with graphql-codegen (Intermediate)

### 2.1 Codegen Configuration

```typescript
// codegen.ts
import type { CodegenConfig } from '@graphql-codegen/cli'

const config: CodegenConfig = {
  schema: process.env.NEXT_PUBLIC_WORDPRESS_GRAPHQL_URL!,
  documents: ['lib/queries/**/*.ts', 'lib/mutations/**/*.ts'],
  generates: {
    './lib/generated.ts': {
      plugins: ['typescript', 'typescript-operations'],
      config: {
        avoidOptionals: false,
        maybeValue: 'T | null',    // WP fields are nullable — never use T | undefined
        skipTypename: true,         // Cleaner types unless using union discrimination
        enumsAsTypes: true,         // String unions, not JS enum objects
      },
    },
  },
  ignoreNoDocuments: true,
}
export default config
```

Key: `maybeValue: 'T | null'` — GraphQL returns `null`, never `undefined`. This must match.

### 2.2 WPGraphQL Introspection

Enable "Public Introspection" in WPGraphQL Settings for codegen to work. Disable in production.

### 2.3 Environment Variables

```env
NEXT_PUBLIC_WORDPRESS_GRAPHQL_URL=https://your-site.com/graphql
NEXTJS_AUTH_REFRESH_TOKEN=your-jwt-token
NEXTJS_PREVIEW_SECRET=your-preview-secret
NEXTJS_REVALIDATION_SECRET=your-revalidation-secret
```

`NEXT_PUBLIC_` = client-exposed. Everything else = server-only.

---

## Level 3: Schema Extension (Advanced)

### 3.1 register_graphql_field for Computed Data

Use for derived/computed data that doesn't come from ACF or post meta.

```php
add_action('graphql_register_types', function() {
    register_graphql_field('Post', 'estimatedReadingTime', [
        'type'        => 'Int',
        'description' => 'Estimated reading time in minutes',
        'resolve'     => function(\WPGraphQL\Model\Post $post) {
            $content = $post->contentRendered;
            if (empty($content)) return 0;
            return (int) ceil(str_word_count(strip_tags($content)) / 200);
        },
    ]);
});
```

### 3.2 ACF vs Programmatic: Decision Tree

| Criterion | Use ACF | Use register_graphql_field |
|-----------|---------|--------------------------|
| Data source | Editorial input (post meta) | Computed, third-party API, SQL |
| Editor needs UI? | Yes | No |
| Dependencies | ACF Pro + WPGraphQL for ACF | None (native WPGraphQL) |
| Performance | Relies on meta queries | You control the resolver |

---

## Performance: Make It Fast

- Use Next.js cache tags: `next: { tags: [slug, 'graphql', 'type:post'] }`
- Use `revalidateTag('wordpress')` for on-demand ISR instead of time-based revalidation
- Request only the fields you need — no `SELECT *` equivalent
- Include `id` and `databaseId` for client-side cache normalization

## Observability: Know It's Working

- Log GraphQL errors from `response.errors` — they arrive with HTTP 200
- Track `x-cache` response headers to detect CDN cache misses
- Use `GRAPHQL_DEBUG=true` in dev only, never production
- Monitor codegen output for schema drift after WP plugin updates

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Always WPGraphQL, Never REST API
**You will be tempted to:** use `/wp-json/wp/v2/posts` because "it's already there."
**Why that fails:** REST over-fetches (huge payloads) and under-fetches (requires waterfall requests for authors/media). WPGraphQL returns exactly what you ask for in one request.
**The right way:** Always use the `/graphql` endpoint with typed queries.

### Rule 2: Never Forget show_in_graphql
**You will be tempted to:** register a CPT and assume WPGraphQL exposes it automatically.
**Why that fails:** WPGraphQL uses strict opt-in for security. The CPT exists in WordPress but is invisible in GraphQL.
**The right way:** Always include `show_in_graphql`, `graphql_single_name`, and `graphql_plural_name`.

### Rule 3: Never Throw from fetchGraphQL
**You will be tempted to:** `throw new Error()` when GraphQL returns errors.
**Why that fails:** Throwing triggers the nearest `error.tsx` boundary, replacing the entire UI. The user sees a full-page error instead of a graceful fallback.
**The right way:** Return `{ data: undefined, errors }` and let the component decide how to degrade.

### Rule 4: Never Use Cookie-Based WP Auth
**You will be tempted to:** rely on WordPress session cookies for authenticated requests.
**Why that fails:** Next.js runs on a different domain than WordPress. Cookies don't cross domains. WordPress nonce validation requires server-side PHP context.
**The right way:** Use JWT tokens via `Authorization: Bearer` header, server-side only.

### Rule 5: Never Hardcode API URLs
**You will be tempted to:** write `fetch('https://mysite.com/graphql')` directly in components.
**Why that fails:** Breaks across environments (local, staging, production). Leaks infrastructure details into the codebase.
**The right way:** Always use `process.env.NEXT_PUBLIC_WORDPRESS_GRAPHQL_URL`.
