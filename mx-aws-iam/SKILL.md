---
name: mx-aws-iam
description: IAM roles, policies, permission boundaries, ABAC tag-based access, SCPs, Organizations, Identity Center (SSO), cross-account access, MFA enforcement, and AI-generated wildcard anti-patterns
---

# AWS IAM — Identity & Access Management for AI Coding Agents

**Load this skill when creating IAM roles/policies, configuring Organizations/SCPs, setting up Identity Center, or implementing cross-account access.**

## When to also load
- `mx-aws-security` — KMS key policies, Secrets Manager, GuardDuty IAM findings
- `mx-aws-lambda` — execution roles, resource policies
- `mx-aws-iac` — CDK/CloudFormation IAM role generation
- `mx-aws-operations` — SSM automation assume roles, Config rules for IAM compliance

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: Roles Over Users — Always
| BAD | GOOD |
|-----|------|
| IAM users with long-lived access keys | IAM roles with temporary credentials (STS) |

Roles provide automatic credential rotation. Users require manual key rotation and are the #1 source of credential leaks.

### Pattern 2: Least Privilege Starting Point
| BAD | GOOD |
|-----|------|
| `"Action": "*", "Resource": "*"` | Start with AWS managed policy, then scope down with Access Analyzer |

Use **IAM Access Analyzer** to generate least-privilege policies from CloudTrail activity. Never start with `*` and "plan to tighten later" — you won't.

### Pattern 3: MFA Mandatory for All Human Users
```json
{
  "Condition": {
    "BoolIfExists": { "aws:MultiFactorAuthPresent": "false" }
  },
  "Effect": "Deny",
  "Action": "*",
  "Resource": "*"
}
```
Apply via SCP at the Organization root. Support FIDO2, TOTP, push notifications.

### Pattern 4: Groups for Identity Center Assignments
| BAD | GOOD |
|-----|------|
| Assign permission sets to individual users | Assign permission sets to **groups** mapped to job functions |

Individual assignments don't scale and create audit nightmares. Groups + SCIM auto-sync from IdP (Azure AD, Okta, OneLogin).

### Pattern 5: Block Public Access by Default
SCP to deny any action that would make S3 buckets public, create public AMIs, or expose resources to `0.0.0.0/0`. Apply at Organization root.

---

## Level 2: ABAC & Permission Boundaries (Intermediate)

### ABAC (Attribute-Based Access Control)

| Aspect | RBAC (Traditional) | ABAC (Tag-Based) |
|--------|--------------------|--------------------|
| Scale | New role per team/project | Single policy, scale with tags |
| Maintenance | Update roles for every new resource | Add tags to new resources, policy unchanged |
| Cross-account | Complex trust policies per account | `aws:PrincipalOrgID` + tag matching |

**Implementation:**
```json
{
  "Condition": {
    "StringEquals": {
      "aws:ResourceTag/Department": "${aws:PrincipalTag/Department}"
    }
  }
}
```

**Critical:** Protect ABAC tags with SCPs — prevent unauthorized modification of access-control tags. Standardize tag keys: `Department`, `Environment`, `Project`, `CostCenter` (case-sensitive).

### Permission Boundaries
- **Purpose:** Cap the maximum permissions a role can have — delegates role creation safely
- Apply to roles that **developers create**, not to developers themselves
- Prevents privilege escalation: dev creates role → boundary limits what that role can do
- Combine with identity policies + SCPs for defense-in-depth

### Cross-Account Access
| Pattern | Use Case |
|---------|----------|
| `sts:AssumeRole` with tight scope | Service-to-service cross-account |
| `ExternalId` in trust policy | Third-party access (confused deputy prevention) |
| `aws:PrincipalOrgID` | Trust all accounts in Organization (not individual account IDs) |
| Tag cross-account roles | ABAC integration across account boundaries |

Short session durations (1hr) for sensitive operations. Never use long-lived credentials for cross-account.

---

## Level 3: SCPs & Identity Center (Advanced)

### SCP Strategy: Deny-List
Start with `FullAWSAccess` (default) + explicit Deny SCPs. This is safer than allow-list (which blocks new services).

### Critical SCPs Every Organization Needs

