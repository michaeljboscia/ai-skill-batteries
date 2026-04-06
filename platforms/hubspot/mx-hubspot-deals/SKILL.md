---
name: mx-hubspot-deals
description: "HubSpot Deals API — create deal, update deal stage, deal pipelines and stages API, stage transitions, weighted forecasting hs_forecast_amount, quotes CPQ, line items, products, deal associations, deal amount auto-calculation"
---

# HubSpot Deals — Pipelines, Quotes, Line Items, Forecasting for AI Coding Agents

**Load when working with deals, pipelines, quotes, or line items.**

## When to also load
- `mx-hubspot-core` — SDK setup, search, associations (co-default)
- `mx-hubspot-companies` — company dedup, company-deal associations
- `mx-hubspot-contacts` — contact-deal associations
- `mx-hubspot-commerce` — payments, invoices, subscriptions

---

## Level 1: Deal CRUD and Pipelines (Beginner)

### Pattern 1: Create Deal — Always Specify Pipeline

**BAD:**
```typescript
// Omitting pipeline — falls back to "default" which admins can change
await hubspot.crm.deals.basicApi.create({
  properties: { dealname: 'Acme Contract', dealstage: 'appointmentscheduled' }
});
```

**GOOD:**
```typescript
// Dynamically fetch pipeline ID, then create with explicit pipeline
const pipelines = await hubspot.crm.pipelines.pipelinesApi.getAll('deals');
const salesPipeline = pipelines.results.find(p => p.label === 'Sales Pipeline');

await hubspot.crm.deals.basicApi.create({
  properties: {
    dealname: 'Acme Contract',
    pipeline: salesPipeline!.id,           // Internal ID, not label
    dealstage: salesPipeline!.stages[0].id, // Internal stage ID
    amount: '50000',
    closedate: new Date().toISOString(),
  },
  associations: [{
    to: { id: contactId },
    types: [{ associationCategory: 'HUBSPOT_DEFINED', associationTypeId: 3 }]
  }]
});
```

Must use **internal IDs** for pipeline and dealstage — not human-readable labels.

### Pattern 2: Update Deal Stage

```typescript
await hubspot.crm.deals.basicApi.update(dealId, {
  properties: { dealstage: newStageId }
});
```

Pipeline rules can enforce linear progression (no stage skipping). Workflows can auto-move deals based on triggers.

### Pattern 3: Retrieve Pipelines and Stage Metadata

```typescript
const pipelines = await hubspot.crm.pipelines.pipelinesApi.getAll('deals');
for (const pipeline of pipelines.results) {
  const stages = await hubspot.crm.pipelines.pipelineStagesApi.getAll('deals', pipeline.id);
  // Each stage has: id, label, displayOrder, metadata.probability
}
```

Stage `metadata.probability` is a float string ("0.0" to "1.0") — critical for forecasting.

---

## Level 2: Forecasting, Line Items, Products (Intermediate)

### Pattern 4: Weighted Forecasting

`hs_forecast_amount` = `amount` x stage `probability`

```typescript
const deal = await hubspot.crm.deals.basicApi.getById(dealId, [
  'amount', 'dealstage', 'hs_forecast_amount', 'hs_forecast_probability'
]);
// hs_forecast_amount is auto-calculated — read-only
```

Not returned by default — must explicitly request via `properties` param.

### Pattern 5: Products vs Line Items — Never Confuse Them

| Object | Role | Can associate to Deal? |
|--------|------|----------------------|
| Product (`/crm/v3/objects/products`) | Catalog template | **NO** — products cannot link to deals |
| Line Item (`/crm/v3/objects/line_items`) | Instance of product on a deal | **YES** — via associationTypeId 20 |

**BAD:** Trying to associate a Product directly to a Deal.

**GOOD:** Create a Line Item from the Product, then associate to Deal:

```typescript
// Create line item from product catalog
await hubspot.crm.lineItems.basicApi.create({
  properties: {
    hs_product_id: productId,  // Inherits name, price from product
    quantity: '2',
    price: '5000',
  },
  associations: [{
    to: { id: dealId },
    types: [{ associationCategory: 'HUBSPOT_DEFINED', associationTypeId: 20 }]
  }]
});
```

Deal `amount` auto-calculates from associated line items (quantity x price - discounts). Can override with "Manual entry" setting.

---

## Level 3: CPQ Quotes (Advanced)

