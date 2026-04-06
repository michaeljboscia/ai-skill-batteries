# Comprehensive Guide to the HubSpot Contacts API in TypeScript

**Key Points**
*   **API Client Architecture**: The `@hubspot/api-client` library in TypeScript provides a robust, object-oriented interface to the HubSpot CRM v3 API, featuring built-in rate-limiting management and automatic retry mechanisms for 429 and 5xx errors [cite: 1, 2].
*   **Strict Data Integrity Constraints**: Operations such as contact merging are strictly irreversible [cite: 3, 4], and lifecycle stages enforce a forward-only progression paradigm unless explicitly cleared [cite: 5, 6]. 
*   **The Leads Object Evolution**: HubSpot has introduced a dedicated Leads object (`/crm/v3/objects/leads`) to separate prospecting activities from general contact management, complete with its own dedicated pipeline and mandatory contact association [cite: 7, 8].
*   **Compliance and Billing**: GDPR deletions permanently blocklist email addresses from user interface recreation [cite: 9, 10], while the management of "Marketing Contacts" directly impacts enterprise billing tiers, heavily relying on the `hs_marketable_status` property [cite: 11, 12].

**Overview**
The integration of customer relationship management (CRM) systems with external applications requires rigorous adherence to data models, API limitations, and business logic constraints. The HubSpot CRM API, particularly when accessed via the official `@hubspot/api-client` in TypeScript environments, offers profound capabilities but demands strict architectural discipline. This report provides an exhaustive, academic-level technical reference for engineering teams. It explores the programmatic execution of Contact CRUD operations, the utilization of the novel Leads object, the rigid rules governing Lifecycle Stages and Lead Statuses, version 4 of the Email Subscriptions API, and the financial implications of marketing contact designations.

**Methodology and Application**
Navigating the HubSpot API necessitates an understanding of its underlying architectural philosophies. Developers must routinely handle unique identifiers (often dynamically switching between HubSpot Record IDs and email addresses), navigate pagination and batch limits, and gracefully manage state transitions that are heavily guarded by internal CRM validation rules. This guide is structured to transition engineers from fundamental client initialization through complex state management, concluding with decision trees and critical "anti-rationalization" rules designed to prevent systemic data corruption.

---

## 1. Technical Setup and Client Instantiation

The official `@hubspot/api-client` serves as the primary conduit for TypeScript applications interacting with HubSpot. Built upon standard REST principles, it provides strongly typed models for request payloads and responses. 

### 1.1 Instantiation and Retry Mechanisms
Instantiating the client correctly is the foundational step for resilient API integrations. The client supports authentication via OAuth 2.0 access tokens or Private App access tokens [cite: 1, 2]. Furthermore, to handle network volatility and rate limiting, the client features an integrated retry mechanism.

```typescript
import { Client } from "@hubspot/api-client";

// Initialize the client with built-in retry logic for 429 and 5xx responses
const hubspotClient = new Client({ 
    accessToken: process.env.HUBSPOT_PRIVATE_APP_TOKEN,
    numberOfApiCallRetries: 3 // Can be set from 0 to 6
});
```

When `numberOfApiCallRetries` is configured greater than 0, the SDK automatically intercepts `5xx` Internal Server Errors and retries them after a delay calculated as `200 * retryNumber` milliseconds [cite: 1, 2]. Crucially, if a `429 Too Many Requests` error is encountered (specifically for the `TEN_SECONDLY_ROLLING` rate limit), the client will pause and retry after a 10-second delay [cite: 1, 2]. This built-in resiliency prevents intermittent network or quota issues from crashing background synchronization jobs.

---

## 2. Contact CRUD Operations

Contact management represents the core of any HubSpot integration. Contacts are standard CRM objects that store demographic, firmographic, and behavioral data about individuals interacting with your business [cite: 13].

### 2.1 Creating Contacts (Email as Unique Identifier)
When creating contacts, the email address serves as the paramount unique identifier. Failing to include an email address frequently results in duplicate records and fragmentation of the customer journey [cite: 13]. 

```typescript
import { SimplePublicObjectInputForCreate } from '@hubspot/api-client/lib/codegen/crm/contacts';

async function createContact(email: string, firstName: string, lastName: string) {
    const contactObj: SimplePublicObjectInputForCreate = {
        properties: {
            email: email,
            firstname: firstName,
            lastname: lastName,
            // Additional custom or standard properties
        },
        associations: []
    };

    try {
        const response = await hubspotClient.crm.contacts.basicApi.create(contactObj);
        console.log(`Contact created with ID: ${response.id}`);
        return response;
    } catch (error) {
        console.error("Failed to create contact", error);
        throw error;
    }
}
```

### 2.2 Updating Contacts (By ID and by Email)
Contacts can be updated using either their internal HubSpot Record ID (`id`) or a custom unique identifier property, which is most commonly the `email` [cite: 13, 14]. When querying or updating via an email address, developers must explicitly append the `idProperty=email` parameter to the request [cite: 14]. In the TypeScript SDK, this is passed as a function argument.

