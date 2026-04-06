---
name: mx-hubspot-core
description: "HubSpot API client setup, authentication (private apps, OAuth), @hubspot/api-client SDK initialization with Bottleneck rate limiting, numberOfApiCallRetries, properties API, associations v4, CRM search API, pagination, date-based API versioning, batch operations, error handling — any HubSpot API work"
---

# HubSpot Core — SDK, Auth, Properties, Associations, Search for AI Coding Agents

**This skill co-loads with mx-hubspot-perf and mx-hubspot-observability for ANY HubSpot API work.**

## When to also load
- `mx-hubspot-contacts` — working with contact records
- `mx-hubspot-deals` — working with deal records, pipelines, quotes
- `mx-hubspot-companies` — working with company records
- `mx-hubspot-sales` — logging activities, sequences
- `mx-hubspot-marketing` — emails, forms, campaigns, custom events

---

## Level 1: Client Setup and Authentication (Beginner)

### Pattern 1: SDK Initialization with Rate Limiting

**BAD:**
```typescript
const client = new Client({ accessToken: token });
// No rate limiting, no retries — will hit 429s immediately under load
```

**GOOD:**
```typescript
import { Client } from '@hubspot/api-client';

// Token from env — never hardcode
const hubspot = new Client({
  accessToken: process.env.HUBSPOT_TOKEN!,
  numberOfApiCallRetries: 3,  // 0-6, retries on 429 and 5xx
  limiterOptions: {
    maxConcurrent: 5,
    minTime: 110,  // ~9 req/sec (under 10/sec limit)
    id: 'hubspot-client',
  },
});
```

SDK uses Bottleneck internally. Default limiter: `minTime: 1000/9` (~111ms), `maxConcurrent: 6`. Search API has separate, stricter defaults: `minTime: 550`, `maxConcurrent: 3`.

Retry behavior: 5xx delays `200 * retryNumber` ms. 429 TEN_SECONDLY_ROLLING delays 10s.

### Pattern 2: Authentication Decision Table

| Use Case | Auth Method | Config Key |
|----------|-------------|------------|
| Internal integration, single account | Private App token | `accessToken` |
| Public/marketplace app, multi-account | OAuth 2.0 | `accessToken` (from OAuth flow) |
| App developer operations (webhooks, timeline) | Developer API key | `developerApiKey` |

API keys are **DEPRECATED** (retired late 2022). Never use `hapikey` query parameter.

### Pattern 3: Date-Based API Versioning

HubSpot transitioned to `/YYYY-MM/` versioning effective March 30, 2026.

| Version | Status | Support Until |
|---------|--------|---------------|
| `/2026-03/` | Current GA | Sept 2027 |
| `/2026-09-beta/` | Beta preview | Promoted to GA Sept 2026 |
| `/crm/v3/` | Legacy (transition) | Will be deprecated |

GA releases every 6 months (March + September). Each version immutable once GA. 18-month lifecycle: Current (6mo) → Supported (12mo) → Unsupported.

---

## Level 2: Properties, Associations, Search (Intermediate)

### Pattern 4: Properties API — Type/FieldType Decision Table

Create: `POST /crm/v3/properties/{objectType}` — requires `groupName`, `name`, `label`, `type`, `fieldType`.

| Data | `type` | `fieldType` |
|------|--------|-------------|
| Single-line text | `string` | `text` |
| Multi-line text | `string` | `textarea` |
| Number | `number` | `number` |
| Date only | `date` | `date` |
| Boolean | `bool` | `booleancheckbox` |
| Single dropdown | `enumeration` | `select` |
| Multi checkbox | `enumeration` | `checkbox` |
| Computed formula | `number` | `calculation_equation` |

Property groups must exist BEFORE creating properties (no auto-create). Enumerations: max 5,000 options. Calculated properties: set `calculationFormula`, can't be edited in UI after creation.

### Pattern 5: Associations v4

| Category | Type | Example |
|----------|------|---------|
| `HUBSPOT_DEFINED` | Unlabeled (default) | Generic contact-to-company link |
| `HUBSPOT_DEFINED` | Primary | Contact's primary company (only 1) |
| `USER_DEFINED` | Custom label | "Decision Maker" role |

Create labeled: `PUT /crm/v4/objects/{from}/{fromId}/associations/{to}/{toId}` with `associationCategory` + `associationTypeId`.

Batch create: `POST .../batch/create` — **2,000 inputs max**. Batch read: **1,000 inputs max**. Max 10 custom labels per object pairing. Direction matters: Contact-to-Company is different from Company-to-Contact.

### Pattern 6: CRM Search API

```typescript
const results = await hubspot.crm.contacts.searchApi.doSearch({
  filterGroups: [{
    filters: [
      { propertyName: 'lifecyclestage', operator: 'EQ', value: 'customer' },
      { propertyName: 'createdate', operator: 'GT', value: '1704067200000' }
    ]  // AND within group
  }],  // OR between groups (max 5 groups)
  properties: ['email', 'firstname'],
  sorts: [{ propertyName: 'createdate', direction: 'DESCENDING' }],
  limit: 200,
  after: 0,
});
```

