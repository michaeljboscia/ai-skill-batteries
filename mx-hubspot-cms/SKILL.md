---
name: mx-hubspot-cms
description: "HubSpot CMS API — blog posts API, site pages API, landing pages API, HubDB tables API, source code API templates modules, URL redirects API, domains API, CMS content management"
---

# HubSpot CMS — Pages, Blog, HubDB, Templates for AI Coding Agents

**Load when managing CMS content programmatically.**

## When to also load
- `mx-hubspot-core` — SDK setup (co-default)
- `mx-hubspot-marketing` — landing pages in campaigns

---

## Level 1: Content CRUD (Beginner)

### Pattern 1: CMS Content APIs

| API | Endpoint Pattern | Key Features |
|-----|-----------------|-------------|
| Blog Posts | Blog Posts API | CRUD, multi-language, scheduling |
| Site Pages | Site Pages API | Draft/published, scheduling, batch create |
| Landing Pages | Landing Pages API | Same as site pages, multi-language groups |
| HubDB | HubDB Tables API | Relational tables, draft/published, public access |
| Source Code | Source Code API | Templates, modules, CSS, JS, HubL validation |
| URL Redirects | URL Redirects API | 301/302/305, pattern matching, precedence |
| Domains | Domains API | Read-only, primary flags, SSL status |

### Pattern 2: Draft vs Published

All CMS content supports draft/published model. Edit drafts without affecting live content. Publish immediately or schedule for future.

### Pattern 3: HubDB for Dynamic Content

HubDB = relational data tables for CMS dynamic pages. Supports draft/published versions. Public tables accessible without auth (by account ID). Use for: dynamic CMS pages, feedback storage, programmable email data.

---

## Level 2: Templates and Redirects (Intermediate)

### Pattern 4: Source Code API

Upload, download, and validate CMS assets (templates, modules, CSS, JS). Supports draft/published environments. Validates HubL syntax. Recommended over legacy v2 template API.

### Pattern 5: URL Redirects

Types: 301 (permanent), 302 (temporary), 305 (proxy). Supports pattern matching, query string matching, and precedence control.

---

## Performance: Make It Fast

### Batch Page Creation
Use batch endpoints for creating multiple site pages. More efficient than individual calls.

## Observability: Know It's Working

### CMS Content Audit API
Track content changes by type, time period, object, or user. Separate from general audit logs.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never edit live content without using drafts
**You will be tempted to:** Directly update published pages to save time.
**Why that fails:** Visitors see half-finished edits. No rollback if something breaks.
**The right way:** Edit the draft, review, then publish.

### Rule 2: Never use v2 template API for new work
**You will be tempted to:** Use legacy template endpoints because they're simpler.
**Why that fails:** v2 is deprecated. Source Code API is the modern replacement with better features.
**The right way:** Use Source Code API for all template/module management.
