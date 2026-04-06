---
name: mx-wp-auth
description: Use when implementing authentication, JWT tokens, preview mode, draft content, application passwords, or headless auth flows in WordPress with WPGraphQL and Next.js. Also use when the user mentions 'JWT', 'preview mode', 'draft mode', 'draftMode', 'asPreview', 'application passwords', 'headless login', or 'revalidation webhook'.
---

# Headless WordPress Auth & Preview — JWT, Draft Mode, Revalidation for AI Coding Agents

**Loads when implementing authentication or preview/draft functionality in headless WordPress.**

## When to also load
- `mx-wp-core` — fetchGraphQL, codegen, architecture
- `mx-wp-deploy` — environment variables, webhook setup
- `mx-nextjs-middleware` — auth redirects, middleware patterns

---

## Level 1: Auth Method Selection (Beginner)

### 1.1 Auth Method Decision Tree

| Method | When to Use | Plugin | Auth Header |
|--------|------------|--------|-------------|
| JWT Auth | Standard headless, preview, mutations | `wp-graphql-jwt-authentication` | `Authorization: Bearer {token}` |
| Application Passwords | Server-to-server, SSR, simple setup | None (WP core 5.6+) | `Authorization: Basic base64(user:pass)` |
| Headless Login | OAuth2/OIDC, NextAuth, social login | `wp-graphql-headless-login` | Varies by provider |
| Cookie Auth | **NEVER USE HEADLESS** | N/A | N/A |

### 1.2 JWT Setup

**WordPress side:**
```php
// wp-config.php — add BEFORE "That's all, stop editing!"
define('GRAPHQL_JWT_AUTH_SECRET_KEY', 'your-64-char-cryptographically-secure-string');
```

**Apache — preserve Authorization header:**
```apache
# .htaccess
SetEnvIf Authorization "(.*)" HTTP_AUTHORIZATION=$1
```

**GraphQL login mutation:**
```graphql
mutation LoginUser {
  login(input: { username: "editor", password: "password" }) {
    authToken      # Short-lived, use for requests
    refreshToken   # Long-lived, use to get new authToken
    user { id, name }
  }
}
```

### 1.3 Authenticated Fetch

```typescript
export async function fetchGraphQL(query: string, variables = {}, token?: string) {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (token) headers['Authorization'] = `Bearer ${token}`

  const res = await fetch(process.env.NEXT_PUBLIC_WORDPRESS_GRAPHQL_URL!, {
    method: 'POST',
    headers,
    body: JSON.stringify({ query, variables }),
  })
  return res.json()
}
```

---

## Level 2: Preview Mode (Intermediate)

### 2.1 The Complete Preview Flow

```
Editor clicks "Preview" in WP Admin
    ↓
WP redirects to: /api/draft?secret=XXX&id=123
    ↓
Next.js API route verifies secret
    ↓
Calls draftMode().enable()  →  Sets __prerender_bypass cookie
    ↓
Redirects to post URL
    ↓
Page component checks draftMode().isEnabled
    ↓
If true: fetches draft via GraphQL with asPreview:true + DATABASE_ID
```

### 2.2 Draft API Route

```typescript
// app/api/draft/route.ts
import { draftMode } from 'next/headers'
import { redirect } from 'next/navigation'

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url)
  const secret = searchParams.get('secret')
  const id = searchParams.get('id')
  const slug = searchParams.get('slug')

  // Verify secret — prevents unauthorized cache bypass (DDoS vector)
  if (secret !== process.env.NEXTJS_PREVIEW_SECRET || !id) {
    return new Response('Invalid token', { status: 401 })
  }

  const draft = await draftMode()
  draft.enable()

  redirect(`/blog/${slug}?previewId=${id}`)
}
```

### 2.3 Querying Draft Content

Drafts have NO URI. Query by `DATABASE_ID` with `asPreview: true`.

**BAD — Querying draft by slug (returns null):**
```graphql
# FAILS: Drafts don't have URIs
query { post(id: "my-draft-post", idType: SLUG) { title } }
```

**GOOD — Query by DATABASE_ID with asPreview:**
```graphql
query PreviewPost($id: ID!) {
  post(id: $id, idType: DATABASE_ID, asPreview: true) {
    databaseId
    title
    content(format: RENDERED)
    status
    featuredImage { node { sourceUrl, altText, mediaDetails { height, width } } }
  }
}
```

### 2.4 Page Component with Draft Mode

```typescript
// app/blog/[slug]/page.tsx
import { draftMode } from 'next/headers'

export default async function BlogPost({ params, searchParams }: {
  params: Promise<{ slug: string }>
  searchParams: Promise<{ previewId?: string }>
}) {
  const { slug } = await params
  const { previewId } = await searchParams
  const { isEnabled } = await draftMode()

  let post
  if (isEnabled && previewId) {
    const token = process.env.NEXTJS_AUTH_REFRESH_TOKEN!
    post = await getPreview(previewId, token)  // Authenticated, asPreview:true
  } else {
    post = await getPostBySlug(slug)           // Public, by slug
  }

  if (!post) return notFound()
  return <PostContent post={post} />
}
```

