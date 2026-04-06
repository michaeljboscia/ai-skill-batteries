# Comprehensive Technical Guide to HubSpot API Client Setup and Core Patterns in TypeScript

**Key Points:**
*   **Initialization robustness is critical:** Configuring `@hubspot/api-client` with appropriate `Bottleneck` rate limiting and a defined `numberOfApiCallRetries` (up to 6) is essential for enterprise stability.
*   **Search constraints require architectural workarounds:** The CRM Search API strictly enforces a 10,000-record pagination ceiling and an 18-filter maximum across `filterGroups`, necessitating index-based pagination via `hs_object_id`.
*   **Version immutability provides predictability:** HubSpot's transition to Date-Based Versioning (`/YYYY-MM/`) enforces a 6-month release cadence and an 18-month support lifecycle, effectively deprecating the semantic `v3`/`v4` numeric paths.
*   **Property architectures demand precise typing:** Aligning base data `type` (e.g., `number`) with interface `fieldType` (e.g., `calculation_equation`) requires strict adherence to HubSpot's schema, particularly when embedding mathematical logic via `calculationFormula`.
*   **Associations have evolved to semantic linkages:** The Associations v4 schema separates relationships into `HUBSPOT_DEFINED` and `USER_DEFINED` categories, permitting up to 10 custom labels per object pairing.

The integration of HubSpot into enterprise architectures often involves negotiating complex rate limits, strict pagination boundaries, and evolving API schemas. This guide provides an exhaustive technical reference for engineers configuring the HubSpot API in TypeScript environments. While standard documentation typically highlights baseline integrations, production-scale deployments require resilient network configurations, meticulous schema definitions, and robust query strategies. It seems likely that developers transitioning from legacy semantic versions to the new date-based versioning will face immediate architectural decisions regarding technical debt and SDK instantiation. By adhering to the patterns detailed below, engineering teams can construct fault-tolerant systems that respect platform constraints while maximizing throughput.

***

## 1. HubSpot API Client SDK Initialization in TypeScript

The `@hubspot/api-client` package provides a robust TypeScript-compatible wrapper for interacting with the HubSpot REST API [cite: 1]. However, naive instantiation frequently leads to `HTTP 429 Too Many Requests` errors or unhandled `HTTP 5xx` server faults during high-volume operations [cite: 2]. To construct a resilient client, engineers must implement explicit rate limiting via `limiterOptions` and configure the built-in retry mechanism.

### 1.1 Core Configuration Parameters

The `Client` class accepts a configuration object containing several pivotal properties:
*   **`accessToken`**: The OAuth2 token or Private App token utilized for standard authentication [cite: 1].
*   **`developerApiKey`**: An auxiliary key required specifically when interacting with App Developer endpoints (e.g., managing app installations, timeline event templates). It can be supplied concurrently with the `accessToken` [cite: 3].
*   **`numberOfApiCallRetries`**: An integer ranging from 0 to 6. Setting this value activates interceptors that automatically retry requests yielding `5xx` errors (delayed by \( 200 \times \text{retryNumber} \) ms) or `429` rate limit exceptions for "TEN_SECONDLY_ROLLING" windows (delayed by 10 seconds) [cite: 1].
*   **`limiterOptions`**: A configuration object passed directly to the underlying `Bottleneck` library, which regulates concurrent requests and execution intervals [cite: 1, 4]. 

### 1.2 Rate Limiting (Bottleneck) Configuration

HubSpot imposes strict limits on private apps, typically allowing 100 to 190 requests per 10 seconds depending on the subscription tier [cite: 2, 5]. By default, the SDK does not throttle requests sufficiently for high-concurrency environments. Developers must instantiate the `Bottleneck` options to smooth out request bursts [cite: 4, 6]. 

For an application limited to 100 requests per 10 seconds (10 requests per second), the `minTime` should be set to `1000 / 10` (100ms) with a constrained `maxConcurrent` value.

### 1.3 TypeScript Implementation Pattern

