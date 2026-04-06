# Comprehensive Technical Reference: HubSpot Marketing API Architecture and TypeScript Integration

**Key Points:**
*   The HubSpot Marketing API is segmented into distinct services: Marketing Emails v3, Transactional Single Send API, Forms API v3, Custom Events, Campaigns, and Subscription Preferences. 
*   Developers must differentiate between creating marketing email content (v3 Emails API) and executing programmatic sends (Transactional Single Send API).
*   Form submissions require a contextual footprint (the `hubspotutk` token and `pageUri`) to properly stitch web analytics history to CRM contact records.
*   Custom Events operate on a strict schema-first architecture requiring explicit event definition prior to data ingestion.
*   Data sovereignty is rigorously enforced; EU-based portals must route traffic through specific regional subdomains.
*   TypeScript implementations should leverage strongly typed interfaces to navigate complex nested JSON payloads effectively.

**Introduction for the Layperson:**
Integrating software applications with the HubSpot CRM can seem daunting due to the sheer volume of available endpoints and varying architectural rules. At its core, the HubSpot Marketing API acts as a digital bridge, allowing external servers and applications to securely read, write, and manipulate marketing data such as emails, forms, behavioral events, and campaigns. Research suggests that while the platform provides extensive documentation, developers often struggle with knowing *which* specific tool to use for a given task. It seems likely that explicitly mapping out these boundaries—such as when to use marketing versus transactional emails, or how to handle European Union data routing—can drastically reduce integration errors.

**Systematic Breakdown:**
The following technical reference systematically deconstructs the six major pillars of the HubSpot Marketing API ecosystem. It is intended for software engineers and systems architects tasked with building robust, server-side integrations using TypeScript. By combining theoretical architectural guidelines with practical code implementations, this report aims to eliminate ambiguity, provide definitive decision-making frameworks, and enforce strict "anti-rationalization rules" to prevent common integration anti-patterns.

***

## 1. Abstract and Ecosystem Overview

The modern marketing technology stack relies heavily on programmatic interoperability. The HubSpot CRM exposes a RESTful API ecosystem designed to facilitate bidirectional data synchronization, event tracking, and automated communication. This guide provides an exhaustive architectural reference for implementing the HubSpot Marketing API utilizing TypeScript.

The complexity of the HubSpot ecosystem necessitates a strict categorization of concerns. Marketing APIs are distinct from Sales (Engagements) APIs and CRM Object APIs, possessing unique rate limits, authentication constraints, and payload structures. Furthermore, the migration toward v3 and v4 API endpoints introduces enhanced capabilities for data validation, asynchronous processing, and schema enforcement [cite: 1, 2].

This reference strictly examines six fundamental domains: Marketing Emails v3, Transactional Single Send API, Forms API v3, Custom Behavioral Events API, Campaigns API, and the Communication Preferences (Subscriptions) API.

***

## 2. Marketing Emails v3: Programmatic Construction and Analytics

The Marketing Emails v3 API (`/marketing/v3/emails`) provides programmatic interfaces for the creation, modification, and retrieval of marketing email assets [cite: 2, 3]. A critical architectural distinction must be made: **this API is designed for content management, not for message dispatching** on most subscription tiers [cite: 2].

### 2.1 Distinction from Sales Emails and Transactional APIs
Marketing emails managed through this endpoint represent broadcast-style communications utilized in newsletters and automated workflows. The Marketing Email API cannot be used to create or retrieve data for one-to-one sales emails sent via the contact record; developers must utilize the Engagements API for sales communications [cite: 2]. Furthermore, to programmatically trigger an email to a specific recipient, the Transactional Single Send API must be used [cite: 2].

### 2.2 Schema and Full JSON Content 
When creating an email via `POST /marketing/v3/emails`, the API ignores standard UI drag-and-drop template IDs in terms of automatic HTML generation. Instead, the endpoint expects the full structural definition of the email as a nested JSON payload, including all modules, flex areas, and specific content [cite: 4, 5].

If a developer attempts to pass a simple HTML string to the wrong property, it will fail to render within the HubSpot UI editor [cite: 5]. The content must be formatted within the `content.flexAreas` or `content.widgets` nodes [cite: 3].

### 2.3 Email Statistics vs. Email Events API
Retrieving a marketing email via `GET /marketing/v3/emails/{emailId}` yields a `stats` object containing aggregated post-send statistics (e.g., total opens, clicks, bounces), matching the in-app Performance page [cite: 2]. However, to analyze granular, time-stamped interactions (e.g., exactly when Contact X clicked Link Y), developers must rely on the Email Events Analytics API, which tracks discrete occurrences [cite: 6].

### 2.4 TypeScript Implementation: Email Management

