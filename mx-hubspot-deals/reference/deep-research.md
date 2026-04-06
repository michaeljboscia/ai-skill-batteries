# Comprehensive Technical Reference: Implementing the HubSpot Deals API and CRM Workflows in TypeScript

**Key Points:**
*   **Architectural Rigor:** Effectively orchestrating HubSpot’s CRM operations via the API requires strict adherence to its underlying relational models. It is absolutely necessary to understand the distinct object hierarchies, such as the dichotomy between abstract `Products` and instanced `Line Items`.
*   **Data Integrity Imperatives:** Research dictates that the HubSpot API bypasses certain UI-level fail-safes. Notably, the API does not automatically deduplicate company records by domain. Developers must manually implement search-then-create workflows to preserve database integrity. 
*   **Workflow Automation and State Management:** Advanced objects like CPQ Quotes and weighted forecasting metrics depend heavily on the proper synchronization of associations (Deals, Line Items, Contacts) and the precise manipulation of state variables (`hs_status`, `hs_template_type`). 
*   **Scalability:** It seems highly likely that relying on single-operation endpoints for bulk updates will result in rate-limiting penalties; thus, utilizing batch endpoints is a critical best practice.

**Systemic Context**
The modern customer relationship management (CRM) environment requires sophisticated data orchestration to ensure consistency across sales pipelines, financial forecasting, and quoting engines. Integrating an external application with the HubSpot CRM via TypeScript presents unique challenges, primarily stemming from the translation of relational CRM concepts into strict, statically typed programmatic interfaces. 

**API Philosophy**
HubSpot's v3 and v4 APIs adopt a heavily normalized object model. Transactions are represented by Deals, the lifecycle of which is dictated by Pipelines and Stages. Financial data is not monolithic; it is a composite of instanced Line Items derived from a centralized Product library. This reference serves as a definitive guide to modeling these domain entities, mapping their associations, and avoiding common anti-patterns that degrade data quality.

**Scope of the Guide**
This technical reference examines six core domains: Deal Operations (CRUD), Pipeline Metadata Management, Weighted Forecasting, Configure-Price-Quote (CPQ) Architecture, Line Item/Product Associations, and Company Deduplication. It concludes with explicit Anti-Rationalization Rules to enforce architectural compliance.

---

## 1. Deal CRUD Operations and Pipeline Dynamics

### 1.1 The Deal Object Paradigm
In the HubSpot ecosystem, a Deal represents a transaction with a contact or company, tracked through a standardized sales process [cite: 1]. Managing deals programmatically requires an understanding of HubSpot’s property schema and the required fields for deal initialization. The minimum requirements for a robust deal creation payload include the `dealname`, the `pipeline`, and the `dealstage` [cite: 1]. 

It is a critical constraint of the API that developers must utilize the **internal IDs** for pipelines and stages, rather than their human-readable labels [cite: 1]. If a developer omits the `pipeline` property during the POST request, the API will automatically fall back to the account's default pipeline [cite: 1, 2]. Relying on this fallback programmatically introduces severe risks in multi-pipeline organizations, often resulting in misclassified revenue.

### 1.2 TypeScript Implementation of Deal CRUD
To interact with the API, the `@hubspot/api-client` package provides a robust, typed Node.js SDK [cite: 3]. Operations are grouped under `hubspotClient.crm.deals`.

```typescript
import { Client } from '@hubspot/api-client';
import { SimplePublicObjectInputForCreate } from '@hubspot/api-client/lib/codegen/crm/deals';

const hubspotClient = new Client({ accessToken: process.env.HUBSPOT_ACCESS_TOKEN });

export class DealService {
  /**
   * Creates a deal using strict internal IDs for pipeline and dealstage.
   * @param dealName - Human readable name of the deal
   * @param pipelineId - Internal ID of the pipeline (e.g., "default" or numeric)
   * @param stageId - Internal ID of the dealstage (e.g., "appointmentscheduled")
   * @param amount - Optional revenue amount
   */
  static async createDeal(dealName: string, pipelineId: string, stageId: string, amount?: string) {
    const properties = {
      dealname: dealName,
      pipeline: pipelineId,
      dealstage: stageId,
      ...(amount && { amount })
    };

    const dealInput: SimplePublicObjectInputForCreate = { properties, associations: [] };

    try {
      const apiResponse = await hubspotClient.crm.deals.basicApi.create(dealInput);
      console.log(`Deal created successfully. ID: ${apiResponse.id}`);
      return apiResponse;
    } catch (error) {
      console.error('Failed to create deal:', error);
      throw error;
    }
  }

  /**
   * Updates a deal's stage via PATCH operation.
   * @param dealId - The unique HubSpot identifier for the deal.
   * @param newStageId - The internal ID of the new dealstage.
   */
  static async updateDealStage(dealId: string, newStageId: string) {
    try {
      const apiResponse = await hubspotClient.crm.deals.basicApi.update(dealId, {
        properties: { dealstage: newStageId }
      });
      return apiResponse;
    } catch (error) {
      console.error(`Failed to update stage for deal ${dealId}:`, error);
      throw error;
    }
  }
}
```

