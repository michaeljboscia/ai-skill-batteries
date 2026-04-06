---
name: mx-hubspot-companies
description: "HubSpot Companies API — create company, update company, search companies, domain-based deduplication, merge companies, batch operations, company associations to contacts and deals, hs_merged_object_ids"
---

# HubSpot Companies — CRUD, Domain Dedup, Merge for AI Coding Agents

**Load when working with company records.**

## When to also load
- `mx-hubspot-core` — SDK setup, search, associations (co-default)
- `mx-hubspot-contacts` — contact-company associations
- `mx-hubspot-deals` — deal-company associations

---

## Level 1: Company CRUD (Beginner)

### Pattern 1: Create Company — Include Domain

```typescript
await hubspot.crm.companies.basicApi.create({
  properties: {
    name: 'Acme Corp',
    domain: 'acme.com',  // Primary dedup key
    industry: 'Technology',
  },
});
```

### Pattern 2: Update Company

```typescript
await hubspot.crm.companies.basicApi.update(companyId, {
  properties: { name: 'Acme Corporation' }
});
// Clear a property: pass empty string
```

### Pattern 3: Associate Company at Creation

```typescript
await hubspot.crm.companies.basicApi.create({
  properties: { name: 'Acme Corp', domain: 'acme.com' },
  associations: [{
    to: { id: contactId },
    types: [{ associationCategory: 'HUBSPOT_DEFINED', associationTypeId: 280 }]
  }]
});
```

---

## Level 2: Domain Dedup and Merge (Intermediate)

### Pattern 4: API Does NOT Auto-Dedup by Domain

**This is the #1 AI mistake with companies.** Imports and forms auto-dedup by domain. The API does NOT.

**BAD:**
```typescript
// Blindly creating — will generate duplicates
await hubspot.crm.companies.basicApi.create({ properties: { domain: 'acme.com' } });
```

**GOOD:** Search-then-create pattern:

```typescript
async function upsertCompany(domain: string, props: Record<string, string>) {
  const search = await hubspot.crm.companies.searchApi.doSearch({
    filterGroups: [{ filters: [{ propertyName: 'domain', operator: 'EQ', value: domain }] }],
    properties: ['name', 'domain'],
    limit: 1,
  });

  if (search.total > 0) {
    return hubspot.crm.companies.basicApi.update(search.results[0].id, { properties: props });
  }
  return hubspot.crm.companies.basicApi.create({ properties: { domain, ...props } });
}
```

### Pattern 5: Merge Companies

```typescript
await hubspot.crm.companies.basicApi.merge({
  primaryObjectId: 'KEEP_THIS',
  objectIdToMerge: 'ABSORB_THIS',
});
```

Irreversible. Surviving record gets `hs_merged_object_ids` property listing absorbed IDs.

### Pattern 6: Self-Healing Syncs with hs_merged_object_ids

If your external system references a company ID that no longer exists (it was merged), search for it:

```typescript
// Old ID stopped working — find where it was merged
const search = await hubspot.crm.companies.searchApi.doSearch({
  filterGroups: [{ filters: [{
    propertyName: 'hs_merged_object_ids', operator: 'CONTAINS_TOKEN', value: oldCompanyId
  }] }],
});
// Update your external system's foreign key to the surviving ID
```

---

## Level 3: Batch and Advanced (Advanced)

### Pattern 7: Batch Operations

```typescript
// Batch create (max 100)
await hubspot.crm.companies.batchApi.create({
  inputs: companies.map(c => ({ properties: c }))
});

// Batch update (max 100)
await hubspot.crm.companies.batchApi.update({
  inputs: updates.map(u => ({ id: u.id, properties: u.props }))
});
```

---

## Performance: Make It Fast

### Pre-fetch Domains for Dedup
Before batch creation, search for ALL domains in one query (use `IN` operator, max 500 values). Then only create companies not found.

### Cache Company IDs by Domain
Maintain a domain-to-companyId map. Eliminates repeated search calls.

## Observability: Know It's Working

### Monitor Duplicate Count
Periodically search for companies sharing the same domain. If duplicates appear, your dedup logic has a gap.

### Track Merge Events
Log all merge operations with both IDs + timestamp. Essential for external sync reconciliation.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never trust API auto-dedup for companies
**You will be tempted to:** Assume the API deduplicates like forms do.
**Why that fails:** The API creates duplicates every time. Your CRM fills with duplicate company records.
**The right way:** Always search by domain first. Found? Update. Not found? Create.

### Rule 2: Never automate merges on loose criteria
**You will be tempted to:** Merge companies with similar names or partial domain matches.
**Why that fails:** Merge is permanent. "Acme Corp" and "Acme Industries" might be different companies.
**The right way:** Only merge on exact domain match + manual review for edge cases.

### Rule 3: Never ignore hs_merged_object_ids in syncs
**You will be tempted to:** Treat missing company IDs as deletions.
**Why that fails:** The ID was merged, not gone. Your sync breaks permanently.
**The right way:** Search hs_merged_object_ids to find the surviving record and update your foreign key.