```typescript
import axios from 'axios';

// Interfaces for Marketing Email payload
interface EmailStyle {
  backgroundType: string;
  paddingBottom?: string;
  paddingTop?: string;
  backgroundColor?: string;
}

interface EmailColumn {
  id: string;
  widgets: string[];
  width: number;
}

interface EmailSection {
  id: string;
  columns: EmailColumn[];
  style: EmailStyle;
}

interface MarketingEmailPayload {
  name: string;
  subject: string;
  templatePath: string;
  activeDomain: string;
  archived: boolean;
  content: {
    flexAreas: {
      main: {
        boxed: boolean;
        isSingleColumnFullWidth: boolean;
        sections: EmailSection[];
      };
    };
    plainTextVersion: string;
  };
}

export class MarketingEmailClient {
  private readonly baseUrl = 'https://api.hubapi.com/marketing/v3/emails';
  
  constructor(private readonly accessToken: string) {}

  /**
   * Creates a marketing email definition. 
   * Note: This does NOT send the email.
   */
  public async createEmail(payload: MarketingEmailPayload): Promise<any> {
    try {
      const response = await axios.post(this.baseUrl, payload, {
        headers: {
          'Authorization': `Bearer ${this.accessToken}`,
          'Content-Type': 'application/json'
        }
      });
      return response.data;
    } catch (error) {
      console.error('Error creating marketing email:', error);
      throw error;
    }
  }

  /**
   * Retrieves aggregated statistics for a specific email.
   */
  public async getEmailStats(emailId: string): Promise<any> {
    try {
      const response = await axios.get(`${this.baseUrl}/${emailId}`, {
        headers: { 'Authorization': `Bearer ${this.accessToken}` }
      });
      return response.data.stats;
    } catch (error) {
      console.error('Error retrieving email stats:', error);
      throw error;
    }
  }
}
```

***

## 3. Transactional Single Send API: Reliable Event-Driven Communications

The Single Send API (`POST /marketing/v3/transactional/single-email/send`) merges the capabilities of the native HubSpot email editor with programmatic triggers, serving as a powerful alternative to traditional SMTP configurations [cite: 7]. 

### 3.1 Architectural Dynamics
This endpoint operates asynchronously. A successful POST request returns a `statusId` (with statuses like `PENDING`, `PROCESSING`, `CANCELED`, `COMPLETE`), which can be continuously polled using the Email Send Status API [cite: 8, 9]. 

Crucially, any emails dispatched through the Single Send API are automatically associated with CRM contact records based on the provided email address. If no contact exists with the matching email address, HubSpot automatically creates a new contact record [cite: 7, 9]. If automatic contact creation is strictly undesirable, developers must bypass the Single Send API and utilize the HubSpot SMTP API instead [cite: 7, 9].

### 3.2 Custom External Tokens and Overrides
To inject external system data (e.g., e-commerce receipts, shipping numbers) into the email, the API accepts a `customProperties` object [cite: 7, 8]. In the HubSpot email template designer, these properties must be referenced using the `{{ custom.property_name }}` syntax [cite: 10]. Attempting to use standard contact token syntax for custom properties will fail to render the injected values [cite: 10]. Contact properties can also be updated at send-time using the `contactProperties` object [cite: 8].

### 3.3 TypeScript Implementation: Single Send Execution

```typescript
import axios from 'axios';

interface SingleSendRequest {
  emailId: number;
  message: {
    to: string;
    from?: string;
    bcc?: string[];
    cc?: string[];
  };
  contactProperties?: Record<string, string>;
  customProperties?: Record<string, string>;
}

interface SingleSendResponse {
  requestedAt: string;
  statusId: string;
  status: 'PENDING' | 'PROCESSING' | 'CANCELED' | 'COMPLETE';
}

export class TransactionalEmailClient {
  private readonly baseUrl = 'https://api.hubapi.com/marketing/v3/transactional/single-email/send';
  
  constructor(private readonly accessToken: string) {}

  /**
   * Asynchronously sends a transactional email and auto-associates to CRM contact.
   */
  public async sendEmail(request: SingleSendRequest): Promise<SingleSendResponse> {
    try {
      const response = await axios.post<SingleSendResponse>(this.baseUrl, request, {
        headers: {
          'Authorization': `Bearer ${this.accessToken}`,
          'Content-Type': 'application/json'
        }
      });
      return response.data;
    } catch (error) {
      console.error('Transactional Single Send failed:', error);
      throw error;
    }
  }
}
```

***

## 4. Forms API v3: Inbound Data Capture and Compliance

The HubSpot Forms API facilitates the programmatic capture of lead data from custom front-end applications, bypassing the native HubSpot embedded scripts [cite: 11, 12]. Form definitions are managed at `/marketing/v3/forms`, whereas data submissions are routed to the integration endpoint.

### 4.1 Endpoint Routing and Data Sovereignty
Submission requests utilize a cross-origin (CORS) supported POST request [cite: 13]. The standard global endpoint is:
`https://api.hsforms.com/submissions/v3/integration/submit/{portalId}/{formGuid}` [cite: 13, 14].

**Critical Geographical Exception:** Portals provisioned within the European Union data center possess an entirely independent API infrastructure. Consequently, EU submissions must be routed exclusively to `https://api-eu1.hsforms.com/submissions/v3/integration/submit/{portalId}/{formGuid}` [cite: 15]. Failure to respect this routing will result in unauthorized/failed request errors [cite: 15].

### 4.2 The Context Object and `hubspotutk`
The most critical architectural component of a form submission is the `context` object. The HubSpot tracking script installed on a website generates an anonymous tracking cookie named `hubspotutk` [cite: 12, 16]. Submitting a form without parsing and including this cookie prevents HubSpot from linking the visitor's prior anonymous web browsing history to the newly generated CRM contact [cite: 12].

