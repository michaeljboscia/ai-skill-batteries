---
name: mx-wp-deploy
description: Use when setting up headless WordPress hosting, local development with wp-env, Docker, CI/CD deployment with Vercel, environment variable management, or webhook configuration. Also use when the user mentions 'wp-env', 'WP Engine Atlas', 'Kinsta', 'Vercel deployment', 'preview environments', '.env.local', or 'headless hosting'.
---

# Headless WordPress Deployment — Hosting, CI/CD, Local Dev for AI Coding Agents

**Loads when deploying or configuring infrastructure for headless WordPress + Next.js.**

## When to also load
- `mx-wp-core` — architecture, fetchGraphQL
- `mx-wp-auth` — preview mode, revalidation webhooks
- `mx-nextjs-deploy` — Next.js deployment patterns

---

## Level 1: Local Development (Beginner)

### 1.1 wp-env Setup

`@wordpress/env` spins up WordPress + MySQL in Docker from a single config file.

```bash
npm install -g @wordpress/env
```

### 1.2 .wp-env.json Configuration

```json
{
  "core": null,
  "port": 8888,
  "plugins": [
    "https://downloads.wordpress.org/plugin/wp-graphql.zip",
    "https://downloads.wordpress.org/plugin/advanced-custom-fields.zip",
    "https://github.com/wp-graphql/wp-graphql-acf/archive/refs/heads/main.zip"
  ],
  "config": {
    "WP_DEBUG": true,
    "WP_DEBUG_LOG": true,
    "GRAPHQL_DEBUG": true
  }
}
```

```bash
wp-env start   # Starts WP at http://localhost:8888
wp-env stop    # Stops containers
wp-env clean   # Resets to fresh state
```

### 1.3 Local .env.local

```env
NEXT_PUBLIC_WORDPRESS_GRAPHQL_URL=http://localhost:8888/graphql
NEXTJS_AUTH_REFRESH_TOKEN=local-dev-token
NEXTJS_PREVIEW_SECRET=local-preview-secret
NEXTJS_REVALIDATION_SECRET=local-revalidation-secret
```

Generate a secure secret:
```bash
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

---

## Level 2: Hosting Decision (Intermediate)

### 2.1 Hosting Decision Tree

| Host | WP Backend | Frontend | Cost (base) | Best For |
|------|-----------|----------|-------------|----------|
| **Vercel + Managed WP** | Cloudways/Kinsta/WPE | Vercel | ~$34-55/mo | Best Next.js features, most flexible |
| **WP Engine Atlas** | WPE Managed | WPE Node.js | ~$49+/mo | Single vendor, Faust.js ecosystem |
| **Kinsta** | Kinsta WP | Kinsta App Hosting | ~$55/mo | Google Cloud, MyKinsta dashboard |
| **Self-hosted** | Your server | Your server | ~$10-40/mo | Full control, high DevOps overhead |

### 2.2 Key Hosting Considerations

- **Vercel + managed WP** is the industry standard — native Next.js edge features, preview deployments, ISR
- **WP Engine Atlas** ties you to Faust.js — diverges from vanilla Next.js patterns
- **Kinsta** gives usage-based scaling on both layers — good for high-traffic blogs
- **Self-hosted** requires managing SSL, CDN, backups, security patches yourself

---

## Level 3: CI/CD with Vercel (Advanced)

### 3.1 Deployment Pipeline

```
Developer pushes to feature branch
    ↓
GitHub webhook → Vercel Build
    ↓
PR opened → Preview Deployment (unique URL per PR)
    ↓
PR merged to main → Production Deployment
```

### 3.2 Environment Variables per Environment

| Variable | Production | Preview | Development |
|----------|-----------|---------|-------------|
| `NEXT_PUBLIC_WORDPRESS_GRAPHQL_URL` | `https://api.site.com/graphql` | `https://staging.api.site.com/graphql` | `http://localhost:8888/graphql` |
| `NEXTJS_REVALIDATION_SECRET` | production secret | staging secret | local secret |
| `NEXTJS_PREVIEW_SECRET` | production secret | staging secret | local secret |

Configure in Vercel Dashboard → Settings → Environment Variables. Select which environments each variable applies to.

### 3.3 WordPress Webhook for Revalidation

**Option A: Custom MU-Plugin** (recommended — lightweight, version-controlled)

See `mx-wp-auth` skill for the full `save_post` webhook implementation.

**Option B: WP Webhooks Plugin** (no-code)

1. Install WP Webhooks
2. Configure "Post published" trigger
3. Target URL: `https://your-site.com/api/revalidate`
4. Custom header: `x-revalidate-secret: your-secret`
5. Payload: `{ "tag": "post-{post_id}" }`

### 3.4 Env Var Security Rules

| Prefix | Exposure | Use For |
|--------|----------|---------|
| `NEXT_PUBLIC_*` | Client + Server | Public GraphQL URL, site config |
| No prefix | Server only | Secrets, tokens, passwords |

**NEVER put secrets in `NEXT_PUBLIC_` variables.** They're bundled into client JavaScript.

---

## Performance: Make It Fast

- Use Vercel Preview Deployments for PR review — don't deploy to production untested
- Enable Redis object cache on WordPress host (WPE, Kinsta include this)
- Use wp-env for local dev — consistent environment across team members
- Separate WP and frontend scaling — WP needs PHP workers, Next.js needs edge functions

## Observability: Know It's Working

- Monitor Vercel deployment logs for build failures
- Check WordPress error log for webhook delivery failures
- Verify environment variables are set per environment in Vercel dashboard
- Test revalidation endpoint manually: `curl -X POST -H "x-revalidate-secret: XXX" -d '{"tag":"test"}' https://site.com/api/revalidate`

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Assume Monolithic Deployment
**You will be tempted to:** deploy WordPress and Next.js on the same server.
**Why that fails:** WordPress needs PHP/MySQL. Next.js needs Node.js. They have different scaling profiles, security requirements, and deployment cycles.
**The right way:** Separate hosting for CMS (managed WordPress) and frontend (Vercel/edge platform).

### Rule 2: Never Hardcode API URLs
**You will be tempted to:** write `fetch('https://mysite.com/graphql')` directly in code.
**Why that fails:** Breaks across environments (local, staging, production). Every developer has a different local URL.
**The right way:** Always use `process.env.NEXT_PUBLIC_WORDPRESS_GRAPHQL_URL`.

### Rule 3: Never Put Secrets in NEXT_PUBLIC_ Variables
**You will be tempted to:** use `NEXT_PUBLIC_REVALIDATION_SECRET` for "convenience."
**Why that fails:** `NEXT_PUBLIC_` variables are bundled into client-side JavaScript. Anyone can view-source and extract the secret.
**The right way:** Server-only variables (no prefix) for all secrets, tokens, and passwords.
