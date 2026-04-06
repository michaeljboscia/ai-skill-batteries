# Comprehensive Technical Guide to the HubSpot Sales Activities API in TypeScript

**Key Points:**
* The HubSpot CRM API v3 transitions sales engagements into dedicated standard objects, offering discrete RESTful endpoints for calls, emails, meetings, notes, and tasks.
* Absolute chronological integrity is maintained via the `hs_timestamp` property; its omission results in non-deterministic timeline positioning or defaults to the execution time.
* Relational mapping upon object creation strictly requires the definition of an `associations` array, mapped via `associationCategory` (typically `HUBSPOT_DEFINED`) and explicitly defined numerical `associationTypeId`s.
* The API enforces strict limitations to preserve platform stability, such as a 65,536-character maximum for note bodies and a 1,000-per-day sequence enrollment limit per inbox.
* API-driven unenrollment for HubSpot Sequences does not exist; developers must fundamentally alter their architectural approach to rely on HubSpot Workflows or manual UI interventions. 

**Architectural Paradigm Shifts**
Historically, developers interacting with customer relationship management (CRM) systems utilized monolithic "engagement" endpoints. The HubSpot Sales Activities API diverges from this by strictly adhering to an object-oriented API topology. Every engagement type (calls, meetings, tasks, notes, communications, and emails) operates as an independent CRM object, possessing its own unique property schemas and relational constraints [cite: 1, 2]. 

**The Necessity of Type Safety**
Within distributed systems and integrations, the failure to validate payload structures pre-flight results in cascading network errors and data corruption. By leveraging TypeScript, developers can enforce strict static typing over HubSpot's highly specific payload requirements, such as the dichotomy between internal millisecond durations and ISO 8601 timestamps, or the precise integer mapping of relational graphs (e.g., `associationTypeId: 200` for Meeting-to-Contact) [cite: 3, 4].

**Operational Limitations and System Boundaries**
Interacting with the HubSpot CRM is not merely an exercise in data transmission, but an orchestration of rate limits, pagination cursors, and silent constraints. For example, API-created tasks actively suppress user notifications to prevent notification flooding, and sequence enrollments impose strict constraints requiring specific licensing (Sales Hub Professional or Enterprise) [cite: 5].

---

## 1. Epistemology of HubSpot Engagements in API v3

The transition to HubSpot's CRM API v3 represents a fundamental paradigm shift from legacy monolithic engagement structures to a polymorphic, object-oriented schema. In this architecture, each sales activity is codified as a discrete entity with highly specialized properties. 

### 1.1 Dedicated Endpoints and the Object Model
Instead of routing all activities through a single `/engagements` endpoint, API v3 dictates that each engagement type is interacted with via a dedicated path [cite: 1, 2]. This structural segregation ensures that payload schemas can be strictly enforced at the routing level.

The core endpoints covered in this treatise include:
* `/crm/v3/objects/calls` [cite: 6]
* `/crm/v3/objects/emails`
* `/crm/v3/objects/meetings` [cite: 7]
* `/crm/v3/objects/notes` [cite: 8]
* `/crm/v3/objects/tasks`
* `/crm/v3/objects/communications` [cite: 9]

### 1.2 The Critical Role of `hs_timestamp`
In the context of chronological systems like a CRM timeline, time is not merely metadata; it is the primary sorting vector. The `hs_timestamp` property dictates the exact chronological position of the engagement on the associated record's timeline [cite: 6, 8]. 
* For historical syncs, `hs_timestamp` accepts either a Unix timestamp in milliseconds or a UTC string format.
* For Tasks, the `hs_timestamp` uniquely acts as the **due date** for the task [cite: 10].

### 1.3 Graph Relational Modeling: The Associations Array
Creating an engagement without linking it to a primary CRM record (such as a Contact or Company) results in an "orphaned" object, inaccessible via the user interface. API v3 mandates that relationships be defined at the moment of creation using the `associations` array [cite: 8, 11].

The structure requires defining the target object (`to.id`) and the edge relationship (`types`). The types array requires:
1. `associationCategory`: Typically `HUBSPOT_DEFINED` for default relationships.
2. `associationTypeId`: A numerical identifier representing the specific directional relationship (e.g., Contact to Meeting is `200`) [cite: 3, 4].

### 1.4 TypeScript Base Interfaces
To establish a foundation for the technical reference, we must first define the generic base interfaces that govern all engagement creations.

```typescript
// types/hubspot-base.ts

export type AssociationCategory = "HUBSPOT_DEFINED" | "USER_DEFINED";

export interface HubSpotAssociationType {
  associationCategory: AssociationCategory;
  associationTypeId: number;
}

export interface HubSpotAssociation {
  to: {
    id: string;
  };
  types: HubSpotAssociationType[];
}

export interface BaseEngagementCreate<T> {
  properties: T;
  associations: HubSpotAssociation[];
}

export interface BaseEngagementResponse<T> {
  id: string;
  properties: T;
  createdAt: string;
  updatedAt: string;
  archived: boolean;
}
```