A fully formed context object must include [cite: 12, 14, 16]:
*   `hutk`: The extracted value of the `hubspotutk` cookie.
*   `pageUri`: The absolute URL where the form submission occurred.
*   `pageName`: The document title of the page.

### 4.3 GDPR and Legal Consent Options
For GDPR-enabled portals, the submission payload must explicitly declare consent mechanisms within the `legalConsentOptions` object [cite: 13, 14]. Developers must specify whether the consent to process data was explicitly granted and to which specific subscription types (`subscriptionTypeId`) the user has opted-in [cite: 14].

### 4.4 File Upload Restrictions
The Forms API does not natively accept multipart form-data binary payloads for file uploads [cite: 11]. To attach files to a form submission, a two-step process is required:
1. Upload the binary file utilizing the dedicated HubSpot Files API, which returns a public or hidden URL.
2. Pass the resulting URL string as the value for the file upload property within the standard JSON Form submission payload [cite: 11, 17].

### 4.5 Submissions Are Write-Only
Form submissions are asynchronously processed data pipelines. The API responds with a simple `200 OK` (containing inline messages or redirect URIs) but **does not return the resulting Contact ID** [cite: 13]. To retrieve the Contact ID, a subsequent query to the CRM Contacts API utilizing the submitted email address is required.

### 4.6 TypeScript Implementation: Form Submission

```typescript
import axios from 'axios';

interface FormField {
  name: string;
  value: string;
}

interface FormContext {
  hutk?: string;
  pageUri: string;
  pageName: string;
  ipAddress?: string;
}

interface ConsentCommunication {
  value: boolean;
  subscriptionTypeId: number;
  text: string;
}

interface LegalConsentOptions {
  consent: {
    consentToProcess: boolean;
    text: string;
    communications: ConsentCommunication[];
  };
}

interface FormSubmitPayload {
  fields: FormField[];
  context: FormContext;
  legalConsentOptions?: LegalConsentOptions;
}

export class FormsApiClient {
  constructor(private readonly isEU: boolean = false) {}

  private getBaseUrl(): string {
    return this.isEU 
      ? 'https://api-eu1.hsforms.com/submissions/v3/integration/submit'
      : 'https://api.hsforms.com/submissions/v3/integration/submit';
  }

  /**
   * Submits data to a HubSpot Form (Unauthenticated CORS allowed)
   */
  public async submitForm(
    portalId: string, 
    formGuid: string, 
    payload: FormSubmitPayload
  ): Promise<any> {
    const url = `${this.getBaseUrl()}/${portalId}/${formGuid}`;
    
    try {
      const response = await axios.post(url, payload, {
        headers: { 'Content-Type': 'application/json' }
      });
      return response.data;
    } catch (error) {
      console.error('Form submission failed:', error);
      throw error;
    }
  }

  /**
   * Utility function to parse the hubspotutk cookie client-side
   */
  public static getHubSpotCookie(documentCookie: string): string | undefined {
    const match = documentCookie.match(/(?:(?:^|.*;\s*)hubspotutk\s*\=\s*([^;]*).*$)|^.*$/);
    return match ? match[cite: 14] : undefined;
  }
}
```

***

## 5. Custom Behavioral Events: Defining and Tracking User Journeys

Custom behavioral events represent highly specific user interactions—such as logging into a SaaS application or abandoning a cart—that cannot be tracked via standard page views [cite: 18, 19]. The architecture mandates a strict schema-first approach [cite: 20, 21]. 

### 5.1 Event Definition Prior to Ingestion
Before sending event occurrence data to HubSpot, the event schema must be explicitly defined using the Custom Event Definition API (`POST /events/v3/event-definitions`) [cite: 19, 21]. The definition includes metadata, the target CRM object (e.g., Contacts), and up to 50 custom properties formatted tightly around specific naming conventions (lowercase letters, numbers, underscores) [cite: 21, 22]. 

Once defined, HubSpot assigns a `fullyQualifiedName` (formatted as `pe{HubID}_{name}`), which acts as the primary key for all subsequent data ingestions [cite: 19].

### 5.2 Server-Side (HTTP) vs. Client-Side (Tracking Code)
Occurrences can be sent via the client-side JavaScript Tracking Code or server-side via the HTTP API [cite: 19]. 
*   **Server-Side HTTP API:** Requires a `POST` request to `/events/v3/send`. The payload must contain the `eventName` (`fullyQualifiedName`) and an `objectId` or `email` to associate the event with a specific CRM record [cite: 19]. If a contact does not exist, providing an email identifier will auto-create the contact [cite: 18]. 
*   **Rate Limits and Data Sovereignty:** The server-side API enforce a hard rate limit of 1,250 requests per second [cite: 18]. Furthermore, for EU portals, requests must be dispatched strictly to the `track-eu1.hubspot.com` endpoint [cite: 18].

### 5.3 TypeScript Implementation: Custom Events

