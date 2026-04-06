---
name: mx-hubspot-extensions
description: "HubSpot CRM Extensions — CRM cards, app cards, UI extensions, calling extensions, video extensions, custom channels, hubspot.fetch, hubspot.extend, React components for HubSpot, developer platform 2025"
---

# HubSpot Extensions — CRM Cards, UI Extensions, App Cards for AI Coding Agents

**Load when building custom UI inside HubSpot's CRM interface.**

## When to also load
- `mx-hubspot-core` — SDK setup, authentication (co-default)
- `mx-hubspot-automation` — webhooks for extension data flow

---

## Level 1: Modern App Cards (Beginner)

### Pattern 1: Legacy CRM Cards are Deprecated

Legacy CRM cards deprecated 2025, sunset October 2026. Use modern **app cards** (UI extensions) on developer platform v2025.1+.

### Pattern 2: App Card Project Structure

```
/extensions/
  example-card.json     # Card configuration (*-hsmeta.json)
  ExampleCard.tsx       # React component
  package.json          # Dependencies (@hubspot/ui-extensions)
```

Config fields: `uid`, `type: "card"`, `config.name`, `config.location`, `config.entrypoint`, `config.objectTypes`.

Location examples: `crm.record.tab`, right sidebar, preview panel, help desk sidebar.

### Pattern 3: hubspot.extend() — Register Your Extension

```typescript
import { hubspot } from '@hubspot/ui-extensions';

hubspot.extend(({ context, actions }) => {
  // context: account info, user info, extension metadata
  // actions: addAlert, fetch CRM properties, etc.
  return <MyCard context={context} actions={actions} />;
});
```

---

## Level 2: Data Fetching and Components (Intermediate)

### Pattern 4: hubspot.fetch() — External APIs Only

`hubspot.fetch()` calls EXTERNAL REST services. It does NOT call HubSpot APIs. For HubSpot data, route through your backend or HubSpot Functions.

### Pattern 5: React Components

HubSpot provides pre-built React components: buttons, forms, tables (standard), CRM data components, CRM action components. Import from `@hubspot/ui-extensions`.

New 2025: charts, copy text actions, loading buttons.

### Pattern 6: HubSpot CLI Workflow

```bash
hs project create    # Scaffold new project
hs project add       # Add card component
hs project dev       # Local dev with hot reload
hs project upload    # Deploy to HubSpot
```

---

## Performance: Make It Fast

### Minimize External Fetches
hubspot.fetch() adds latency. Cache external data where possible, use loading states.

## Observability: Know It's Working

### Monitor Extension Errors
Check developer project logs in HubSpot for React rendering errors and fetch failures.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never use hubspot.fetch() to call HubSpot APIs
**You will be tempted to:** Fetch HubSpot CRM data via hubspot.fetch().
**Why that fails:** hubspot.fetch() is for external services only. Use context/actions or route through backend.
**The right way:** Use the built-in CRM data components or proxy through HubSpot Functions.

### Rule 2: Never build on legacy CRM cards
**You will be tempted to:** Use the simpler v3 CRM cards API because there are more examples online.
**Why that fails:** Legacy cards are deprecated (2025) and sunset October 2026.
**The right way:** Build on the modern developer platform with app cards and UI extensions.