```typescript
import { Client } from '@hubspot/api-client';

/**
 * Interface representing the custom initialization parameters 
 * for an enterprise-grade HubSpot Client.
 */
export interface HubSpotConfig {
  accessToken: string;
  developerApiKey?: string;
  maxConcurrent?: number;
  requestsPerSecond?: number;
  retries?: 0 | 1 | 2 | 3 | 4 | 5 | 6;
}

/**
 * Factory class to instantiate a resilient HubSpot client.
 */
export class HubSpotClientFactory {
  public static createClient(config: HubSpotConfig): Client {
    // Calculate Bottleneck minTime based on allowed requests per second
    const rps = config.requestsPerSecond || 10;
    const minTimeMs = Math.ceil(1000 / rps);

    const client = new Client({
      accessToken: config.accessToken,
      developerApiKey: config.developerApiKey,
      // numberOfApiCallRetries must be between 0 and 6 inclusive
      numberOfApiCallRetries: config.retries ?? 6,
      
      // limiterOptions interface provided by Bottleneck
      limiterOptions: {
        maxConcurrent: config.maxConcurrent || 3, // Prevent TCP starvation
        minTime: minTimeMs, // Throttle to prevent 429s
        id: 'hubspot-enterprise-client',
        // Optional: High water mark to drop requests if queue gets too deep
        highWater: 5000, 
        strategy: 3 // Bottleneck.strategy.LEAK (drops oldest if overflow)
      }
    });

    return client;
  }
}

// Usage Example
const hubspotClient = HubSpotClientFactory.createClient({
  accessToken: process.env.HUBSPOT_ACCESS_TOKEN as string,
  developerApiKey: process.env.HUBSPOT_DEVELOPER_API_KEY,
  requestsPerSecond: 9, // Slightly under the 10/sec limit for safety
  maxConcurrent: 5,
  retries: 4
});
```

By encapsulating the client creation, the architecture guarantees that no rogue microservice can instantiate a non-throttled connection to the HubSpot API, thereby safeguarding the 10-second rolling quota [cite: 1, 6].

***

## 2. Properties API Architecture and Implementation

The Properties API governs the schema of CRM objects. When creating custom properties programmatically, developers must understand the relationship between the underlying data `type` and the UI rendering `fieldType` [cite: 7]. 

### 2.1 Decision Tree: Property `type` vs `fieldType`

Selecting the correct combination is imperative; invalid combinations will result in schema validation errors. The following decision tree dictates proper configuration [cite: 7, 8, 9]:

1.  **Is the data a simple text string?**
    *   Yes: `type: "string"` -> `fieldType: "text"` (Single-line) or `fieldType: "textarea"` (Multi-line, up to 65,536 characters).
2.  **Is the data a binary boolean?**
    *   Yes: `type: "bool"` -> `fieldType: "booleancheckbox"`.
3.  **Is the data a set of predefined options?**
    *   Yes: `type: "enumeration"`.
    *   Does it allow only one selection? -> `fieldType: "select"` (Dropdown) or `fieldType: "radio"`.
    *   Does it allow multiple selections? -> `fieldType: "checkbox"` (values stored as a semicolon-separated string).
4.  **Is the data temporal?**
    *   Yes, date only: `type: "date"` -> `fieldType: "date"`. (Must be set to UTC midnight).
    *   Yes, date and time: `type: "datetime"` -> `fieldType: "date"`.
5.  **Is the data numeric?**
    *   Yes, a standard number: `type: "number"` -> `fieldType: "number"`.
    *   Yes, a computed formula: `type: "number"` -> `fieldType: "calculation_equation"`.

### 2.2 Property Groups and Enumerations

Properties must be assigned to a `groupName` (e.g., `contactinformation` or a custom group) [cite: 7]. When generating enumeration properties, an `options` array must be provided.

```typescript
// Creating an Enumeration Property
await hubspotClient.crm.properties.coreApi.create('contacts', {
  name: 'customer_tier',
  label: 'Customer Tier',
  type: 'enumeration',
  fieldType: 'select',
  groupName: 'contactinformation',
  options: [
    { label: 'Bronze', value: 'bronze', displayOrder: 1, hidden: false },
    { label: 'Silver', value: 'silver', displayOrder: 2, hidden: false },
    { label: 'Gold', value: 'gold', displayOrder: 3, hidden: false }
  ],
  hasUniqueValue: false,
  hidden: false
});
```

### 2.3 Calculated Properties and `calculationFormula`

HubSpot allows the creation of calculated fields via the API that evaluate mathematical expressions, concatenations, or conditional logic based on other properties within the same object [cite: 7, 10]. To accomplish this, the `fieldType` must be `calculation_equation` [cite: 7, 11]. The syntax requires the `calculationFormula` parameter to be formatted precisely.