**Hard constraints:**
- Max 5 filterGroups x 6 filters each = **18 total filters**
- Max **200 results per page**
- **10,000 result hard cap** — 400 error if you paginate past it
- Rate limit: **5 req/sec** for private apps (separate from general limits)
- Search does NOT return associations (separate call needed)
- `IN`/`NOT_IN` with strings: values MUST be lowercase
- Enumeration values: always case-sensitive

---

## Level 3: Advanced Patterns (Advanced)

### Pattern 7: Bypassing the 10K Search Limit

**BAD:** Standard cursor pagination — breaks at 10,000 records.

**GOOD:** Index-based pagination using `hs_object_id`:

```typescript
async function exhaustiveSearch(baseFilters: any[]) {
  const all: any[] = [];
  let lastId = '0';
  let hasMore = true;

  while (hasMore) {
    const filters = [
      ...baseFilters,
      { propertyName: 'hs_object_id', operator: 'GT', value: lastId }
    ];
    const res = await hubspot.crm.contacts.searchApi.doSearch({
      filterGroups: [{ filters }],
      sorts: [{ propertyName: 'hs_object_id', direction: 'ASCENDING' }],
      properties: ['email', 'hs_object_id'],
      limit: 200,
      after: 0,
    });
    all.push(...res.results);
    hasMore = res.results.length === 200;
    if (hasMore) lastId = res.results[res.results.length - 1].id;
  }
  return all;
}
```

Alternative: segment by `createdate` ranges. For full exports, use Export API (`POST /crm/v3/exports/export/async`).

### Pattern 8: Batch Operations

Always batch when operating on multiple records. Each batch call = 1 rate limit hit regardless of record count.

```typescript
// Batch create contacts (max 100 per call)
await hubspot.crm.contacts.batchApi.create({
  inputs: contacts.map(c => ({ properties: c }))
});

// Batch read by IDs (max 100 per call)
await hubspot.crm.contacts.batchApi.read({
  inputs: ids.map(id => ({ id })),
  properties: ['email', 'firstname'],
});
```

| Object | Batch Create | Batch Read | Batch Update | Assoc Create | Assoc Read |
|--------|-------------|------------|-------------|--------------|------------|
| Limit  | 100         | 100        | 100         | 2,000        | 1,000      |

---

## Performance: Make It Fast

### Cache Static Metadata
Owners, pipelines, properties, and association type IDs change rarely. Fetch once, cache for hours — not per transaction.

### Webhooks Over Polling
Webhooks don't count toward API rate limits. Subscribe to specific `propertyChange` events instead of polling the search API.

### Specify Only Needed Properties
Every unspecified property wastes bytes. Always pass explicit `properties` array in reads and searches.

## Observability: Know It's Working

### Monitor Rate Limit Headers
Check response headers: `X-HubSpot-RateLimit-Daily-Remaining`, `X-HubSpot-RateLimit-Remaining` (burst), `X-HubSpot-RateLimit-Interval-Milliseconds`. Search API has NO standard rate-limit headers — must track client-side.

### Error Response Format
All HubSpot errors return JSON with `message`, `correlationId`, `category`, `errors[]`. Log the `correlationId` — HubSpot support needs it for debugging.

### Common Error Codes
| Code | Meaning | Action |
|------|---------|--------|
| 400 | Bad request (missing fields, wrong types) | Check errors context for details |
| 401 | Invalid/expired token | Refresh OAuth token or check private app |
| 403 | Missing scopes | Add required scopes to app settings |
| 409 | Duplicate record (email exists) | Search first, then update |
| 429 | Rate limit exceeded | Honor Retry-After header, backoff |
| 5xx | Server error | Auto-retry via numberOfApiCallRetries |

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never use deprecated API keys
**You will be tempted to:** Pass hapikey as a query parameter because old tutorials show it.
**Why that fails:** API keys were retired in late 2022. No scoped access control, no audit trail.
**The right way:** Use private app tokens or OAuth 2.0.

### Rule 2: Never skip rate limiting
**You will be tempted to:** Fire Promise.all() across thousands of records without throttling.
**Why that fails:** HubSpot returns 429 within seconds. Retry storms consume more quota.
**The right way:** Configure limiterOptions with Bottleneck and set numberOfApiCallRetries to 3-6.

### Rule 3: Never fetch all records to filter in memory
**You will be tempted to:** Call the list API and filter with array.filter() in your code.
**Why that fails:** Wastes rate limit on records you don't need. Doesn't scale.
**The right way:** Use the CRM Search API with filterGroups to query server-side.

### Rule 4: Never hardcode pipeline or stage IDs
**You will be tempted to:** Copy IDs from the UI and paste them as string constants.
**Why that fails:** IDs differ between portals, sandboxes, and production.
**The right way:** Dynamically retrieve via GET /crm/v3/pipelines/{objectType} and cache.

### Rule 5: Never paginate past 10,000 with standard cursors
**You will be tempted to:** Write while(paging.next.after) assuming it scales infinitely.
**Why that fails:** Search API returns 400 error at record 10,001. Your sync silently drops data.
**The right way:** Use index-based pagination with hs_object_id GT filter (see Pattern 7).