```typescript
import { SimplePublicObjectInput } from '@hubspot/api-client/lib/codegen/crm/contacts';

async function updateContactByEmail(email: string, newPhone: string) {
    const updateInput: SimplePublicObjectInput = {
        properties: {
            phone: newPhone
        }
    };

    try {
        // Method signature: update(contactId, SimplePublicObjectInput, idProperty)
        const response = await hubspotClient.crm.contacts.basicApi.update(
            email, 
            updateInput, 
            "email" // Defines the idProperty [cite: 15, 16]
        );
        return response;
    } catch (error) {
        console.error("Update failed. Contact may not exist.", error);
    }
}
```
*Note on clearing properties*: If a property value needs to be completely removed rather than overwritten, the API requires passing an empty string (`""`) [cite: 14].

### 2.3 Searching Contacts with FilterGroups
The Search API is powerful but heavily constrained to optimize database performance. HubSpot restricts search queries to a maximum of 3 `FilterGroups`, with a maximum of 3 `Filters` per group [cite: 1, 17, 18]. FilterGroups act as logical `OR` conditions, while the Filters within them act as logical `AND` conditions.

```typescript
import { PublicObjectSearchRequest } from '@hubspot/api-client/lib/codegen/crm/contacts';

async function searchHighValueContacts(domain: string) {
    const searchRequest: PublicObjectSearchRequest = {
        filterGroups: [
            {
                filters: [
                    {
                        propertyName: "email",
                        operator: "CONTAINS_TOKEN",
                        value: domain
                    },
                    {
                        propertyName: "lifecyclestage",
                        operator: "EQ",
                        value: "customer"
                    }
                ]
            }
        ],
        sorts: ["-createdate"], // Descending sort by creation date [cite: 17]
        properties: ["email", "firstname", "lastname", "hs_lead_status"],
        limit: 10,
        after: 0
    };

    const results = await hubspotClient.crm.contacts.searchApi.doSearch(searchRequest);
    return results.results;
}
```

### 2.4 Batch Operations (100 Max)
To conserve API quotas, operations should be batched whenever possible. The HubSpot batch endpoints allow for processing up to 100 records per request [cite: 19]. For integrations processing thousands of records, arrays must be chunked programmatically.

```typescript
async function batchCreateContacts(contactsData: Array<{email: string, firstname: string}>) {
    // Ensure array does not exceed 100 elements
    if (contactsData.length > 100) {
        throw new Error("Batch size exceeds HubSpot limit of 100");
    }

    const batchInput = {
        inputs: contactsData.map(contact => ({
            properties: {
                email: contact.email,
                firstname: contact.firstname
            }
        }))
    };

    // basicApi.createBatch replaced by batchApi.create in recent SDK versions [cite: 1]
    const response = await hubspotClient.crm.contacts.batchApi.create(batchInput);
    return response;
}
```

### 2.5 Merging Contacts (Irreversible)
Merging is a critical operation used for deduplication. It combines property histories and object associations from a secondary contact into a primary contact, subsequently deleting the secondary contact. **This action is strictly irreversible** [cite: 3, 4]. While third-party forensic tools exist to attempt reconstruction, the HubSpot API provides no unmerge endpoint [cite: 4].

```typescript
async function mergeDuplicateContacts(primaryId: string, secondaryId: string) {
    const mergeInput = {
        primaryObjectId: primaryId,
        objectIdToMerge: secondaryId
    };

    try {
        // Merges secondary into primary [cite: 1, 20]
        const response = await hubspotClient.crm.contacts.basicApi.merge(mergeInput);
        return response;
    } catch (error) {
        console.error("Merge failed. Ensure both IDs are valid and not already merged.", error);
    }
}
```

### 2.6 GDPR Deletion vs. Archiving
HubSpot differentiates between standard archiving (soft delete) and GDPR deletion (hard delete with blocklisting).
1.  **Archive**: Invoking `hubspotClient.crm.contacts.basicApi.archive(id)` places the contact in the recycling bin, from which it can be restored within 90 days [cite: 21, 22].
2.  **GDPR Delete**: Invoking the GDPR delete endpoint permanently purges the record, its timeline, and associated PII within 30 days [cite: 23]. Furthermore, if executed using an email address, that email is placed on a permanent blocklist, preventing users from manually recreating the contact via the HubSpot UI [cite: 10, 24]. Interestingly, while UI recreation is blocked, the Contacts API *can* technically bypass this blocklist if an integration has a legitimate, compliant reason to re-track the user [cite: 9].

```typescript
async function executeGdprDelete(email: string) {
    const gdprInput = {
        objectId: email,
        idProperty: "email"
    };

    // Performs a GDPR-compliant permanent deletion [cite: 24]
    await hubspotClient.crm.contacts.gdprApi.purge(gdprInput); 
    // Note: Depending on SDK version, purge() may have moved to basicApi [cite: 1]
}
```

---

## 3. The Leads Object: `/crm/v3/objects/leads`

Historically, HubSpot heavily relied on the Contact and Deal objects to represent the entirety of a sales process. However, the introduction of the standard **Leads** object (`/crm/v3/objects/leads`) marks a massive architectural shift, allowing organizations to separate early-stage prospecting and qualification from general contact data and late-stage deal pipelines [cite: 7, 8].

