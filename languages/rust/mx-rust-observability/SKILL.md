---
name: mx-rust-observability
description: Use when writing any Rust code. Co-loads with mx-rust-core by default. Rust observability — tracing crate spans and events, structured logging with tracing-subscriber, OpenTelemetry integration, Prometheus metrics, tokio-console, tokio-metrics, distributed tracing, health checks, axum middleware instrumentation. Also use when the user mentions 'tracing', 'logging', 'metrics', 'Prometheus', 'tokio-console', 'health check', 'observability', or any Rust monitoring setup.
---

# Rust Observability — Know It's Working for AI Coding Agents

**This skill co-loads with mx-rust-core for ANY Rust work.** It prevents the most common AI failure: shipping Rust code without structured tracing, never setting up metrics, using `println!` in production, and declaring work done without knowing if it is healthy.

## When to also load
- `mx-rust-core` — tracing initialization patterns
- `mx-rust-async` — async task instrumentation, tokio-console
- `mx-rust-network` — axum middleware, request tracing
- `mx-rust-services` — NATS consumer lag, Temporal metrics

---

## Level 1: Structured Logging with tracing (Beginner)

### Initialize Early, Configure Per-Environment

```rust
use tracing_subscriber::{EnvFilter, fmt, layer::SubscriberExt, util::SubscriberInitExt};

// FIRST thing in main(), before any business logic
tracing_subscriber::registry()
    .with(EnvFilter::from_default_env())  // RUST_LOG=info,my_crate=debug
    .with(fmt::layer().json())            // JSON in prod
    // .with(fmt::layer().compact())      // Compact in dev
    .init();
```

### Structured Fields, Not String Concatenation

**BAD:** `info!("Processing request for user {}", user_id);`
**GOOD:** `info!(user_id = %user_id, "processing request");`

Structured fields are queryable, filterable, and machine-parseable. String concatenation is grep-only.

### #[instrument] on Public Functions

```rust
#[tracing::instrument(
    skip(password),                    // Never log secrets
    fields(user_id = %user_id),       // Add business context
    level = "info"
)]
async fn authenticate(user_id: &str, password: &str) -> Result<Token> {
    // Auto-creates a span with entry/exit timing
    info!("auth attempt");  // This event is nested inside the span
    // ...
}
```

### Log Level Guidelines

| Level | Use For | Production |
|-------|---------|------------|
| `ERROR` | Failures requiring attention | Always on |
| `WARN` | Degraded but functional | Always on |
| `INFO` | Request lifecycle, significant events | Always on |
| `DEBUG` | Detailed internal state | Off by default, enable per-module |
| `TRACE` | Per-iteration, per-byte level detail | Off, compile-time filter if noisy |

Runtime filtering: `RUST_LOG=info,my_crate::db=debug,hyper=warn`

---

## Level 2: Metrics & Health (Intermediate)

### Prometheus Metrics

```rust
use prometheus::{IntCounter, Histogram, register_int_counter, register_histogram};
use lazy_static::lazy_static;

lazy_static! {
    static ref REQUESTS: IntCounter = register_int_counter!(
        "requests_total", "Total requests processed"
    ).unwrap();
    static ref LATENCY: Histogram = register_histogram!(
        "request_duration_seconds", "Request latency in seconds"
    ).unwrap();
}

// In handler:
REQUESTS.inc();
let _timer = LATENCY.start_timer();  // Dropped = records duration
```

**Rules:**
- snake_case names with units (`_seconds`, `_bytes`, `_total`)
- NEVER use unbounded label cardinality (no user IDs, request IDs as labels)
- Expose `/metrics` endpoint for Prometheus scraping
- Counter for events, Gauge for current values, Histogram for distributions

### axum Request Instrumentation

```rust
use tower_http::trace::TraceLayer;
use axum_prometheus::PrometheusMetricLayer;

let (prometheus_layer, metric_handle) = PrometheusMetricLayer::pair();

let app = Router::new()
    .route("/api", get(handler))
    .route("/metrics", get(move || async move { metric_handle.render() }))
    .layer(TraceLayer::new_for_http())   // Structured request logging
    .layer(prometheus_layer);             // Auto request/duration/pending metrics
```

`axum-prometheus` auto-tracks: `axum_http_requests_total`, `axum_http_requests_duration_seconds`, `axum_http_requests_pending`.

### Health Check Endpoints

```rust
async fn health() -> impl IntoResponse {
    // Check dependencies
    let db_ok = pool.acquire().await.is_ok();
    let nats_ok = client.connection_state() == State::Connected;

    if db_ok && nats_ok {
        (StatusCode::OK, Json(json!({"status": "healthy"})))
    } else {
        (StatusCode::SERVICE_UNAVAILABLE, Json(json!({
            "status": "degraded", "db": db_ok, "nats": nats_ok
        })))
    }
}
```

