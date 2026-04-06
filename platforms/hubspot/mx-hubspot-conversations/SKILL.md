---
name: mx-hubspot-conversations
description: "HubSpot Conversations API — inboxes, threads, messages, custom channels API, visitor identification API, chatflows, help desk API, conversation inbox management"
---

# HubSpot Conversations — Inbox, Threads, Custom Channels for AI Coding Agents

**Load when interacting with the conversations inbox or custom messaging channels.**

## When to also load
- `mx-hubspot-core` — SDK setup (co-default)
- `mx-hubspot-automation` — webhooks for conversation events

---

## Level 1: Conversations Basics (Beginner)

### Pattern 1: Core Endpoints

| Resource | Endpoint |
|----------|----------|
| List inboxes | `GET /conversations/v3/conversations/inboxes` |
| Get inbox | `GET /conversations/v3/conversations/inboxes/{inboxId}` |
| List threads | `GET /conversations/v3/conversations/threads` |
| Get messages | `GET /conversations/v3/conversations/threads/{threadId}/messages` |

Send outbound messages and internal comments to agents via the same API.

### Pattern 2: Webhook Events for Conversations

Subscribe to: `conversation.creation`, `conversation.deletion`, `conversation.propertyChange`, `conversation.newMessage`.

---

## Level 2: Custom Channels and Visitor ID (Intermediate)

### Pattern 3: Custom Channels API

Integrate any text-based messaging into HubSpot: SMS, Instagram, Telegram, LINE, WhatsApp, Slack. Available with Sales/Service Hub Professional+.

2025 updates: validation enforcement for deliveryIdentifierTypes, webhooks for channel connection, channel metadata customization (name, logo).

### Pattern 4: Visitor Identification API

Generate tokens for authenticated chat visitors. Enables HubSpot chat widget to recognize known contacts across devices. Requires Professional or Enterprise subscription.

---

## Level 3: Help Desk Integration (Advanced)

### Pattern 5: Help Desk API Patterns

Conversations API manages Help Desk channels and messages directly. Calling Extensions SDK (2025) supports inbound calling with auto-ticket creation. Transcription API (beta Fall 2025) syncs third-party call transcriptions.

**BREAKING CHANGE:** Thread comments transitioning to notes by Sept 2026. Use CRM Notes API instead of `type: "COMMENT"` for Help Desk threads.

---

## Performance: Make It Fast

### Filter Threads by Status
Use query parameters to filter for open/closed threads. Don't fetch all and filter in memory.

## Observability: Know It's Working

### Monitor Message Delivery
Track outbound message delivery status. Failed deliveries on custom channels need retry logic.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never use thread comments for Help Desk after Sept 2026
**You will be tempted to:** Keep using `type: "COMMENT"` because it works today.
**Why that fails:** Will return errors after September 23, 2026.
**The right way:** Migrate to CRM Notes API for Help Desk internal notes.
