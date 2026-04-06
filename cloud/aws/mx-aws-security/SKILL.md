---
name: mx-aws-security
description: Secrets Manager rotation, KMS envelope encryption/key hierarchy/rotation, GuardDuty threat detection/EKS runtime/S3 malware/findings automation, Security Hub aggregation/ASFF/remediation, Macie PII detection, and AI-generated anti-patterns
---

# AWS Security — KMS, GuardDuty, Security Hub for AI Coding Agents

**Load this skill when configuring encryption, setting up threat detection, managing secrets, or implementing security monitoring.**

## When to also load
- `mx-aws-iam` — IAM policies, SCPs, permission boundaries
- `mx-aws-observability` — CloudTrail, CloudWatch alarms for security events
- `mx-aws-networking` — Security groups, NACLs, VPC Flow Logs
- `mx-aws-dns` — DNS Firewall for threat protection

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: Secrets Manager Over Hardcoded Credentials
| BAD | GOOD |
|-----|------|
| Passwords in env vars, config files, or code | Secrets Manager with automatic rotation |

Enable automatic rotation. Cache secrets in application with TTL refresh. Never log secrets.

### Pattern 2: KMS CMK Over AWS-Managed Keys
| BAD | GOOD |
|-----|------|
| AWS-managed keys (no audit trail of who decrypted) | Customer-managed CMK (full CloudTrail audit) |

AWS-managed keys work but provide no visibility into who accessed what. CMKs give full audit trail + cross-account sharing + custom key policies.

### Pattern 3: Enable GuardDuty Everywhere
- Centralized management: delegated admin account in Organizations
- Enable all protection plans: EKS, S3, Malware, Lambda, RDS
- Custom threat intelligence: ingest known-bad IP/domain lists
- **Free 30-day trial, then pay-per-analysis** — the cost is trivial vs the risk

### Pattern 4: Security Hub as Single Pane
Enable Security Hub + all integrations. Aggregated view of GuardDuty + Config + Inspector + Macie findings in one console. ASFF normalized format.

### Pattern 5: Block Public Access on Everything
S3 Block Public Access at account level. No public AMIs. No 0.0.0.0/0 on security groups. Enforce via SCPs.

---

## Level 2: KMS & GuardDuty Deep (Intermediate)

### KMS Architecture

| Concept | Purpose |
|---------|---------|
| **Envelope encryption** | DEK encrypts data, CMK encrypts DEK. CMK never leaves HSMs |
| **Key hierarchy** | Separate CMKs per app/environment/classification |
| **Auto-rotation** | Annually for customer-managed keys. Retains all previous material |
| **Key policies** | Least privilege. Separate admin (manage key) from user (use key) |

**Rotation is NOT re-encryption.** If a key is compromised, you must explicitly re-encrypt all data keys. Rotation just adds new key material for future encryptions.

### GuardDuty Protection Plans

| Protection | What It Detects |
|------------|----------------|
| **Foundational** | CloudTrail + VPC Flow + DNS anomalies |
| **EKS Audit Log** | Suspicious K8s API calls |
| **EKS Runtime** | Reverse shells, privilege escalation, crypto mining, file tampering |
| **S3 Protection** | Reconnaissance + exfiltration patterns |
| **Malware for S3** | Auto-scan uploads. Tags with `GuardDutyMalwareScanStatus` |
| **Malware for EC2** | Scans EBS volumes attached to suspicious instances |
| **Lambda** | Suspicious Lambda function invocations |
| **RDS** | Anomalous login attempts to databases |

### GuardDuty S3 Malware (July 2024)
- Auto-scan objects on upload to selected buckets
- Tags objects: `NO_THREATS_FOUND` or `THREATS_FOUND`
- Use TBAC (Tag-Based Access Control) to isolate malicious files
- On-demand scanning via `SendObjectMalwareScan` API for existing objects
- EventBridge + Lambda for automated quarantine workflows
- **Target untrusted upload buckets** — not your entire S3 estate (cost control)

### EKS Runtime Monitoring
- Automated DaemonSet/managed add-on deployment. Monitor agent health
- Detects runtime threats: reverse shells, crypto mining, privilege escalation
- **NOT supported on Fargate-for-EKS** — EC2-backed EKS only
- Combine with K8s network policies for preventive controls (GuardDuty is detective)

---

## Level 3: Security Hub Automation & Macie (Advanced)

### Security Hub Automation