```typescript
import axios from 'axios';

interface EventDefinitionPayload {
  label: string;
  name?: string;
  primaryObjectMetadata: {
    primaryObjecType: 'CONTACT' | 'COMPANY' | 'DEAL' | 'TICKET';
  };
  // Max 50 properties
  properties: Array<{
    name: string;
    label: string;
    type: 'string' | 'number' | 'datetime' | 'enumeration';
    options?: Array<{ label: string; value: string }>;
  }>;
}

interface EventOccurrencePayload {
  eventName: string; // The fullyQualifiedName
  objectId?: string;
  email?: string;
  occurredAt?: string; // ISO 8601 string
  properties: Record<string, string | number>;
}

export class CustomEventsClient {
  constructor(
    private readonly accessToken: string,
    private readonly isEU: boolean = false
  ) {}

  /**
   * 1. Define the Event Schema (Max 50 properties)
   */
  public async defineEvent(payload: EventDefinitionPayload): Promise<any> {
    const url = 'https://api.hubapi.com/events/v3/event-definitions';
    const response = await axios.post(url, payload, {
      headers: { 'Authorization': `Bearer ${this.accessToken}` }
    });
    return response.data; // Contains fullyQualifiedName
  }

  /**
   * 2. Send Event Occurrence
   */
  public async sendOccurrence(payload: EventOccurrencePayload): Promise<void> {
    // EU portals strictly require the track-eu1 subdomain
    const baseUrl = this.isEU ? 'https://track-eu1.hubspot.com' : 'https://api.hubapi.com';
    const url = `${baseUrl}/events/v3/send`;

    await axios.post(url, payload, {
      headers: { 'Authorization': `Bearer ${this.accessToken}` }
    });
  }
}
```

***

## 6. Marketing Campaigns: Aggregation, Budgeting, and Attribution

The Campaigns API (`/marketing/v3/campaigns`) manages the aggregation of disparate marketing assets (emails, landing pages, custom events) under a unified attribution umbrella [cite: 23]. Campaigns are distinct from standard CRM objects; they do not behave natively like Deals or Contacts, requiring middleware solutions if integrating heavily with external ERPs or CRMs like Zoho [cite: 24].

### 6.1 Creating and Associating Campaigns
Campaign creation (`POST /marketing/v3/campaigns`) returns a UUID (`campaignGuid`) [cite: 23]. A major API update significantly expanded the asset types that can be associated with campaigns, bridging the gap between API capabilities and UI features. Assets such as `EMAIL`, `SEQUENCE`, `MEETING_EVENT`, `WEB_INTERACTIVE`, and `PODCAST_EPISODE` can now be read and manipulated [cite: 25]. 

### 6.2 Financial Tracking: Budget and Spend Management
Historically managed manually within the UI, HubSpot introduced dedicated public endpoints for financial tracking. Budgets can be modified via `POST /marketing/v3/campaigns/{campaignGuid}/budget` and specific spend line items via `POST /marketing/v3/campaigns/{campaignGuid}/spend/` [cite: 25, 26]. 

For Enterprise-tier customers, custom UTM property tracking (`hs_utm`) is fully accessible for precise revenue attribution, allowing data warehouses to sync ROI metrics dynamically [cite: 25].

### 6.3 TypeScript Implementation: Campaigns

```typescript
import axios from 'axios';

interface CampaignProperties {
  hs_name: string;
  hs_start_date?: string;
  hs_notes?: string;
  hs_utm?: string; // Requires specific tiers for full attribution tracking
}

interface BudgetItemPayload {
  amount: number;
  name: string;
  description?: string;
  displayOrder?: number;
}

export class CampaignsClient {
  private readonly baseUrl = 'https://api.hubapi.com/marketing/v3/campaigns';

  constructor(private readonly accessToken: string) {}

  public async createCampaign(properties: CampaignProperties): Promise<string> {
    const response = await axios.post(this.baseUrl, { properties }, {
      headers: { 'Authorization': `Bearer ${this.accessToken}` }
    });
    return response.data.campaignGuid;
  }

  public async addBudgetItem(campaignGuid: string, payload: BudgetItemPayload): Promise<any> {
    const url = `${this.baseUrl}/${campaignGuid}/budget`;
    const response = await axios.post(url, payload, {
      headers: { 'Authorization': `Bearer ${this.accessToken}` }
    });
    return response.data;
  }
}
```

***

## 7. Email Subscriptions: Consent Management and Compliance

Data privacy regulations (e.g., GDPR, CAN-SPAM, CCPA) necessitate strict governance over user communication consent [cite: 1, 27]. The HubSpot Subscription Preferences API provides endpoints to explicitly subscribe, unsubscribe, and verify the status of contact communication preferences.

### 7.1 Subscription Types and Legal Basis
A subscription type represents the legal classification for sending an email (e.g., "Weekly Newsletter", "Product Updates") [cite: 28]. Transactional emails operate independently of these preferences, as they are triggered by user actions (e.g., receipts) rather than marketing promotions [cite: 9, 28]. However, for marketing emails, checking the subscription status is paramount.

The v3 Subscribe endpoint (`POST /communication-preferences/v3/subscribe`) allows programmatic opting-in of an email address to a specific `subscriptionId` [cite: 27, 28]. Crucially, for portals with GDPR features enabled, developers must explicitly provide a `legalBasis` (e.g., `CONSENT_WITH_NOTICE`, `LEGITIMATE_INTEREST_CLIENT`) and a `legalBasisExplanation` string detailing how consent was captured [cite: 27, 29]. 

