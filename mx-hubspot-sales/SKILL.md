---
name: mx-hubspot-sales
description: "HubSpot Sales Activities API — create call, log email, create meeting, create note, create task, engagements, sequences API, enroll contact, calling SDK, Communications API WhatsApp LinkedIn SMS, pin activity hs_pinned_engagement_id, sales activities"
---

# HubSpot Sales Activities — Engagements, Sequences, Communications for AI Coding Agents

**Load when logging activities, enrolling in sequences, or tracking sales touches.**

## When to also load
- `mx-hubspot-core` — SDK setup, associations (co-default)
- `mx-hubspot-contacts` — contact records these activities attach to
- `mx-hubspot-deals` — deal records these activities attach to

---

## Level 1: Engagement Basics (Beginner)

### Pattern 1: Each Engagement Type Has Its Own Endpoint

| Type | Endpoint | Key Properties |
|------|----------|---------------|
| Call | `/crm/v3/objects/calls` | hs_call_body, toNumber, fromNumber, status, durationMilliseconds, recordingUrl, disposition |
| Email | `/crm/v3/objects/emails` | hs_email_subject, hs_email_text, hs_email_direction |
| Meeting | `/crm/v3/objects/meetings` | hs_meeting_title, start_time, end_time, hs_meeting_outcome |
| Note | `/crm/v3/objects/notes` | hs_note_body (max 65,536 chars), hs_attachment_ids |
| Task | `/crm/v3/objects/tasks` | hs_task_subject, hs_task_body, hs_task_status, hs_task_priority |
| Communication | `/crm/v3/objects/communications` | hs_communication_channel_type, hs_communication_body |

Every engagement REQUIRES `hs_timestamp` — it determines position on the CRM timeline.

### Pattern 2: Create an Engagement with Association

```typescript
// Log a call associated with a contact
await hubspot.crm.objects.calls.basicApi.create({
  properties: {
    hs_timestamp: new Date().toISOString(),
    hs_call_body: 'Discussed renewal terms',
    hs_call_status: 'COMPLETED',
    hs_call_duration: '180000',  // 3 minutes in milliseconds
    hs_call_to_number: '+15551234567',
  },
  associations: [{
    to: { id: contactId },
    types: [{ associationCategory: 'HUBSPOT_DEFINED', associationTypeId: 194 }]
  }]
});
```

### Pattern 3: Common Association Type IDs

| From | To | associationTypeId |
|------|----|-------------------|
| Call | Contact | 194 |
| Meeting | Contact | 200 |
| Note | Contact | 202 |
| Email | Contact | 198 |
| Task | Contact | 204 |
| Communication | Contact | 81 |

Always associate at creation time — orphaned engagements are invisible in the UI.

---

## Level 2: Tasks, Notes, Meetings Details (Intermediate)

### Pattern 4: Tasks — hs_timestamp is the Due Date

For tasks only, `hs_timestamp` acts as the **due date**, not the creation date.

```typescript
await hubspot.crm.objects.tasks.basicApi.create({
  properties: {
    hs_timestamp: '2026-04-15T17:00:00.000Z',  // Due date
    hs_task_subject: 'Follow up on proposal',
    hs_task_body: 'Send revised pricing deck',
    hs_task_status: 'NOT_STARTED',
    hs_task_priority: 'HIGH',
    hubspot_owner_id: ownerId,
  },
  associations: [{
    to: { id: contactId },
    types: [{ associationCategory: 'HUBSPOT_DEFINED', associationTypeId: 204 }]
  }]
});
```

**Critical:** Tasks created via API do NOT trigger user notifications. Build your own notification layer if needed.

### Pattern 5: Notes — 65K Character Limit

```typescript
const noteBody = longText.substring(0, 65536);  // Truncate to prevent 400
await hubspot.crm.objects.notes.basicApi.create({
  properties: {
    hs_timestamp: new Date().toISOString(),
    hs_note_body: noteBody,
    hs_attachment_ids: '12345;67890',  // Semicolon-separated file IDs
  },
  associations: [{
    to: { id: contactId },
    types: [{ associationCategory: 'HUBSPOT_DEFINED', associationTypeId: 202 }]
  }]
});
```

### Pattern 6: Meetings — Start Time Must Match Timestamp