### 3.1 Lead Object Architecture and Requirements
Leads represent a prospect's active intent or a specific sales outreach effort. A single Contact may have multiple Leads over time (e.g., expressing interest in different product lines or re-engaging after a dormant period).
When creating a lead via the API, strict relational and property rules apply:
1.  **Mandatory Naming**: The property `hs_lead_name` is strictly required upon creation [cite: 7, 8].
2.  **Mandatory Association**: A Lead cannot exist in a vacuum; it *must* be associated with an existing Contact (or Company) at the time of creation [cite: 7, 25].
3.  **Workspace Isolation**: Leads are designed to be worked from the HubSpot Sales Workspace and require the assigned owner to possess a paid Sales seat [cite: 7].

### 3.2 Lead Pipelines and Properties
Leads utilize their own distinct pipeline, completely separate from Deals. The standard Lead pipeline progression follows:
`New` → `Attempting` → `Connected` → `Qualified` → `Disqualified`

Key properties driving this object include:
*   `hs_lead_label`: Represents the current pipeline status of the lead [cite: 7].
*   `hs_lead_type`: Distinguishes between inbound marketing leads, outbound sales leads, etc [cite: 7].
*   **Auto-syncing**: Activities logged against the Lead object (calls, emails, meetings) will automatically synchronize and roll up to the associated Contact record, preserving a holistic view of engagement.

```typescript
import { SimplePublicObjectInputForCreate } from '@hubspot/api-client/lib/codegen/crm/objects/leads';

async function createLeadForContact(contactId: string, leadName: string) {
    const leadInput: SimplePublicObjectInputForCreate = {
        properties: {
            hs_lead_name: leadName, // Mandatory [cite: 8]
            hs_lead_type: "INBOUND",
            hs_pipeline: "default",
            hs_pipeline_stage: "NEW" // Maps to the 'New' stage
        },
        associations: [
            {
                to: { id: contactId },
                types: [
                    {
                        associationCategory: "HUBSPOT_DEFINED",
                        associationTypeId: 578 // Association Type ID for Lead to Primary Contact [cite: 25]
                    }
                ]
            }
        ]
    };

    // Note: Requires crm.objects.leads.write scope [cite: 8]
    const response = await hubspotClient.crm.objects.leads.basicApi.create(leadInput);
    return response;
}
```

---

## 4. Lifecycle Stages: The Ordered Progression

The `lifecyclestage` property is arguably the most critical macro-metric in HubSpot, dictating attribution reporting, funnel analytics, and marketing automation. The standard ordered progression is:
**Subscriber** → **Lead** → **MQL** (Marketing Qualified Lead) → **SQL** (Sales Qualified Lead) → **Opportunity** → **Customer** → **Evangelist** (with "Other" acting as a separate bucket).

### 4.1 The Forward-Only API Constraint
HubSpot enforces a rigorous, system-level constraint: **Lifecycle stages can only move forward via standard update calls** [cite: 5, 26]. This is designed to preserve historical funnel conversion data. For example, if a contact is currently an `Opportunity`, an API call attempting to set their `lifecyclestage` to `MQL` using standard last-write-wins logic will be silently ignored or fail, corrupting external synchronization logic [cite: 6].

Furthermore, standard CRM behaviors impact this property automatically. Notably, when a Deal associated with a Contact is moved to `Closed Won`, HubSpot's internal logic will automatically update the Contact's lifecycle stage to `Customer`.

### 4.2 Clearing Values for Backward Movement
In complex B2B sales, a "Customer" might churn and need to be reverted back to a "Lead" for a re-engagement campaign [cite: 27]. To move a lifecycle stage backwards via the API, the integration must perform a two-step operation:
1.  **Clear the property**: Send a `PATCH` request setting `lifecyclestage` to an empty string `""` [cite: 5, 14].
2.  **Set the new stage**: Send a subsequent `PATCH` request setting the new, earlier stage.
*Note: Because batch APIs do not guarantee exact ordering, clearing and resetting should generally not be bundled in a single batch request to avoid race conditions* [cite: 28].

```typescript
async function revertLifecycleStage(contactId: string, targetStage: string) {
    // Step 1: Clear the current lifecycle stage [cite: 5]
    await hubspotClient.crm.contacts.basicApi.update(contactId, {
        properties: { lifecyclestage: "" } 
    });

    // Step 2: Set the new (backward) lifecycle stage
    await hubspotClient.crm.contacts.basicApi.update(contactId, {
        properties: { lifecyclestage: targetStage } // e.g., "lead"
    });
}
```

---

## 5. Lead Status Management

While `lifecyclestage` tracks the macro-level journey of the customer, the **Lead Status** (`hs_lead_status`) property tracks the micro-level actions taken by a sales representative while the contact is in the `SQL` or `Lead` lifecycle stage.

### 5.1 Standard Lead Status Values
By default, the `hs_lead_status` property supports the following operational phases:
*   **New**: A newly assigned lead awaiting initial outreach.
*   **Open**: The lead is acknowledged but no action has commenced.
*   **In Progress**: Active communication is underway.
*   **Open Deal**: A deal is actively being negotiated (usually coincides with `Opportunity` lifecycle stage).
*   **Unqualified**: The prospect does not meet target criteria.
*   **Attempted to Contact**: Outreach made, awaiting response.
*   **Connected**: Two-way communication established.
*   **Bad Timing**: Qualified prospect, but currently unable to buy; candidate for future nurturing.