### 7.2 Migrating: v3 vs. v4 Considerations
While the v3 API is widely utilized, the v4 API endpoints introduce enhanced support for Business Units (Brands) and, notably, allow for the *resubscription* of contacts who had previously opted out (a restriction historically enforced rigidly by the v3 API) [cite: 1, 28]. Additionally, v4 requires specific OAuth scopes (`communication_preferences.read_write`) depending on the execution [cite: 1].

### 7.3 TypeScript Implementation: Consent Verification

```typescript
import axios from 'axios';

interface SubscribePayload {
  emailAddress: string;
  subscriptionId: string;
  legalBasis?: 'LEGITIMATE_INTEREST_PQL' | 'LEGITIMATE_INTEREST_CLIENT' | 'CONSENT_WITH_NOTICE';
  legalBasisExplanation?: string;
}

export class SubscriptionClient {
  private readonly baseUrl = 'https://api.hubapi.com/communication-preferences/v3';

  constructor(private readonly accessToken: string) {}

  /**
   * Subscribes a user to a specific email type with GDPR context.
   * Note: v3 cannot resubscribe users who manually opted out.
   */
  public async subscribeContact(payload: SubscribePayload): Promise<any> {
    const response = await axios.post(`${this.baseUrl}/subscribe`, payload, {
      headers: { 'Authorization': `Bearer ${this.accessToken}` }
    });
    return response.data;
  }

  /**
   * Validates if a user is eligible to receive marketing emails
   */
  public async getSubscriptionStatus(emailAddress: string): Promise<any> {
    const response = await axios.get(`${this.baseUrl}/status/email/${encodeURIComponent(emailAddress)}`, {
      headers: { 'Authorization': `Bearer ${this.accessToken}` }
    });
    return response.data;
  }
}
```

***

## 8. Architectural Decision Trees

To synthesize the technical requirements outlined above, developers should utilize the following decision frameworks when architecting HubSpot API workflows.

### Decision Tree 1: Email API Selection
*   **Condition 1:** Are you sending a generalized promotional email to a large list?
    *   *Yes* $\rightarrow$ Use UI or workflows. **Stop.** (Standard API limits programmatic mass sending).
*   **Condition 2:** Are you creating a draft/template for marketing to use later?
    *   *Yes* $\rightarrow$ Use **Marketing Emails v3 API** (`POST /marketing/v3/emails`). Ensure payload is nested JSON [cite: 3].
*   **Condition 3:** Are you triggering an email based on an external system event (e.g., purchase receipt)?
    *   *Yes* $\rightarrow$ Use **Transactional Single Send API** (`POST /marketing/v3/transactional/single-email/send`) [cite: 8].
    *   *Condition 3a:* Do you need to prevent HubSpot from automatically creating CRM contacts for unknown emails?
        *   *Yes* $\rightarrow$ Abandon REST API. Use **HubSpot SMTP API** [cite: 7].

### Decision Tree 2: Form Submission Architecture
*   **Condition 1:** Is your HubSpot portal hosted in the EU?
    *   *Yes* $\rightarrow$ Base URL must be `api-eu1.hsforms.com` [cite: 15].
    *   *No* $\rightarrow$ Base URL is `api.hsforms.com` [cite: 13].
*   **Condition 2:** Does the form contain a file attachment?
    *   *Yes* $\rightarrow$ First call Files API $\rightarrow$ inject URL into string field $\rightarrow$ Call Forms API [cite: 11, 17].
*   **Condition 3:** Is this a client-side or server-side submission?
    *   *Client-Side* $\rightarrow$ Extract `document.cookie` for `hubspotutk` [cite: 16].
    *   *Server-Side* $\rightarrow$ Ensure the front-end passed the cookie token to the backend, then inject into `context.hutk` [cite: 12].

***

## 9. Anti-Rationalization Rules

System integrations often degrade due to developers rationalizing workarounds that conflict with intended architectural constraints. Adhere strictly to the following rules:

1.  **Do Not Mix Marketing and Transactional Email APIs.**
    *   *Rule:* Never attempt to use `/marketing/v3/emails` to dispatch an individual alert or receipt. Conversely, never use the Transactional Single Send API for mass promotional blasts. Doing so will severely impact deliverability scores and likely violate the Terms of Service.
2.  **Do Not Send Marketing Emails Without Verifying Subscription Status.**
    *   *Rule:* If you bypass the HubSpot UI to dispatch emails via your own ESP but sync back to HubSpot, or if utilizing legacy tools, always query `/communication-preferences/v3/status` first. Ignorance of an opt-out is not a valid defense against CAN-SPAM or GDPR violations.
3.  **Do Not Submit Forms Without the `context.hutk` Payload.**
    *   *Rule:* Submitting form data without parsing and including the `hubspotutk` cookie actively damages the CRM's attribution modeling. Without it, web analytics history remains permanently detached from the newly created contact record [cite: 12, 30].
