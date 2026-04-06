---
name: mx-supa-edge
description: Use when writing Supabase Edge Functions, working with the Deno runtime, or deploying serverless functions. Also use when the user mentions 'edge function', 'Deno', 'Deno.serve', 'Deno.env', 'supabase functions', 'import_map', 'deno.json', 'cold start', '_shared', 'CORS', or any file in supabase/functions/.
---

# Supabase Edge Functions — Deno Runtime for AI Coding Agents

**This skill loads for ANY Supabase Edge Function work.** It prevents the most common AI failures: writing Node.js code in a Deno runtime, bloated dependencies causing cold starts, missing error handling, and using process.env instead of Deno.env.get().

## When to also load
- Database queries from Edge Functions → `mx-supa-queries`
- Auth/RLS in Edge Functions → `mx-supa-auth`
- Client SDK for Edge Functions → `mx-supa-client`
- Monitoring Edge Functions → `mx-supa-observability`

---

## Level 1: Patterns That Always Work (Beginner)

### Deno is NOT Node.js — the critical differences

| Node.js (WRONG) | Deno/Supabase (RIGHT) |
|-----------------|----------------------|
| `const x = require('x')` | `import x from 'npm:x'` |
| `process.env.KEY` | `Deno.env.get('KEY')` |
| `node_modules/` | URL imports or `deno.json` imports |
| `exports.handler = async (event) => {}` | `Deno.serve(async (req) => {})` |
| `module.exports` | `export default` / `export` |
| `package.json` | `deno.json` (per-function) |
| `fs.readFileSync()` | `Deno.readFileSync()` |

### The correct Edge Function structure

```typescript
// supabase/functions/my-func/index.ts
import { createClient } from 'npm:@supabase/supabase-js@2'
import "jsr:@supabase/functions-js/edge-runtime.d.ts"

Deno.serve(async (req: Request) => {
  try {
    // 1. Guard HTTP method
    if (req.method !== 'POST') {
      return new Response('Method Not Allowed', { status: 405 })
    }

    // 2. Environment variables via Deno.env
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseKey)

    // 3. Parse request body
    const { name } = await req.json()

    // 4. Database operation
    const { data, error } = await supabase
      .from('users')
      .select('id, email')
      .eq('name', name)

    if (error) throw error

    // 5. Web Standard Response
    return new Response(JSON.stringify(data), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    })
  } catch (err) {
    console.error('Function error:', err)
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})
```

### Always wrap Deno.serve in try/catch

Without try/catch, unhandled errors produce generic 500 WORKER_ERROR with no debugging info.

### CORS handling pattern

```typescript
// supabase/functions/_shared/cors.ts
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// In your function:
import { corsHeaders } from '../_shared/cors.ts'

Deno.serve(async (req) => {
  // Handle preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // ... your logic ...
  return new Response(JSON.stringify(data), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
```

---

## Level 2: Optimization & Production (Intermediate)

### Dependency management — deno.json per function

```json
// supabase/functions/my-func/deno.json
{
  "imports": {
    "@supabase/supabase-js": "npm:@supabase/supabase-js@2",
    "lodash-es": "npm:lodash-es@4.17.21"
  }
}
```

Each function should have its OWN `deno.json`. A global `import_map.json` is legacy — causes cross-function dependency pollution.

### _shared directory for reusable code

```
supabase/functions/
  _shared/
    supabaseClient.ts    # Shared client factory
    cors.ts              # CORS headers
    types.ts             # Shared type definitions
  my-func/
    index.ts
    deno.json
  another-func/
    index.ts
    deno.json
```

Folders prefixed with `_` are NOT deployed as standalone endpoints.

### Cold start optimization

| Technique | Impact | How |
|-----------|--------|-----|
| Minimize dependencies | High | Import only what you need (`lodash-es` not `lodash`) |
| S3 persistent storage | Up to 97% faster | Mount bucket at `/s3/bucket-name` for heavy assets |
| Combine related routes | Medium | One function handles multiple endpoints → stays warm |
| `x-region` header | Medium | Force execution near your database region |
| Lazy dependency evaluation | Auto | Use CLI v1.192.5+ (auto-optimized) |

### Status codes you must know

| Code | Name | Meaning |
|------|------|---------|
| 401 | Unauthorized | Invalid/missing JWT |
| 404 | Not Found | Function doesn't exist |
| 500 | WORKER_ERROR | Uncaught exception in your code |
| 503 | BOOT_ERROR | Function failed to start (syntax/import error) |
| 504 | Gateway Timeout | Exceeded wall clock limit (150s free, 400s paid) |
| 546 | WORKER_LIMIT | Memory (256MB) or CPU (2s active) limit exceeded |

