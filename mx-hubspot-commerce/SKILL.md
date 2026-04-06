---
name: mx-hubspot-commerce
description: "HubSpot Commerce API — payments API, invoices API, subscriptions API, Stripe integration, commerce hub, payment processing, billing, commerce_payments object"
---

# HubSpot Commerce — Payments, Invoices, Subscriptions for AI Coding Agents

**Load when working with billing, invoices, or payment processing.**

## When to also load
- `mx-hubspot-core` — SDK setup, associations (co-default)
- `mx-hubspot-deals` — line items, quotes, deal associations

---

## Level 1: Commerce Objects (Beginner)

### Pattern 1: Commerce Endpoints

| Object | Endpoint | Purpose |
|--------|----------|---------|
| Payments | `/crm/v3/objects/commerce_payments` | Track payment records |
| Invoices | `/crm/v3/objects/invoices` | Create/manage invoices |
| Subscriptions | `/crm/v3/objects/subscriptions` | Recurring billing |

All require HubSpot Payments or Stripe integration to be configured.

### Pattern 2: Create Payment (Tracking, NOT Processing)

```typescript
await hubspot.crm.objects.commercePayments.basicApi.create({
  properties: {
    hs_initial_amount: '5000',      // Required
    hs_initiated_date: new Date().toISOString(),  // Required
    hs_payment_method: 'credit_card',
  },
  associations: [{
    to: { id: contactId },
    types: [{ associationCategory: 'HUBSPOT_DEFINED', associationTypeId: /* lookup */ 0 }]
  }]
});
```

**Critical:** This API TRACKS payments from external systems. It does NOT process credit cards. Payments processed through HubSpot Payments or Stripe CANNOT be modified via API.

---

## Level 2: Invoices and Subscriptions (Intermediate)

### Pattern 3: Invoice Workflow

1. Create draft invoice (set currency, initial details)
2. Configure: add associations (contacts, line items), properties, payment settings
3. Move to "open" status
4. Share via URL

```typescript
// Create draft
const invoice = await hubspot.crm.objects.invoices.basicApi.create({
  properties: {
    hs_currency: 'USD',
    hs_invoice_status: 'draft',
  }
});

// Update to open (after associations configured)
await hubspot.crm.objects.invoices.basicApi.update(invoice.id, {
  properties: { hs_invoice_status: 'open' }
});
```

As of April 2025, invoices can be paid digitally via HubSpot Payments or Stripe.

### Pattern 4: Subscriptions

```typescript
// Create line item first, then associate to subscription
const sub = await hubspot.crm.objects.subscriptions.basicApi.create({
  properties: {
    hs_subscription_name: 'Enterprise Annual',
  },
  associations: [
    { to: { id: lineItemId }, types: [/* subscription to line item type */] },
    { to: { id: contactId }, types: [/* subscription to contact type */] },
  ]
});

// Make billable
await hubspot.crm.objects.subscriptions.basicApi.update(sub.id, {
  properties: { hs_invoice_creation: 'on' }
});
```

### Pattern 5: Stripe Integration

Stripe Connect is the foundation. HubSpot = source of truth for commerce data. Stripe = payment processor. Available: US, UK, Canada (HubSpot Payments); Stripe available more broadly.

---

## Performance: Make It Fast

### Cache Payment Status
Payment statuses change infrequently. Poll on schedule, not per-request.

## Observability: Know It's Working

### Monitor Invoice State Machine
Track invoices stuck in "draft" — indicates missing associations or configuration.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never expect Payments API to process transactions
**You will be tempted to:** Think creating a payment record charges a credit card.
**Why that fails:** This API is for recording/tracking, not processing. Use HubSpot Payments UI or Stripe for actual processing.
**The right way:** Process via HubSpot Payments/Stripe, then track via Commerce API.

### Rule 2: Never modify HubSpot-processed payments via API
**You will be tempted to:** Update amount or status on a payment that went through HubSpot Payments.
**Why that fails:** Payments processed through native payment processors are immutable via API.
**The right way:** Manage refunds/adjustments through the HubSpot Payments or Stripe dashboard.
