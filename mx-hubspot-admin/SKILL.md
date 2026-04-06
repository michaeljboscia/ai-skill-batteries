---
name: mx-hubspot-admin
description: "HubSpot Admin API — user provisioning, SCIM, account information, audit logs, business units brands, webhooks management, import export, currencies, settings"
---

# HubSpot Admin — Users, Audit Logs, Account Settings for AI Coding Agents

**Load when managing the HubSpot account itself (users, settings, audit).**

## When to also load
- `mx-hubspot-core` — SDK setup, authentication (co-default)

---

## Level 1: Account Info (Beginner)

### Pattern 1: Account Details

```typescript
// GET /account-info/v3/details
// Returns: portalId, accountType, timeZone, companyCurrency, dataHostingLocation
```

### Pattern 2: API Usage

```typescript
// GET /account-info/v3/api-usage/daily/private-apps
// Monitor daily API consumption against limits
```

---

## Level 2: User Management (Intermediate)

### Pattern 3: User Provisioning

| API | Endpoint | Auth | Purpose |
|-----|----------|------|---------|
| Settings Users | `/settings/v3/users` | Private App / OAuth | Full CRUD, roles, teams |
| SCIM 2.0 | `/scim/v2/Users` | Portal SCIM token | Enterprise SSO auto-provisioning |
| CRM Users | `/crm/v3/objects/users` | Standard | Job title, working hours |

Settings Users handles firstName/lastName + role assignment. CRM Users handles other profile data.

### Pattern 4: Audit Logs (Enterprise)

```typescript
// GET /account-info/v3/activity/audit-logs
// Filter by: actingUserId, occurredAfter, occurredBefore
// Returns: CRM object changes, property updates, security events
```

CMS Content Audit API is separate — tracks content-specific changes.

---

## Level 3: Business Units and Config (Advanced)

### Pattern 5: Business Units (Brands)

Now called "Brands" in UI, still `/business-units/v3/business-units/` in API. Associate CRM objects via `hs_all_assigned_business_unit_ids` property.

### Pattern 6: Sandbox Environments

- Developer accounts: free sandbox environments
- Standard Sandbox (Enterprise): sync up to 5K contacts, sunset April 30, 2026
- Configurable Test Accounts: simulate different subscription tiers, CLI import data
- CMS Developer Sandbox: templates, CSS, JS development

Always test in sandbox. Never experiment in production.

---

## Performance: Make It Fast

### Cache Account Settings
Account details, currencies, business units change very rarely. Cache for 24+ hours.

## Observability: Know It's Working

### Monitor Audit Logs
Set up periodic audit log pulls for security monitoring. Track permission changes and data exports.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never test in production
**You will be tempted to:** Skip the sandbox because it's faster.
**Why that fails:** Test data pollutes production CRM. Broken workflows affect real customers.
**The right way:** Use developer test accounts or configurable test accounts.

### Rule 2: Never ignore audit log monitoring
**You will be tempted to:** Skip audit log integration because "we trust our team."
**Why that fails:** Security incidents and accidental bulk changes go undetected.
**The right way:** Pull audit logs on schedule. Alert on unusual patterns.
