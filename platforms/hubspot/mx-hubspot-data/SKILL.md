---
name: mx-hubspot-data
description: "HubSpot Data API — custom objects schema creation, custom object instances CRUD, import export API, GDPR compliance, sensitive data, consent management, search API for custom objects, data privacy"
---

# HubSpot Data — Custom Objects, Import/Export, GDPR for AI Coding Agents

**Load when working with custom objects, bulk data operations, or privacy compliance.**

## When to also load
- `mx-hubspot-core` — SDK setup, search, properties (co-default)
- `mx-hubspot-contacts` — GDPR contact operations
- `mx-hubspot-admin` — user management, audit logs

---

## Level 1: Custom Objects (Beginner)

### Pattern 1: Create Custom Object Schema — API Only

Custom objects can ONLY be created via API (not UI). Requires Enterprise subscription.

```typescript
// POST /crm/v3/schemas
const schema = {
  name: 'subscription_plan',
  labels: { singular: 'Subscription Plan', plural: 'Subscription Plans' },
  metaType: 'PORTAL_SPECIFIC',
  primaryDisplayProperty: 'plan_name',
  requiredProperties: ['plan_name'],
  properties: [
    { name: 'plan_name', label: 'Plan Name', type: 'string', fieldType: 'text' },
    { name: 'monthly_price', label: 'Monthly Price', type: 'number', fieldType: 'number' },
  ],
  associatedObjects: ['CONTACT', 'COMPANY'],
};
```

Name and labels CANNOT be changed after creation. Max 10 unique value properties.

### Pattern 2: Custom Object Instances

Same CRUD pattern as standard objects: `/crm/v3/objects/{objectType}`.

```typescript
// Create instance
await hubspot.crm.objects.basicApi.create('subscription_plan', {
  properties: { plan_name: 'Enterprise', monthly_price: '999' }
});

// Search uses standard CRM Search API
await hubspot.crm.objects.searchApi.doSearch('subscription_plan', { /* filters */ });
```

Object identifiers: use `fullyQualifiedName` or `objectTypeId` (not `name` — deprecated April 2025).

---

## Level 2: Import/Export (Intermediate)

### Pattern 3: Import Data

`POST /crm/v3/imports` — CSV, XLSX, or XLS. Up to 80M rows/day. Specify column mappings and file details.

### Pattern 4: Export Data

`POST /crm/v3/exports/export/async` — XLSX, CSV, or XLS. Specify object, properties, and filters. Async operation — poll for completion.

---

## Level 3: GDPR and Privacy (Advanced)

### Pattern 5: GDPR Endpoints

Contact GDPR purge permanently removes all PII within 30 days. Email used for lookup gets blocklisted from UI recreation. See `mx-hubspot-contacts` for implementation details.

Sensitive data properties: created via UI only (Super Admin), readable via CRM Search API with appropriate scopes. Encrypted in transit and at rest.

Consent tracking: `Legal basis for processing contact's data` property set automatically on GDPR-enabled form submissions.

---

## Performance: Make It Fast

### Batch Custom Object Operations
Same limits as standard objects: 100 per batch create/read/update.

## Observability: Know It's Working

### Schema Change Monitoring
Custom object schemas are immutable after creation (name/labels). Track schema versions if iterating.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never try to create custom objects via UI
**You will be tempted to:** Look for a "Create Custom Object" button in settings.
**Why that fails:** Custom object schemas can only be created via API. No UI option exists.
**The right way:** Use POST /crm/v3/schemas with the full schema definition.

### Rule 2: Never use 'name' as object identifier in API calls
**You will be tempted to:** Use the human-readable name in URL paths.
**Why that fails:** Deprecated as of April 2025. Will eventually stop working.
**The right way:** Use fullyQualifiedName or objectTypeId.

### Rule 3: Never assume schema changes are reversible
**You will be tempted to:** Create a custom object with a rough name, planning to rename later.
**Why that fails:** Name and labels are immutable after creation.
**The right way:** Plan your naming carefully. Use hard-remove (archived=true) and recreate if you must change.