---

## 2. Call Engagements

Call engagements represent synchronous audio communications. The data schema for calls must capture both the metadata of the telecommunications transmission and the qualitative outcome of the interaction.

### 2.1 Call Properties Specification
When initiating a POST request to `/crm/v3/objects/calls`, the properties object supports a robust set of fields tracking the call's origination, termination, and duration [cite: 6, 12]:

* `hs_call_body`: The qualitative notes or transcription of the call.
* `hs_timestamp`: The exact time the call was initiated.
* `toNumber` / `hs_call_to_number`: The terminating phone number.
* `fromNumber` / `hs_call_from_number`: The originating phone number.
* `status` / `hs_call_status`: The current state of the call (e.g., COMPLETED, CONNECTING, RINGING).
* `durationMilliseconds` / `hs_call_duration`: The total length of the call, strictly formatted as an integer representing milliseconds [cite: 12, 13].
* `recordingUrl` / `hs_call_recording_url`: A secure HTTPS link to the audio file (.mp3 or .wav), enabling in-app playback [cite: 12].
* `disposition` / `hs_call_disposition`: The internal GUID representing the outcome of the call (e.g., Busy, Connected, Left Voicemail) [cite: 6, 12].

### 2.2 TypeScript Implementation for Calls

```typescript
// types/calls.ts
import { BaseEngagementCreate, BaseEngagementResponse } from './hubspot-base';

export interface CallProperties {
  hs_timestamp: string; // ISO-8601 or millisecond string
  hs_call_body: string;
  toNumber: string;
  fromNumber: string;
  status: "COMPLETED" | "MISSED" | "BUSY" | "RINGING" | "CANCELED";
  durationMilliseconds: string; // e.g., "120000" for 2 minutes
  recordingUrl?: string; // Must be HTTPS
  disposition?: string; // Internal GUID for outcome
  hs_pinned_engagement_id?: string; // Optional pinning parameter
}

export type CallCreatePayload = BaseEngagementCreate<CallProperties>;
export type CallResponse = BaseEngagementResponse<CallProperties>;

// Example execution
async function logCall(payload: CallCreatePayload): Promise<CallResponse> {
  const response = await fetch('https://api.hubapi.com/crm/v3/objects/calls', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${process.env.HUBSPOT_TOKEN}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(payload)
  });
  
  if (!response.ok) {
    throw new Error(`Failed to log call: ${response.statusText}`);
  }
  return response.json();
}
```

---

## 3. Meeting Engagements

Meetings encompass scheduled interactions and calendar events. The API maps these explicitly to the `/crm/v3/objects/meetings` endpoint, requiring stringent time boundary definitions [cite: 7].

### 3.1 Meeting Properties Specification
The schema for meetings necessitates an understanding of start and end chronologies:

* `hs_meeting_title`: The subject line or title of the meeting.
* `hs_meeting_start_time`: The ISO-8601 or Unix timestamp representing the beginning of the event. This must strictly equal the `hs_timestamp` parameter [cite: 7].
* `hs_meeting_end_time`: The timestamp representing the conclusion of the event.
* `hs_meeting_location`: A string representing the physical address, room, or videoconference link [cite: 7].
* `hs_meeting_outcome`: The status of the meeting. Acceptable values typically include `SCHEDULED`, `COMPLETED`, `RESCHEDULED`, `NO_SHOW`, and `CANCELED` [cite: 7].

### 3.2 Association Enforcement
To ensure a meeting appears on a Contact's timeline, it must be associated using `associationTypeId: 200` (Contact to Meeting) [cite: 3, 4, 14].

### 3.3 TypeScript Implementation for Meetings

```typescript
// types/meetings.ts
import { BaseEngagementCreate, BaseEngagementResponse } from './hubspot-base';

export interface MeetingProperties {
  hs_timestamp: string; // Must match hs_meeting_start_time
  hs_meeting_title: string;
  hs_meeting_body?: string;
  hs_meeting_start_time: string;
  hs_meeting_end_time: string;
  hs_meeting_location?: string;
  hs_meeting_outcome?: "SCHEDULED" | "COMPLETED" | "RESCHEDULED" | "NO_SHOW" | "CANCELED";
}

export type MeetingCreatePayload = BaseEngagementCreate<MeetingProperties>;

// Payload Example for meeting->contact association
const meetingPayload: MeetingCreatePayload = {
  properties: {
    hs_timestamp: "2024-08-20T11:30:00.000Z",
    hs_meeting_title: "Q3 Vendor Review",
    hs_meeting_start_time: "2024-08-20T11:30:00.000Z",
    hs_meeting_end_time: "2024-08-20T12:30:00.000Z",
    hs_meeting_location: "https://zoom.us/j/123456789",
    hs_meeting_outcome: "SCHEDULED"
  },
  associations: [
    {
      to: { id: "104901" }, // Contact ID
      types: [
        {
          associationCategory: "HUBSPOT_DEFINED",
          associationTypeId: 200 // Explicit integer for Meeting-to-Contact
        }
      ]
    }
  ]
};
```