4.  **Do Not Create Custom Events Without Prior Schema Definition.**
    *   *Rule:* Unlike legacy APIs that allowed dynamic property creation on-the-fly, the Custom Behavioral Events API enforces a rigid schema. You cannot send a `POST /events/v3/send` request containing properties that were not explicitly predefined via the `events/v3/event-definitions` endpoint [cite: 20, 21]. All dynamic property inputs will be rejected by validation routines [cite: 20].

## Conclusion
Integrating with the HubSpot Marketing API requires a nuanced understanding of CRM boundaries, compliance protocols, and asynchronous networking logic. By adhering to the TypeScript frameworks, structural schemas, and anti-rationalization rules detailed in this reference, engineering teams can build highly resilient, compliant, and deeply integrated marketing pipelines.

**Sources:**
1. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEhbhC0XIp0JqmdX-bFjLrI0CDXQ1ZfwnI8cBMXjz7a-br48vL1DDPQw829JQaDIWHMyXSAvNXHz3y5Bk76m6RAMDmep9Ntpgkm8G6n-aZ5zk8RAUvHpDNyjsd55hp3pIUwCH_J0KJF6ALE5UVQKUnuLmiihmnAHCYJ_9LlklxGOLdKxprrjBMAvN7MW8qTsnC3U60r0QKGnw==)
2. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGmaC_uivuVUkMQNMNsBxL-zFYRaVJzy9NjRigmM_K19LYh9sKbn9shXcLgjPevg5NGEfrux557rabhWnXFT-SsEIPchJd9MzruPWLkJLML2Gpal3lp_vqrKKUI-sHz2uDjC_dxXX8WIzWSeCqivyapgN4WzdnA4z3cGR59ayborC2WXAL5T_08eTHBY1riVw==)
3. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQF30KwTTCOIzKctE5jkUEMXu1Gs79Xz-VW-_IZWKhCf8rP8rfjWS_3dEIqqhJAfYJieBXrY8rOgtzV4f8X7TfVhwdwFYRA9fqPb3hMNSxtJO3pZCIotVDiWwCQlS8AyDdHK3gLLA8FzGRJzyHTiIEMq_bRuFxjCCPoKNiArUWbSmtXW7Wx_E_TaZ2_TBjYAxyg6-GrPVpMU5juh8H_DVGAROuW5S8ffWuqjJcK4CJlf)
4. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGOdsFr445UrujMivVD7uWDnW_n_rN-DA-EAmGBHtyRbobpScpo8DesCUGAnitY1DUN4BGvfUd6_xDCUV3T6QwAlf00pVlI5apofdlcf4DiTrJquEo3-ksqX_MSLAWgUS1YOu6J5EZATLLx7KpDO1HiKm_XGt9fMrXhF90zg49ZpUZGxoC6mSndXIk3sbE=)
5. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFyJhvr9sc3h4ma7WnM0dgsOaw1lI9wcfXkr0MrT2-wn5scNo2756Szpb2yOycyzKxZuY4HVWkMO-CUEqf3pf1KmeTugFamUBiWPeg9g1nWUjzPfzMBD3kDgiDAsf70z3KPRNGkvHGfpvJXQXvWBD2JjFnsA15iNkBp5TP8103routlV_b1SAFv658BxowevfFTZrUGYB7eA9ERriqKEwOh_3N_gjs9TTFKywSSVYeIo78=)
6. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHTkeFP6K4KIeeQlZdrpN833DnU54a-6rvLUgPUwG8xVrrUtyiOEF83es3mKb6GA4Z1XB6f2IRndfdzB9bjNlL7_bHF0LzwrBVI1kJzi93KbCfwKodSsIp6G4MvMFK72mJJF8hOzYVHyavsTeK8CfcHlr1_lCnukYgjXxA=)
7. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFgSXgCHG1CwcUSjXovSQAosr1VNjHRmth6xaY7uRcyQS5mls3p-I4e8ulxffJxHFkOA7vFShZPcyIY5st9BbEubvDyjCkw2YW6YskXOERWvkVEe7yioSH396X3EWWe4gEm-sU-JljRcAftcu2O7JVrFsV5qYhYAGG2VFZB9WTbqdu4n7KGaBKdiXUK8pt0KLNaSyo=)
8. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGftn9psKlheRlS9CLfvwufJ1HI4CFa2cbGlO38dG4ORIyr9JYudqOGThZ5WEin2_eEXqAqQ1W3MPqnS2SpaXOoFYnV5UiHvPMF6n-9_R0DgbXNfrVt-suLzp2CGWgQBTZ3s6AntYhqBev55FIVPdgOsb5PPRiKRhEBNRrxpSFrrr4gTDuOxkG73tHHb6NHessz_MxrW1z74HpQSWxnbHS1bo8iWg-9XoMddik4boo2yBXvFQNfZcCSjQW1cpmjf-XUeh76Li-b6s1Yj3iS)
9. [postman.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHY2qAWMDu5KuvoDpopQre9ogkwRXMdlm3GLiqPt-anWD_VvWokS45GqPJbTDr3tWFAe3htGwWXF-H013LpyPclS7EJZpsRJEmVCiRySMb4Btg1l6lisUDYVtgZkWDaQNN4xFPXaqCLwBRE5NRYosZ5V_QxerU1xF3EUh6GQoPyXkShOuYhaQQ9fyE0jVpmHcXAtpMucYnANi-oEJtNofhXF9M=)
10. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEe8x8LXboFVxNO6Bs6C_V02znciXjiRDjreA-oK8ZuEfQAQbzsLSBGtrsFtHcpn8Y8pLgPC-vdVHfYkEyOU0Q690y_8FiKnbmXowyQTbb2zEvAUv5jncb3FCVCXifmGf5BeDg9CnS6fsyySka2Ff_GdTIvASZKM1g5ZO_kKkvlrjtrBCBJ6Tg7Z872JWqF)
11. [mpiresolutions.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQG-cr750Memt18x_ciECEur_vrg2ttYGflwRfD-i0XbfQ9IJaVscoVeRvRT8wtKJnG3oQIGSYx4sqhFmic-rtyI0wRQdg4zjcq0BoxzTEHvRSooblQ5wy5Cfa9seqW9kJjwQrmCEjMT)
12. [github.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQF-WrsIy0beCk9WxjrrcdYmjAzoft5RbIfpB-bND-Ls3wPjJxmjNqlqHuFKMDfZbiCOAh-sBdhpkk---m9cU5USFutnxiuaprUhR5DxyjvI9xyRBR_kVrdhlGaBa38In8jD7PHXl-rxc2f1HMiBD2dX2QRa915xDh_1Ikdr)
13. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEHgNB_vnvCf3t2wIpb4Et4fqXAyHlbYqa81edxjvGSIoKpW99_SE3Etji3dFLIfIACtYDLmmNQ_jeyn88wAtBzbC2MUJlCZfzZp29galK8K18weO6z-_BA0qJre4gPf8DrcpxJXwInJg5oE3RpVX47esgF9I5jUMP1iz7qu1RO-ptRY5MbcTqXwJ1BwwF0WFDpOWZXrZMKicy6dtgwnRc01jI1kA==)
14. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQH6PeuGCAzYnz-C3JGkxAx1R-6CucyakXLYmaQtSyMtNY71SDkaJKUVsl_5jvAbeEFvv0mn6pk60GxbZqtdvDSmYqbjeGXapSroCxiJvp9SIFytEMjjQHnMfaO5_LoRenj75RDEGBns4fNGM22alrYpgEkJQnXywFLcCNrMX0bY7SeZMp9tFDaT0rYR_bc=)
15. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFRAVAIfh4rk5AHL97CwuKnCpJdyt1SBNLFOgMY2vIyqcHFVOfiBKewuHDMqXaLNg5TdKScYg4V_I26_xyzsHx3uuJL3tfw9M8y3xRJvhyz_38x7yjoUrXYi87SxS-IDSEcjHJl2KiMzfhqZKonYtbmksMomnukLafXcdMDRa3mHLUpFQ==)
16. [robertpainslie.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFW1oO9vhU76ZJC7VMhyxsDtJ7PcgBLRB1Tugi5n05FpJXTe0uLUKO343Otmg1BFR1FqJu7j6bE5_uzPbVtFUVhCJr2HTyKvf4uWokcLOqDmIUfJsZRm1VFu3FdDCMPRDxlWbVMEY7pI0wZTevtEHOkDhURpFMlgkCwhe4-W7BHVGnnCPoErvEFU-KvE9txObVUFf3Zte0ecFXUvku8QMI5ehkv1k8tH-g=)
17. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEqkTTlHBarFXXatH19xYSm1PEFhsJPsgAYQ1SY2B2QyF224LCPHgvIqtVIezafpaTfv0YrRSBq2dboAqEl4JBrM0CnsJO4z4mq3arcp6G63inDCTV-2p5akSeQdqQrirseOGeOWPXKWgNRsjYfy1jOM8B2-Hjz99f3VExHfSPj1oXGNBSFgZYXN26BIrE3fa7xsL1jpyvQqfE6Jy9-)
18. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHU5_G1hTxg-Ne3yVfJa2hLEejUkK6jRjtlk4zbGz6jqVqRr4lWpnXZ4mmIjiTbNzD28Zy7STdTMM6eyB_7ePTRl26mEIejoLwgUhqmeRKHfNRHaZjd35cWMxMfdYoOZBnUqfMN2ZIvUDQwztw_-eOwsLm51o1t0Oh1XTNOcU7fSCywgz5DBkaHdOXCtE77NiGkSRd_6ieNiJ8=)
19. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHnQP3ISV8Xdo6pWhUXPj3g55v1zja8h6EOsmjpRFtAXuo7eBVzadCCyrr0NH-eRcXsYZfkUVk2af2ZARukzSxzT4kjSunsYZ5gONqyBG_uxGCSV4AfWUCCLSA7DCKCPndGIya4F44WYJoBEGLlkNmjpyxX3e7hU7LsRsAhJ8XvQJsCzVVDAi-PmZ0tbMzj)
20. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQF0ZBFCDuQo-GB1fqu1XKdK3656diexlmZlGG29VzQNdN7-bzDWqVLBP8KeOalYBcKRoNV5DL8wlYo9UQ1L_YnoBKUeNoMI8nQyk-uDeXARbvWfuJSAFopKXbVhqsAsk-pE2lc29oBjYNpQWjT65OSEX3sLk2Dp57hWLh2h7L6GHaUjm43azEb_XvBc2ng9vUFu1QOtm_CljZq8WBtmeT8E)
21. [postman.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHlaaYLx6BKCpIqxvq5A02k_QKCGF1AKOQd7hQl7TT0XKi-oR6zf4EUoWPP_Rsko-CXDsb65ySxN_u9_iT2labKq6BM-jOUpyBoEQWlbxV27UB0QBSx9wde5luzND8DwKhQQRcnQ5anoSOhkZ4q7ZF4SZ5Qmd_C_WUYqeLjdMbjtoE7fHxoAx3wpkzkfdNHZW4jyWPAa3_L9EcxKntbpg==)
22. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQER4wUBIcEacw71QMW4GqCXMKsqbPu7FhJcs5CGp2HwCQWbB0CqGfH-MAGRx7cvxq6Gczff_8aUOQFU2HhSSb1IY9anZOh2o7q7P8y9ytDZY1d0I0UqSzrowU_H_0RJ5XJAizHXP0Mk3s2PdZFomftMYFcTbLrvnpOqcti7MCsJFy-PPr-lcMHJISk6I6fVeGs=)
23. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHG7F8aU61M9zUoXgaLXV6qQemGu189w1ekVlL36-LRtQV2ovNMXLZ2wGTZIQ5rhvqW4KiBrKDlWUcySDxh-A-zWgpH8rA9WN9Vj-mWN_7XwcaqJyY1WNBOiFVg_1hPd-EwARgoOU2HQryzcrCxmNrJcRo4ind-bvPTutSQGxZGlTx5KfOx7KxD)
24. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHjJ61xwuYhRnDYgk0mQVvFX88aZmpCVP9lSpkcf9qyeaDjvbp03ro50RBRlHANtOZSeWWg-f0hO4tWjpFLC0uKYyCQSs_bqPvUp_qgVXhFtT_0OjtpBj0QcZ7z98tKeZ_VcgbX8UbQhQgX0p64TGBaEfSaCMWTQg4Ii3_tzteNdkzkxpqK8NOxAykit2JcQEypb1xEEFmSkXno1pAS00emiJ6OZYrCKGgGnGR191aBv6qWhw==)
25. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGr4XxL4MbAdf64hH9Kx7Q7OHABMJ6hg3rEFCSbL_1IV6vkmivVs5Ni33rrB1eY__F03EpAO1cDvSpruz_dk6-eb6mMoArs86odChyWk6rSqTTmdNflcdCl_Q1KQbPu1COmiMtYUnTN_GM8o6M8J7dHtjumd8cZEQ==)
26. [arcade.dev](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFyRxYLrQBGfKkWFxtgg2bUNN02BE6t2g0BRwQPg5Ps6z2NveQseULoUogHOsGJF4w_Jcz6bxohjL9R-Wol-uBvzEFQ_YnbP73kS2gI9dPePFGoDCOXqIoBDqf9wAyaZAtUCxvFvnkm9f118PwLUSZUJUVmI_7TH3aynO38dTLSZe47sw==)
27. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFXfflGsr6OmAQqRNZbQu7kUocR2irnim6UjwwvdFlDR-mWSkjVrARYgiJbn5lmuTVFi0LlV6RpypA6iGJ24ui1pqY99kM1eRBqtTpDOiGpXf9QzG6cSzEeT30fbz9Ou5r6N2UfjjDmh7kEfyZMWgDUu27WRrDKS3RgJ6JAWHsrQxdBMULofJ8LGGQ-XWjw4ow1d08qYwA3zV0wQ6DsTGYL8fe3bdTKUjXN2Fl8j2kbOcstQZJpFnKYRxpM012u9pA0q17T9RE=)
28. [hubspot.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHipRPGjAdkMcDAO0MXb6lLRxc5AfA8UzU4I6MM9Nfrk8YRP1ZZqwUAOcrk_AK6vzLz2I6rbcZScfzc-58BFo-UnzKljKgwovHonlTDFHnwMP_VqEMsI_cIZxvjvEkdINjdcQYSnbUgExcjZvCy2tkPMlxWK05ZWIl6n14O4GIM6Jg_9Sc5zKSecxOVcdsQqus6zmPKgyXYDg==)
29. [hubspot.fr](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFYZ01EkN-y9nnqMfTag7aJeCFzHlssjouv7y45b7gpRLowcYPp-4Ud0bm5-foO-oWC3JF1al8nmzm9CI1VyBIN1Og_XvyBWpSwQUFkYV4IQ00S4ECnruHVazNP1Q8iBFAjhNbRQcoawTXFNtN6WaD9fbXs7OlTtecUjpFa0sphoVCbye3seRDrtCfuNCPOEohNtxz3ByIgWPhINhQ=)
30. [insidea.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGaq2A6kYryrGXSpvdYJAJC8oB9Xvi24dGPNfV9Z6Jr6hIurUaDGFrdOlvuU_selX0J7EsahLCl0Uv-AHcOZR5iBUUqCW1OnWz23oNC-5oDKbVorViwb4WYK8tzLKF-mneGJF9l0OiFyqItJ9csgXU4ZdtQBroLrlFY1CKhaJ7oMGSKIu81uOTh)
