---
name: mx-supa-client
description: Use when initializing the Supabase client SDK, handling auth tokens, managing subscriptions, working with Storage, or using the Python client. Also use when the user mentions 'createClient', 'supabase-js', 'supabase-py', 'anon key', 'service_role', '@supabase/ssr', 'getUser', 'getSession', 'subscription', 'unsubscribe', 'removeChannel', 'storage', 'upload', 'signed URL', 'TUS', 'image transformation', or 'supabase-py vs supabase'.
---

# Supabase Client SDK — Integration Patterns for AI Coding Agents

**This skill loads for ANY Supabase client SDK work.** It prevents the most common AI failures: service_role in browser code, missing subscription cleanup, installing the wrong Python package, and using getSession for auth decisions.

## When to also load
- RLS policies → `mx-supa-auth`
- Realtime channels → `mx-supa-realtime`
- Query patterns → `mx-supa-queries`
- Edge Functions → `mx-supa-edge`

---

## Level 1: Client Initialization (Beginner)

### anon key vs service_role — the security boundary

| Key | Where | RLS | Security |
|-----|-------|-----|----------|
| `anon` | Browser, mobile, client-side | Enforced | Safe to expose publicly |
| `service_role` | Server ONLY (Edge Functions, backends) | **BYPASSED** | NEVER expose in client code |

```typescript
// BROWSER — anon key only
import { createClient } from '@supabase/supabase-js'
const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
)

// SERVER ADMIN — service_role with auth disabled
const supabaseAdmin = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!,
  { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } }
)
```

### SSR — initialize per-request, never module-level

```typescript
// BAD: Shared client leaks sessions between users
export const supabase = createServerClient(URL, KEY, { cookies })

// GOOD: Factory function creates fresh client per request
export async function createClient() {
  const cookieStore = cookies()
  return createServerClient(URL, KEY, {
    cookies: {
      get(name) { return cookieStore.get(name)?.value },
      set(name, value, options) { cookieStore.set({ name, value, ...options }) },
      remove(name, options) { cookieStore.set({ name, value: '', ...options }) },
    }
  })
}
```

Use `@supabase/ssr` for Next.js/Nuxt SSR with cookie-based PKCE auth.

### TypeScript — generate and use database types

```bash
supabase gen types typescript --project-id "your-project-id" > types/supabase.ts
```

```typescript
import { Database } from './types/supabase'
const supabase = createClient<Database>(URL, KEY) // Full type safety
```

### Python — correct package and async client

```python
# Install: pip install supabase (NOT supabase-py — that's outdated)

# Sync client
from supabase import create_client, Client
supabase: Client = create_client(url, key)

# Async client (REQUIRED for FastAPI/async frameworks)
from supabase import acreate_client, AsyncClient
supabase: AsyncClient = await acreate_client(url, key)
```

Default row limit is 1000. Use `.range(0, 999)` for pagination.

---

## Level 2: Subscriptions & Auth (Intermediate)

### Subscription cleanup — prevent memory leaks

```typescript
// GOOD: Subscribe in useEffect, cleanup on unmount
useEffect(() => {
  const channel = supabase
    .channel('room-1')
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages' },
      (payload) => setMessages(prev => [...prev, payload.new])
    )
    .subscribe()

  return () => { supabase.removeChannel(channel) } // MANDATORY cleanup
}, [])
```

Without cleanup: memory leaks, "state update on unmounted component" warnings, ChannelRateLimitReached errors.

### Auth validation — getUser vs getSession

```typescript
// BAD: getSession reads unverified local storage — spoofable
const { data: { session } } = await supabase.auth.getSession()
await performSecureAction(session.user.id) // VULNERABLE

// GOOD: getUser validates JWT with Auth server
const { data: { user }, error } = await supabase.auth.getUser()
if (error || !user) return unauthorized()
await performSecureAction(user.id) // SECURE
```