```typescript
const startTime = '2026-04-10T14:00:00.000Z';
await hubspot.crm.objects.meetings.basicApi.create({
  properties: {
    hs_timestamp: startTime,              // Must match start time
    hs_meeting_title: 'Discovery Call',
    hs_meeting_start_time: startTime,
    hs_meeting_end_time: '2026-04-10T14:30:00.000Z',
    hs_meeting_location: 'https://zoom.us/j/placeholder-id',
    hs_meeting_outcome: 'SCHEDULED',
  },
  associations: [{
    to: { id: contactId },
    types: [{ associationCategory: 'HUBSPOT_DEFINED', associationTypeId: 200 }]
  }]
});
```

Outcomes: SCHEDULED, COMPLETED, RESCHEDULED, NO_SHOW, CANCELED.

---

## Level 3: Sequences + Communications (Advanced)

### Pattern 7: Sequences API — Enrollment

Requires Sales Hub Professional or Enterprise seat.

```typescript
const enrollUrl = `https://api.hubapi.com/automation/sequences/2026-03/enrollments?userId=${userId}`;
await fetch(enrollUrl, {
  method: 'POST',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({
    contactId: contactId,
    sequenceId: sequenceId,
    senderEmail: 'rep@company.com',  // Must be connected inbox
  })
});
```

Limits: 1,000 enrollments/inbox/day. `senderEmail` must be connected. `userId` query param required.

### Pattern 8: NO Unenrollment API — Use Workflows

There is **NO API endpoint** for sequence unenrollment. Workaround:

1. Create custom contact property `unenroll_trigger` (boolean)
2. Build Workflow: trigger on property change -> action "Unenroll from sequence"
3. From API: PATCH contact property to fire the workflow

### Pattern 9: Communications API — WhatsApp, LinkedIn, SMS

For LOGGING external messages only (not sending):

```typescript
await hubspot.crm.objects.communications.basicApi.create({
  properties: {
    hs_timestamp: new Date().toISOString(),
    hs_communication_channel_type: 'WHATS_APP',  // or LINKEDIN_MESSAGE, SMS
    hs_communication_logged_from: 'CRM',          // Required
    hs_communication_body: 'Discussed pricing options',
  },
  associations: [{
    to: { id: contactId },
    types: [{ associationCategory: 'HUBSPOT_DEFINED', associationTypeId: 81 }]
  }]
});
```

This API is archival only — does NOT transmit messages.

### Pattern 10: Pin Activity to Timeline

```typescript
// Pin engagement to top of contact timeline (only 1 pin per record)
await hubspot.crm.contacts.basicApi.update(contactId, {
  properties: { hs_pinned_engagement_id: engagementId }
});
```

---

## Performance: Make It Fast

### Batch Engagement Creation
For historical syncs, batch create via `/crm/v3/objects/{type}/batch/create` (100 per call).

### Cache Owner IDs
Map rep emails to owner IDs once, cache for hours. Owner lookup is read-only.

### Pre-validate Sequence Enrollment
Check status first to avoid wasting calls on already-enrolled contacts.

## Observability: Know It's Working

### Track hs_timestamp Accuracy
Missing timestamps cause all activities to cluster at execution time — destroys timeline analytics.

### Monitor Sequence Enrollment Count
Track daily enrollment count against 1,000/inbox/day limit.

### Log Association Payloads
If engagements don't appear on timelines, the association was missing. Log for debugging.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never log sales emails via Marketing Email API
**You will be tempted to:** Use Marketing Email API because it handles HTML well.
**Why that fails:** Marketing emails trigger CAN-SPAM headers and unsubscribe links on 1-to-1 sales outreach.
**The right way:** Use `/crm/v3/objects/emails` for sales email logging.

### Rule 2: Never omit hs_timestamp
**You will be tempted to:** Skip it and let HubSpot default to "now."
**Why that fails:** Historical syncs of thousands of activities all cluster at one millisecond.
**The right way:** Always provide the actual timestamp.

### Rule 3: Never create orphaned engagements
**You will be tempted to:** Create now, associate later.
**Why that fails:** Orphaned engagements are invisible. Association batch jobs fail silently.
**The right way:** Include `associations` array at creation time.

### Rule 4: Never search for a sequence unenrollment endpoint
**You will be tempted to:** Try reverse-engineering frontend calls.
**Why that fails:** No endpoint exists. Scraping gets your token suspended.
**The right way:** Contact property change triggers a Workflow that unenrolls.

### Rule 5: Never use Communications API to send messages
**You will be tempted to:** Think it sends WhatsApp/SMS because of the channel type field.
**Why that fails:** Purely archival. Does not transmit anything.
**The right way:** Use external APIs (Twilio, WhatsApp Business), log via Communications API.
