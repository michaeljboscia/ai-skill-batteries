---
name: mx-hubspot-contacts
description: "HubSpot Contacts API — create contact, update contact by ID or email, search contacts, merge contacts (irreversible), batch create, GDPR delete, leads object, lifecycle stages, lead status, email subscriptions, marketing vs non-marketing contacts"
---

# HubSpot Contacts + Leads — CRUD, Lifecycle, Subscriptions for AI Coding Agents

**Load when working with contact or lead records.**

## When to also load
- `mx-hubspot-core` — SDK setup, search patterns, associations (co-default)
- `mx-hubspot-sales` — logging activities against contacts, sequences
- `mx-hubspot-deals` — associating contacts with deals

---

## Level 1: Contact CRUD (Beginner)

### Pattern 1: Create Contact — Email is Required

**BAD:**
```typescript
// Creating without email — causes duplicates, breaks dedup
await hubspot.crm.contacts.basicApi.create({
  properties: { firstname: 'Jane', lastname: 'Doe' }
});
```

**GOOD:**
```typescript
await hubspot.crm.contacts.basicApi.create({
  properties: {
    email: 'jane@example.com',  // Primary unique identifier
    firstname: 'Jane',
    lastname: 'Doe',
  },
});
```

Email is HubSpot's primary dedup key. Without it, every form submit or API call creates a new record.

### Pattern 2: Update by ID vs by Email

```typescript
// Update by HubSpot Record ID
await hubspot.crm.contacts.basicApi.update('12345', {
  properties: { phone: '555-0100' }
});

// Update by email — pass idProperty as 3rd argument
await hubspot.crm.contacts.basicApi.update(
  'jane@example.com',
  { properties: { phone: '555-0100' } },
  'email'  // idProperty parameter
);

// Clear a property value — send empty string
await hubspot.crm.contacts.basicApi.update('12345', {
  properties: { phone: '' }
});
```

### Pattern 3: Batch Create (Max 100)

```typescript
await hubspot.crm.contacts.batchApi.create({
  inputs: [
    { properties: { email: 'a@example.com', firstname: 'Alice' } },
    { properties: { email: 'b@example.com', firstname: 'Bob' } },
  ]
});
```

SDK naming inconsistency: some versions use `BatchInputSimplePublicObjectInputForCreate` vs `BatchInputSimplePublicObjectBatchInputForCreate`. Align SDK version with deployment environment.

---

## Level 2: Merge, GDPR, Lifecycle (Intermediate)

### Pattern 4: Merge Contacts — IRREVERSIBLE

```typescript
await hubspot.crm.contacts.basicApi.merge({
  primaryObjectId: 'KEEP_THIS_ID',
  objectIdToMerge: 'DELETE_THIS_ID',
});
// Secondary contact is destroyed. No unmerge endpoint exists.
```

Never automate merges based on fuzzy matching (name similarity). Only merge on exact unique identifiers (email match). Always log both IDs for audit trail.

### Pattern 5: GDPR Delete — Permanent + Blocklists Email

```typescript
// Delete by ID — permanent, all PII purged within 30 days
await hubspot.crm.contacts.gdprApi.purge({ objectId: '12345' });

// Delete by email — email gets BLOCKLISTED from UI recreation
await hubspot.crm.contacts.gdprApi.purge({
  objectId: 'jane@example.com',
  idProperty: 'email'
});
```

GDPR delete is NOT the same as archive. Archive = 90-day recycle bin. GDPR = permanent destruction + email blocklist.

### Pattern 6: Lifecycle Stages — Forward-Only

Default ordered progression:
`Subscriber → Lead → MQL → SQL → Opportunity → Customer → Evangelist`

```typescript
// Moving FORWARD — works normally
await hubspot.crm.contacts.basicApi.update('12345', {
  properties: { lifecyclestage: 'customer' }
});

// Moving BACKWARD — must clear first, then set
// Step 1: Clear
await hubspot.crm.contacts.basicApi.update('12345', {
  properties: { lifecyclestage: '' }
});
// Step 2: Set backward stage
await hubspot.crm.contacts.basicApi.update('12345', {
  properties: { lifecyclestage: 'lead' }
});
```

Auto-update: HubSpot sets lifecycle to "Customer" when associated deal = Closed Won.

### Pattern 7: Lead Status vs Lifecycle Stage

| Property | Scope | Values | Who owns it |
|----------|-------|--------|-------------|
| `lifecyclestage` | Macro buyer journey | Subscriber, Lead, MQL, SQL, Opportunity, Customer | Marketing |
| `hs_lead_status` | Micro sales action | New, Open, In Progress, Attempted to Contact, Connected, Open Deal, Unqualified, Bad Timing | Sales |