### 5.2 Differentiating Lead Status from Lifecycle Stage
A common architectural flaw is attempting to force micro-status updates into the macro Lifecycle Stage property. 
*   **Lifecycle Stage** asks: *Where is this person in the grand scheme of our business relationship?* (Marketing's domain).
*   **Lead Status** asks: *What is the salesperson actively doing with this person right now?* (Sales' domain).
Developers must map external systems (like a dialer's "Left Voicemail" disposition) to the `hs_lead_status` (Attempted to Contact), *not* to the Lifecycle Stage.

---

## 6. Email Subscriptions v4 API

Respecting communication preferences is a legal and operational mandate. The HubSpot Subscriptions v4 API (`/communication-preferences/v4`) replaces legacy endpoints to provide a robust framework for managing GDPR/CAN-SPAM compliance [cite: 29, 30].

### 6.1 Understanding the v4 Paradigm
Subscription types represent the lawful basis to communicate with a contact [cite: 29]. The v4 API currently exclusively supports the `EMAIL` channel [cite: 29, 31]. Statuses are rigorously tracked, and a contact will generally fall into one of three distinct statuses for any given subscription type:
*   `SUBSCRIBED`: Explicit opt-in.
*   `UNSUBSCRIBED`: Explicit opt-out.
*   `NOT_SPECIFIED`: Implicit state; can receive mail if legal basis exists (e.g., legitimate interest) but hasn't explicitly opted in or out.

### 6.2 Fetching and Modifying Status
To evaluate a contact's eligibility to receive marketing collateral, integrations must check their specific statuses via their email address.

```typescript
// Using standard fetch as SDK wrappers for v4 comm prefs may require direct HTTP calls [cite: 32]
async function checkSubscriptionStatus(email: string) {
    const url = `https://api.hubapi.com/communication-preferences/v4/statuses/${email}`;
    const response = await fetch(url, {
        method: 'GET',
        headers: {
            'Authorization': `Bearer ${process.env.HUBSPOT_TOKEN}`,
            'Content-Type': 'application/json'
        }
    });
    return await response.json(); // Returns array of subscription statuses [cite: 29, 33]
}
```

### 6.3 Resubscribing Opted-Out Contacts
Contacts frequently unsubscribe from "All Email" by accident or later change their minds. To programmatically resubscribe a contact who is entirely opted out, you must interact with the `/communication-preferences/v4/statuses/batch/subscribe` endpoint. Note that doing so programmatically without a verifiable paper trail of consent violates HubSpot Terms of Service and international spam laws.

```typescript
async function globalUnsubscribe(emails: string[]) {
    // Unsubscribe multiple contacts from ALL email communications [cite: 29]
    const url = `https://api.hubapi.com/communication-preferences/v4/statuses/batch/unsubscribe-all?channel=EMAIL`;
    await fetch(url, {
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${process.env.HUBSPOT_TOKEN}`,
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ inputs: emails })
    });
}
```

---

## 7. Marketing vs. Non-Marketing Contacts

HubSpot's pricing model underwent a paradigm shift with the introduction of "Marketing Contacts." Instead of billing for every contact in the CRM, HubSpot only charges for contacts that the business actively targets with marketing emails or ads [cite: 11].

### 7.1 Billing Implications
*   **Marketing Contacts**: Count toward the account's billable contact tier limits. Allowed to receive mass marketing emails and be pushed to ad network audiences [cite: 11].
*   **Non-Marketing Contacts**: Free to store (up to 15 million). Cannot be emailed via marketing tools, but *can* receive 1-to-1 sales emails from the CRM and transactional emails (if the transactional add-on is purchased) [cite: 34].

### 7.2 Programmatic Management (`hs_marketable_status`)
The property controlling this state is `hs_marketable_status`, which accepts the string values `"true"` or `"false"` [cite: 35]. 

**Critical Constraint**: When creating a contact via the API, the `hs_marketable_status` and `hs_marketable_reason_type` properties are structurally **read-only** and cannot be set directly in the creation payload [cite: 12]. Attempting to do so will result in an error. By default, API-created contacts are typically created as Non-Marketing unless the account's global settings default API creations to Marketing [cite: 36]. To manipulate this programmatically post-creation, developers must use the dedicated Marketing status endpoints or rely on active lists/workflows to toggle the status dynamically based on custom properties [cite: 12].

---

## 8. Decision Trees for Integration Architecture

To ensure robust implementation, engineering teams should follow these decision trees when designing workflows.

### 8.1 The Inbound Lead Creation Tree
```text
Does the Contact already exist in HubSpot?
├── NO
│   ├── Create Contact via basicApi.create() (Ensure email is provided)
│   └── Create Lead via objects.leads.create() and Associate to new Contact ID
└── YES (Identified via email or Record ID)
    ├── Does an active Lead already exist for this context?
    │   ├── YES -> Update existing Lead status via objects.leads.update()
    │   └── NO -> Create new Lead and Associate to existing Contact ID
```

### 8.2 The Lifecycle Stage Synchronization Tree
```text
Target external stage maps to HubSpot Lifecycle Stage 'X'.
Is 'X' chronologically BEHIND the current HubSpot Lifecycle Stage 'Y'?
├── NO (Moving forward or same)
│   └── Call basicApi.update({ lifecyclestage: 'X' })
└── YES (Moving backward)
    ├── Step 1: Call basicApi.update({ lifecyclestage: "" })
    └── Step 2: Call basicApi.update({ lifecyclestage: 'X' })
```

---

## 9. Anti-Rationalization Rules

Developers building middleware often make assumptions about how a CRM "should" work, leading to rationalizations that ultimately cause data fragmentation, infinite synchronization loops [cite: 6], and rate-limit violations. The following Anti-Rationalization rules must be strictly enforced during code review.

### Rule 1: The "Email is Optional" Fallacy
*   **Rationalization:** *"Our external system allows users to create accounts with just a phone number or a username. We'll just create the HubSpot contact with a First and Last name and backfill the email later."*
*   **Reality:** Without an email address, HubSpot's native deduplication engine cannot function. Multiple form submissions or API calls for the same user will generate duplicate records. Creating contacts without email addresses ensures a fragmented database requiring expensive third-party deduplication tools later. **Rule:** If no email is present, do not create a Contact; store the data in a custom object or cache it until an email is acquired.

### Rule 2: The "Blind Upsert" Fallacy
*   **Rationalization:** *"I'll just blindly call the create endpoint every time an event happens in our app. If the contact exists, HubSpot will figure it out and update it."*
*   **Reality:** Calling `POST /crm/v3/objects/contacts` repeatedly without checking for duplicates will generate thousands of duplicates if an email isn't strictly enforced. **Rule:** Always use the `batch/upsert` endpoint with `idProperty="email"` or perform a search first. *Note:* Partial upserts via email have limitations in batch endpoints [cite: 6, 37]; if a stable external ID exists, create a custom unique property in HubSpot and upsert against that instead.

### Rule 3: The "Force-Update Lifecycle" Fallacy
*   **Rationalization:** *"Our product downgraded the user from Premium to Free, so I'm sending an API call to change their HubSpot Lifecycle Stage from 'Customer' to 'Lead'. HubSpot will just accept the newest value."*
*   **Reality:** HubSpot silently ignores attempts to move lifecycle stages backward to preserve funnel reporting integrity [cite: 6]. **Rule:** You must deliberately clear the property with an empty string `""` in one API call before setting it backward in a subsequent call [cite: 5].

### Rule 4: The "Lifecycle = Lead Status" Fallacy
*   **Rationalization:** *"The sales rep couldn't reach the prospect, so I'm updating their Lifecycle Stage to 'Attempted to Contact'."*
*   **Reality:** "Attempted to Contact" is not a Lifecycle Stage; it is a Lead Status. Mixing these up destroys marketing attribution models and funnel velocity reporting. **Rule:** Confine macro-level buyer journey steps to `lifecyclestage` (MQL, SQL, Customer) and confine micro-level sales actions to `hs_lead_status` (New, Connected, Bad Timing).

### Rule 5: The "Merge is Reversible" Fallacy
*   **Rationalization:** *"I'm writing an automated script to find and merge contacts with similar names to clean up the database. If it makes a mistake, we'll just restore the contacts."*
*   **Reality:** Contact merging via the API is permanent and entirely irreversible [cite: 3, 4]. The secondary contact is destroyed, and the primary contact absorbs its data. A poorly written automated merge script can destroy a database in minutes. **Rule:** Never execute automated API merges based on loose criteria (like matching first/last names). Only merge when exact, unique identifiers match, and always log the `primaryObjectId` and `objectIdToMerge` for compliance.

**Sources:**
1. [yarnpkg.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQF5ojwFUH3drESCzxdVk_YA3Sb-Ts5BLSTaLwN4dkqtUa70REOS1t-Y9osPVVHHvPmZDko6O9NU2eSvN1sKNXc_KnKsNxDZJu5zq5lZNzuhuRhi31HHkTTftdChUfi_xTXc4DXXSTfTdjqeAobbKrmn)
2. [github.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFHT-p-LxTtQStRdU-221TZoKw1td3qjR1XPjldvW4n24VRhCseHk3nE0ffjQFzslqSblwbA2WFJunRzL34WhvWbRhGWSGyUtsbp4tY2ODtoSKriaTMNra0wmnED0EyP71rlig=)
3. [insidea.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFpuNIwYqUxRKpXGej1_9ySFfeHxpnf1OtTPzBQtDEUAri6rtseTmA40bqqVo4QXcKtclPxVh_gjU9PPv4aZQ1sB_2Ahtp22FaT75-20hWEL45eJNtiHhYDT6HoS1ycFpVmXPnx0k2PsAQ=)
4. [emergencyunmerge.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGGq0KIRSLNyMViwOKWoVef30H055wY8x2lT_LbfgWdgJR8UAO43uSmTDKANM2sbE28giRkA_w44-NUlmtUpga0RBz7QdLVduG1aeN7N8j_uLz2aQVj4jc=)
5. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHRCXJbW8ZYqhz6kmFWr9XNagfkE9iYhvw0slB4adbLHTnI18-GUkjCbFbuCwyZQW25Fqs_nDpfcswM6Nu5DCA6Z7fnM6YH9oG_mwdgMOB6hoLL2In0OUI754gA7S2sbgKbl_VxHm9GthJVxiD85Mf555G5cZyInLjoQ-WGmzrqO0sdPrQklfSnVw==)
6. [truto.one](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEKUzKIaxgEekiAR9slIYN5NSn7rzir66ELRsbd65Bm4gCFCI7PhGReOSerRk5uqTN7ystgv6N9ViRuzmGIvEsfN17b_1x7K2ml9g9N82n1G4v6GOCTgCbcJWj_8A4FRwfWfnJllaZ5UygdKTqmq59S_3l0yNfTzX8PFZ3mWxGezuHGvP__2_9GBQbdUsDPu4LYcXM=)
7. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGXLgcCgq9rj4I9ptrp-3NBetzkEeTx1-wWV58-XsDs3_9CmfCJUKRWZhastmVRDbKssVL64hnavpdymaxnr8G5OaOw04tUiLz4V0rd3SBfmvhkNkHqK9kMm0mu1Y_S-7JGynhQ2W4E9JaVdkKQTlMCSLmkfi5Nih1WGiZ87mfJquVKG_T28g==)
8. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFIif5Y_rbt59Y3-FBRwUBdWoqQ75dTHZFj5aQo-GdchI5dRU5O-cx6TddowpcM2mY-2o-49u_4PzPFh_n47-YHzoaYWNKIfWJmvFfdTR2JEAna9WAwxBxnwyG103VxSi857XOjYP1KHACZ-oHjsGKKt8ahaOsRMMlgwg==)
9. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFPARPtmxv4HhznduFQyg8_jCH7TFjun-_pCng_-W1sXbvrtSD7DP3Ufc2MH56ahNIOYwpdDwWNxOWS_tLEpwc-ka58sjeMOJVMqhV7Ah-ns-Cwn8IX8Ct6QCFJA6ahnlWPVAmJe1m58D8=)
10. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEg8Fs_-Z0kp5uGxMMRE_YdrBl6C1Y0EQj3wbCU1oQItagX6fkhy1-i7i5pTQsu-QfP5e6L8LxF8GqPUHjWUSLCnGmMjSSeqzmWb-_00Ww4pGUsbJamNQ-O11tS01cI_MU7Hypv8r488SP15nkhcdUSmgDefZ9fuqu0tM9YJPrpdBXl3mkWwA5zHEevL8RA6wm0)
11. [sequenzy.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFWGUdoX42KFgSEQIdJFnIDow4d9O-LsZBiEJDmfVs8gmOh94Tq7W-iqe6kv83Xp2NZys8RNgc7oakhtjsgQiqPW0Xp6kRruuZOT2PHOsuQ1yMjR7vhcm4a4KhzcFAT6tD9-kq6g2Y=)
12. [scopiousdigital.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEXrKrQNNaHBdsH0RxzkdduJtJmPisfofsWxQMEogF7pw5sdyWBg6HbUpsr8ac7jFGwaFb_Z47e-I5jl1vRdzZTXOiXWaMgcF4f3FVMQVjasLsCJTjMUKFy7tL35ypWaaAWzogwUndnhoDJoCU73Gkf-WlnLYQaeBH20bBPzh_yQTk9rg==)
13. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFR4WmmSmiRwsEOkawjx8A9GLplLF7cYIyS71lN5TPaW8sfZ3g-_PTu3ICjKeBe4Oh0KZs3bXL3YxmTDvXugtuoxx1uVYt-Z6kvzScQKftJpe7sqg0AuXD0d9ZxQUBM0RhqQLx5VjitDBQYi45aTgEm4YPUNBIF1jjEYNT0gw==)
14. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHfpvU1giKx7Mz_JoMHgil3hKQBVo67zi-nXP2_ZCo9r6IW9NvaycHPhdIjZq-OLJYfSx0k3xZGmyXhcE53eWp61iiGljtYQJbvYKaKuGqIqLU2-Wq_AM-BaoLl4c1UbpjLmLZukIKUu8ywM3UwfTyw5A72xHFM_VcqFP8qcmPO84zKZyKdrGvRceKkqQHd1PAFuQ==)
15. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEWd097CTtm_fFj25vkHnHuNAzz_Mo0yts3y6YpTJ2x6QaOCzX2Hl7HbUTOy7_ExBqmhZefUrruoSNPF-A9DsU8VnocCBJkKeUO6vftADvFGO_KaowF_s-mmhZ4jKgik3W37_OrYJxDY6bBkjpLL8j-XY8fWcjmsnToMfATLTqz36t68z_toTTjk1QdIftHIzP_uWpnF0gUFDVoU0ZMPJOT5SHmQF-YsQa9EeU=)
16. [zapier.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFE4u4k5cXrASCdJBLMIkC8bok7drZJCTAt0RXSpeColgO2FKUp6QBT81R51qNGYxkxx5d8ds62GzEuxH444-sdnS-OqywzIjLwfXugeL2RMAP9ejU3-4eOTGe-HZQ3ac9b411RvwFHdyRednIyVd5TUj3bBSuvKm3P1ibVylxs9gI7zkLCdMIke-VqWVM-kZBvqA3bK2qvx7R_ZO1Afcuy_13lGEw9vFmCDwb0Q2r9KGE4GShMfxHbrHJD8IYqMeil58Dak_KC-HvHsrgABp_tiOCklIinPX_D7FyKJw==)
17. [npmjs.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHddeWeI9wzw8t-FCmZ_W0h6ADo6doK4XLDGsrCPYQDxk1t-AzBiT1ZAcebU1i5UcajLJ7RdF6NaDvN1vrlUvpHTUXm9X5mwsaadMBb6cOqVMMYTvOBZ2pDmGpT_OSsZUrVy5NgMgAX)
18. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGqbFVYbLPvOdel478TFyQx0Ysy0RbRGHPeWfkBkCmyfsAUycq7PTM2GABQDtvrMPjVpZ1sfRH1nLbJqu8SX7pcW9zW7c1Z0iIULOEjOOmQfNaQota0iOejh-Rcv5b9FMAoGUSR)
19. [a2zdevcenter.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE9HodQmVRUxpt62dPrUt68OB4NJN6OBrAuugRObNhJWk_ZB61LGYF-mtWmajuuJ33acaeW4v7rjm5U5ZN3b5F9N1GWz6UCAHNk4BXWtpO36FJJ54QKYYsgL1Z6Qy1uD50N1bc1lmDXsbVGhiAPX6foojU2Je3i8pX3gGbE5jW_zjcgk2xdt_Gd4vE=)
20. [composio.dev](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHI-a-eUidg9XNWdRFcpU_0KSDwgwN1C2zTB0gI4_m01R9jrapsTRocG73ZE0Lcn9oPV2BZV3t-4MT1ubL5MeHXsMyiG0XdDk-u3bjOPTze2wkoBlnFAXRjwn9h-5td84gyCFbJ9ajRQkK_le7fCpcUBbSJMm5vZg==)
21. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHyW43h4EpmK96vyRmq7xSHDDJxEoLAukPnCz9zDSMWUqaeQqiRi0BRvnEXnzMLuxhN8DHGJC7rduvs7bAiC93Mbz962fdJFda7I_irlMUF0N9Ki_v7zUMHLIfB_7J3LoPInrg30B3_GIt32kcDJ4OToHfM6GS65IF4AL4S3mpTNyb-WUJUAXCOYhMg0Q8=)
22. [github.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEg23IMqOfCdPzvZ8ngY6KhiHWTatDSMQ7PkoYzyF8eGFXC4udOjSMBhaxBjvhI5FBQZbH2o-Yej2Smok5BGOBtIIlUYrYIi5i4yy20KCHvfxDczqJzl7-UXo4v8Qx9CTcvuAY2LMSLu53AD2MwtJBsAG5WoQ4f4UdF3T2Qrdf6kRAKP7a7v4sc623HVp00RkSob5-EeGlYX4ZPvQ94YJbOTZ9mZQU-FJwjy-c=)
23. [mineos.ai](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGPB_Kz93iEwVuX9YGHPIglIlWu1wVb70h-kgyfTL9VTYcwF9fRm2-0qknhsYdImHH_cWuCceuZyr4LkzXgssm0-toYQ-Dc9o5yafDI8TErgOdAF9rLGOpan6TkXsUPPBUfmbAlwOckjA==)
24. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGtPpLrhLYZvwJtgO71z4UgKwcM1YWEzF2F2rdhmG_qaNDpyhagVfvBhU1vxCOpScINlawwylK05BA4fit2m-e-5I2jrI-p7UFqXbTE0n-UcZ5Xwb5OrXP16rPQ6F6egg77zqrkdGbwnyai-W_nFxpPMxylexTgVZZzGWXYEcPK1RgZgPCCtiCCEQpLSB0lID2D-YEfh1LxhXnOidwk4cEWESljqTty)
25. [clonepartner.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEigj4_Iaxm70G-baUpIXt9HIodCZ7YIUqHs6ySxvGw5Y8X6fYP_xUQ5fb-6H38c7Y5JDPXnZILmZtaIa_n-Mqt2yWxjYWPBEbhzhARJ4-_XvNxMS5RVAVBOZMCv7aeBv16QYP47DkQOmoewf3HQ9qXxxS_0X4Lj_qPpbhTTlgIuAcjsMimPzSJyFm2K5L4jQ==)
26. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGT3HCHvmeTJBbHTXOXxj8H-oVhL49Neb7IItV_3fqAKoJu-KbbvdP37DnSdeEYdmVa76J3f5GusS8MzWYvqlSfQN9kWmgu5-VRXguMGosvoGr-y_xNKN6-teTXDYGrRg9E0yE-MQ6pz7UCBsFUU01Exbqx6fphXACLIdHh8FVp3XALnKODv9z4EOM=)
27. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFBduJ_izX4K0bUAnWKx5VgDPrdDcpMK1lv5UK4u7jzVJSuB2NWYbdepV6x3AN8hY25ICTKg1bn7KT0j4zt40ZkmA_s8RIZQ1y_IhoX-PJfpB7I4md9Uoq0dVISOzH1MD7dSKuT088sx4H9VnGOSeA3vqBHMIWDSCcx2eM-EP59vrFt-wNTb90Qv4zoJi77Bi98vr5D)
28. [apideck.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGPgvDXl90CWTm964LuH0_GxWlrBh8oGYlEWoLG0-V1JVourTA4-oBEvmk8rvU8xagxVwtn96TQfummvz-5zj2zNmjgioPkhoZErYEpvf9GoARAXQwgTBFCoUwl5KthLVFMT3kVsetHDubTXFQfKXxk3vG7Jcdi)
29. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFHkIhWzi6b8HX6gXEVvX7Po-wjNNfpXP3dQwuJX0yPsmsSfmN1KOlpiZNb2P_CvTNyRB2-HxvMa7qQRTsLX60Arll8wqXKA1Bw4BdNaUfsLGgaq6XiGfd2PqHpqbCqCuRnurg_2wofZFzRIp3eSQyawEz2pPWUZVgnXwO3DbOSQbO1jvFrwRu76xM4aT-fvM28txR2YLIEDA==)
30. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFp964EO9LcNXalJvmn3J3h60UuN1h2SVdxN0rtCdvUVisfTbyug2LCqdqK7j_2MBw8KKuvvg8_-iP9BL4jBWixUoPuHqSMGbTozIX0n1A3WOm-H4BvAK9k48bI5Lck5ouwjdyaL1FZuJ8AmZ51T0oJnND28m_vcxfpY4j_jcBK5zRN_0qJmgiKwQsXXKznChgFXzQtu2OAsgJwBA==)
31. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFONMt_CjfpxmMlXHub-FHaWUX1VC19BQOSui0S9opXSuweVjhbDx-HW2wafEGOoq1XwJgnGx5x6alyNBB_sGzHyBc3yAbp4LujRoYv3MQQe_N97uVj3J7wV2vLn6Gno-PV5Of8j4E8VQLd76D2sb5Z7WhBf5KHEox0jRU2JI5ErfE1u8vnKWtDhkmAtbhILEtJb5h-068R8pgh54w=)
32. [mugo.ca](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHgQ3yDUNsPnoq6DYw47HN_zq3aZ_2VoO7_dPT4zJrgheBR72cu_vg8NPG51dFJQgSlk2emrdqapK0uoolOAKsAN-LFKIStvVjIgqPeEvbl72nX7U0FOWAISP2-8kCn3QI6o3MmcpoUmjXhrJQ7MK-DcqLjeQyk1qIdegYIpxtT1T7YeQDa8_z1hKcjxvDy)
33. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQH1m4Cc8rYZRtcWpmLRzoVMInW4oV_j1ggoHrxmSE0YPZYeqVvfoLHD4FlBUXYmY7MTq_M08ymqXVL9Ct5ub6z4QRHZsPvbR-7ZoIq-6hTHsqdv1yXiKsNe62C0AQqfxkvo6BX7GgX1aXw0FXVU7uOR-y8ackO4jaLZ6hgo1yxlJWaaAAUboqlBLGUdnJTM0p1Zwc7EBawyUoi2QIhiw4vsOris-z9fLXnKFCj4xAxwsaq6HwfBOggJ6VyQZqZzThoft1qGPGcq5q4fRfsv9qbNSp39G80YZvXse27vDRg3X1DjvOM=)
34. [loops.so](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGysY56NdQP1mpvBAwpEp_Scsycj5W-AxX8cH11DbLW5sV05nSeQAoOgdo0nZRTn2lGc78ZEVVvIAA5h7hq5c4pBm94WXNMZvgjYecdXe13GQTUA_dA8gsGfw==)
35. [customer.io](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHxebQGIEzZAbntzU8xCajb0Ox-JTyD_E026G3uvwgZbZf0Egb_gR1RSGRLMTGBdH2yNS1I7Xp4AYJxefqEx0vxYIBixicA5lKRmLfTpwtUE8xMBYw6OaluV2iiREv604ZyCovKONICuH3q1GeHtwdOdPCFAq9hOf3cY-4SJxRjCZcdb0K-gPEWPqccntM=)
36. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFhMIMuD-0xYx_O1dIzDeZ6T8goHx7OT9Ql1elzp-AMeWWPTrvLabrW2ynVXnKKFJITkj9pVI1INjeQ6j_62jICnDkrFid0K8vgrIhFDTd0sLR27UGG9pFNY-a0_1R2ua1clOqxCWncLwStty7RUn5B3U154CWnL0acpXeS2vP1hdNzEwxA2unzedK3ubmYAgR169gatF7AxX0HSUMB)
37. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHUg3VuLQ4Fkts4iJIG8grZDemaC-zHm_ICC_oT2KbPRoNsShlKxRzhNrBwbZWdIlvX7cBALqO10BFdfZpwF3IVIoBh6_llBfUm6g3lPkef9lTaSc2_ToAlINXc1ZYTAYb8uUOiaV02e9gk8sWZs3Qkalccbhl6)
