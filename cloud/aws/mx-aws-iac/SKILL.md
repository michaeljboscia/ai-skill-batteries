---
name: mx-aws-iac
description: CloudFormation nested stacks/drift detection/stack refactoring, CDK L1-L3 constructs/Aspects/Pipelines/testing, SAM CLI local testing/Accelerate/policy templates/connectors, and AI-generated anti-patterns
---

# AWS Infrastructure as Code — CloudFormation, CDK, SAM for AI Coding Agents

**Load this skill when writing CloudFormation templates, CDK constructs, SAM templates, or managing infrastructure deployments.**

## When to also load
- `mx-aws-lambda` — SAM for Lambda development, CDK Lambda constructs
- `mx-aws-iam` — IAM roles in IaC, CDK policy generation
- `mx-aws-cicd` — CDK Pipelines, CodePipeline deploy stages
- `mx-aws-security` — SCPs for IaC guardrails, Config rules for compliance

---

## Level 1: Patterns That Always Work (Beginner)

### Pattern 1: CDK Over Raw CloudFormation
| BAD | GOOD |
|-----|------|
| Hand-written CloudFormation YAML (verbose, error-prone) | CDK with L2/L3 constructs (type-safe, defaults, less code) |

CDK generates CloudFormation but gives you programming language power: loops, conditionals, type checking, testing.

### Pattern 2: CDK Construct Levels
| Level | What | When |
|-------|------|------|
| **L1** | Raw CloudFormation (`CfnBucket`) | Escape hatch for unsupported features |
| **L2** | Opinionated defaults (`Bucket`) | Standard usage — start here |
| **L3** | Patterns (`ApplicationLoadBalancedFargateService`) | Common architectures — highest productivity |

**Start with L2/L3.** Drop to L1 only for new features not yet in L2 constructs (escape hatch).

### Pattern 3: SAM for Serverless
| BAD | GOOD |
|-----|------|
| CDK for a simple Lambda + API Gateway | SAM: `sam init` → `sam local invoke` → `sam deploy` |

SAM is purpose-built for serverless. Local testing, hot-reload, policy templates. Use CDK for complex multi-service architectures, SAM for simple serverless.

### Pattern 4: Change Sets Before Deploy
| BAD | GOOD |
|-----|------|
| `cdk deploy` or `aws cloudformation deploy` directly | Review change set first, then execute |

Change sets show exactly what will be created, modified, or deleted before it happens.

### Pattern 5: Stack Policies for Critical Resources
Protect databases, S3 buckets, and stateful resources from accidental deletion or replacement with CloudFormation stack policies.

---

## Level 2: CDK & SAM Deep (Intermediate)

### CDK Patterns

| Feature | Purpose |
|---------|---------|
| **Aspects** | Cross-cutting policy enforcement (tagging, encryption checks) |
| **CDK Pipelines** | Self-mutating CI/CD pipeline for CDK apps |
| **Property Injection (May 2025)** | Override properties across constructs |
| **CDK Toolkit Library (May 2025)** | Programmatic CDK actions |
| **`cdk drift`** | Identify out-of-band changes |
| **Testing** | Unit tests with assertions, snapshot tests |

### CDK Testing
```typescript
const template = Template.fromStack(stack);
template.hasResourceProperties('AWS::Lambda::Function', {
  Runtime: 'nodejs20.x',
  Architectures: ['arm64']
});
```
Test every stack. Snapshot tests catch unintended changes. Fine-grained assertions validate specific properties.

### SAM Deep

| Feature | Purpose |
|---------|---------|
| `sam local invoke` | Docker-based Lambda emulation |
| `sam local start-api` | Local API Gateway emulator |
| **SAM Accelerate** (`sam sync --watch`) | Hot-reload to cloud. Bypasses CloudFormation for code changes |
| **Policy templates** | Pre-defined least-privilege IAM (`S3ReadPolicy`, `DynamoDBCrudPolicy`) |
| **SAM Connectors** | Describe resource interactions → auto-generates IAM policies |
| **Layers** | `AWS::Serverless::LayerVersion` for shared deps |
| **Nested apps** | `AWS::Serverless::Application` for modular design |

### SAM Testing Pyramid
1. **Unit tests** (no SDK) — fast, test business logic
2. **SAM local** (integration) — Docker-based, test with real AWS event schemas
3. **Cloud** (`sam sync`) — highest fidelity, test real AWS services

### CloudFormation Features