Never put sales micro-actions into lifecycle stage. "Attempted to Contact" is a lead status, NOT a lifecycle stage.

---

## Level 3: Leads Object + Subscriptions (Advanced)

### Pattern 8: Leads Object (New, Sales Hub Pro/Enterprise)

Leads are a separate CRM object at `/crm/v3/objects/leads` — NOT the "Lead" lifecycle stage.

```typescript
// Create a Lead — must associate with existing contact
await hubspot.crm.objects.leads.basicApi.create({
  properties: {
    hs_lead_name: 'Q3 Enterprise Upsell',  // REQUIRED
    hs_lead_type: 'NEW_BUSINESS',
    hs_pipeline_stage: 'NEW',
  },
  associations: [{
    to: { id: contactId },
    types: [{ associationCategory: 'HUBSPOT_DEFINED', associationTypeId: 578 }]
  }]
});
```

Lead pipeline stages: New → Attempting → Connected → Qualified → Disqualified. Activities on leads auto-sync to associated contact. Multiple leads can exist per contact.

### Pattern 9: Email Subscriptions v4

```typescript
// Check subscription status
const status = await fetch(
  `https://api.hubapi.com/communication-preferences/v4/statuses/${email}`,
  { headers: { Authorization: `Bearer ${token}` } }
);
// Returns array with status: SUBSCRIBED | UNSUBSCRIBED | NOT_SPECIFIED
```

v4 supports resubscribing opted-out contacts (v3 cannot). Default types: "One to One" and "Marketing Information". Check status BEFORE sending marketing email — CAN-SPAM/GDPR violation if you skip this.

### Pattern 10: Marketing vs Non-Marketing Contacts

| Type | Billing | Can receive marketing email | Property |
|------|---------|---------------------------|----------|
| Marketing | Counts toward tier (costs money) | Yes | `hs_marketable_status: true` |
| Non-Marketing | Free (up to 15M) | No (sales/transactional only) | `hs_marketable_status: false` |

`hs_marketable_status` is READ-ONLY on create — cannot set via API at creation time. Toggle post-creation via dedicated endpoints or workflows.

---

## Performance: Make It Fast

### Search-Then-Create for Dedup
Before creating any contact, search by email first. The API does NOT auto-dedup on create (unlike forms/imports).

### Batch Everything
Single creates in a loop = 100x more API calls than batch. Always chunk into arrays of 100.

### Request Only Needed Properties
Default contact read returns minimal properties. Explicitly list what you need in the `properties` param.

## Observability: Know It's Working

### Track Merge Operations
Log both `primaryObjectId` and `objectIdToMerge` with timestamps. Merges are irreversible — you need the audit trail.

### Monitor GDPR Deletes
GDPR deletions take up to 30 days to fully purge. Track deletion requests separately for compliance reporting.

### Watch for 409 Conflicts
A 409 on contact create means the email already exists. In batch operations, one 409 can fail the entire batch. Implement pre-flight dedup checks.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never create contacts without email
**You will be tempted to:** Create contacts with just name/phone because your source system allows it.
**Why that fails:** Every subsequent form submit or API call for the same person creates a duplicate. Database fragments within weeks.
**The right way:** If no email exists, cache the data externally until one is acquired.

### Rule 2: Never blindly create without checking for duplicates
**You will be tempted to:** Call POST create every time, assuming HubSpot deduplicates.
**Why that fails:** The API does NOT auto-dedup. You will generate thousands of duplicates.
**The right way:** Search by email first. Found? Update. Not found? Create.

### Rule 3: Never force lifecycle stages backward without clearing
**You will be tempted to:** PATCH lifecyclestage from "Customer" to "Lead" in one call.
**Why that fails:** HubSpot silently ignores backward moves. Your sync thinks it succeeded but nothing changed.
**The right way:** Clear with empty string first, then set the new stage in a second call.

### Rule 4: Never confuse Lead Status with Lifecycle Stage
**You will be tempted to:** Map "Attempted to Contact" to lifecyclestage because it sounds like a stage.
**Why that fails:** Destroys marketing attribution and funnel reporting. Lifecycle is macro, lead status is micro.
**The right way:** Sales micro-actions go to `hs_lead_status`. Buyer journey stages go to `lifecyclestage`.

### Rule 5: Never automate merges on fuzzy criteria
**You will be tempted to:** Write a script that merges contacts with similar first+last names.
**Why that fails:** Merge is permanent and irreversible. Fuzzy matching will destroy real, distinct contacts (John Smith the CEO vs John Smith the intern).
**The right way:** Only merge on exact unique identifier match (email). Always log both IDs.