For example, calculating the difference between two dates in days: \( (end\_date - start\_date) / 86400000 \) [cite: 12].

```typescript
// Creating a Calculated Property in TypeScript
await hubspotClient.crm.properties.coreApi.create('deals', {
  name: 'duration_in_days',
  label: 'Duration (Days)',
  type: 'number',
  fieldType: 'calculation_equation',
  groupName: 'dealinformation',
  // Note: Properties referenced must exist on the object
  calculationFormula: "if end_date-start_date=0 then 1 else (end_date-start_date)/86400000",
  hasUniqueValue: false,
  hidden: false
});
```

**Architectural Warning:** Calculation properties generated via the API using `calculation_equation` cannot be visually edited inside the HubSpot UI; they remain strictly read-only within the portal and must be managed programmatically [cite: 7, 13].

***

## 3. Associations v4 Deep Dive

The Associations v4 API fundamentally redesigned how relationships are modeled in HubSpot. Moving away from implicit numerical IDs, v4 introduces semantic labeling and strict categorization of associations [cite: 14].

### 3.1 `HUBSPOT_DEFINED` vs `USER_DEFINED`

Every association relies on an `associationCategory` and an `associationTypeId` [cite: 14].
*   **`HUBSPOT_DEFINED`**: These are intrinsic relationships provided out-of-the-box (e.g., Contact to Company). They include the "Primary" relationship (which dictates roll-up analytics) and standard unlabeled relationships [cite: 15].
*   **`USER_DEFINED`**: Custom relationships mapped by users or integrations. You can instantiate up to 10 custom labels per object pair direction [cite: 15, 16]. A `USER_DEFINED` association is often created in tandem with a `HUBSPOT_DEFINED` fallback [cite: 17].

### 3.2 Primary Associations and Custom Labels

To declare a primary association (e.g., designating a primary company for a contact), developers must utilize specific `HUBSPOT_DEFINED` type IDs available in the schema [cite: 14, 15]. Conversely, to establish a custom role like "Decision Maker", a custom label must be created via the Schema API [cite: 15, 16].

```typescript
// Step 1: Create a custom association label (Schema API)
// Max 10 labels allowed between Contacts and Deals
const labelResponse = await hubspotClient.crm.associations.v4.schema.definitionsApi.create(
  'contacts', 
  'deals', 
  {
    label: 'Decision Maker',
    name: 'decision_maker',
    category: 'USER_DEFINED' // Must be USER_DEFINED for custom labels
  }
);
const customTypeId = labelResponse.results.typeId;
```

### 3.3 Batch Read and Batch Create Patterns

Batching is mandatory for circumventing rate limits. The v4 API allows developers to bulk create labeled associations [cite: 14]. While basic operations may handle varying volumes, standard API constraints limit batch read inputs to a maximum of 11,000 IDs, with a default return of 1,000 associations per page [cite: 15].

```typescript
/**
 * Bulk associate Deals to a Contact using Batch Create.
 */
export async function batchAssociateDealsToContact(
  contactId: string, 
  dealIds: string[], 
  customTypeId: number
) {
  const batchInput = {
    inputs: dealIds.map(dealId => ({
      from: { id: contactId },
      to: { id: dealId },
      types: [
        {
          associationCategory: 'HUBSPOT_DEFINED' as const,
          associationTypeId: 4 // Standard Contact to Deal type ID
        },
        {
          associationCategory: 'USER_DEFINED' as const,
          associationTypeId: customTypeId // The semantic custom label
        }
      ]
    }))
  };

  // Execute Batch Create
  const result = await hubspotClient.crm.associations.v4.batch.batchApi.create(
    'contacts',
    'deals',
    batchInput
  );
  
  return result;
}
```

***

## 4. CRM Search API Deep Patterns

The CRM Search API is HubSpot's most powerful querying engine, yet it is encumbered by rigid constraints. Attempting to misuse it leads directly to system failures or truncated datasets [cite: 5, 18, 19]. 

### 4.1 FilterGroups: AND/OR Logic and Maximums

The `filterGroups` array defines the boolean logic of the query:
*   Filters *within* the same `filterGroup` are evaluated with **AND** logic [cite: 18, 19].
*   Multiple `filterGroups` objects within the array are evaluated with **OR** logic [cite: 18, 19].