### 1.3 Update Dynamics and Batch Operations
Deals can be updated individually via `PATCH /crm/v3/objects/deals/{dealId}` or in bulk via `POST /crm/v3/objects/deals/batch/update` [cite: 1]. Bulk updates accept an array of deal identifiers alongside the mutated properties, providing significant performance benefits and minimizing rate limit exhaustion [cite: 1].

---

## 2. Pipelines API and Stage Metadata

### 2.1 Retrieving Pipelines
Pipelines serve as the tracks upon which deals progress. Accounts may feature multiple pipelines (e.g., "New Sales" vs. "Renewals") [cite: 4]. To query the entire taxonomy of an account's deal pipelines, developers utilize the `GET /crm/v3/pipelines/deals` endpoint [cite: 4, 5]. 

This endpoint returns each pipeline's `id`, `label`, `displayOrder`, and an array of its constituent `stages`. The stages are not merely labels; they are objects containing functional `metadata` [cite: 4].

### 2.2 Stage Probability Metadata
For deals, a critical piece of stage metadata is the `probability` parameter, a required float value between `0.0` (Closed Lost) and `1.0` (Closed Won) [cite: 4]. This probability is fundamental to the CRM's financial logic and heavily informs weighted forecasting capabilities [cite: 6].

```typescript
export interface PipelineStage {
  id: string;
  label: string;
  displayOrder: number;
  metadata: {
    probability: string; // Stored as a string representation of a float (e.g., "0.5")
  };
}

export interface DealPipeline {
  id: string;
  label: string;
  stages: PipelineStage[];
}

export class PipelineService {
  /**
   * Fetches all deal pipelines and their respective stages with probability metadata.
   */
  static async getPipelines(): Promise<DealPipeline[]> {
    try {
      // Direct REST call example using fetch, as SDK coverage for pipeline config can vary
      const response = await fetch('https://api.hubapi.com/crm/v3/pipelines/deals', {
        headers: {
          'Authorization': `Bearer ${process.env.HUBSPOT_ACCESS_TOKEN}`,
          'Content-Type': 'application/json'
        }
      });
      
      if (!response.ok) throw new Error(`HTTP error: ${response.status}`);
      
      const data = await response.json();
      return data.results as DealPipeline[];
    } catch (error) {
      console.error('Error fetching pipelines:', error);
      throw error;
    }
  }
}
```

### 2.3 Decision Tree: Enforcing Linear Progression
When building external integrations, developers often need to enforce linear progression rules (ensuring a deal moves from Stage 1 -> Stage 2 -> Stage 3 sequentially without skipping). HubSpot allows deals to skip stages via the UI, but external automation can impose strict business rules based on the `displayOrder` of the pipeline's stages [cite: 4, 5].

**Linear Progression Enforcement Tree:**
1.  **Receive Deal Update Intent:** Identify Target Stage ID.
2.  **Retrieve Pipeline Taxonomy:** Query `GET /crm/v3/pipelines/deals`.
3.  **Map Stages:** Extract stages for the specific pipeline and sort by `displayOrder`.
4.  **Evaluate Current vs Target Stage:**
    *   Find the index of the Deal's *Current* Stage ID.
    *   Find the index of the Deal's *Target* Stage ID.
    *   *Condition:* Is `Target Index` === `Current Index` + 1?
        *   **YES:** Allow PATCH update.
        *   **NO (Target Index > Current Index + 1):** Reject update (Skipping stages prevented).
        *   **NO (Target Index < Current Index):** Evaluate regression rules (Is regression allowed by business logic? If no, reject).

---

## 3. Weighted Forecasting Mechanics

### 3.1 Financial Properties Context
Financial projections in HubSpot rely on several intersecting properties. While the base `amount` property captures the gross value of a deal, sales forecasting requires a probability-adjusted view of the pipeline. HubSpot handles this mathematically using two primary properties: `hs_forecast_amount` and the deal stage probability [cite: 6, 7].

