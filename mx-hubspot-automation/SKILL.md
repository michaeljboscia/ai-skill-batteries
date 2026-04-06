---
name: mx-hubspot-automation
description: "HubSpot Automation API — workflows v4 API, create workflow, workflow actions, custom code actions, enrollment triggers, webhook subscriptions v3 v4, HMAC validation, timeline events v4, workflow types contact deal company ticket"
---

# HubSpot Automation — Workflows, Webhooks, Timeline Events for AI Coding Agents

**Load when creating/managing workflows, webhook subscriptions, or timeline events.**

## When to also load
- `mx-hubspot-core` — SDK setup, associations (co-default)
- `mx-hubspot-observability` — webhook HMAC verification, error tracking

---

## Level 1: Workflows v4 Basics (Beginner)

### Pattern 1: Workflow Types

| Type | Config Value | Objects |
|------|-------------|---------|
| Contact workflows | `CONTACT_FLOW` | Contacts |
| Platform workflows | `PLATFORM_FLOW` | Deals, Companies, Tickets, Custom Objects |

Records can only enroll in workflows of the same type. v4 is in **public beta** (Jan 2025).

### Pattern 2: Create Workflow

```typescript
// POST /automation/v4/flows
const workflow = await fetch('https://api.hubapi.com/automation/v4/flows', {
  method: 'POST',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({
    type: 'CONTACT_FLOW',
    // Full workflow spec including triggers, actions, branches
  })
});
```

### Pattern 3: Workflow Actions

Available actions: delays, branches (if/then), communications (email/SMS), CRM actions (create records), AI actions (beta — summarize data).

Custom code actions: JavaScript (Node.js) or Python (beta). Requires Operations Hub Pro/Enterprise.

### Pattern 4: Enrollment Triggers

| Trigger Type | Example |
|-------------|---------|
| Filter-based | Contact property matches criteria |
| Event-based | Form submission, CTA click, custom event |
| Schedule-based | Calendar date or date property |

### Pattern 5: Batch Read Workflows

```typescript
// Fetch multiple workflows by ID
await fetch('https://api.hubapi.com/automation/v4/flows/batch/read', {
  method: 'POST',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ inputs: [{ id: flowId1 }, { id: flowId2 }] })
});
```

v3-to-v4 migration endpoints available (get v4 flowId from v3 workflowId).

---

## Level 2: Webhook Subscriptions (Intermediate)

### Pattern 6: Webhooks v3 (Push Model)

```typescript
// Create subscription — POST /webhooks/v3/{appId}/subscriptions
// Subscribe to contact property changes
const sub = {
  eventType: 'contact.propertyChange',
  propertyName: 'lifecyclestage',
  active: true,
};
```

Event types: `creation`, `propertyChange`, `associationChange`, `merge`, `restore`. Conversations: `conversation.creation`, `.newMessage`.

Private app webhooks: **UI only** — cannot configure via API.

### Pattern 7: HMAC Signature Verification

Verify every incoming webhook to prevent spoofing:

```typescript
import crypto from 'crypto';

function verifyWebhook(req: Request, clientSecret: string): boolean {
  const timestamp = req.headers['x-hubspot-request-timestamp'];
  const signature = req.headers['x-hubspot-signature-v3'];

  // Reject if timestamp > 5 minutes old (replay attack)
  if (Date.now() - Number(timestamp) > 300000) return false;

  const sourceString = `${req.method}${req.url}${req.body}${timestamp}`;
  const hash = crypto.createHmac('sha256', clientSecret)
    .update(sourceString, 'utf8')
    .digest('base64');

  // Use constant-time comparison to prevent timing attacks
  return crypto.timingSafeEqual(Buffer.from(hash), Buffer.from(signature));
}
```

### Pattern 8: Webhook Retry Policies

| Source | Max Retries | Duration | Retry on 4xx? |
|--------|------------|----------|---------------|
| Webhooks v3 API | 10 | 24 hours | No (except 429) |
| Workflow webhooks | Unlimited | 3 days | No (except 429) |
| Both | — | — | Always retry 5xx |

Timeout: 30s response, 3s TCP connect. Best practice: respond 2xx immediately, process async.

### Pattern 9: Webhooks v4 Journal (Beta)

Pull-based model — you poll for events instead of receiving pushes. 3-day event retention. Install-specific (not app-distributed). Requires `developer.webhooks_journal.*` scopes. Limited availability — requires coordination with HubSpot.

---

## Level 3: Timeline Events v4 (Advanced)

### Pattern 10: Send Timeline Event

```typescript
// Event types defined in developer project config (*-hsmeta.json)
await fetch('https://api.hubapi.com/integrators/timeline/v4/events', {
  method: 'POST',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({
    eventTypeName: 'my_custom_event',
    objectId: contactId,
    tokens: { action: 'Upgraded', plan: 'Enterprise' },
    occurredAt: new Date().toISOString(),
  })
});
```

Templates: `headerTemplate` (1,000 chars max), `detailTemplate` (10,000 chars max). Up to 500 properties per event type. "App events" require HubSpot approval; non-partners use custom events API instead.

---

## Performance: Make It Fast

### Webhook Processing
Respond 2xx immediately, queue processing. HubSpot times out at 30s — any sync processing delays risk retries.

### Batch Workflow Reads
Use `/automation/v4/flows/batch/read` instead of individual GET calls.

## Observability: Know It's Working

### Webhook Delivery Monitoring
Track volume, failure rates, and processing times on your webhook endpoints. Alert on sustained retry rates.

### Workflow Error Logs
Custom code actions auto-retry on 429/5xx for 3 days. Monitor custom code execution logs in HubSpot for persistent failures.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never skip HMAC verification on webhooks
**You will be tempted to:** Accept all incoming POSTs without signature validation.
**Why that fails:** Anyone who discovers your webhook URL can inject fake events into your system.
**The right way:** Verify X-HubSpot-Signature-v3 with HMAC SHA-256 + reject timestamps > 5 minutes old.

### Rule 2: Never process webhooks synchronously
**You will be tempted to:** Do database writes and API calls inside the webhook handler before responding.
**Why that fails:** HubSpot times out at 30s. Slow processing triggers retries, causing duplicate processing.
**The right way:** Respond 2xx immediately, push to a message queue, process async.

### Rule 3: Never assume workflow v3 and v4 are interchangeable
**You will be tempted to:** Use v3 endpoints for workflows you created via v4.
**Why that fails:** v3 and v4 have different ID systems. Use migration endpoints to map between them.
**The right way:** Standardize on v4. Use migration endpoints for legacy v3 workflows.