---

## 4. Note Engagements

Notes serve as the unstructured repository for textual qualitative data linked to CRM records. They are accessed via `/crm/v3/objects/notes` [cite: 8].

### 4.1 Note Properties and Strict Limitations
* `hs_timestamp`: The chronological placement of the note on the timeline [cite: 8].
* `hs_note_body`: The HTML or plain text body of the note. This property enforces a rigorous constraint: **it cannot exceed 65,536 characters**. Exceeding this limit will trigger a `400 Bad Request` with an error indicating `MAX_CHARACTERS` [cite: 8, 15].
* `hs_attachment_ids`: A semi-colon separated string of file IDs uploaded via the Files API, linking specific documents directly to the note interface [cite: 8].

### 4.2 TypeScript Implementation for Notes

```typescript
// types/notes.ts
import { BaseEngagementCreate, BaseEngagementResponse } from './hubspot-base';

export interface NoteProperties {
  hs_timestamp: string;
  hs_note_body: string; // Strictly <= 65536 characters
  hs_attachment_ids?: string; // Semi-colon separated, e.g., "12345;67890"
}

export type NoteCreatePayload = BaseEngagementCreate<NoteProperties>;

// Best practice: Truncate strings before transmission to prevent 400 errors
function sanitizeNoteBody(body: string): string {
  const MAX_LIMIT = 65536;
  return body.length > MAX_LIMIT ? body.substring(0, MAX_LIMIT) : body;
}
```

---

## 5. Task Engagements

Tasks are actionable items assigned to users. They are manipulated via `/crm/v3/objects/tasks`. 

### 5.1 Temporal Mapping and Silent Operations
Tasks diverge temporally from other engagements. While `hs_timestamp` determines historical placement for calls and meetings, for tasks, **`hs_timestamp` functions as the Due Date** [cite: 10]. 

A critical architectural limitation that developers frequently overlook: **Tasks created via the API do NOT trigger in-app or email notifications for the assigned user** [cite: 10, 16]. This is an intentional anti-spam mechanism implemented by HubSpot. If notifications are required, developers must architect workaround solutions (such as using an external Slack/Teams API ping, or enrolling the contact in a Workflow that assigns a task natively).

### 5.2 TypeScript Implementation for Tasks

```typescript
// types/tasks.ts
import { BaseEngagementCreate, BaseEngagementResponse } from './hubspot-base';

export interface TaskProperties {
  hs_timestamp: string; // Represents the DUE DATE
  hs_task_body: string;
  hs_task_subject: string;
  hs_task_status: "NOT_STARTED" | "COMPLETED" | "IN_PROGRESS" | "WAITING" | "DEFERRED";
  hs_task_priority?: "LOW" | "MEDIUM" | "HIGH";
}

export type TaskCreatePayload = BaseEngagementCreate<TaskProperties>;
```

---

## 6. Sequences API and Automation Constraints

The Sequences API represents one of the most highly restricted and operationally complex surfaces in the HubSpot ecosystem. Sequences are automated series of targeted, timed email templates and task reminders meant to nurture sales prospects [cite: 5].

### 6.1 Licensing and Global Limitations
To interact with the Sequences API, the underlying portal and the specific user must possess a **Sales Hub Professional or Enterprise** (or Service Hub equivalent) seat [cite: 5]. 

Furthermore, HubSpot implements strict, unyielding rate limits to preserve email deliverability and prevent spam:
* There is a strict limit of **1,000 sequence enrollments per portal inbox per day** [cite: 5].

### 6.2 The Enrollment Endpoint
Enrollments are processed via a POST request to `/automation/sequences/2026-03/enrollments` (or `/automation/v4/sequences/enrollments` depending on the specific beta/versioning path utilized, though `/2026-03/` is commonly specified in targeted enterprise documentation and the prompt directives) [cite: 5, 17, 18, 19].

**Required Data Points:**
1.  **userId**: Provided as a query parameter in the URL. This must be the ID of the user who *owns* the sequence [cite: 5, 17, 20].
2.  **contactId**: The internal string identifier of the CRM contact being enrolled [cite: 19, 20].
3.  **sequenceId**: The identifier of the specific public sequence [cite: 19, 20].
4.  **senderEmail**: The authenticated, connected email address of the user initiating the send [cite: 17, 19].
5.  **steps array**: An array dictating the progression, utilizing `actionType`, `delayMillis`, and `stepOrder`.

