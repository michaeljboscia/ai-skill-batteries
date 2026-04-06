---
name: mx-hubspot-marketing
description: "HubSpot Marketing API — marketing emails v3, transactional email single send API, forms API v3, form submissions, custom events API, behavioral events, campaigns API, email subscriptions, CAN-SPAM GDPR consent, lists segmentation"
---

# HubSpot Marketing — Emails, Forms, Events, Campaigns for AI Coding Agents

**Load when working with marketing emails, forms, custom events, or campaigns.**

## When to also load
- `mx-hubspot-core` — SDK setup, search (co-default)
- `mx-hubspot-contacts` — subscriptions, marketing contact status
- `mx-hubspot-automation` — workflows triggered by marketing events

---

## Level 1: Marketing Emails and Transactional Sends (Beginner)

### Pattern 1: Marketing Email API is for Content, NOT Sending

| API | Purpose | Sends Email? |
|-----|---------|-------------|
| Marketing Emails v3 (`/marketing/v3/emails`) | Create/update/retrieve email content | **NO** (most tiers) |
| Transactional Single Send (`/marketing/v3/transactional/single-email/send`) | Send individual triggered email | **YES** |
| Engagements Email (`/crm/v3/objects/emails`) | Log 1-to-1 sales email | **NO** (logging only) |
| SMTP API | Send via SMTP relay | **YES** |

Marketing Emails v3 creates content as full JSON structure. No drag-and-drop template ID passthrough — design in UI, GET the JSON, use as base.

### Pattern 2: Transactional Single Send

```typescript
const response = await fetch('https://api.hubapi.com/marketing/v3/transactional/single-email/send', {
  method: 'POST',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({
    emailId: 12345678,  // Template ID from HubSpot email tool
    message: { to: 'customer@example.com' },
    customProperties: {  // Renders as {{ custom.order_number }} in template
      order_number: 'ORD-2026-0042',
      shipping_date: '2026-04-10',
    },
    contactProperties: {  // Updates contact record at send time
      firstname: 'Jane',
    }
  })
});
// Returns statusId — poll for PENDING -> PROCESSING -> COMPLETE
```

Auto-associates with CRM contact by email. If no contact exists, **creates one automatically**. To prevent auto-creation, use SMTP API instead.

### Pattern 3: Email Statistics

```typescript
// Aggregated stats (opens, clicks, bounces) — matches in-app Performance page
const email = await fetch(`https://api.hubapi.com/marketing/v3/emails/${emailId}`, {
  headers: { Authorization: `Bearer ${token}` }
});
const stats = (await email.json()).stats;

// Granular event-level data (who clicked what, when) — use Email Events API
```

---

## Level 2: Forms and Custom Events (Intermediate)

### Pattern 4: Form Submission — Context Object is Critical

Submit endpoint (no auth required for standard submissions):
`POST https://api.hsforms.com/submissions/v3/integration/submit/{portalId}/{formGuid}`

EU portals MUST use: `https://api-eu1.hsforms.com/...`

```typescript
await fetch(`https://api.hsforms.com/submissions/v3/integration/submit/${portalId}/${formGuid}`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    fields: [
      { name: 'email', value: 'lead@example.com' },
      { name: 'firstname', value: 'Alex' },
    ],
    context: {
      hutk: hubspotutk,   // CRITICAL — from hubspotutk cookie
      pageUri: 'https://www.example.com/demo',
      pageName: 'Request Demo',
    },
    legalConsentOptions: {  // GDPR-enabled portals
      consent: {
        consentToProcess: true,
        text: 'I agree to the privacy policy',
        communications: [{
          value: true,
          subscriptionTypeId: 123,
          text: 'Marketing emails',
        }]
      }
    }
  })
});
```

**Critical:** Without `context.hutk`, the contact's anonymous web browsing history is permanently detached from their CRM record.

### Pattern 5: Form Submission Gotchas

- Custom fields must be created as properties FIRST (API won't auto-create)
- Submissions do NOT return the contact ID — extract email, then look up via Contacts API
- File uploads: Forms API is JSON-only. Upload file via Files API first, pass URL as string
- External (non-HubSpot) forms: all data maps to single-line text properties only
- Form redirects: HubSpot page, external URL, meeting link, or payment link — supports conditional logic

### Pattern 6: Custom Events — Schema First

```typescript
// Step 1: Define the event schema (up to 50 custom properties)
await fetch('https://api.hubapi.com/events/v3/event-definitions', {
  method: 'POST',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({
    label: 'Product Viewed',
    name: 'product_viewed',
    primaryObject: 'CONTACT',
    propertyDefinitions: [
      { name: 'product_name', label: 'Product Name', type: 'string' },
      { name: 'product_price', label: 'Price', type: 'number' },
    ]
  })
});
// Returns fullyQualifiedName (e.g., pe12345_product_viewed)