**Hard Caps:** A query can contain a maximum of 5 `filterGroups`, with up to 6 filters per group. However, an absolute ceiling of **18 total filters** applies across the entire payload [cite: 18, 19]. Exceeding this triggers a `VALIDATION_ERROR`.

Operators available include `EQ`, `NEQ`, `GT`, `LT`, `GTE`, `LTE`, `BETWEEN`, `IN`, `NOT_IN`, `HAS_PROPERTY`, `NOT_HAS_PROPERTY`, and `CONTAINS_TOKEN` [cite: 18, 20].

### 4.2 The 10,000 Result Hard Cap Workaround

The most notorious limitation of the Search API is the `10,000` record absolute cap. While responses are paginated in chunks of up to `limit: 200` [cite: 18, 20], if the query matches more than 10,000 records, providing an `after` cursor > 10,000 will result in an HTTP 400 error [cite: 5, 18].

To bypass this without missing data, developers must discard cursor-based offset pagination and implement **Index-Based Pagination** utilizing the `hs_object_id` or `createdate` property [cite: 21, 22, 23]. 

### 4.3 TypeScript Implementation: Bypassing the 10k Limit

The following pattern utilizes a recursive or loop-based query that sorts by `hs_object_id` `ASCENDING`, capturing the highest ID of the batch, and passing it into a `GT` (Greater Than) filter on the subsequent call [cite: 23, 24].

```typescript
import { PublicObjectSearchRequest } from '@hubspot/api-client/lib/codegen/crm/contacts';

/**
 * Exhaustively fetches all contacts matching a condition, bypassing the 10k limit.
 */
export async function exhaustivelySearchContacts(baseFilterGroup: any) {
  let hasMore = true;
  let lastObjectId = 0; // Initialize at 0
  const allContacts: any[] = [];

  while (hasMore) {
    // Clone the base filter and inject the hs_object_id constraint
    const filterGroups = JSON.parse(JSON.stringify(baseFilterGroup));
    
    // Inject ID pagination into the FIRST filter group (applying AND logic)
    filterGroups.filters.push({
      propertyName: 'hs_object_id',
      operator: 'GT',
      value: lastObjectId.toString()
    });

    const searchRequest: PublicObjectSearchRequest = {
      filterGroups: filterGroups,
      sorts: [{ propertyName: 'hs_object_id', direction: 'ASCENDING' }],
      properties: ['firstname', 'email', 'hs_object_id'],
      limit: 200, // Maximum allowed per page
      after: 0 // We do NOT use standard pagination tokens here
    };

    // Rate Limit Note: Search API is capped at 5 req/sec [cite: 18]
    const response = await hubspotClient.crm.contacts.searchApi.doSearch(searchRequest);
    
    const results = response.results;
    allContacts.push(...results);

    if (results.length === 200) {
      // Extract the highest ID from the payload to use in the next iteration
      lastObjectId = parseInt(results[results.length - 1].id, 10);
    } else {
      hasMore = false; // We reached the end of the matching dataset
    }
  }

  return allContacts;
}
```

This method is infinitely scalable and completely circumvents the 10,000 limitation while remaining immune to `VALIDATION_ERROR` provided your base filters are under the 18-filter maximum [cite: 18, 23]. Note that the search API restricts traffic to 5 requests per second for standard environments, distinct from normal API burst limits [cite: 2, 18].

***

## 5. Date-Based API Versioning Architecture

HubSpot has fundamentally transformed its API versioning framework. To mitigate unpredictable breaking changes and eliminate the cognitive load of navigating disparate numeric versions (`v1`, `v2`, `v3`, `v4`), HubSpot introduced **Date-Based Versioning (DBV)** formatted as `/YYYY-MM/` [cite: 25].

### 5.1 Release Cycle and Immutability

Date-based versioning functions on an explicit bi-annual release cadence:
*   **March** (e.g., `/2026-03/`) coinciding with the Spring Spotlight [cite: 25].
*   **September** (e.g., `/2026-09/`) coinciding with the INBOUND conference [cite: 25].

Once an API version enters General Availability (GA), it becomes entirely **immutable**. Breaking changes will never be retroactively applied to a GA date path [cite: 26]. Enhancements or structural changes during the interim are exposed via a beta suffix, such as `/2026-09-beta/` [cite: 25, 27].