| Feature | Purpose |
|---------|---------|
| **Drift detection** | Drift-aware change sets (2025): compare template + deployed + actual |
| **Stack Refactoring** | Move resources between stacks without disruption (2025) |
| **Nested stacks** | Max 2 levels deep. Version child templates in S3 |
| **CFN Hooks** | Managed proactive controls from Control Tower catalog (2025) |

---

## Level 3: Production Patterns (Advanced)

### CDK Best Practices
- **Constructs for encapsulation** — reusable modules, not monolithic stacks
- **Separate stacks by lifecycle** — network stack (rarely changes) vs app stack (frequently changes)
- **cdk.context.json** — cache context lookups for deterministic deployments
- **`RemovalPolicy.RETAIN`** on stateful resources — prevent accidental deletion
- Run `cdk diff` before every deploy

### CloudFormation Production
- Parameterize templates. Use SSM Parameter Store for environment-specific values
- Stack policies on databases + storage. DeletionPolicy: Retain on stateful resources
- Nested stacks: meaningful output names, versioned child templates in S3
- CFN Hooks for proactive compliance checks before resource creation

### Hexagonal Architecture for SAM
Separate business logic from AWS SDK calls. Mock AWS interactions in unit tests. Test business rules independently of infrastructure.

---

## Performance: Make It Fast

### Deployment Speed
1. **SAM Accelerate** — hot-reload to cloud in seconds (bypasses CloudFormation for code)
2. **CDK Pipelines** — self-mutating, parallel wave deployments
3. **Cached builds** — SAM dependency layer optimization during sync
4. **Separate stacks** — deploy app stack without waiting for network stack
5. **Change sets** — review quickly, execute confidently

### CDK Synth Speed
- Avoid expensive runtime lookups in constructs (use `cdk.context.json` cache)
- Lazy-load heavy dependencies
- Use `PipelineSession` for lazy resource loading in CDK Pipelines

---

## Observability: Know It's Working

### What to Monitor

| Signal | Tool | What to Watch |
|--------|------|--------------|
| Stack drift | CloudFormation drift detection / `cdk drift` | Any drift = manual change bypassed IaC |
| Deploy failures | CloudFormation events | `CREATE_FAILED`, `UPDATE_ROLLBACK` |
| Stack events | CloudFormation + EventBridge | Track all stack operations |
| Resource compliance | AWS Config rules | Resources not matching desired config |
| Pipeline health | CDK Pipeline / CodePipeline metrics | Stage failures, duration trends |

- **Drift detection**: run weekly. Any drift = someone modified resources outside IaC
- **Config rules**: continuous compliance monitoring for IaC-managed resources
- **Stack event notifications**: SNS on failure for immediate awareness

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Manual Console Changes to IaC Resources
**You will be tempted to:** "Quick fix" a resource in the console
**Why that fails:** Creates drift. Next IaC deploy either reverts the fix (if detected) or breaks (if not detected). The console change is undocumented and unreproducible
**The right way:** All changes through IaC. If urgent, make the console change AND immediately update the IaC code. Enable drift detection

### Rule 2: No Secrets in IaC Templates
**You will be tempted to:** Put database passwords, API keys in CloudFormation parameters or CDK code
**Why that fails:** Templates are stored in S3/CloudFormation. Parameters visible in console. Committed to git. Secrets in IaC = secrets everywhere
**The right way:** `AWS::SecretsManager::Secret` with `GenerateSecretString`. Reference via dynamic reference `{{resolve:secretsmanager:...}}`

### Rule 3: No Monolithic Templates
**You will be tempted to:** Put everything in one stack/template because "it's simpler"
**Why that fails:** Hits CloudFormation resource limits (500/stack). Deploy takes 30+ minutes. One failure rolls back everything. Blast radius is the entire application
**The right way:** Separate by lifecycle: network (stable), database (careful), application (frequent). Cross-stack references for dependencies

### Rule 4: No CDK L1 When L2 Exists
**You will be tempted to:** Use `CfnBucket` because CloudFormation docs are more familiar
**Why that fails:** L1 constructs have no defaults, no validation, no convenience methods. You're writing CloudFormation in TypeScript — all the verbosity, none of the benefits
**The right way:** L2 constructs (`Bucket`, `Function`, `Table`) with sensible defaults. L1 only for features not yet in L2 (check first)

### Rule 5: No SAM Deploy Without Local Testing
**You will be tempted to:** Skip `sam local invoke` and deploy directly to AWS
**Why that fails:** Cloud deployments take minutes. Debugging through deploy cycles = hours wasted. Missing event schema issues caught locally in seconds
**The right way:** `sam local invoke` with `sam local generate-event` for sample payloads. Unit tests first, local integration second, cloud deploy third