// Step 2: Send event occurrence
const trackUrl = isEU ? 'https://track-eu1.hubspot.com' : 'https://api.hubapi.com';
await fetch(`${trackUrl}/events/v3/send`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({
    eventName: 'pe12345_product_viewed',
    email: 'customer@example.com',
    occurredAt: new Date().toISOString(),
    properties: { product_name: 'Enterprise Plan', product_price: '999' }
  })
});
```

| Method | When to Use |
|--------|-------------|
| Tracking Code API (client-side JS) | Website interactions (clicks, views) |
| HTTP API (server-side) | Backend events (login, purchase, external actions) |

Rate limit: **1,250 req/sec**. EU portals MUST use `track-eu1.hubspot.com`.

---

## Level 3: Campaigns and Subscriptions (Advanced)

### Pattern 7: Campaigns API

```typescript
// Create campaign
const campaign = await fetch('https://api.hubapi.com/marketing/v3/campaigns', {
  method: 'POST',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({
    properties: { hs_name: 'Q3 Product Launch', hs_start_date: '2026-07-01' }
  })
});
const campaignGuid = (await campaign.json()).campaignGuid;

// Associate assets (emails, forms, blog posts, landing pages, sequences, social posts...)
await fetch(`https://api.hubapi.com/marketing/v3/campaigns/${campaignGuid}/assets/EMAIL/${emailId}`, {
  method: 'PUT',
  headers: { Authorization: `Bearer ${token}` }
});

// Revenue attribution (Enterprise)
const revenue = await fetch(
  `https://api.hubapi.com/marketing/v3/campaigns/${campaignGuid}/reports/revenue`,
  { headers: { Authorization: `Bearer ${token}` } }
);
```

Budget management: `POST .../campaigns/{guid}/budget`. Spend tracking: `POST .../campaigns/{guid}/spend`. Custom UTM: read/write `hs_utm` properties.

### Pattern 8: Email Subscription Compliance

```typescript
// Check before sending
const status = await fetch(
  `https://api.hubapi.com/communication-preferences/v3/status/email/${encodeURIComponent(email)}`,
  { headers: { Authorization: `Bearer ${token}` } }
);
// Each subscription type returns: SUBSCRIBED | UNSUBSCRIBED | NOT_SPECIFIED
```

v3 cannot resubscribe opted-out contacts. v4 can (with proper legal basis). Always verify subscription status before programmatic sends.

---

## Performance: Make It Fast

### Cache Subscription Types
Subscription type IDs rarely change. Fetch once, map by name, cache for hours.

### Batch Custom Event Sends
Custom events support batches of 500 at 1,250 req/sec. Batch instead of individual sends.

### Template Cloning for Email Creation
Design one email in UI, GET the JSON structure, clone it programmatically for variants. Much faster than building JSON from scratch.

## Observability: Know It's Working

### Email Delivery Monitoring
Use Email Events API for bounce, rejection, spam complaint tracking. Build alerts on elevated bounce rates.

### Form Submission Attribution
If new contacts lack web history, the `hutk` cookie was missing. Monitor the percentage of submissions with vs without hutk.

### Custom Event Ingestion Lag
Events may take up to 30 minutes to appear in reports. Don't poll for immediate confirmation.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never mix marketing and transactional email APIs
**You will be tempted to:** Use Marketing Emails v3 to send a password reset or receipt.
**Why that fails:** Marketing emails require subscription opt-in. Transactional emails (receipts, alerts) must bypass subscription checks.
**The right way:** Use Transactional Single Send API for triggered individual emails.

### Rule 2: Never send marketing email without checking subscription status
**You will be tempted to:** Skip the subscription check because "they filled out a form."
**Why that fails:** CAN-SPAM and GDPR violations carry real fines. Form fill does not equal blanket marketing consent.
**The right way:** Query `/communication-preferences/v3/status` before every programmatic send.

### Rule 3: Never submit forms without the context/hutk payload
**You will be tempted to:** Skip the `context` object because it's "just tracking."
**Why that fails:** Without hutk, the contact's anonymous browsing history is permanently detached. Marketing attribution breaks.
**The right way:** Parse the `hubspotutk` cookie on the client, pass it through to the server, include in context.

### Rule 4: Never send custom events without defining the schema first
**You will be tempted to:** POST to `/events/v3/send` with ad-hoc properties.
**Why that fails:** The API validates against predefined schemas. Undefined properties are silently dropped.
**The right way:** Define the event via `/events/v3/event-definitions` FIRST, then send occurrences.

### Rule 5: Never ignore EU data sovereignty
**You will be tempted to:** Use the global `api.hubapi.com` endpoint for all portals.
**Why that fails:** EU portals require `api-eu1.hsforms.com` for forms and `track-eu1.hubspot.com` for events. Wrong endpoint = failed requests.
**The right way:** Check portal data hosting location and route accordingly.