Separate liveness (`/healthz` — "is the process alive?") from readiness (`/readyz` — "can it serve traffic?").

---

## Level 3: Distributed Tracing & OpenTelemetry (Advanced)

### OpenTelemetry Integration

```rust
use tracing_opentelemetry::OpenTelemetryLayer;
use opentelemetry_otlp::new_pipeline;

let tracer = new_pipeline()
    .tracing()
    .with_exporter(new_exporter().tonic().with_endpoint("http://localhost:4317"))
    .with_trace_config(config().with_resource(Resource::new(vec![
        KeyValue::new("service.name", "my-service"),
    ])))
    .install_batch(opentelemetry_sdk::runtime::Tokio)?;

tracing_subscriber::registry()
    .with(OpenTelemetryLayer::new(tracer))
    .with(EnvFilter::from_default_env())
    .with(fmt::layer().compact())
    .init();
```

### Context Propagation in axum

```rust
use axum_tracing_opentelemetry::opentelemetry_tracing_layer;

let app = Router::new()
    .route("/", get(handler))
    .layer(opentelemetry_tracing_layer());  // Auto W3C traceparent/baggage
```

Traces connect across service boundaries automatically. Always call `global::shutdown_tracer_provider()` before exit to flush buffered spans.

### Async Task Instrumentation

```rust
// ALWAYS .instrument() spawned tasks — without it, trace context is lost
tokio::spawn(
    async move { process(msg).await }
        .instrument(info_span!("process_msg", msg_id = %id))
);
```

### tokio Runtime Observability

| Tool | When | What |
|------|------|------|
| `tokio-console` | Development | htop-like TUI for tasks, mutexes, semaphores |
| `tokio-metrics` | Production | RuntimeMonitor + TaskMonitor → Prometheus |

**tokio-console setup:**
```bash
RUSTFLAGS="--cfg tokio_unstable" cargo run
# In another terminal:
tokio-console
```

**tokio-metrics alerts:**
- `global_queue_depth` growing → task starvation
- `total_busy_duration / elapsed` → 1.0 = workers saturated
- `max_poll_duration` → slow future blocking the runtime

---

## Level 4: Domain-Specific Observability (Expert)

### Subprocess Monitoring
`sysinfo` crate: per-process CPU, memory, disk. `metrics-process` for Prometheus FD count, RSS, thread count. Log supervisor state transitions and restart frequency.

### Database Observability
`rusqlite` `trace` feature for SQLite profiling hooks. `serde_path_to_error` for field-level deserialization diagnostics. `metriki_r2d2` for connection pool checkout/wait/timeout metrics.

### Message Queue Monitoring
NATS: query JetStream management API for consumer pending count (lag). Expose as gauge. Alert on sustained growth.
Temporal: `temporal_*` prefixed SDK metrics for workflow/activity rate, latency, errors.

### Cron Job Health
Heartbeat to external monitor on success. Track execution_time histogram, success/failure counters, last_successful_run gauge.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No println! in Production Code
**You will be tempted to:** Use `println!` for debugging because "it's quick."
**Why that fails:** No timestamps, no levels, no structured fields, no filtering, no export to monitoring systems. Invisible in log aggregation.
**The right way:** `tracing::info!()` with structured fields. Always.

### Rule 2: No Logging Without Context
**You will be tempted to:** `error!("something failed");` with no details.
**Why that fails:** When oncall gets paged at 3am, "something failed" tells them nothing.
**The right way:** `error!(error = %e, request_id = %id, user_id = %uid, "auth failed");`

### Rule 3: No Skipping .instrument() on Spawned Tasks
**You will be tempted to:** `tokio::spawn(async { ... })` without `.instrument()`.
**Why that fails:** The spawned task runs without parent span context. Distributed traces break. Logs from that task have no request correlation.
**The right way:** Always `.instrument(info_span!("task_name", key = %value))`.

### Rule 4: No High-Cardinality Metric Labels
**You will be tempted to:** Add `user_id` or `request_id` as a Prometheus label.
**Why that fails:** Prometheus stores a separate time series per unique label set. 1M users = 1M time series = Prometheus OOM.
**The right way:** Use low-cardinality labels (method, status_code, endpoint). High-cardinality data goes in traces, not metrics.

### Rule 5: No Forgetting Tracer Shutdown
**You will be tempted to:** Let the process exit without flushing spans.
**Why that fails:** Buffered spans are lost. The last N seconds of traces before a crash — exactly when you need them most — are gone.
**The right way:** `opentelemetry::global::shutdown_tracer_provider()` in graceful shutdown handler. Register with CancellationToken.