| Component | Purpose |
|-----------|---------|
| **Custom actions** | Trigger Lambda remediation from console |
| **Automation rules** | Auto-update findings (enrich, prioritize, suppress) |
| **EventBridge** | Every finding → EventBridge for custom routing |
| **Cross-account** | Aggregation across all linked accounts |
| **Custom insights** | Aggregated views combining findings by trend/resource |

Workflow: GuardDuty finding → Security Hub (ASFF) → EventBridge → Lambda (auto-remediate) + SNS (notify)

### Macie — Sensitive Data Discovery
- ML-based PII detection in S3: credit cards, SSNs, email addresses, names
- Identifies unencrypted buckets, public access, sensitive data without classification
- Enable across all accounts via Organizations. Findings → Security Hub
- Macie needs KMS key policy permission to scan encrypted objects

### IAM Access Analyzer
- Detects resources shared with external entities (S3, IAM, KMS, Lambda, SQS)
- **Enable in EVERY region** — resources can exist in any region
- EventBridge integration: auto-scan on policy changes. Lambda for automated response
- Unused permissions analysis: identify granted-but-never-used permissions (90-day window)

---

## Performance: Make It Fast

### Security at Speed
1. **Security Hub automation rules** — auto-suppress known-benign findings (reduce noise)
2. **EventBridge + Lambda** — automated remediation in seconds, not hours
3. **Macie sampling** — scan a sample of objects, not every object in every bucket
4. **GuardDuty suppression rules** — filter expected findings (e.g., known scanner IPs)
5. **KMS key caching** — AWS SDK caches data keys automatically. Don't call KMS per request

### Incident Response Speed
- Pre-built response plans in Incident Manager (existing customers) or OpsCenter
- Automated runbooks for common findings (isolate instance, rotate credentials, block IP)
- Pre-authorized IAM roles for incident response (no approval delays during incidents)

---

## Observability: Know It's Working

### What to Monitor

| Signal | Tool | What to Watch |
|--------|------|--------------|
| Active threats | GuardDuty findings | High/Critical severity. Auto-alert immediately |
| Compliance | Security Hub score | Score trending down = configuration drift |
| Sensitive data | Macie findings | New unencrypted PII-containing buckets |
| Key usage | KMS CloudTrail events | Unusual decryption patterns, denied key access |
| External access | IAM Access Analyzer | New external access findings |

- **GuardDuty findings**: severity-based routing. HIGH/CRITICAL → PagerDuty/immediate. MEDIUM → Slack/daily review
- **Security Hub compliance score**: track weekly. Score below 80% = dedicated remediation sprint
- **Tune findings regularly** — alert fatigue kills security programs. Suppress noise, investigate anomalies

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Secrets in Code or Environment Variables
**You will be tempted to:** Store API keys, passwords, or tokens in environment variables "temporarily"
**Why that fails:** Env vars are visible in console, API responses, CloudFormation templates, and process listings. "Temporary" becomes permanent
**The right way:** Secrets Manager with automatic rotation. Fetch at startup, cache with TTL

### Rule 2: No AWS-Managed Keys for Regulated Data
**You will be tempted to:** Use AWS-managed keys (`aws/s3`, `aws/ebs`) because they're simpler
**Why that fails:** No audit trail of who decrypted what. No cross-account sharing. No custom key policy. Can't meet compliance requirements that demand key management control
**The right way:** Customer-managed CMKs with per-application key hierarchy. Auto-rotation enabled

### Rule 3: No GuardDuty Without Automated Response
**You will be tempted to:** Enable GuardDuty and check the console "regularly"
**Why that fails:** "Regularly" means never during incidents, weekends, or vacations. Findings pile up. Critical threats go unnoticed for days
**The right way:** EventBridge → Lambda for auto-remediation (isolate, rotate, block). SNS for immediate notification. Security Hub for aggregation

### Rule 4: No Malware Scanning on All Buckets
**You will be tempted to:** Enable GuardDuty Malware Protection for S3 on every bucket
**Why that fails:** Every scan costs money. Scanning internal data buckets that only receive trusted input wastes budget
**The right way:** Enable on untrusted upload buckets (user uploads, external integrations, SFTP). Skip internal/system buckets

### Rule 5: No Security Without Centralized Logging
**You will be tempted to:** Rely on per-account security tools without centralization
**Why that fails:** An attacker who compromises one account can disable that account's monitoring. Without centralized logging in a separate account, you lose visibility
**The right way:** Organization trail to dedicated logging account. Security Hub aggregation. GuardDuty delegated admin. All in a hardened security account