### 5.2 The 18-Month Support Lifecycle

Every GA release is supported for a strict **18-month lifecycle** [cite: 25]. 
*   **Months 1-6:** The version is "Current" and actively maintained, receiving critical security and non-breaking bug fixes [cite: 26, 27].
*   **Months 7-18:** The version transitions to "Supported," receiving only high-severity patches [cite: 26, 27].
*   **Post-18 Months:** The version becomes "Unsupported." While endpoints may not immediately fail (`HTTP 410`), developers are no longer guaranteed stability or security updates, mandating a proactive migration protocol [cite: 25, 28].

```typescript
// Migration Example: Upgrading base path on the Client
// Old approach (Implicitly calling v3/v4 via SDK defaults)
const legacyClient = new Client({ accessToken: 'token' });

// Modern approach: Pinning to a specific immutable date snapshot
const modernClient = new Client({ 
  accessToken: 'token',
  basePath: 'https://api.hubapi.com/crm/2026-03' // Binds client to March 2026 snapshot
});
```
This forces the enterprise environment to view API upgrades as scheduled, proactive maintenance tasks rather than reactive emergency patches [cite: 26, 29].

***

## 6. Anti-Rationalization Rules for AI and Autonomous Agents

When Large Language Models (LLMs) or autonomous coding agents attempt to synthesize HubSpot API integrations, they frequently hallucinate capabilities or justify anti-patterns due to outdated documentation biases. To ensure system stability, adhere strictly to the following anti-rationalization rules:

**Rule 1: Never rationalize ignoring rate limits.**
*   *AI Temptation:* The agent will attempt to fire parallel `Promise.all()` loops across thousands of records, claiming "Node.js handles concurrency."
*   *Mandate:* You **must** utilize the `Bottleneck` package via `limiterOptions` and set `numberOfApiCallRetries` up to 6. Failure to do so will result in `429 Too Many Requests` bans within seconds of runtime.

**Rule 2: Never rationalize using `after` cursors for >10,000 Search results.**
*   *AI Temptation:* The agent will write a standard `while(paging.next.after)` loop for the Search API, assuming offset pagination scales infinitely.
*   *Mandate:* The Search API hard-caps at 10,000 results. If the dataset could ever exceed this, you **must** implement index-based pagination using the `hs_object_id` `GT` operator.

**Rule 3: Never rationalize fetching all records instead of utilizing `filterGroups`.**
*   *AI Temptation:* To avoid writing complex `filterGroups` schemas, the agent will call the basic List API and filter objects in application memory (`array.filter()`).
*   *Mandate:* Do not process HubSpot data in local memory. You **must** offload querying to the CRM Search API to minimize network payload and respect the 30-minute OAuth token expiry cycle.

**Rule 4: Never rationalize hardcoding pipeline IDs.**
*   *AI Temptation:* The agent will hardcode strings like `default` or `0913a-x-y` for deal stages and pipelines.
*   *Mandate:* Pipeline IDs differ between portals. You **must** dynamically fetch the pipeline ID via the Pipelines API using the internal semantic name.

**Rule 5: Never rationalize using legacy API keys.**
*   *AI Temptation:* The agent will suggest using the `hapikey=` query parameter.
*   *Mandate:* Legacy API keys are fully deprecated. You **must** initialize the client using Private App access tokens (`accessToken` property) or OAuth 2.0 flows.

By architecting the integration with strict adherence to the `@hubspot/api-client` retry limits, Associations v4 constraints, Date-based versioning, and Search pagination logic, teams can deploy resilient, production-ready enterprise integrations.