### 6.3 The Unenrollment Architectural Gap
A paramount consideration for developers is that **there is NO API endpoint to unenroll a contact from a sequence** [cite: 21, 22, 23]. 

If a programmatic system dictates that a contact must be pulled from a sequence (for instance, if they completed a transaction in a disparate external system like Stripe), the developer cannot issue a simple `DELETE` or `POST` request to an `/unenroll` endpoint.

Instead, developers must utilize **HubSpot Workflows**. By building a Contact-based Workflow with an action to "Unenroll from sequence," external systems can use the API to update a custom Contact property (e.g., `external_system_status = "Purchased"`). The Workflow listens for this property change and executes the native unenrollment action on behalf of the API [cite: 22, 24].

### 6.4 TypeScript Implementation for Sequences

```typescript
// types/sequences.ts

export interface SequenceStep {
  actionType: "SEND_TEMPLATE_EMAIL" | "CREATE_TASK";
  delayMillis: number;
  stepOrder: number;
}

export interface SequenceEnrollmentPayload {
  contactId: string;
  sequenceId: string;
  senderEmail: string;
  steps?: SequenceStep[];
}

export interface SequenceEnrollmentResponse {
  id: string;
  contactId: string;
  sequenceId: string;
  createdAt: string;
  updatedAt: string;
}

// Execution block demonstrating the userId query parameter requirement
async function enrollInSequence(
  userId: string, 
  payload: SequenceEnrollmentPayload
): Promise<SequenceEnrollmentResponse> {
  // Ensuring the userId query parameter is attached as required by the documentation
  const url = `https://api.hubapi.com/automation/sequences/2026-03/enrollments?userId=${encodeURIComponent(userId)}`;
  
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${process.env.HUBSPOT_TOKEN}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    throw new Error(`Sequence Enrollment Failed: ${response.status} - ${await response.text()}`);
  }
  
  return response.json();
}
```

---

## 7. Communications API (WhatsApp, LinkedIn, SMS)

With the proliferation of multichannel sales strategies, logging activities outside of traditional email and calls became a necessity. The Communications API (`/crm/v3/objects/communications`) addresses this by allowing programmatic insertion of WhatsApp, LinkedIn, and SMS messaging logs onto the CRM timeline [cite: 9].

### 7.1 Communication Properties Specification
* `hs_communication_channel_type`: This is a strictly typed enum. Acceptable values are `WHATS_APP`, `LINKEDIN_MESSAGE`, or `SMS` [cite: 9, 25].
* `hs_communication_logged_from`: Used to differentiate object origins. For external API integrations, this **must be set to `CRM`** [cite: 9].
* `hs_communication_body`: The textual payload of the message [cite: 9].
* `hs_timestamp`: Determining timeline chronography [cite: 9].

*(Note: This API is exclusively for logging historical sales messages; it does not actually transmit SMS or WhatsApp messages to end-users. It is purely an archival and timeline visualization tool for sales representatives)* [cite: 9].

### 7.2 TypeScript Implementation for Communications

```typescript
// types/communications.ts
import { BaseEngagementCreate, BaseEngagementResponse } from './hubspot-base';

export interface CommunicationProperties {
  hs_communication_channel_type: "WHATS_APP" | "LINKEDIN_MESSAGE" | "SMS";
  hs_communication_logged_from: "CRM"; // Hardcoded required value
  hs_communication_body: string;
  hs_timestamp: string;
  hubspot_owner_id?: string;
}

export type CommunicationCreatePayload = BaseEngagementCreate<CommunicationProperties>;

