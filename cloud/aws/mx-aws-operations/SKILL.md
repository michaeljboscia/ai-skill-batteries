---
name: mx-aws-operations
description: Systems Manager automation runbooks, Session Manager SSH-less access, Patch Manager, AWS Config compliance rules, Inspector vulnerability scanning, OpsCenter incident management, Quick Setup, Change Calendar, and AI-generated anti-patterns
---

# AWS Operations — Systems Manager & Config for AI Coding Agents

**Load this skill when automating operational tasks, patching instances, managing configuration compliance, or responding to incidents.**

## When to also load
- `mx-aws-compute` — EC2 instance management, SSM Agent
- `mx-aws-security` — Inspector findings, Config rules for security compliance
- `mx-aws-iam` — SSM automation assume roles, least privilege
- `mx-aws-observability` — CloudWatch alarms triggering automation

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: Session Manager Over SSH
| BAD | GOOD |
|-----|------|
| SSH with key pairs, bastion hosts, port 22 open | Session Manager: SSH-less, IAM auth, audit logged, no open ports |

Session Manager requires SSM Agent (pre-installed on Amazon Linux, Windows). No bastion host, no key management, full audit trail in CloudWatch/S3.

### Pattern 2: Patch Manager for Automated Security Updates
| BAD | GOOD |
|-----|------|
| Manual patching or no patching | Patch Manager: scheduled maintenance windows, compliance tracking |

Define patch baselines per OS. Schedule maintenance windows. Track compliance. Auto-remediate non-compliant instances.

### Pattern 3: AWS Config for Continuous Compliance
| BAD | GOOD |
|-----|------|
| Manual compliance audits | Config rules: continuous evaluation, auto-remediation |

Config records all resource configuration changes. Rules evaluate compliance (e.g., `ec2-ebs-encryption-by-default`). Non-compliant → auto-remediate via Lambda/SSM Automation.

### Pattern 4: Quick Setup for Multi-Account Baseline
Use Quick Setup to configure SSM across all accounts + regions with recommended best practices. One-time setup, consistent standards.

### Pattern 5: SSM Agent Auto-Update
| BAD | GOOD |
|-----|------|
| Static SSM Agent versions (miss security patches) | Auto-update SSM Agent via State Manager association |

---

## Level 2: Automation Runbooks & Inspector (Intermediate)

### SSM Automation Runbooks
- **Low-code visual designer (Nov 2024)**: drag-and-drop, loops, conditionals
- Python/PowerShell scripting within runbooks
- **CodeGuru security scanning** on runbook scripts
- 100+ AWS-provided runbooks for common tasks

### Runbook Best Practices
| Practice | Why |
|----------|-----|
| Version documents | Easy rollback |
| Validate parameters | Prevent errors from bad input |
| Set step timeouts | Prevent hung automation |
| Modular (single-problem) | Maintainable, composable |
| Test in non-prod first | Prevent production surprises |
| Generous logging | Faster diagnostics |

### Enhanced Execution (Aug 2025)
- Re-execution with pre-populated parameters
- Auto-retry for throttled API calls
- Nested OU targeting for Organization-wide automation
- **Chatbot integration (Jan 2025)**: runbook recommendations in Slack/Teams

### Amazon Inspector
- Automated vulnerability scanning: EC2, Lambda, ECR container images
- Continuous scanning (not point-in-time)
- Findings → Security Hub for centralized view
- Risk-based prioritization using CVSS + exploit availability + network reachability

### **CRITICAL: Service EOL Notices**
- **Change Manager**: closed to new customers Nov 7, 2025. No new features. Existing customers continue
- **Incident Manager**: closed to new customers Nov 7, 2025. No new features. Use **OpsCenter** instead
- **Automation free tier**: ending Dec 31, 2025 for existing customers

---

## Level 3: OpsCenter & Change Management (Advanced)