### Client-side error handling

```typescript
import { FunctionsHttpError, FunctionsRelayError, FunctionsFetchError } from '@supabase/supabase-js'

const { data, error } = await supabase.functions.invoke('my-func', { body: { id: 1 } })

if (error) {
  if (error instanceof FunctionsHttpError) {
    const serverError = await error.context.json()
    console.error('Server error:', serverError.error)
  } else if (error instanceof FunctionsRelayError) {
    console.error('Network/relay error:', error.message)
  } else if (error instanceof FunctionsFetchError) {
    console.error('Fetch failed:', error.message)
  }
}
```

---

## Level 3: Advanced Patterns (Advanced)

### Webhook handling (no JWT verification)

Deploy with `--no-verify-jwt` for webhooks from external services:
```bash
supabase functions deploy stripe-webhook --no-verify-jwt
```

The function must manually verify the webhook signature:
```typescript
Deno.serve(async (req) => {
  const signature = req.headers.get('Stripe-Signature')
  // Verify signature manually...

  // Use admin client (service_role) since no user JWT
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  // Idempotent: check if already processed
  const event = await req.json()
  const { data: existing } = await supabase
    .from('processed_events')
    .select('id')
    .eq('event_id', event.id)
    .single()

  if (existing) return new Response('Already processed', { status: 200 })

  // Process and record
  await supabase.from('processed_events').insert({ event_id: event.id })
  return new Response('OK', { status: 200 })
})
```

### Database connection pooling

Edge Functions scale horizontally — each isolate needs its own connection. Use the Supabase client (PostgREST) or the transaction pooler URL (port 6543), NEVER direct Postgres connections.

### Local debugging

```bash
# Serve all functions locally with hot reload
supabase functions serve

# Debug with Chrome DevTools (v8 inspector)
supabase functions serve --inspect
# Then open chrome://inspect in Chrome
```

---

## Performance: Make It Fast

1. **Import only what you need** — `import { get } from 'lodash-es'` not `import * as _ from 'lodash'`
2. **Mount S3 storage for heavy assets** — avoids re-downloading on cold boot
3. **Keep functions under 1 second execution** — offload heavy work to background jobs
4. **Use `x-region` header** to run functions near your database
5. **Each function gets its own `deno.json`** — prevents bloated shared dependency trees
6. **Design for idempotency** — webhooks get retried, handle duplicate invocations safely

## Observability: Know It's Working

1. **Dashboard metrics** — CPU, memory, execution time per function
2. **Invocations tab** — request/response data, status codes, duration
3. **Logs tab** — platform events, exceptions, console output
4. **100 events per 10 seconds log limit** — aggregate logs, don't log per-item in loops
5. **Sentry Deno SDK** — `@sentry/deno` for production error tracking
6. **Local debugging** — `supabase functions serve --inspect` + Chrome DevTools
7. **Logs Explorer** — SQL-queryable logs across auth, edge, postgres layers

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No require()
**You will be tempted to:** Write `const x = require('x')` because Node.js is your training data.
**Why that fails:** `require` does not exist in Deno. The function crashes immediately with `ReferenceError: require is not defined`.
**The right way:** Use ES Module imports: `import x from 'npm:x'` or URL imports.

### Rule 2: No process.env
**You will be tempted to:** Write `process.env.SUPABASE_URL` because it's universal JavaScript.
**Why that fails:** `process` is undefined in Deno. The function crashes on boot (503 BOOT_ERROR).
**The right way:** `Deno.env.get('SUPABASE_URL')` — the Deno-native environment API.

### Rule 3: No Bloated Imports
**You will be tempted to:** Import entire libraries (`import * as _ from 'lodash'`) for one utility function.
**Why that fails:** The entire library is bundled into the function, dramatically increasing cold start time and potentially hitting the 10MB source limit.
**The right way:** Import specific modules. For heavy assets (SQLite DBs, ML models), use S3 persistent storage mounting.

### Rule 4: No Silent Failures
**You will be tempted to:** Skip the try/catch because "the logic is simple."
**Why that fails:** Any unhandled error produces a generic 500 WORKER_ERROR with zero debugging information in production.
**The right way:** ALWAYS wrap Deno.serve handler logic in try/catch. Return proper HTTP status codes with JSON error messages.

### Rule 5: No Log Spam in Loops
**You will be tempted to:** Put `console.log()` inside a `for` loop processing 500 items.
**Why that fails:** The 100 events/10 seconds log limit is hit instantly. Later logs (including errors) are silently dropped.
**The right way:** Aggregate logging: `console.log(\`Processing ${items.length} items\`)` before the loop, not inside it.