---

## Level 3: On-Demand Revalidation (Advanced)

### 3.1 revalidatePath vs revalidateTag

| Method | Scope | Best For |
|--------|-------|----------|
| `revalidatePath('/blog/my-post')` | Single URL | Simple sites, few affected pages |
| `revalidateTag('post-123')` | All pages using that tag | Complex sites — one webhook purges post page + archive + author index |

`revalidateTag` is superior for headless WP because updating a post affects multiple pages.

### 3.2 Next.js Revalidation Endpoint

```typescript
// app/api/revalidate/route.ts
import { revalidateTag } from 'next/cache'
import { NextResponse } from 'next/server'

export async function POST(request: Request) {
  const secret = request.headers.get('x-revalidate-secret')
  if (secret !== process.env.NEXTJS_REVALIDATION_SECRET) {
    return NextResponse.json({ message: 'Unauthorized' }, { status: 401 })
  }

  const { tag, path } = await request.json()

  if (tag) {
    revalidateTag(tag)
    return NextResponse.json({ revalidated: true, tag, now: Date.now() })
  }
  if (path) {
    const { revalidatePath } = await import('next/cache')
    revalidatePath(path)
    return NextResponse.json({ revalidated: true, path, now: Date.now() })
  }

  return NextResponse.json({ message: 'Missing tag or path' }, { status: 400 })
}
```

### 3.3 WordPress Webhook (save_post hook)

```php
// wp-content/mu-plugins/nextjs-revalidate.php
add_action('save_post', function(int $post_id, WP_Post $post) {
    if (wp_is_post_autosave($post_id) || wp_is_post_revision($post_id)) return;
    if ($post->post_status !== 'publish') return;

    $endpoint = defined('NEXTJS_FRONTEND_URL')
        ? NEXTJS_FRONTEND_URL . '/api/revalidate'
        : '';
    $secret = defined('NEXTJS_REVALIDATION_SECRET')
        ? NEXTJS_REVALIDATION_SECRET
        : '';

    wp_remote_post($endpoint, [
        'headers' => [
            'Content-Type'       => 'application/json',
            'x-revalidate-secret' => $secret,
        ],
        'body'     => wp_json_encode(['tag' => 'post-' . $post_id]),
        'blocking' => false,  // Don't stall WordPress admin
    ]);
}, 10, 2);
```

---

## Performance: Make It Fast

- Use `revalidateTag` over `revalidatePath` — surgical cache purge
- Set `blocking => false` on WP webhooks — don't slow down the editor
- Cache JWT tokens in HttpOnly cookies — avoid re-authenticating per request
- For preview, always use `DATABASE_ID` — avoids slug resolution overhead

## Observability: Know It's Working

- Log webhook delivery success/failure in WordPress error log
- Monitor `/api/revalidate` for 401s (secret mismatch) and 500s (revalidation failures)
- Check `__prerender_bypass` cookie presence when debugging preview mode
- Verify draft queries return `status: "draft"` — if `null`, auth token is invalid or expired

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Use Cookie-Based WordPress Auth
**You will be tempted to:** rely on `wordpress_logged_in_*` cookies for headless auth.
**Why that fails:** Next.js and WordPress run on different domains. SameSite cookie policies block cross-origin cookies. WordPress nonce validation requires PHP context.
**The right way:** JWT tokens via `Authorization: Bearer` header, or Application Passwords via `Authorization: Basic`.

### Rule 2: Never Query Drafts by URI
**You will be tempted to:** query `post(id: "my-draft", idType: SLUG)` for preview.
**Why that fails:** WordPress doesn't assign permanent URIs/slugs until a post is published. Draft queries by slug return `null`.
**The right way:** Pass `DATABASE_ID` from WordPress and query with `asPreview: true`.

### Rule 3: Never Expose Auth Tokens in Client Components
**You will be tempted to:** pass JWT tokens to `"use client"` components or store them in localStorage.
**Why that fails:** Any XSS vulnerability exposes the token, granting full API access to your WordPress backend.
**The right way:** All auth logic in Server Components, Route Handlers, or encrypted HttpOnly cookies only.

### Rule 4: Never Send Credentials in Query Parameters
**You will be tempted to:** pass tokens as `?token=xxx` in URLs.
**Why that fails:** Query params are logged in server access logs, browser history, and proxy caches. Tokens leak everywhere.
**The right way:** Use HTTP headers (`Authorization: Bearer` or custom `x-revalidate-secret`).