| SCP | What It Denies |
|-----|---------------|
| Org integrity | Leaving the organization |
| Security baseline | Disabling CloudTrail, Config, GuardDuty |
| IAM guardrails | Creating IAM admin roles outside approved patterns |
| Region restriction | API calls in unapproved regions |
| Tag enforcement | Creating resources without required tags |
| Public exposure | Public S3, public AMIs, 0.0.0.0/0 SGs |

Apply at highest possible OU level. Maintain a **break-glass account** exempt from restrictive SCPs.

### Identity Center Deep
- **Permission sets:** reusable IAM policy collections. Assign to groups in specific accounts
- **Session duration:** configurable 1-12hr. Shorter for sensitive operations
- **SCIM provisioning:** auto-sync users/groups from external IdP. No manual management
- **JIT (Just-In-Time) access:** Step Functions approval workflow for temporary elevated access
- **SAML attributes → session tags:** pass IdP attributes for ABAC in AWS

---

## Performance: Make It Fast

### Policy Evaluation Speed
1. **Fewer, broader statements** evaluate faster than many narrow statements
2. **Use `aws:PrincipalOrgID`** instead of listing 50 account IDs — single condition vs 50
3. **ABAC over RBAC** — one policy scales to thousands of resources without modification
4. **Managed policies** over inline policies — AWS caches managed policies more efficiently
5. **Permission boundaries** evaluated in parallel with identity policies — no sequential overhead

### STS Token Optimization
- Default session duration where appropriate (avoid unnecessary `DurationSeconds` overrides)
- Cache STS credentials — don't call `AssumeRole` per request
- Use **Identity Center** for human access (handles token lifecycle automatically)

---

## Observability: Know It's Working

### What to Monitor

| Signal | Tool | What to Watch |
|--------|------|--------------|
| Auth failures | CloudTrail `ConsoleLogin` + `AssumeRole` | Failed attempts, unusual source IPs |
| Unused permissions | IAM Access Analyzer | Permissions granted but never used (90-day window) |
| Policy changes | CloudTrail + EventBridge | Any `Put*Policy`, `Attach*`, `Create*Role` events |
| Credential age | IAM Credential Report | Access keys >90 days old, unused keys |
| SCP violations | CloudTrail | `AccessDenied` from SCPs (check `errorCode`) |

- **IAM Access Analyzer:** enable in every region. Identifies external access + unused permissions
- **Credential Report:** generate weekly. Alert on keys >90 days, no MFA, unused accounts
- **EventBridge rules** on IAM changes → SNS → security team notification
- CloudTrail: log all management events. Include global service events (IAM, STS in us-east-1)

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Wildcard Actions or Resources
**You will be tempted to:** Use `"Action": "s3:*"` or `"Resource": "*"` because it's faster
**Why that fails:** Overly permissive policies are the #1 cloud security vulnerability. One compromised role with `*` = full account takeover
**The right way:** Specific actions (`s3:GetObject`, `s3:PutObject`) on specific resources (`arn:aws:s3:::my-bucket/*`)

### Rule 2: No Long-Lived Access Keys
**You will be tempted to:** Create IAM user access keys for CI/CD, scripts, or local dev
**Why that fails:** Keys don't expire, get committed to git, shared in Slack, left in ~/.aws/credentials. Credential leaks are the #1 cause of cloud breaches
**The right way:** OIDC for CI/CD (GitHub Actions, GitLab). IAM roles for EC2/ECS/Lambda. Identity Center for humans

### Rule 3: No Individual Permission Set Assignments
**You will be tempted to:** Assign permission sets directly to users because "it's just one person"
**Why that fails:** Individual assignments create audit nightmares, don't survive employee transitions, and bypass SCIM sync
**The right way:** Groups mapped to job functions. Assign permission sets to groups. SCIM auto-syncs from IdP

### Rule 4: No SCPs Without Break-Glass
**You will be tempted to:** Apply restrictive SCPs globally with no escape hatch
**Why that fails:** If SCPs lock out security tooling or break automation, you need a way to recover without waiting for AWS support
**The right way:** Dedicated break-glass account in separate OU, exempt from restrictive SCPs. Monitored, alarmed, rarely used

### Rule 5: No Trust Policies with Account IDs
**You will be tempted to:** List individual account IDs in role trust policies
**Why that fails:** Every new account requires trust policy updates across all roles. Doesn't scale. Easy to forget
**The right way:** `aws:PrincipalOrgID` condition trusts all accounts in your Organization. Combine with ABAC tags for fine-grained control