| Method | Validates with server? | Use for |
|--------|----------------------|---------|
| `getSession()` | NO | UI display only (name, avatar) |
| `getUser()` | YES | All security decisions |
| `getClaims()` | YES (local signature) | JWT claim validation without network call |

---

## Level 3: Storage & Advanced (Advanced)

### Upload method selection

| File Size | Method | Resumable? |
|-----------|--------|-----------|
| < 6MB | Standard upload | No |
| > 6MB | TUS resumable upload | Yes |
| Server-side large files | S3 multipart | No (speed priority) |

```typescript
// Standard upload
await supabase.storage.from('avatars').upload('path/file.jpg', file, {
  cacheControl: '3600',
  upsert: false // Prevent stale CDN content
})

// Get public URL with image transformation
const { data } = supabase.storage.from('avatars')
  .getPublicUrl('profile.jpg', {
    transform: { width: 200, height: 200, resize: 'cover', format: 'webp' }
  })
```

### Signed URLs for private files

```typescript
// Generate server-side, cache client-side for duration
const { data } = await supabase.storage.from('private-docs')
  .createSignedUrl('report.pdf', 3600) // 1 hour expiry
```

### Storage RLS

Policies on `storage.objects` table. Upsert requires SELECT + UPDATE + INSERT policies.

### Public vs Private buckets

- **Public**: Better CDN cache hit rates, `getPublicUrl()` for access
- **Private**: Requires JWT auth header or signed URLs

---

## Performance: Make It Fast

1. **Singleton client on browser** — initialize once outside components
2. **Per-request client on server** — prevents session leaks between users
3. **TypeScript types from CLI** — compile-time schema validation
4. **Subscription cleanup** — prevents connection pool exhaustion
5. **Image transformation via URL params** — WebP auto-conversion reduces payload
6. **Public buckets for static assets** — better CDN cache hit rates
7. **Cache-Control headers on uploads** — high max-age for immutable assets

## Observability: Know It's Working

1. **ChannelRateLimitReached errors** — leaked subscriptions consuming quota
2. **401 errors on API calls** — expired tokens, wrong key type
3. **cf-cache-status header** — monitor CDN HIT/MISS on storage assets
4. **Auth error types** — AuthApiError (server), CustomAuthError (client)
5. **Storage error codes** — error.status, error.statusCode for debugging

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No service_role in Browser
**You will be tempted to:** Use the service_role key in client code because "it's faster without RLS."
**Why that fails:** The key is in the JavaScript bundle. Anyone can extract it and gain full database access, bypassing all security.
**The right way:** Anon key only in browser. Service_role only in server-side code with auth options disabled.

### Rule 2: No Missing Subscription Cleanup
**You will be tempted to:** Subscribe to Realtime channels without a cleanup function because "the component stays mounted."
**Why that fails:** Navigation, re-renders, and hot-reload create orphaned channels. Eventually hits ChannelRateLimitReached.
**The right way:** Every `.subscribe()` in useEffect MUST have a `return () => supabase.removeChannel(channel)`.

### Rule 3: No supabase-py Package
**You will be tempted to:** `pip install supabase-py` because it appears in older tutorials.
**Why that fails:** `supabase-py` is outdated/legacy. The official package is `supabase`.
**The right way:** `pip install supabase`. Use `acreate_client()` for async frameworks.

### Rule 4: No getSession for Security
**You will be tempted to:** Use `getSession()` in server actions because it's faster.
**Why that fails:** `getSession()` reads unverified local storage. Attackers can forge cookies to impersonate any user.
**The right way:** `getUser()` for security decisions. `getSession()` only for non-sensitive UI rendering.

### Rule 5: No Module-Level Server Client
**You will be tempted to:** Initialize the Supabase client at module scope in a Next.js server file.
**Why that fails:** In serverless/SSR, module-level state is shared across concurrent requests. User A's session leaks to User B.
**The right way:** Create client inside the request handler using `@supabase/ssr`.