const smsPayload: CommunicationCreatePayload = {
  properties: {
    hs_communication_channel_type: "SMS",
    hs_communication_logged_from: "CRM",
    hs_communication_body: "Hey, are we still on for tomorrow?",
    hs_timestamp: new Date().toISOString()
  },
  associations: [
    {
      to: { id: "889922" },
      types: [{ associationCategory: "HUBSPOT_DEFINED", associationTypeId: 81 }] // Contact to Comm
    }
  ]
};
```

---

## 8. Pinning Engagements (`hs_pinned_engagement_id`)

Record timelines can become deeply congested. To elevate critical engagements (such as a finalized contract meeting or a pivotal discovery call), HubSpot provides a mechanism to "pin" exactly one activity to the top of a record's timeline (Contact, Company, Deal, or Ticket) [cite: 26, 27, 28].

### 8.1 Implementation Rules
Pinning is not executed on the engagement object itself. Instead, it is an operation executed on the **Parent Record** (e.g., the Contact or Deal) [cite: 26, 28].

1. Create the engagement and capture its resulting `id`.
2. Ensure the engagement is officially associated with the target CRM record [cite: 26, 27].
3. Execute a `PATCH` request to the target CRM record (e.g., `/crm/v3/objects/contacts/{contactId}`).
4. Update the `hs_pinned_engagement_id` property with the engagement's ID [cite: 26, 27, 28].

```typescript
// Pinning utility
async function pinEngagementToContact(contactId: string, engagementId: string): Promise<void> {
  const url = `https://api.hubapi.com/crm/v3/objects/contacts/${contactId}`;
  
  await fetch(url, {
    method: 'PATCH',
    headers: {
      'Authorization': `Bearer ${process.env.HUBSPOT_TOKEN}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      properties: {
        hs_pinned_engagement_id: engagementId
      }
    })
  });
}
```

---

## 9. Architectural Decision Trees

When orchestrating a HubSpot integration, choosing the correct API surface is critical. Use the following decision trees to navigate complex architectural choices.

### 9.1 Decision Tree: Choosing the Engagement Type
```text
[START] --> Does the interaction represent an external messaging channel?
  |-- YES --> Is it SMS, WhatsApp, or LinkedIn?
  |     |-- YES --> Use POST /crm/v3/objects/communications
  |     |-- NO  --> Is it a postal mail? --> Use Postal Mail API.
  |-- NO  --> Is it a scheduled chronological event with duration?
        |-- YES --> Is it a telephonic conversation?
        |     |-- YES --> Use POST /crm/v3/objects/calls
        |     |-- NO  --> Use POST /crm/v3/objects/meetings
        |-- NO  --> Is it a forward-facing actionable item?
              |-- YES --> Use POST /crm/v3/objects/tasks (hs_timestamp = due date)
              |-- NO  --> Is it unstructured qualitative data/files?
                    |-- YES --> Use POST /crm/v3/objects/notes (Limit: 65,536 chars)
```

### 9.2 Decision Tree: Handling Sequence Unenrollments Programmatically
```text
[START] --> Must unenroll a contact from a Sequence via external API trigger.
  |-- Step 1: Realize there is NO API endpoint for Sequence Unenrollment.
  |-- Step 2: Create a Custom Property on the Contact record (e.g., `unenroll_trigger = boolean`).
  |-- Step 3: Create a Contact-based Workflow in HubSpot UI.
        |-- Trigger: `unenroll_trigger` changes to TRUE.
        |-- Action: "Unenroll from sequence".
  |-- Step 4: From your external TypeScript app, send a PATCH request to /crm/v3/objects/contacts/{id}.
        |-- Payload: { properties: { unenroll_trigger: true } }
  |-- Step 5: HubSpot Workflow detects the API update and unenrolls the contact automatically.
```

---

## 10. Anti-Rationalization Rules for HubSpot Integrations

Cognitive bias and architectural rationalizations frequently lead developers to build brittle integrations that degrade over time. The following rules are absolute mandates designed to prevent common technical rationalizations in the HubSpot API ecosystem.

### Rule 1: Never Log Sales Emails via the Marketing Email API
* **The Rationalization:** *"The Marketing Email API handles HTML delivery so well, I'll just use it to log these one-to-one rep outreach emails."*
* **The Reality:** Marketing emails and Sales emails sit in completely different relational databases and UI paradigms within HubSpot. Marketing emails trigger massive unsubscribe headers, compliance checks (CAN-SPAM/GDPR), and obscure the 1-to-1 nature of sales communication. 
* **The Rule:** Sales emails must be strictly logged via `/crm/v3/objects/emails`. They are individual engagements representing personal communication, not broadcast campaigns.

### Rule 2: Never Omit `hs_timestamp` 
* **The Rationalization:** *"I don't have the exact time the call happened in my source database, I'll just leave `hs_timestamp` blank and let HubSpot figure it out."*
* **The Reality:** Omitting `hs_timestamp` forces the CRM to append the current server execution time to the engagement. If you are running a historical sync of 10,000 calls from three years ago, all 10,000 calls will appear on the Contact's timeline as having occurred today at the exact same millisecond. This destroys analytical reporting and rep trust.
* **The Rule:** You must always calculate, estimate, or explicitly provide an `hs_timestamp` to maintain chronological integrity.

### Rule 3: Never Create Orphaned Engagements
* **The Rationalization:** *"I'll just create the Call record now because I only have the phone number, and I'll associate it to the Contact record later in a batch cron job."*
* **The Reality:** Engagements created without an `associations` array disappear into the hidden ether of the CRM backend. They do not trigger UI updates, they are virtually invisible to standard users, and subsequent association batch jobs are highly prone to race conditions or failing silently.
* **The Rule:** The `associations` array must be populated synchronously at the precise moment of object creation, dictating the `associationCategory` and the strict integer `associationTypeId`.

### Rule 4: Stop Looking for a Sequence Unenrollment Endpoint
* **The Rationalization:** *"There has to be an undocumented or v4 endpoint to `DELETE` a sequence enrollment. I will just try reversing the `POST` endpoint to see if it works, or scrape the frontend."*
* **The Reality:** HubSpot has explicitly restricted Sequence unenrollment from the API to maintain tight controls over sales automation state machines [cite: 21, 22, 23]. Reverse-engineering frontend calls will result in aggressive rate-limiting or immediate suspension of your Private App token.
* **The Rule:** Do not try to unenroll contacts via direct API calls. You must architect an event-driven loop where your API updates a Contact property, which in turn triggers a native HubSpot Workflow to execute the unenrollment [cite: 22, 24].

---

## 11. Conclusion and Implementation Strategy

Mastery of the HubSpot Sales Activities API requires a departure from unstructured data lakes and an embrace of strongly typed, relationally rigid object mapping. By implementing the provided TypeScript interfaces, respecting physical limitations like the 65,536-character note limit, acknowledging system boundaries like the lack of task notifications, and adhering strictly to the Anti-Rationalization Rules, developers can construct deeply embedded, highly reliable enterprise CRM integrations that scale symmetrically with organizational growth.

**Sources:**
1. [github.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEOO8doJImj1P0Lju9JlY4_VcSmVE38sMfOXz2EjBkvQyeFXo67CWk4Bf_viMbHnXIseN2F8SoWrbTtarg2bRSGFgFAkbcr0OzXOqpuqaQC77PBAAkpeF2fB93Jpy2rIejkKS8CsFGxfeSoZZqf67mhRitB)
2. [github.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGpKkmOsCB0ktDmZnO__P-Gaa52Belb9IJHKc_3yUICrLzab8ZOEj8shpslVc2GuwGI_1sFzjAN_YV8fLYMJaOAA7Xifitb-ZjhFIdex2asrTpmrcDggozPFidW8Vbt6H9ixToLu7ra8dQ7AqZcNN9cjWbg)
3. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEglKmGdvpiHBqwOtw4V0nFDolQ1txHWWJ26iUidwDragQDbM8Nq05t6_Wi8FaDD1HoiZ2FPyVtuUxPQ0QeiMga8EKjNZX1m5pCYxKv0zsW1dGHeHyK02STp4G1AwChFpPtTN8ypA4aK5vvFqsVQqXOhGvXo8zy-GZO-ETQLv3BvbcgKLOa5LhxSBj2vhgce9bLVMwRv8oNpCa3nWZDT0QnwaBZaZE=)
4. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHelkMoDUKnnh2mOuTijUZ0UQNdjbqJ6hZU8gpHBWnDIn1Q1tR8-kbnAFp0UcGm3wwgWCaRoBubqR6I5lLD6xjESwWzZ0AiSeQindmn-pnLxnuzTNQ8oTCN1n2NrQ4QRoUDhhmGDfHZJBdcGpcpNP9E-XBZgJ5ojBUV0FaTsAOfgms=)
5. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQET3nZ4ncZ7hkKhrnNJaKQk8zlPow7ir-V18-0Rx3zlq-xYH4G318t-a3veUse5bg8GYoTn0IZ6dCqwifQrc7lPzhL0Q2l2DRSojVEMFlyK-aNVoXBXRv4ZxfqImz1BkUUuQ0BMlMbHSHnmnlHu9xtuKxK9BSOL3jUxCb1RKThmI1-iDvhLjVEvkw==)
6. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGt3dbItQ5S9aksYiMhJitnUBqcSLHaNtryHgb_wlDKY8caE_TSeFVGAjhjkMQ2RM2RaQZyf6oaNbsAY8BcVQ5X_uAYxZ-_9pZyvKjOaql3yGqEHGwkewobEjIPSJmnkDlmKmNyiQ5-p71qOqH7y7TApKE3L9LmUh9vww==)
7. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFBmvDGZaDLKE9VWRlIFtmvAdF2hbrqGTHGN2f_9BvQn24em06z5PriYlkYKaVbncMeF-bxyyfkRkTQCAoj4U_PCgVM7jKQ0uxDLDjzSljTKUiuh2MblLS_4IusdrxsjQRiX2rwGSzkuir0hNryB8X2gwBkalZ0QKXdtxhy2gYBcCsE2b8OGG_E8P8hZA==)
8. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGG5hFyQ3DAaqW8fohvbbOrkGZPJKHSRrWnyFDiPrc7qZIONV-2vbrzY4i14nQ7hBr9LtP_F_U1uMscqcSrOZvgMK_bnPVRRO_rstM9Z5o2oBd1T829ZGCvIZrolDPJpX2EE5rQ0HtoUgooyanvw_B4SAROBChY2vPRMQYjzhFj9udTFIsh1Vjcqg==)
9. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGajQvQIipszK6jhfKSo4dXMHQov8EeYRm7tRkjpEv9ZzES-QlxYOTo0-NzC6ANePv22h0a6fs7HKVNtkRPF2IAq3dCxZd6OVUgn6IrnftUND1HuvG44E_OBg0LV5aoJwLBAzSH2c2e2c56sr8-AAg7ucI9ll69ibvPUdPUAUsiFtKh0ic498qkqPqmN4WXbg==)
10. [clonepartner.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHF_0D7lXDmsshEjhSuw4dbqhJLj_8-zPaM43Tsd3q4ckpARnedx4apNXoOTRDxtVAuqdP5Hplmz28gVlGJAa-7MU6TNdZ6pgUD6nfVylnQbbg5EjNJ2PRxjZ8hpOBKImwIMrvgWvcl_Soi5hD9MwIlJgZ83OIvwSwE6HcMC5-9c3aiSkM7TSZ9yBERRgbgaQ==)
11. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQF56SAAzHiPmYFGgE4U45mv4yMNMAJVG3DTj2ZaJCbeXoXNcYr24bPfUAZTUsOgjevnOM6XwCWmAh9XosNPJUOUPZ41jid4GcrBfyjFaSVek_rnHHJX8GU644Khge3nJKDJmXLSeo7ooSBu2CJcd1oAGHorgmimVM_oBAwoxkmMC0IFrMfOX33i85HsNgJ3rl57JmW3f39VkGYX7JxdJQ==)
12. [postman.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQH2G4iD7Q7ml6z9EAEvzbyt4LAbYF8nUqcR_ZJR_YNe1BCUyO59fWyFhdUevVM-EZlaMESyoGyeP3RHcKZNw-NFql8nBUGxk0y_yDBqC2BIJlQ4fyNxouKnTMxDBmXCYjHeh6m7m4Qglo3qvyKoe7pGAq5V2uPHacmK9igJCC3aHQeGzB7HJoMS175Z)
13. [tibco.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHtw7r6pgpmCHH6PUmziRPHZict5sWjSwxh4krGuU-bcsv5BIdkwFQaPPQPGvIFX1LknzaUOn4iKT2pgAaCbD5H6MmBzAPNdBjRHfMgqH0ZTY-rKzBovuxktWafYOM3v1VbWYKao7yOzv__njMdYFoVeLAHbplJMVyxaH0Kn39QO4mc9zEWBmit6AjJT5uyrA==)
14. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGgOAk968hrwFnuort1QnZ0yRxTVHAgsK4tkVs4Ov3sdzYB8rctTmGIggIIvh_feWKd4KZ7XqmzsWWBicfffljt4aoGtsgpuS5HtW6kkRW354UYDGUIMjw6heoLWnei4Rp_OVwf1aZ-ESxBWIfhB6ptM4g6rcM6eRl3rD-WNyVL0aPKghQ-KpHq7BN1fkh7PXYOmVmtEqiig-3TrVHGX5cswbvj5b3B)
15. [make.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGh1YbbwyHgCP5LLLC-nwuGNFcirANgCaIVyGpaKJz533nXMGb7_ZN1AI8n_VZHElBWWp-_qquv_InnPdh8nwNtQvuSe4tZAvO1KW9VuUZd7LwtACJMjXHbV7A4rB92hg2drFtKD_vrewjvS7xG6nDT2SNkzg0FY39Qwv822DHL)
16. [wazzup24.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGWQ_oXg6XZtZnq6Va_zQTdIiDcwi-yJ2oxiSVc-owo1_zfPO6B_9bQe8Frk2brb8CAhxmb939IdlgZutWjUK1pcMTnwew0w1lebLM9-URKx6ZTLx14_svYt4s=)
17. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFzIqDNO1ywNQomVuLIDXNafcEy0BNT1VCiDdCV25ty8g5UWyaj9et0tY8TEO288JcuDj18VnkgXE-WJObsiCbAMgVzcNFcc66B9rMxAOOV5aHWbk95vpuM9EhnqMMR7bCh2IbK2hnuKfogjCjKT2yIXvliX5RUYVfceU3NRCBeZ5KBscKP9rFsSQp05-7ZDCLI-w==)
18. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGWlthARAfIIZYEv4E4PYG6c0bKghfMg0fsfEwct3-0q7seZHc_8FtGUuO5_1n_k173VD-2vf0ZVYJY9k_jxJHGrkhP17OdtwhsUSOpig0a5BZyWqm3utm8-5DIVAxyNyEEE583GtqNc_KjmLlMDtj3vIoPwxWD4b4OwdHV51Z9urt4NQN38nB3L7elnnK2OMBmjw==)
19. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGNEKqMYSeXtdiomeTvWY4FMIsJsd_ska1ywTsY1RZ1gQdhypzxnBAPTjPfpFHKNCSjxOaL9PdmuovTYM3-DLK6P1jQUaLKuPn5fmuivFFOrfhSM_pUBItNEle1NBTDcBVF1fILJXgiMrLABU9kyjvZmxvQ4WY1pqSXe499ktH8XQlbBDoUwYnv6gjzKugSLiGvCI8_rFs312Ej6SOtGC041FC3rgxDubliqcfF45qVZ1fGMBe6hjqdrYZquw==)
20. [youtube.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQF2D7lcPo63rpsY7gBUNhdLR_jb0f74GnuFXMeg_lHfeDc7GLbxQIOexIP68rXDSQ_WGrS22exfdjMR_x7vq9NjvZ6Hets-AolxvOu2DjNhqK2V2Whr-BP0GxTmL4pARRek)
21. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFyRmpWCbe1LnrKGu5TauCSt0_q9Rp_3wzSekTmu0zBTzFPPp0Yg4QyCdyr3Wotphmz-YQlaSvNF0r9HGx5Q3m-unNDEQ4jEH8sS1VmN_2WpL-8RaqmjTMJZ-yGUkhT3pkIPP3BU-EEr6xokDDIRWNxlBbvpg==)
22. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE_YXADcD-z10xK5qi3wL6vMpH89HfzeyPHmxY5yV2I-VdoFEr7-cJnLzAPVYNJAOVosiNlI5rUgQ62KyWXuxTimM4epw9KC5vXvYx7BpMUyIOsBukyMyKhVbteZakp924W-QrGNA-w9yxmgkjVPIj5R6w7fyWSxFS77Zcd0-BSpdclJq5sP9EhVYWj7n5Tj5_XG9jZSdq0)
23. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE3RGOvESo_Z_osy-GfQsLjwUeL9Br29V4rOnzqQ5frey8U43xPh-3XsEbmgiOcOiVRZWD5YxFGd8R3o_KDKceVMb8dFmQriEpgi-ER6jMBO0g8p0cwKl3LFbx3TN-tK5NUSTWRzdmfzqqWxSaubQMXjHTlibBYuNREgrkLTqgWgoobn_QHSJinVNxvHVL2_VywfkB-d1oYHQ==)
24. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFaLcCP6unTna4CI6B8xHOvaUipgtbJMjYHOoa_OO1YzJFK9hTZhyRP20WB_IyNsOVYZoIqwRPC4wy-MhE8a-PPOIC824e_Ujh4sEYikEcRZY5pnoWOcVCAlXPhTA1ErPdQk2_uDqZ6AJRbytYl3TeuKZ0h0Etrgw==)
25. [datablend.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEosmjTQmvvkGrEx-yvlQj4gkRIEG-ry3RCRyUa_xLBNMBa8NeHiUez7oZluOzZ5f7Q34hUEwy0hPoNs1Zb1avlz7qdAzxvhBpuHlvWFBy1I3TMSePBVa9erEP5E1DIXtOxgtlp8hp3UJvtJFa4HsrSTKB2fOWB_HTbiSHKyOyeZGARpxnPgZc=)
26. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFPJsH0mia1yE2kS8U75T0K3ZzLxcF2vRAZhQFKcBdsLsaEZ-4yfwRiyylXYWnIdYuiVP52l6LIDLHj5ljv0Ka5IyyCNhKbRQg2i3HNYJp9O7YxTUt6tXwe5euqBulDCuEIVOXDZObnTTvlUyOx2T5F)
27. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFFeBmbs3n_1pddAId2hWQSSu0oFuWGaAkM6EH9hVjzlwBZGJ8ilvyoTGUIIw2lBetaqTf0QYVTqWcZgyYkJppYd48cIGmosZ0-u7BWLkEsqFI0MuQu0SG4gXvdctTPo7CiGStc-HdRZLfMoDLGzdDOP2j1BA62ehNdZsnUBMzZSMnt5X59VBCo)
28. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFxPrKo2dxykCj4GHJOvsgzaejzsUcbK4nJhn_ayplf5Qw5BfweaSNOg6UkUyCkMveM-Z-qr1xdBGY5_ZW_8cacxze2Q6tX_QNMxDMK3dyevEr4R5OOhdeK_Ev-c9rTYM9eedh_N8iJgXqSwtyliMA7Te4JZLuG)
