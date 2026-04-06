---
name: mx-hubspot-tickets
description: "HubSpot Tickets API — create ticket, ticket pipelines, ticket stages, SLA properties, feedback surveys API, service hub API patterns, ticket associations"
---

# HubSpot Tickets — Pipelines, SLAs, Service for AI Coding Agents

**Load when working with support tickets or service hub features.**

## When to also load
- `mx-hubspot-core` — SDK setup, search, associations (co-default)
- `mx-hubspot-contacts` — contact-ticket associations
- `mx-hubspot-automation` — workflows triggered by ticket events

---

## Level 1: Ticket CRUD (Beginner)

### Pattern 1: Create Ticket

```typescript
await hubspot.crm.tickets.basicApi.create({
  properties: {
    subject: 'Login issue - Enterprise customer',
    hs_pipeline: pipelineId,        // Internal ID, not label
    hs_pipeline_stage: stageId,     // Internal stage ID
    hs_ticket_priority: 'HIGH',
    content: 'Customer unable to access dashboard since 9am ET',
  },
  associations: [{
    to: { id: contactId },
    types: [{ associationCategory: 'HUBSPOT_DEFINED', associationTypeId: 16 }]
  }]
});
```

Must use internal IDs for pipeline and stage — same pattern as deals.

### Pattern 2: Ticket Pipeline Stages

```typescript
const pipelines = await hubspot.crm.pipelines.pipelinesApi.getAll('tickets');
// Each stage has metadata.ticketState: "OPEN" or "CLOSED"
```

Stage metadata `ticketState` distinguishes open from closed tickets — critical for SLA calculations.

---

## Level 2: SLA Properties and Feedback (Intermediate)

### Pattern 3: SLA Properties (Auto-Populated)

When SLAs are configured in HubSpot inbox, these properties auto-populate:

| Property | Description |
|----------|-------------|
| `hs_time_to_first_response_sla_due_date` | When first response must happen |
| `hs_time_to_first_response_sla_ticket_status` | Active SLA, Due soon, Overdue, Completed on time |
| `hs_time_to_close_sla_due_date` | When ticket must be closed |
| `hs_time_to_close_sla_ticket_status` | Same status options as above |
| `hs_time_to_close_in_sla_hours` | Actual time between creation and closure |

These are read-only computed properties — don't try to set them via API.

### Pattern 4: Feedback Submissions API (Read-Only)

```typescript
// Retrieve NPS, CSAT, CES, or custom survey responses
const submissions = await hubspot.crm.extensions.feedbackSubmissions.basicApi.getPage();
// Supports: NPS, CSAT, CES, custom surveys
// READ-ONLY — cannot create/update/modify survey data via API
```

---

## Level 3: Webhooks and Automation (Advanced)

### Pattern 5: Stage Change Notifications

Set up webhooks to subscribe to `ticket.propertyChange` for `hs_pipeline_stage`. This fires when tickets move between stages — useful for SLA alerting, external escalation, or Slack notifications.

---

## Performance: Make It Fast

### Cache Ticket Pipeline/Stage IDs
Same pattern as deals — fetch once, cache for hours.

### Batch Ticket Operations
Use `/crm/v3/objects/tickets/batch/create` for bulk ticket creation (max 100).

## Observability: Know It's Working

### SLA Breach Monitoring
Query tickets where `hs_time_to_first_response_sla_ticket_status` = "Overdue" to build SLA breach dashboards.

### Track Stage Velocity
Monitor time-in-stage by comparing `hs_pipeline_stage` change timestamps.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never hardcode ticket pipeline IDs
**You will be tempted to:** Copy stage IDs from the service hub UI.
**Why that fails:** Different portals have different IDs. Breaks on environment changes.
**The right way:** Dynamically fetch via Pipelines API.

### Rule 2: Never try to write SLA properties
**You will be tempted to:** Set SLA due dates via API to backfill historical data.
**Why that fails:** SLA properties are computed by HubSpot based on inbox configuration. API writes are rejected.
**The right way:** Configure SLAs in Settings > Inbox, let HubSpot compute them.

### Rule 3: Never use Feedback API for writes
**You will be tempted to:** Create survey responses programmatically for testing.
**Why that fails:** Feedback Submissions API is strictly read-only.
**The right way:** Trigger surveys via workflows or the UI, then read results via API.