### OpsCenter (Incident Management Replacement)
- Centralized OpsItem management across accounts/regions
- Aggregated operational data view — issue distribution + trends
- Runbook integration for remediation
- **Recommended replacement** for Incident Manager for new implementations

### Change Calendar
- Restrict operational changes during business-critical events
- Calendar windows: maintenance OK vs blackout (no changes)
- Integrates with Automation runbooks — runbooks check calendar before executing

### Automated Incident Response (Existing Incident Manager Customers)
- Response plans: who to engage, expected severity, auto runbooks, metrics to monitor
- Auto-engage via CloudWatch alarms or EventBridge events
- SMS, phone calls, chat channels for responder notification
- Post-incident analysis with suggested action items

### Config Aggregator
- Multi-account, multi-region compliance view
- Conformance packs: pre-built rule collections (PCI DSS, HIPAA, CIS)
- Remediation: Lambda or SSM Automation on non-compliant resources

---

## Performance: Make It Fast

### Automation Speed
1. **Pre-built runbooks** — don't reinvent for common tasks
2. **EventBridge triggers** — event-driven automation (not scheduled polling)
3. **Rate controls** — throttle automation across many targets
4. **Nested OUs targeting** — Organization-wide automation without per-account config
5. **Quick Setup** — baseline all accounts in minutes, not days

### Patch Performance
- Maintenance windows: schedule during low-traffic periods
- Patch groups: tag-based targeting for phased rollouts
- Snapshot-based rollback: take AMI before patching for rapid recovery

---

## Observability: Know It's Working

### What to Monitor

| Signal | Tool | What to Watch |
|--------|------|--------------|
| Patch compliance | Patch Manager dashboard | Non-compliant instances > 0 |
| Config compliance | Config dashboard | Non-compliant rules = remediate |
| Automation failures | CloudWatch `AutomationExecutionsFailed` | Any failure = investigate |
| Vulnerability count | Inspector findings | CRITICAL/HIGH > 0 = prioritize |
| OpsItems | OpsCenter dashboard | Open items trending up = bottleneck |

- **Config timeline**: view complete configuration history for any resource
- **SSM Inventory**: centralized view of software installed, patches applied, instance metadata
- **Automation execution history**: full audit trail of every runbook execution

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No SSH Keys for EC2 Access
**You will be tempted to:** Create SSH key pairs and open port 22 because "it's how Linux works"
**Why that fails:** Key management is a security nightmare. Keys get shared, lost, or stolen. Port 22 is the #1 scanned port on the internet
**The right way:** Session Manager. IAM-authenticated. Audit-logged. No open ports. No keys to manage

### Rule 2: No Manual Patching
**You will be tempted to:** "We'll patch when we have time" or manually SSH in to update
**Why that fails:** "When we have time" means never. Manual patching is incomplete and undocumented. Unpatched systems are the #1 entry point for attackers
**The right way:** Patch Manager with scheduled maintenance windows. Compliance tracking. Auto-remediation for non-compliant instances

### Rule 3: No Change Manager for New Projects
**You will be tempted to:** Use Change Manager because it appears in SSM documentation
**Why that fails:** Closed to new customers Nov 7, 2025. No new features. Building on a frozen service creates technical debt
**The right way:** OpsCenter for operational management. Custom automation with Change Calendar for change control. EventBridge + Automation for approval workflows

### Rule 4: No Manual Config Compliance Checks
**You will be tempted to:** Run quarterly manual audits for compliance
**Why that fails:** Configuration drift happens daily. Quarterly audits find problems months too late. Non-compliant resources run for weeks between checks
**The right way:** AWS Config with continuous rules. Auto-remediation. Conformance packs for regulatory frameworks. Real-time compliance dashboard

### Rule 5: No Console Automation
**You will be tempted to:** Click through the console to perform operational tasks
**Why that fails:** Not reproducible, not auditable, not scalable. Human error on every click. Can't delegate safely
**The right way:** SSM Automation runbooks for everything. Version-controlled, parameterized, tested in non-prod, with IAM-based access control