### Pattern 6: Create CPQ Quote

CPQ quotes require `hs_template_type: CPQ_QUOTE` and MUST associate with line items + contact + deal.

```typescript
// 1. Create quote in DRAFT state
const quote = await hubspot.crm.quotes.basicApi.create({
  properties: {
    hs_title: 'Q3 Enterprise Proposal',
    hs_expiration_date: '2026-06-30T00:00:00.000Z',
    hs_template_type: 'CPQ_QUOTE',
    hs_status: 'DRAFT',
  },
  associations: [
    { to: { id: dealId }, types: [{ associationCategory: 'HUBSPOT_DEFINED', associationTypeId: 286 }] },
    { to: { id: contactId }, types: [{ associationCategory: 'HUBSPOT_DEFINED', associationTypeId: 69 }] },
  ]
});

// 2. Associate line items (separate calls or batch)

// 3. Publish the quote
await hubspot.crm.quotes.basicApi.update(quote.id, {
  properties: { hs_status: 'APPROVAL_NOT_NEEDED' }
});
```

Quote states: `DRAFT` → `APPROVAL_NOT_NEEDED` or `APPROVED` → published. E-signatures: set `hs_esign_enabled: true` and associate signer contacts with correct association type.

### Pattern 7: Company Domain Dedup (Cross-Reference)

HubSpot API does NOT auto-dedup companies by domain (imports/forms do). Always search-then-create:

```typescript
async function upsertCompany(domain: string, props: Record<string, string>) {
  const search = await hubspot.crm.companies.searchApi.doSearch({
    filterGroups: [{ filters: [{ propertyName: 'domain', operator: 'EQ', value: domain }] }],
  });
  if (search.total > 0) {
    return hubspot.crm.companies.basicApi.update(search.results[0].id, { properties: props });
  }
  return hubspot.crm.companies.basicApi.create({ properties: { domain, ...props } });
}
```

Track merged companies via `hs_merged_object_ids` property for self-healing syncs.

---

## Performance: Make It Fast

### Cache Pipeline/Stage IDs
Pipelines change rarely. Fetch on startup, refresh every few hours. Never call the Pipelines API per-deal.

### Batch Deal Updates
Use `POST /crm/v3/objects/deals/batch/update` for bulk stage moves. 100 deals per call vs 100 individual PATCH calls.

### Limit Requested Properties
Deal objects can have hundreds of properties. Only request what you need — `['dealname', 'amount', 'dealstage']` not everything.

## Observability: Know It's Working

### Track Stage Transitions
Log `dealId`, old stage, new stage, timestamp. Pipeline rules may silently reject invalid transitions.

### Monitor Deal Amount Drift
If deal amounts don't match expected line item totals, check if "Manual entry" overrides are enabled.

### Watch for Pipeline ID Mismatches
If deals appear in the wrong pipeline, the dynamic pipeline fetch is stale. Reduce cache TTL or add webhook on pipeline changes.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never hardcode pipeline or stage IDs
**You will be tempted to:** Copy "default" or a UUID from the UI into your code.
**Why that fails:** Different portals, sandboxes, and environments have different IDs. Code breaks on deploy.
**The right way:** Fetch dynamically via Pipelines API and cache.

### Rule 2: Never create deals without specifying pipeline
**You will be tempted to:** Omit the `pipeline` property to save code.
**Why that fails:** Default pipeline is arbitrary and admin-changeable. Deals land in the wrong funnel.
**The right way:** Always explicitly set `pipeline` in every deal creation payload.

### Rule 3: Never associate Products directly to Deals
**You will be tempted to:** Pass a Product ID in the deal's associations array.
**Why that fails:** HubSpot schema forbids Product-to-Deal links. Products are templates, not instances.
**The right way:** Create a Line Item (with `hs_product_id`), then associate the Line Item to the Deal using associationTypeId 20.

### Rule 4: Never use single operations in loops for bulk
**You will be tempted to:** Write a for-loop calling PATCH for each deal individually.
**Why that fails:** 50 deals = 50 API calls = instant rate limiting. Batch = 1 call.
**The right way:** Use batch endpoints. Always.

### Rule 5: Never create quotes without all required associations
**You will be tempted to:** Create a quote with just title and expiration, planning to associate later.
**Why that fails:** CPQ quotes without line items + contact + deal cannot be published. They stay stuck in draft.
**The right way:** Include all associations at creation time or in the same atomic workflow.