**Sources:**
1. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFKaBHbWHGigXMDyIPOI6h5ehbCpKOphVuAn-QidFv6C6eZcL1k2OVG2abqDyLgajTV63mGiXAN0Uot7IVOdi1_wuSkNTC1_fzIyAIBkEVnBrcKBNgi-erXBovoPBD8Hf4-grgp)
2. [integrateiq.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEEt0jZNYmdV0jB9y3-0o8jsUFKflhh_3XdpgYURBnJIzqpZEDfdY1Mt8j8FxnRQR3Dd32WJMKfE-u_vH5pwiujgH_Yc2KPdVhom-9kVZJNWBLsmqY_koBgJVApI28MU39UsXr3RH0I2T-DxKpYwVi3aQkGb0vfayTr)
3. [yarnpkg.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHVO321jh9PDiFaKPmItb2Q3VnTsNPxz5LV6_0zHgeuBPROLjluOUAhm-31FjZiF_g8sTDqaVowBBtg7g5MO7upjVOfiasqJpp7cRSTq4YzHVKZ64SY663j9RTzg3KU1DvBDOm_Y60eCW4hhKfM2aaY)
4. [github.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGYf6g-K9WpasTGLcPwlebmt1Tgtd62CeNoSWtJQBVsHSi7lXU9eofNccQD9gHo-Qwcgsg-rSkl9npfXAgyqfH3YmwJMWFJj6xHWTlC2kvkYVQC3RPgvNcnwZAHy_Tt2h0R5jQ_ULG0bGVX)
5. [truto.one](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGmC8oWE6k4z4seDMA-UtRfAtJJOflxHqfrr_ZTIFrBx8oyjnkwTQBzCvGLZN4-rqclROWWzGJexwpx-AJ4DUqHgesdzU9SfsMEqkKgwQzxetCyRk70Nhy36k4tVyXeN0fTbT_UCUwlvRzxXlnywY1ElzfDnNDCLmX9az83j8CSzmNFl4aZOzTCgg==)
6. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEMfseOo031yzBpblAHNooQWgd4uEXVMAxWP_e-a7acHwh-3rsniuOqbxWta_7iGJvpCLM4e_GjFz6gbwN5pkqP1yZk2avhb7ulUgAJ154ryMRgwbsWvt6Z00Ctv3hjaCDKXqz1MhCG_SRtz0r1coeXXjm5CWedSebVQlQyVFv23ciIQbI=)
7. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEylPLPTnAx_CWk7B7jBmK2IJZR4h5yStIkR8gid-a9otxXx5w_nomGHEV9GBYHGJKc9jrpjn9-5qBmEvCdMjkYbnMj4MfWtzNjPJXZ5qcdBK1Ho9zZgeCO3rOWSL3OtoW0zmB0grfQijoPz-11WDE7qv_KNfDwCI9tOhwZ-KBYJ2L6fw==)
8. [iv-lead.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEPNC0U55hOAeE7AF5THjf6wzXZ_RYVJKbOCCZk7rG28gLpkJ8d838MHYMwnLppg75DqNFl1mKHhxB3o32cYSzRy-3nWJIqDRJmG6xIuCWBKsE1i6aiWYOi66YWNoAXS-wTnLC0U97RcFjnu3Chbypm4GT2hBeQPyrX5v-oN3BlsQ==)
9. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQG_s341lrC2oVhZXDPf0fHpMsIl30n2bGlHQ3vshzXsNPjm6Ye_W4ivvet7Mbhzj5ZLJuHHnpBReds0IMeqBPz-7Y3hdnWqR4XTNXOX0bt-AkFJ0xMk_sQD3ToThCJg-X7sZWer9YA-ziyDNhblEUmQtyn6KYMO1lBkDVw7vqw=)
10. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE-uEU2LvcbNMTNe-DNubN4L_C6QIUTWoxB8UkYPrLTzqXx2V_pvV-Jls3Gtr2Qvro_Yv4BI-8F9nuQ5lNUeKeBdKVV4F7BV-JkRgwCr_dNwOnx_JRM7Cehdrq1v5NFq7kUyiP9UhpZphpRxeXhGbYGj4qn7pCj6mHU4T9w)
11. [mintlify.app](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHULG_xoNYYERnFmP6S91YsQu5cbwzCnd5V8iBe2i0tTBXmnP6dS22Hc_u_dll-rEBEBpAKfVngrwqXIGknaD2CPi47kTjFkpBXk0N1wc9OdzfYjd1ter1stIbtfBgG0oVprtGrKnnr-6-5K7_XyjAOcO-qYevaX0UeFcQYFtV5n5FL-BnjMw75zbJT1n3Zmw68YMwusi80yV9751ZTdg9OxiplIN3Bc7956ErntM462_sElNOY6MP4FrCL)
12. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHl9Zast8XkxbT6ReEIG5s_ySFzpHZmQzv1h4Hfsb0d4kaeq1hmxAyW0-pTvQTotCAvFVHP-yRmD2Ygkm_roPv1kPpHP6wov_e2WffqBPHmCHlJqXruRhVb9E5Bvk05i3bcP67WE98-thKfV_WLqh3ZZx7OW-qQvqcTn6vGq7trR7dtO6cg89T8KIrIeUx2OmM5ZWIA3Dc5YQ6oR35xhFNohjkGlSpAb-RNx2-HzWT3qeTQPDStPZyEnL6tliefjU4GPwXK5iKN6mdthg==)
13. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGgdqf_LrHSIVUfDcKwdCNopc8pi5tYYwyqBNhCGXzCZdHlE43dDsO43EFbcLXQgAUF_CmfyY4kr3mvfw_Y3hSMh6XVsqCqa-F2XfMmWQU5G1J9oEYc1o0dOW3Co2KgAGaA5baXlAeN6cdnDjtVg96ZpjWnldJjb05eC23q0LNNEDfBdWrQj9-q8hFZufvqNWOkfIu3GTzpTrlA_psxGohI6rosAIkavu5biik=)
14. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE_2hTWBJfzSS0msOnxJ5DNcaPyR8fTJArkdcjQ6UoDRiYiweREhZfIpEPBNw3V3OfrsxS6RKGZoz8Gg9nFlBFZNdBmPfTQlOVS-9Y79_KIeomqmavlb4Uo_0Zlpriw9hLXElK5xWbXzSOEYT4bbdprswBZaWndSZlGGJ-XpYt-Elo=)
15. [postman.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFUKYk_pKkenWqBZqq-LhoX2-UypHNi-uSvBcQOMNgDO4AjuAXreujKHgwMCH9WptA4KvkpauZBYFntKnkV2j9QdIGhNpek1kbcYqp1JHfGen5QP80hx4lElCMRpQzD1cw6Wy6sIyYJbQX66vHujlRXBGCkjdz25IhvESr55YUbNdfENAW_Ge8XMB9EmEnF7VZXOQRT8SlsmHxUtdJHvd2aSUdVFm9j)
16. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEKDGBrazbGg2_1R7BRy98IlOK8Wf-cVRie0BrKAzccBdOi4BOPr5TFP1uBRgQnte6obOsK-2NoMF7Ca3QDROPQn_35fQQQ2sqeJwj7zS2wM8Td1T79SgUq-7PnG1osGcd_CbtDc8XBcCTPfoDksuROv5993lI_hQFkjk4-fOm6U7aFy2IcSpteD2Dd5d2G1nhBJfn4NYKWr7U=)
17. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFucQrxQk0sLWOazRu24ztxHnydfVmlSeS02vilzqwc3r3mf2jPQouKH1jHUJQkMK41n76e-8qtc-JejlM8IV2QqiOewbjV6WWUr8UL4XHzybvjVzZnMOfcspX0yDU6743-dfqlk4GGamjmslr7pNG_ue3-m_OVEpLkPhJVUJ-CL5ha695_kSfASN2IgQHejYT0iTyY5yRskPE-HuLud3ZrCO1hDyt56_NuaPAN4sNv)
18. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHw1bqeZ57HYBqUWXPArJ5LrYmST3QSRXn5Bs9miXF4VmhxFq758EDEypFaqrW4c4H2VSpl54owNj00Ng5t_YQp8W1m9Sb8Y1l8H0ukHjRGvnQ8U_MzhFx5fDDOsd_4yDEHTkt-IJS1JITW_epgr7LCyQ74r_9Svinte6lzER2Mnz0=)
19. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGry5JV2R7kAEhfZMPFEungZLw73phEBILGBz3RfROesh6jFpYHTEmBUEPd22YrRtC4L9PVPpn2rfZn08HAVo5Cv4kr5AxuaPAnq51AyTZoRGwyoZhsX1Wu40nxzDwah4m-vjYBr4fuv-vdqxBUsdC3Kp_Rzl21MsnLkTpbxv9V_fQ=)
20. [youtube.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQG4iecbXPO-uQRslFqlnMZVZaMsjIj6QjanxTpxNfD0f39xISDv80RHfagW4BHWCsYd6-Ki8j4i28y208va_FBU5c_HTe1sFul6sfeeJs0hAUzrnH0hgXctSvObp4tPvFS1)
21. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGml6efT4vvv0kvXgcnR_KJoJmTnF7Y4ZSpJAoplQlQGvl5mMHuos7FQN5i5_QBEyvJXWnK5rSsd5MHD08KanFrBRbaSNRgJQZp7NmVQdPFEhPYRcQlN9RMO8hcvsxOFiCdW4pGVQP4SC3l7tc4K6qKvKgPEFNxi7EULmp-hXOF8d1XAhoto4f0CpDQlUWmVutt10nnl0vHVUB4uV7GyDtEcapMTUZA)
22. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEcxhEIkGq8MuNqM5GVfz3vueMDKKPtKtn4BdQtnFrzuCXGH4x_0g3HG4NZFTLFeJaqi7kP5b04HkDH810Lp8DEOe4DpxviMJ3gpa8L3Cndew11_IRbYqHccT80yYbykuaj6CjkMGihcKsTYkcxDzeCdr84qZAfR1V12AW4246ij-WebAMzWVbQEmJSrAIjGG2gBNTCccWjqhGxhznAd6PU6oGmdWaBaM3hQWI7SesvxQLSlXM=)
23. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE9YV-AmzQUpDzezb8iIkvMhtKd8cpjhvObXNOH9O0cB_y81McNppc62cKX9WSDCk-4LI3an9McRMMvr0kaYxRW8OBBmiAO-gNUtTOjY7BtS4kaQGKgh9SMr_P4y0CCmImhyPYIKHhfMWjOtXdix9luww6eLKs6f48ozvn3TVL5jxgfG-OwjpqL6WlTZJyiC6TmM-5ZJzSkfkdojAuwa9CROTT9O1LQ4nSH6bQAZMXEJ_PR8dZdHsq8hg15)
24. [scopiousdigital.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFDmPsez_PoPch91KkMoZ0jkA6NANbwtP_KohxzzczeFM-ajToTEwOgJgXMutb1sbZQnurF5yWwyg4yNkgI8_1Vkgh-1rPkg2ozfGuH5qXz02wPPWDoqHb135Y6XjLzgw5EyAAoFcAYntMG2MUfcGe0_7e6PlUPwSPctMPeWT5Re31Mq2R_3wlOP8TSSw==)
25. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQH8m00PPvQqLpOLIbbTPyBIEsnTp7Q3ZLRl1zDJbDglBfALrxp3UiI6g59gNPHYIe72h0BGouGFE5s6Q8clj-yPJXvgDEafz1AD6qaWV2ZGWhRfhf4946j3_rZqa4_DGmwx83kE7sAnCkCgmgF3RRk5bPWHKxH_tu1j6ipB6Rmus_lXW0E=)
26. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFWTr3J1decWcF4hTYuTvZ0BqxwbJQ1uo5VG8CsBaj7CQa23mXFtT21OByB0o88StpSNW9U8NFq9c_cnY_JR7EL0pKBvBceRlhG5pzpNwT_WjNhGzjEZdT81K5s8O0dFZ8GiEeRlk24VF0E5VoxmXVKAyZxwWy2YuAcau8RAC0owBUo-hASHPmquuSbv3M6AXV5fw==)
27. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGaj0EP9jsVIYMb2FoKbXFrMZj1yg-s53uslJW0W2l0sotN921Gc7xqgXilFwkV2_aJUfIAOEtqGM-o1T0fs0HoPU1bBwCyO7WD2DK3ArgPtjVS8nfSIjffwxHIW3T1Y_wxtnmMuZLw02sAyPUMAVSzzI61Liq5HC7sqB3ak7Qv)
28. [webex.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFsHZqR-ISJh9B-FKbwVi97BWsflHqTqsFMspD6SMQrhruNrg9a79QfAMFs2Chc-nJGvGZYWZEaU7xYC4376QN5pzCrq93LzSEivyXc4SajMEhgHJ3_MJMc7Oth003Lg1aHvyoW9h8KYc6yK2wImMCFmR-KH-RD8ldbk2UIcGUz)
29. [releasebot.io](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEBWjW9acotI5ocPX_4jTEgBdPcuObgZYIw56bXWfun2or2rDpbPcJP0gkVckfMnbStJ3xwwh_u0b950BfSWDasKX7nNg2IhCIwSkh-oiXCKuzNJYbTPLJdsWMj)