The mathematical formula applied internally is:
`hs_forecast_amount` = `amount` × `stage probability` (derived from the deal's current pipeline stage) [cite: 6, 7, 8].

### 3.2 Fetching and Utilizing Forecasting Metrics
When requesting deal data via the API, properties such as `hs_forecast_amount` are not necessarily returned by default. Developers must explicitly append `properties=hs_forecast_amount` to their queries [cite: 9, 10]. In reporting engines or custom dashboards, `hs_forecast_amount` provides an immediate, dynamically adjusted expected revenue figure without requiring manual client-side computation.

Furthermore, HubSpot documentation recommends utilizing the `Weighted amount` when reviewing expected revenue for individual deals, while distinguishing it from manually entered forecast categories [cite: 11, 12]. 

```typescript
export class ForecastingService {
  /**
   * Retrieves a deal including its weighted forecast properties.
   * @param dealId - The Deal ID
   */
  static async getDealForecast(dealId: string) {
    try {
      const response = await hubspotClient.crm.deals.basicApi.getById(
        dealId,
        ['amount', 'dealstage', 'hs_forecast_amount', 'hs_forecast_probability']
      );
      
      const properties = response.properties;
      console.log(`Gross Amount: ${properties.amount}`);
      console.log(`Forecast Amount (Weighted): ${properties.hs_forecast_amount}`);
      
      return properties;
    } catch (error) {
      console.error(`Error retrieving forecast for deal ${dealId}:`, error);
      throw error;
    }
  }
}
```

---

## 4. CPQ Quotes Architecture

### 4.1 CPQ vs. Legacy Quotes
HubSpot has transitioned toward a Configure, Price, Quote (CPQ) system. When generating quotes via the API, specifying the correct template type is non-negotiable [cite: 13]. Legacy templates are deprecated, and modern integrations must rely on the CPQ framework.

To instantiate a CPQ quote, the `hs_template_type` property must explicitly be set to `CPQ_QUOTE` [cite: 13]. By doing so, HubSpot automatically routes the quote generation through its AI-powered quoting system and utilizes the default CPQ template [cite: 13].

### 4.2 Mandatory Properties and Structural Associations
Creating a valid CPQ quote via the API is significantly stricter than UI creation. At an absolute minimum, a CPQ quote payload must define:
1.  `hs_title` (String): The nomenclature of the quote document [cite: 13].
2.  `hs_expiration_date` (Epoch timestamp): The validity deadline [cite: 13].
3.  `hs_template_type`: Set to `CPQ_QUOTE` [cite: 13].

However, defining these properties results only in an isolated, draft quote. For a CPQ quote to be published and functional, it **must** be associated with three distinct CRM objects [cite: 13]:
*   **Line Items:** Representing the products/services sold.
*   **Contact:** The recipient of the quote.
*   **Deal:** The transaction umbrella.

### 4.3 Quote States and E-Signatures
Quotes operate under a state machine governed by the `hs_status` property. Upon creation, quotes are typically placed in a `DRAFT` state [cite: 14, 15]. To finalize and publish a quote programmatically, the state must be updated to `APPROVAL_NOT_NEEDED` or `APPROVED` [cite: 14, 15].

For organizations requiring contractual signatures, e-signatures can be initiated by setting the boolean property `hs_esign_enabled` to `true` [cite: 15, 16]. Crucially, e-signature activation requires that the quote be correctly associated with a "Signer" contact via the correct association type, otherwise the publication will fail [cite: 15, 16]. 

```typescript
export class QuoteService {
  /**
   * Creates a CPQ quote, links associations, and publishes it with e-signature.
   */
  static async createAndPublishCPQQuote(
    title: string, 
    expirationDate: string, 
    dealId: string, 
    contactId: string, 
    lineItemIds: string[]
  ) {
    // 1. Create the base quote
    const quoteInput = {
      properties: {
        hs_title: title,
        hs_expiration_date: expirationDate,
        hs_template_type: 'CPQ_QUOTE',
        hs_status: 'DRAFT', // Start as draft to allow association linking
        hs_esign_enabled: 'true'
      },
      associations: [
        {
          to: { id: dealId },
          types: [{ associationCategory: 'HUBSPOT_DEFINED', associationTypeId: 286 }] // Quote to Deal
        },
        {
          to: { id: contactId },
          types: [{ associationCategory: 'HUBSPOT_DEFINED', associationTypeId: 69 }] // Quote to Contact
        }
      ]
    };

    const quoteResponse = await hubspotClient.crm.quotes.basicApi.create(quoteInput);
    const quoteId = quoteResponse.id;

    // 2. Associate Line items
    // (In a real implementation, batch associate line items to the quote using Associations API)
    
    // 3. Publish the Quote
    await hubspotClient.crm.quotes.basicApi.update(quoteId, {
      properties: { hs_status: 'APPROVAL_NOT_NEEDED' }
    });

    return quoteId;
  }
}
```

**Decision Tree: Quote Publishing Readiness**
*   *Node 1:* Has `hs_title` and `hs_expiration_date` been populated?
    *   No -> API Rejection.
    *   Yes -> Proceed to Node 2.
*   *Node 2:* Are Deal, Contact, and Line Item(s) associated?
    *   No -> Quote remains in `DRAFT` or errors upon publication.
    *   Yes -> Proceed to Node 3.
*   *Node 3:* Is `hs_esign_enabled` set to true?
    *   No -> Update status to `APPROVAL_NOT_NEEDED` -> **Quote Published (No Signature).**
    *   Yes -> Proceed to Node 4.
*   *Node 4:* Is the Contact properly associated as a *Signer*?
    *   No -> Signature logic fails; cannot publish [cite: 15].
    *   Yes -> Update status to `APPROVAL_NOT_NEEDED` -> **Quote Published (Awaiting Signature).**

---

## 5. Products, Line Items, and Automatic Amount Calculations

### 5.1 The Distinction Between Products and Line Items
A prevalent conceptual error among integrators is attempting to link a Product directly to a Deal. The HubSpot architectural paradigm expressly forbids this. Products (`/crm/v3/objects/products`) act as abstract templates within a central library [cite: 17, 18]. 

To apply a product to a specific transaction, the developer must instantiate a **Line Item** (`/crm/v3/objects/line_items`) [cite: 17, 18]. A Line Item is a unique, discrete instance of a product tailored to a specific deal or quote.

### 5.2 Inheritance and Association Type 20
When creating a Line Item, developers can pass the `hs_product_id` property. By including this ID, the new Line Item will inherit baseline properties (such as name and base price) directly from the corresponding Product [cite: 18, 19]. 

Once the Line Item is created, it must be tethered to the Deal. The official `associationTypeId` for a Line Item to Deal relationship is **20** [cite: 17, 20].

```typescript
export class CommerceService {
  /**
   * Creates a Line Item from a Product and links it to a Deal using associationTypeId 20.
   */
  static async addLineItemToDeal(dealId: string, productId: string, quantity: number, price: string) {
    const lineItemInput = {
      properties: {
        hs_product_id: productId, // Inherits product details
        quantity: quantity.toString(),
        price: price
      },
      associations: [
        {
          to: { id: dealId },
          types: [{ associationCategory: 'HUBSPOT_DEFINED', associationTypeId: 20 }] // Line Item to Deal
        }
      ]
    };

    try {
      const response = await hubspotClient.crm.lineItems.basicApi.create(lineItemInput);
      return response;
    } catch (error) {
      console.error('Failed to attach line item:', error);
      throw error;
    }
  }
}
```

### 5.3 Auto-Calculation of Deal Amounts
Historically, integrating systems required manually recalculating the total deal amount whenever line items were updated. However, modern HubSpot behavior facilitates automatic calculation. When line items are added to or removed from a deal, HubSpot automatically calculates complex financial roll-ups including Total Contract Value (TCV), Annual Contract Value (ACV), Annual Recurring Revenue (ARR), and Monthly Recurring Revenue (MRR) based on the line items' individual prices, quantities, and billing frequencies [cite: 21, 22, 23]. 

The aggregate sum is automatically pushed to the Deal's primary `amount` property, ensuring that the CRM perfectly mirrors the specific items being sold.

---

## 6. Company Deduplication and Merge Lifecycle

### 6.1 The API Deduplication Gap
While HubSpot's user interface, form submissions, and import tools automatically deduplicate Company records based on their primary domain name [cite: 24], **the API explicitly does not auto-deduplicate** [cite: 24, 25, 26]. If a developer makes a POST request to create a Company with a domain that already exists in the database, the API will happily create a duplicate record [cite: 26].

This architectural decision allows enterprises with shared corporate domains (e.g., subsidiaries of a conglomerate) to maintain discrete records [cite: 26]. However, for standard integrations, it causes catastrophic data duplication.

### 6.2 Search-then-Create Workflows
To maintain a pristine database, API integrations must adopt a strict "search-then-create" methodology. 

1.  **Search:** Issue a `POST /crm/v3/objects/companies/search` query using a filter where the `propertyName` is `domain` [cite: 25].
2.  **Evaluate:** If the `total` is > 0, extract the existing `id` and execute a `PATCH` request to update the company [cite: 25].
3.  **Create:** If the `total` is 0, safely execute the `POST` request to create the company [cite: 25].

```typescript
export class CompanyService {
  /**
   * Search-then-Create pattern to prevent domain duplicates.
   */
  static async upsertCompanyByDomain(domain: string, properties: Record<string, string>) {
    // 1. Search for existing domain
    const searchBody = {
      filterGroups: [{
        filters: [{ propertyName: 'domain', operator: 'EQ', value: domain }]
      }]
    };

    const searchResponse = await hubspotClient.crm.companies.searchApi.doSearch(searchBody);

    if (searchResponse.total > 0) {
      // 2. Company exists, Update via PATCH
      const existingId = searchResponse.results.id;
      return await hubspotClient.crm.companies.basicApi.update(existingId, { properties });
    } else {
      // 3. No duplicates found, safely Create
      const createInput = { properties: { domain, ...properties } };
      return await hubspotClient.crm.companies.basicApi.create(createInput);
    }
  }
}
```

### 6.3 Managing Merged Records (`hs_merged_object_ids`)
Over time, human operators will inevitably merge duplicate records via the HubSpot UI. When Company A is merged into Company B, Company A is ostensibly deleted, and Company B survives [cite: 27]. 

If an external integration continues to attempt to sync data using Company A's ID, errors will occur. HubSpot solves this gracefully via the `hs_merged_object_ids` property [cite: 27, 28]. When a merge completes, the surviving record inherits a list of all IDs that were merged into it [cite: 27, 28]. 

If a sync operation fails because an ID is suddenly missing, developers can run a Search API query where `hs_merged_object_ids` contains the old ID. This search will yield the new canonical ID of the surviving record, allowing the external integration to update its foreign keys and heal the synchronization link [cite: 27, 28, 29].

---

## 7. Anti-Rationalization Rules

To ensure system integrity, maintainers must strictly enforce the following rules. Rationalizing violations of these protocols inevitably leads to corrupted data states, unhandled API exceptions, and synchronization failures.

### Rule 1: Never Hardcode Pipeline or Stage IDs
*   **The Rationalization:** "The pipeline ID is just 'default' and stages like 'appointmentscheduled' never change, so I will just hardcode them in my payload."
*   **The Reality:** If users edit pipeline settings, rename internal values, or migrate between sandbox and production environments, the hardcoded IDs will fail instantly, bringing deal creation to a halt [cite: 1].
*   **The Mandate:** You **must** dynamically retrieve pipeline and stage internal IDs via `GET /crm/v3/pipelines/deals` and map them programmatically based on business logic [cite: 4, 5].

### Rule 2: Never Create Deals Without Specifying a Pipeline
*   **The Rationalization:** "HubSpot will just dump it into the default pipeline anyway, so I can omit the `pipeline` property to save code."
*   **The Reality:** The system default pipeline is arbitrary and can be altered by CRM administrators [cite: 1, 2]. If the default pipeline is inadvertently changed to a "Customer Success" pipeline, all new sales deals will inject into the wrong funnel, destroying sales reporting.
*   **The Mandate:** Every deal creation payload **must** explicitly define the `pipeline` property [cite: 1].

### Rule 3: Never Rely on Loop-Based Single Operations for Bulk Data
*   **The Rationalization:** "I only have 50 deals to update; a quick `for` loop executing `PATCH` requests is easiest to write."
*   **The Reality:** HubSpot imposes strict rate limits (e.g., 100 requests per 10 seconds for standard OAuth apps) [cite: 3]. Rapid loops will instantly trigger HTTP 429 Too Many Requests errors, leading to partial data syncs.
*   **The Mandate:** You **must** use the Batch endpoints (e.g., `POST /crm/v3/objects/deals/batch/update`) whenever updating, creating, or archiving multiple records [cite: 1, 30].

### Rule 4: Never Attempt to Directly Associate a Product to a Deal
*   **The Rationalization:** "I want to link my product library to a deal. I will just pass the Product ID in an association array directly to the Deal ID."
*   **The Reality:** The HubSpot data schema does not permit Products to connect directly to Deals. Products are templates. Attempting this association will fail silently or throw validation errors [cite: 17, 18].
*   **The Mandate:** You **must** create a Line Item (passing `hs_product_id` to inherit base data) and then associate that specific Line Item to the Deal using `associationTypeId: 20` [cite: 17, 18, 20].

---

## 8. Conclusion

Architecting a robust, scalable HubSpot integration in TypeScript transcends simply sending HTTP requests to endpoints. It demands a rigorous understanding of the CRM's underlying relational model. From managing the nuance of CPQ quote state machines to navigating the complexities of line-item financial rollups, developers must treat HubSpot's schema with surgical precision. 

By implementing strict search-then-create methodologies for company deduplication, leveraging `hs_merged_object_ids` for self-healing syncs, and rejecting the anti-patterns outlined in this guide, engineering teams can ensure flawless data parity between their native applications and the HubSpot ecosystem.

**Sources:**
1. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEz9QkhC2td5SKONeli6t8OjxU6EuVROuL2omeo3-LvA8uT511fjTbxVukZQa-cGej-1XJoBfrHGKAGL45c1Z4PM-uVVBTKcdNYA2jHkWsOm1un1jSQe60Z7pJ8FZslgghgj1F8xzvueXPpmaKiu0TwnYN-eO7DI5IrsA==)
2. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFgFp_NPlMtnAK0rZ87hkrGmM5pkgkbAhjmi6cIjtpDC5jWeh3p7pnIOc5Z_zNp6jeSk-xqqq5_6Fej4h59p6Ih4oGrzW2qUWdK6nwhfjcUgngOo_PWCr2OMB8ExoawWyd4CwjMNUYcmVuL8Q-Jp5cD8Lwrx3zfpOge9U9PTGhA4ucpxMQZsA==)
3. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGnWcDKZw1XD2CiEe3iIRLIH9vvsZKsrKw4Xq4oPJJyIavjc4FV_2uifl9XXwrFKeweEMd406WtwUls6a8iLf8cFA1alxBf8PR8wgEPm_EMBheGS2ai_1IW-Me3ZM38VCKdjzHX)
4. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHWmpF62nH8P4pjafi094HDfQgNCGjBxbDxR44oVOHNRLmB27kDpEV-N_qwq3TnfRWmophu30Q8iZ7wa7_mmLYddfpHBvc6bHHiOoHSu6N8kp2Tj718hyWHE9oP-T1RdUdRj7TW-Ma96birmfTagz2KfR1c80bsYFs6qC-RXeA=)
5. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHFu3Bvm7A7kMpPoJLVjA-Z50nP_Xi_PTX26D6Rm-XQChYMxlPuVSR_-hUeKiTFqu_Y-E1ikjkduNaRQEeLJ3rqOPJAP4p3rP82o_xjw3zMq8FpBYzWPIWMkCl7oNGOLWxuS7u2jr9vgZny9w4-cm-RFCnL4HznkRa5am7CCkPVORaZho8yuNxKmitDSw==)
6. [babelquest.co.uk](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGOqR5uAB2iCa-Jry3MBx9628PBFzXV3QE8ASLFVrSSPQrz21v0Y1z-SOUcoSYQtj8hjB-yvmAMvixuOg_QuXgztMU-gvtEGs4fdhDcHK5qbZYdzg6NgJMEsb90SPxCmuITlyzzrC-6OU51duLormwe_X4_sWGDB9L3I2dxNQqVOyOFlxj-kwzy352jSoc4)
7. [henrywang.nl](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHx66o1wqJnT_nXXGAJKzOpCBWIBLPcsItW5vgJOwRSLJDHHh3IscpyXbqZMFLiXmnf4v_1-6BecMIXjfBV5mINWZGuyBAomZXL5xfwPB1fY1yQTV-Cnv3wRRsdf8zWxyDVD800ts-b0w==)
8. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEjNp53K1IqP-5VuWqOuZHSCUEQaNDT0SbN-LsbIbBojf2AA2PxPLW3XmNw5BOwuw4BuhGnAPOfg9l9gNGIwBB0wFEz1WuAv1U2phxRtgBFgGIWRtQPE4ODI7QEcYccce2Gwgs5bvSyAlseej74O4vtMPggbBU=)
9. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQG3qj1j2T0fX-BLOHVy_rqzCKsGJRCKtY1dlMw-lvamQxvW5k77uh-CNU2eHFkeMjuBbz2pRc1yRABXQLKOi750WgUPk7bwzuI0teprfCkbXrraUKPERlTABuIIZS8dEG-nEF2rBx0GrpbTLrLPIFRfzEEBABoJJEd72l9_0BUjAl7BQlZevUgGorpeVS7Rmlm9llXVD-btHZype9lVTZv_)
10. [powerbi.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGwva5hqlTFnPBLckKkTMMRHy5azJ57BYsP4rIGqpyghVsRkJSxI-AXWxcx2KCIQqM-ecAg1ctxpROsZo-73fT9j2_ZuLfg1Qpx_QMyGDHyusHU2hEOqi4l2ln63LWbEsCMJ8IWMlc8iqDcAnmc24NuzACKjQxjdfsazLJImzG1aBDkRgbAd3K2PWDw__bDCRQrweC_0anIb-s5x1yYXxciaU93y9rSBg==)
11. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQG413ErOtBBFSKPtxMPj0WfEj-PDicCuxIbBu67Wsg2LHeqdAdur3yIoAeuX98wVDmcD4KfpxDKSrNTMTiLs747fb0ukYI-iAvSG3xqpZUyYgcUHAlJgxiWX-4fzjzXH1_fDlm7sAY1BgOtcypleCCU_iHjbsg1E-BCt0KOfd6qiWnLpLB10UP1XkMw7KeLYMrIUShwXehDiw==)
12. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHmzP-B3XD5id-Bcbd8KpX-YBLNwcwXZR9qY2Q2AW7nqZyrsCKohh4-tnTooM4P2MJRUTTQz0RNwXHNsB4776SEXbx3MZxGDaABEdyfDYyVbEBzKRL70RYNVdjZc-yz_-6IzqLt3JEztQOzLFm4f9hbOJe5BdQRFaiezyrSYuS_uc2yMdk2cnnoshz9lOU9tMJZZ9k9yzZuFD-C7Yc2tK7ErA==)
13. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFYqRI4LePkYdN2krahCNBYdseK5Z-jAHklUZLFE2_AkF-f9xl2XR11K4YkId39mdj-Nt17VgqTahizSVEkLCszlqQGNkc5PumRpAaygo7G8UXFGy2nMQhuPN5os562kDCbBZLe_QsyPae7fMNqnFAS8unSi8Um)
14. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEKKQRxAnLJq0tU6XmZfBNE25MmmuHSTASZ1Br72N73S94TC1RSWFTIQkcef2ooOi_tq3IIN1BvRDQvHwdFLvXzXC6AYVv-mPx_HBZ0R1kCAMvagZI35BA2rJJybzd_q73_lswmuJCM4C-8_eGeH_vIO9bwVT5yCZ99S2zBEeR2KHBx2nw0E5adR_-YNd-e0Q==)
15. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE69d52TuycyNfzaE2FpyRYhGckaIDMWXUilMdT2Ja30Q7Pri-2N-9Vl2theu8ugZ9ThCbaqxEyl-EhDJVHgOsr7iExhhuoDY2pqPC9GwTY6sj1mt7DClnzYifFll7oQTE-j_bIDQhOxANUZM1T71G4KngdkZWrawxDbLRDFDlarSN0guaWQuFnlt9ut5_ZUbuRxVyU-mPG_MgrbPFlp68_AS5lSoNh)
16. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQF-_RPBjkIucJLtMUQvCPrJUgbBFt3lGWd_XaDPlj-wKLxaG4uBonnebwrNikEyKzgCGjqhbFg2B2rdb36X7n4Efzxp_oj49GyJnPawq45TgAk4bccQ1lBEcm9e5AiHf43DaqlmyVjQQ7p-F8uUwgt3AOWsdTv8gcNdBWE=)
17. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHZnH0lgDCo6ROszV-B9ugZMgLt-acIMUejK5GinkWIhobliAVGKmDdYTgle7-tCIGqGiFn0-l2aUoXIqEJvIFl5imnZOridf4HlxrOIi9FzCs85DWqH7sPwkL1cdOMbF7pLIlwqNvHEcWx7NXNhm32tsoBrj4U4aFXMzWeqVS_Iv8NnCXhZXF6tQ==)
18. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFi-QkvcHUsDd7ijy1xBr5IwMdD7C9Xzg2TLk-7lN9DHkeKZN6F94GfeF2pUYQp2XapHiQEb5lTJgqd55evNRr5gUOVw4Qoz36kuX9Sf6vnWURjHSjz7kDcBQDDSpVmRUE6-VGNvmMXikySxkQ4uZURs_TNOgBrjMoZoQ0c-lvlOD2sPyARZPdSL4cz)
19. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQF81GxBMMEszaClCO7ho32NP3RtD_vbeX3CPY1v4mGmNRNw-R9XSC_F7pDuG4QXHkMXcrn3BLyaAk6RFA3zjBeYurDNvoCjwYPlYHhwareKlcBxIzjTH6HD3RnwFcXw0E61z_ItOCrOzrhWUTTnad5nCbTk-CJI38DRRvKkEFb04L6KU07l1eOny2ecHrVTtzBYac-1Nope4heJ0Q==)
20. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEE1MXgL7tBhKbxBCh5s86XM5Kj-dPAkC1hr4iBpbthpmOB9jNM3j-LCVGIklU9hWJR_w-5x4yeR_PG_DLq55J-eAmCVrYDokchvuWhdLcDbs0WyO64AMbRQcysi8Zn8cCcoi80moXKjh5_sMlRCxQAwqh4DbwWwRbYaGZZCQ5e7DU=)
21. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFmGIY4QA57inSBtqYmVBA44iSzna_YgRmJcijsm6nLET0gXHb_R7DXOBuka9FOqM65rdJaSxwziRoWvBTp5zE0D7QG5nPF43b2ZzAgrqeMR8EMtZ2H5YoPyXt57nXY6FQdpZEk6f5MOg2WaXHScamHAAFdH7U=)
22. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEASIAlWf5AI5BEDmgi42tV_TLJ2yzFYxn8U1Mc6PmEHsGGmgKIx3QOihYb-8N4tx1echboSzDmgHl6dJj8gh_pnxJqZKzw7zUH07hBR6kNjvbCIxkkc81vMMUOmWxdgMm4nf0N74_bHgKkQgbYrS2c7oM2M4I9devEPsFYOGIbEDOoLeeaz1-yumnKCm5RGqdN_iqBSMU=)
23. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQH6qZOW_yW8EsQJFz3QtcKC7ID2pNY-FSIfIEo60lsG29y4DmLQTx-VXSSDVuFXTa5oyXB29jZVRCIqfvl4neKIVltTwzsJzuANqMSdou4dwio7icuaOipVgzuGLsjZlSA5XbUFmh3XSeOSzRE6KjxbFmC7m45UJIBKDskPhuzBpyu9_hULqnPD4h5_oCgJO_L8o0M=)
24. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEpzK9HMyOEGTIOak6PhN_TlZ35cCEmYzhObtIjidNqP6nwtzlujIBDxQCJrtBC4myUvGKUSR0i5ey5H8Cgp2ukt47oB4ory2XhnbImF4wxtnUhifU0lXeOQt-kyNJEZQccUeoWkiv5m56pLRyXbXblG7aw2g==)
25. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHzV61DEImDfGy3R_TMLKBxF2Qq3q9a_8sK1jjVanIGBPjmvmKIFLTLrR-ZX9MJd5PYRMwrVlbkmYdJzpt7mE6O7t0CEoFZiAkpZowss4BpkjAQPJ_R_udiJUpfNCvj9rkiEuF5h-DsA_JakN2-2TjLb_wrHi-pVfNOrfMFHuehZZyf2xHGMeHYnPiJ3M_xiKJPQ8AcKUqX0lwSRhNzid0=)
26. [scopiousdigital.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFy_W1XxemzzpRliVcnM7Pqpzt3t9hGkoMQyQDlCYK9eprHzqY0F1QAE-HbGuVHZZs0Tz3GcjNYWkjCG7p5baxbom0mB7rLY_c2O3jwAmNFqrv1jpssskWejoX_BPVYGLysITEVbpZz8BPq_9-zCBxPHoUixeTnYva4dxL6WL8MsZvzmIyHYTW3f2OUF-VdGym_24g=)
27. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGNBAouO4AJlU3wnkmwLww-8foFRjtuxKHyyjhzsYyAsidEY3_dlXnm8M6Ux9zaMdNb_u7XzO6lTolAMxxmSqQVJ5zHXj8M7FnEgziasbUmv-gixcYiblxv0tXOtGU0RGa6W78ydvpkUKUnFdb7ZVQi5OQT64-jdbCcexyPlOKyP7lhdX4aA8dh3n4NPR77lU5luVp7DBGg7bgKUaqtu0uQUmPa)
28. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEeYGWCb2M8omEOORdrvZDN2Fk13KJQWFxZX6-xZJFrcJ268YyoMtyyR3lNDU4dGsx4YeEchSXPV1cG86fTPs9m3ObAC7SFcqgORMhGGr_dvhqwv9Kn6SxsS73i2XpVzRqH7B7eXaSXkrTAhbpD9IE7RvR-sSMCqxFCbi3veo5056LyK6akYF5GLiv-TovlbzmvcTKhaannOk6vGIPIGx6a-HNPDQhVkevk)
29. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFS9I2j5C3p5-1DxCtrvVH9YNMbyRXARKvpfhOX0FfRkJagVuYsXw4HnPMLWLlycho8UbdNgCZzupkh_iTQo-TvQgVYvI7uSu8p35F9HOHP8HJITPG13lw8nD0FvVgb6LYlRKKzOuXzumaplF4vabDYSbNePAQvZjjOM5yQXIFaTnRtgMqY4vzkFei05D0tOt3bajNlMJWtTe6y)
30. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQENk_FXgg1hLuXTcm8AETazCSSf8x48oplCLVdI47fO-4VCvsWmkDKLCwiPu6qPSJ3bGqxs3hhCEwGrRJQcuLNuaRqTuQKAUZOhiMqctI_-ijy7ViKeSstDYFhpHruLCs-gH0R2S9Qbs_K_cBawYwSU4nlP8SWY)
