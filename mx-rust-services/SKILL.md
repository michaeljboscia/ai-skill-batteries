---
name: mx-rust-services
description: Use when integrating NATS messaging, Temporal workflows, policy engines, embedded dashboards, or scheduled tasks in Rust. Covers async-nats with JetStream, Temporal Rust SDK workflows/activities, regorus/Cedar/Cerbos policy engines, rust-embed for SPA embedding, and tokio-cron-scheduler. Also use when the user mentions 'NATS', 'JetStream', 'Temporal', 'workflow', 'activity', 'signal', 'query', 'policy engine', 'OPA', 'Rego', 'Cedar', 'Cerbos', 'rust-embed', 'SPA', 'dashboard', 'cron', or 'scheduled task'.
---

# Rust Service Integration — NATS, Temporal, Policy & Dashboard Patterns

**Loads when wiring external services into a Rust daemon.** Specifically designed for the triumvirate architecture: NATS for messaging, Temporal for durable workflows, policy engines for auth, embedded Svelte dashboard.

## When to also load
- Async patterns → `mx-rust-async`
- Web server → `mx-rust-network`
- Subprocess management → `mx-rust-systems`

---

## Level 1: NATS Messaging (Beginner)

### async-nats Connection with Reconnection Jitter

```rust
use async_nats::ConnectOptions;

let client = ConnectOptions::new()
    .max_reconnects(10)
    .retry_delay_callback(|attempts| {
        let base = Duration::from_millis(500);
        let jitter = rand::random::<u64>() % 1000;
        std::cmp::min(base * attempts as u32 + Duration::from_millis(jitter),
                      Duration::from_secs(5))
    })
    .connect("nats://localhost:4222").await?;
```

**Client is cloneable** — share across tasks without Arc.

### JetStream Publish/Subscribe

```rust
let js = async_nats::jetstream::new(client.clone());

// Create stream
js.get_or_create_stream(async_nats::jetstream::stream::Config {
    name: "AGENT_EVENTS".into(),
    subjects: vec!["agent.*.events.>".into()],
    ..Default::default()
}).await?;

// Publish
js.publish("agent.claude.events.started", "{}".into()).await?;

// Consume (pull consumer — recommended for daemons)
let consumer = stream.get_consumer("processor").await?;
let mut messages = consumer.batch().max_messages(100).messages().await?;
while let Some(Ok(msg)) = messages.next().await {
    process(&msg);
    msg.double_ack().await?;  // Exactly-once semantics
}
```

### NATS Architecture: Sidecar vs Managed

| Deployment | Pattern | When |
|-----------|---------|------|
| Cloud/K8s | **Sidecar** | Independent scaling, lifecycle, fault isolation |
| Edge/standalone | **Managed lifecycle** | Daemon spawns + supervises nats-server binary |

NATS server is Go — can't embed in Rust binary. Manage as subprocess or sidecar.

---

## Level 2: Temporal Workflows (Intermediate)

### CRITICAL: Determinism Requirements

Temporal workflows replay from event history. **Non-deterministic code breaks replay.**

**FORBIDDEN in workflows:**
- `tokio::select!`, `tokio::spawn`, `futures::select!`
- Direct HTTP requests, file I/O, random numbers
- `std::time::Instant::now()`

**USE INSTEAD:**
- `temporalio_sdk::workflows::select!`
- `temporalio_sdk::workflows::join!`
- Activities for all I/O operations

### Workflow Definition

```rust
#[workflow]
pub struct AgentWorkflow { /* state fields */ }

#[workflow_methods]
impl AgentWorkflow {
    #[workflow::run]
    pub async fn run(&mut self, ctx: WorkflowContext, agent_id: String) -> WorkflowResult<()> {
        // Start an activity (non-deterministic work)
        ctx.start_activity("execute_agent_task", payload).await?;
        Ok(())
    }

    #[workflow::signal]
    pub async fn pause(&mut self, _ctx: WorkflowContext) {
        self.paused = true;  // Mutations are deterministically replayed
    }

    #[workflow::query]
    pub fn get_status(&self) -> String {
        self.status.clone()  // Read-only, never mutate in queries
    }
}
```

### Activities with Shared State

```rust
pub struct AgentActivities {
    pub state: Arc<SharedState>,  // DB pool, NATS client, etc.
}

#[activities]
impl AgentActivities {
    #[activity]
    pub async fn execute_agent_task(&self, payload: String) -> Result<String, ActivityError> {
        // Activities CAN do I/O, HTTP calls, etc.
        self.state.nats.publish("agent.task", payload.into()).await?;
        Ok("done".into())
    }
}
```

**Temporal SDK is pre-release** — API may change. Pin versions in Cargo.toml.

---

## Level 3: Policy, Dashboard & Scheduling (Advanced)

### Policy Engine Decision Tree

| Condition | Use |
|-----------|-----|
| Existing OPA/Rego investment | **regorus** (pure Rust Rego interpreter, no_std) |
| Native Rust, formally verified | **Cedar** (AWS, RBAC/ABAC, provably correct) |
| Multi-language, managed SaaS | **Cerbos** (WASM ePDP via Cerbos Hub) |
| Default choice for new projects | **Cedar** |

### rust-embed for Svelte SPA

```rust
use rust_embed::RustEmbed;

#[derive(RustEmbed)]
#[folder = "frontend/build/"]  // SvelteKit static output
struct SpaAssets;

// SPA fallback: unknown routes serve index.html
async fn spa_fallback(uri: Uri) -> impl IntoResponse {
    match SpaAssets::get("index.html") {
        Some(content) => Html(content.data.into_owned()).into_response(),
        None => StatusCode::NOT_FOUND.into_response(),
    }
}

let app = Router::new()
    .nest("/api", api_routes)
    .fallback(spa_fallback);
```

Dev workflow: run Vite dev server + Rust backend separately. Vite proxies `/api` to Rust.

### tokio-cron-scheduler

```rust
use tokio_cron_scheduler::{Job, JobScheduler};

let mut sched = JobScheduler::new().await?;

// Every 5 minutes: "0 */5 * * * *" (sec min hour dom mon dow)
sched.add(Job::new_async("0 */5 * * * *", |_, _| {
    Box::pin(async move { run_health_check().await; })
})?).await?;

sched.start().await?;
```

Optional persistence: PostgreSQL or NATS backends for surviving restarts.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No tokio::select! in Temporal Workflows
**The right way:** `temporalio_sdk::workflows::select!` for deterministic replay.

### Rule 2: No Unbounded NATS Publishing
**The right way:** Flow control with consumer `max_messages` and `max_bytes` limits.

### Rule 3: No Embedding NATS + External NATS Cluster
**The right way:** Pick one topology. Mixing "ends in tears" per NATS maintainers.
