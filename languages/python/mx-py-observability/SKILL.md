---
name: mx-py-observability
description: Python observability — structlog, OpenTelemetry, prometheus_client, Sentry, correlation IDs, health checks. Use for any Python work involving logging, tracing, metrics, or error tracking.
---

# Python Observability — Structured Logging, Distributed Tracing, Metrics & Error Tracking

**This skill co-loads with mx-py-core for ANY Python work.** It defines how every Python service emits logs, traces, metrics, and errors.

## When to also load
- `mx-py-core` — always (typing, error handling, module structure)
- `mx-py-web` — when building FastAPI endpoints with instrumentation
- `mx-py-perf` — when profiling or optimizing hot paths affected by telemetry overhead

---

## Level 1: Structured Logging & Health Endpoints (Beginner)

### structlog Configuration

Configure once at application startup. Never reconfigure mid-process.

```python
import sys
import structlog
import orjson

def configure_logging(*, is_production: bool = True) -> None:
    processors: list[structlog.types.Processor] = [
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso", utc=True),
        structlog.processors.format_exc_info,
        structlog.processors.StackInfoRenderer(),
    ]

    if is_production:
        processors.append(
            structlog.processors.JSONRenderer(serializer=orjson.dumps)
        )
        logger_factory = structlog.BytesLoggerFactory(sys.stdout.buffer)
    else:
        processors.append(structlog.dev.ConsoleRenderer())
        logger_factory = structlog.PrintLoggerFactory()

    structlog.configure(
        processors=processors,
        logger_factory=logger_factory,
        wrapper_class=structlog.make_filtering_bound_logger(
            import_logging_levels=True,
        ),
        cache_logger_on_first_use=True,
    )
```

**Key decisions:**
- **Dev:** `ConsoleRenderer` to stderr — human-readable, colored output
- **Prod:** `JSONRenderer` with `orjson.dumps` to stdout — machine-parseable, 3-10x faster than stdlib `json`
- **`BytesLoggerFactory`** in prod avoids encoding ping-pong (orjson returns bytes; writing bytes to stdout skips UTF-8 encode)
- **`cache_logger_on_first_use=True`** is critical for performance (makes loggers unpickleable — acceptable trade-off)
- Alternative to orjson: `msgspec.json.encode` — same byte-level speed, smaller dependency

### Processor Pipeline Order

Processors run sequentially. Order matters.

1. `merge_contextvars` — pull async-scoped context (request IDs, user IDs) into event dict
2. `add_log_level` — append severity (INFO, ERROR, etc.)
3. `TimeStamper(fmt="iso", utc=True)` — UTC ISO-8601 timestamps
4. `format_exc_info` — serialize stack traces into `exception` key
5. `StackInfoRenderer` — append call stack when requested
6. **Custom processors** (OTel trace injection, PII redaction) go here
7. **Renderer** (JSONRenderer or ConsoleRenderer) — ALWAYS last

### Canonical Log Lines

Emit one rich log event per request instead of many small ones. Reduces log volume while maximizing queryability.

```python
log = structlog.get_logger()

async def handle_request(request):
    structlog.contextvars.bind_contextvars(
        user_id=request.user.id,
        tenant=request.headers.get("X-Tenant-ID"),
    )
    # ... business logic ...
    log.info(
        "request_completed",
        method=request.method,
        path=request.url.path,
        status=response.status_code,
        duration_ms=elapsed_ms,
    )
```

### Health Endpoints

Three probes, three purposes. Confusing them causes cascading outages.

| Probe | Path | Purpose | Checks dependencies? |
|-------|------|---------|---------------------|
| Liveness | `/livez` | "Is the process alive?" | **NEVER** |
| Readiness | `/readyz` | "Can it serve traffic?" | Yes (DB, Redis, etc.) |
| Startup | `/startup` | "Has it finished booting?" | Yes (model loading, etc.) |

```python
from fastapi import FastAPI, Response, status

def setup_health_checks(app: FastAPI) -> None:

    @app.get("/livez", tags=["Health"])
    async def liveness():
        # Returns 200 if the event loop is responsive. That's it.
        # NEVER check DB, Redis, or any external dependency here.
        return {"status": "alive"}

    @app.get("/readyz", tags=["Health"])
    async def readiness(response: Response):
        db_ok = await check_database()
        redis_ok = await check_redis()
        if db_ok and redis_ok:
            return {"status": "ready"}
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {
            "status": "not_ready",
            "dependencies": {
                "database": "up" if db_ok else "down",
                "redis": "up" if redis_ok else "down",
            },
        }
```

**Why liveness NEVER checks DB:** If Postgres is down, restarting your API containers does not fix Postgres. It creates a thundering herd of reconnects when Postgres recovers, making the outage worse. A failed liveness probe kills the container. A failed readiness probe removes it from the load balancer — the correct response to a dependency outage.

---

## Level 2: Distributed Tracing & Error Tracking (Intermediate)

### OpenTelemetry Setup

```python
import os
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor

def initialize_tracing(app) -> None:
    resource = Resource.create({
        "service.name": os.environ["SERVICE_NAME"],       # REQUIRED
        "service.version": os.environ["SERVICE_VERSION"],  # REQUIRED
        "deployment.environment": os.environ["ENV"],       # REQUIRED
    })

    provider = TracerProvider(resource=resource)

    # BatchSpanProcessor — MANDATORY for production
    exporter = OTLPSpanExporter(
        endpoint=os.getenv("OTLP_ENDPOINT", "http://otel-collector:4317"),
    )
    provider.add_span_processor(
        BatchSpanProcessor(
            exporter,
            max_queue_size=4096,
            schedule_delay_millis=3000,
            max_export_batch_size=1024,
        )
    )
    trace.set_tracer_provider(provider)

    # Auto-instrumentation — no manual span creation for standard I/O
    FastAPIInstrumentor.instrument_app(app)
    HTTPXClientInstrumentor().instrument()
    # SQLAlchemyInstrumentor().instrument(engine=your_engine)
```

**Critical rules:**
- **`BatchSpanProcessor`** queues spans and exports asynchronously in a background thread. `SimpleSpanProcessor` blocks the event loop on every span — forbidden in production.
- **Resource attributes** `service.name`, `service.version`, `deployment.environment` are non-negotiable. Without them, traces cannot be filtered or aggregated downstream.
- **Auto-instrumentation** covers FastAPI (ASGI lifecycle), httpx (outbound HTTP), SQLAlchemy (DB queries). Use `opentelemetry-bootstrap -a install` to auto-detect available instrumentors.
- **Custom spans** for business logic only when auto-instrumentation does not cover the operation:

```python
tracer = trace.get_tracer(__name__)

async def process_order(order_id: str) -> None:
    with tracer.start_as_current_span("process_order") as span:
        span.set_attribute("order.id", order_id)
        # ... business logic ...
```

### Sampling Strategies

| Strategy | Decision point | Keeps error traces? | Cost |
|----------|---------------|--------------------|----|
| Head-based (10%) | At trace start | No guarantee | Cheap |
| Tail-based | After trace completes (at Collector) | Yes — keep 100% errors | More infra |

**Tail-based sampling is the production recommendation.** Configure at the OTel Collector level: keep 100% of traces with errors or latency > p95, sample 5-10% of successful traces.

Do NOT use `--reload` (uvicorn) with OTel instrumentation active — reload creates duplicate instrumentors.

### Sentry Integration

```python
import os
import sentry_sdk
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.sqlalchemy import SqlalchemyIntegration

def traces_sampler(sampling_context: dict) -> float:
    """Dynamic sampling — NOT uniform traces_sample_rate."""
    asgi_scope = sampling_context.get("asgi_scope", {})
    path = asgi_scope.get("path", "")

    # Never sample health checks or metrics endpoints
    if path in {"/livez", "/readyz", "/metrics", "/startup"}:
        return 0.0

    # Higher rate for critical paths
    if path.startswith("/api/payments"):
        return 0.5

    # Default production rate
    return 0.1

def initialize_sentry() -> None:
    sentry_sdk.init(
        dsn=os.environ["SENTRY_DSN"],
        environment=os.getenv("ENV", "production"),
        release=os.getenv("GIT_COMMIT_SHA", "unknown"),
        integrations=[
            FastApiIntegration(transaction_style="endpoint"),
            SqlalchemyIntegration(),
        ],
        traces_sampler=traces_sampler,  # NOT traces_sample_rate
        profiles_sample_rate=1.0,       # Relative to traces_sampler result
        include_source_context=True,
        include_local_variables=True,
    )
```

**`traces_sampler` vs `traces_sample_rate`:** A uniform `traces_sample_rate=0.1` samples health checks and `/metrics` at the same rate as critical business endpoints. This wastes Sentry quota on noise. `traces_sampler` gives per-endpoint control — always use it.

### Breadcrumbs, Tags, and Context

```python
import sentry_sdk

# Tags — indexed, searchable in Sentry UI. Use for low-cardinality dimensions.
sentry_sdk.set_tag("payment.provider", "stripe")
sentry_sdk.set_tag("tenant.id", tenant_id)

# Context — structured data, NOT searchable. Use for debugging detail.
sentry_sdk.set_context("order", {
    "order_id": order_id,
    "total": total_amount,
    "items_count": len(items),
})

# Scoped capture — prevents context pollution across unrelated events
with sentry_sdk.push_scope() as scope:
    scope.set_tag("retry.attempt", str(attempt))
    scope.set_context("request", {"url": url, "method": method})
    sentry_sdk.capture_exception(err)
```

**Never put PII or secrets in tags or context.** Tokens, passwords, and email addresses in Sentry events are compliance violations (GDPR, SOC2). Use `before_send` hooks to scrub sensitive fields.

---

## Level 3: Metrics, Correlation IDs & Advanced Patterns (Advanced)

### Prometheus Metrics

```python
from prometheus_client import Counter, Gauge, Histogram, generate_latest, CONTENT_TYPE_LATEST
from fastapi import FastAPI, Request, Response
import time

# SLO-driven histogram buckets — density around your SLO target
# If SLO = "99% of requests < 500ms", the 0.5 bucket is mandatory
LATENCY_BUCKETS = (0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, float("inf"))

REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency",
    labelnames=["method", "endpoint", "status"],
    buckets=LATENCY_BUCKETS,
)

REQUEST_TOTAL = Counter(
    "http_requests_total",
    "Total HTTP requests",
    labelnames=["method", "endpoint", "status"],
)

ACTIVE_CONNECTIONS = Gauge(
    "http_active_connections",
    "Currently active HTTP connections",
)
```

**Metric type decision:**

| Type | Direction | Use case | Example |
|------|-----------|----------|---------|
| Counter | Only up | Totals, events | `http_requests_total` |
| Gauge | Up and down | Current state | `active_connections` |
| Histogram | Observations into buckets | Latency, sizes | `request_duration_seconds` |
| Summary | Client-side quantiles | Single-instance percentiles | Rarely needed — prefer Histogram |

**Prefer Histogram over Summary.** Histograms are aggregatable across instances via `histogram_quantile()`. Summaries are not.

### Label Cardinality Rules

Every unique label combination creates a new time series. Cardinality is multiplicative.

| Label | Cardinality | Allowed? |
|-------|-------------|----------|
| `method` (GET, POST, etc.) | ~5 | Yes |
| `status` (200, 404, 500) | ~10 | Yes |
| `endpoint` (`/users/{id}`) | ~50 parameterized | Yes |
| `endpoint` (`/users/abc123`) | Unbounded | **NEVER** |
| `user_id` | Unbounded | **NEVER** |
| `request_id` / UUID | Unbounded | **NEVER** |

**The rule:** If a label value set is unbounded or grows with traffic, it belongs in logs or traces, NOT metrics. Use parameterized route paths (`/users/{id}`) never resolved paths (`/users/abc123`).

```python
# GOOD: Use route template, not resolved path
async def metrics_middleware(request: Request, call_next):
    start = time.time()
    route = request.scope.get("route")
    path = route.path if route else "unknown"  # "/users/{id}" not "/users/abc123"

    response = await call_next(request)
    duration = time.time() - start

    REQUEST_LATENCY.labels(
        method=request.method, endpoint=path, status=response.status_code
    ).observe(duration)
    REQUEST_TOTAL.labels(
        method=request.method, endpoint=path, status=response.status_code
    ).inc()
    return response
```

### Pushgateway: Batch Jobs ONLY

```python
from prometheus_client import CollectorRegistry, Counter, push_to_gateway

# Dedicated registry — never pollute the default one
registry = CollectorRegistry()
rows_processed = Counter(
    "etl_rows_processed_total", "Rows processed", registry=registry
)

def run_etl_job():
    # ... process rows, increment counter ...
    rows_processed.inc(count)
    push_to_gateway("pushgateway:9091", job="nightly_etl", registry=registry)
```

Pushgateway is ONLY for short-lived batch jobs (cron, ETL, CI/CD) that terminate before Prometheus can scrape them. **Never use Pushgateway for web services or workers.** It becomes a single point of failure, loses the `up` metric for health monitoring, and creates zombie metrics that never expire.

### Naming conventions

- Snake_case: `http_request_duration_seconds`
- Include units: `_seconds`, `_bytes`, `_total`
- Prefix with service or domain: `payment_charge_total`
- Counters end in `_total`

### Correlation IDs: Unifying Logs and Traces

The structlog processor that injects OTel trace context into every log event:

```python
from opentelemetry import trace

def add_otel_context(logger, method_name, event_dict):
    """Structlog processor — injects trace_id and span_id from active OTel span."""
    span = trace.get_current_span()
    if span and span.is_recording():
        ctx = span.get_span_context()
        if ctx.is_valid:
            event_dict["trace_id"] = format(ctx.trace_id, "032x")
            event_dict["span_id"] = format(ctx.span_id, "016x")
    return event_dict
```

Add this processor AFTER `StackInfoRenderer` and BEFORE the renderer in the processor pipeline.

### Request ID Middleware (when OTel is not available)

```python
import uuid
import structlog
from fastapi import Request

async def request_id_middleware(request: Request, call_next):
    req_id = request.headers.get("X-Request-ID") or str(uuid.uuid4())
    structlog.contextvars.clear_contextvars()
    structlog.contextvars.bind_contextvars(
        request_id=req_id,
        client_ip=request.client.host if request.client else "unknown",
    )
    response = await call_next(request)
    response.headers["X-Request-ID"] = req_id
    return response
```

`contextvars` propagates across async boundaries automatically. Every log emitted during the request lifecycle includes `request_id` without explicit passing.

### Full Processor Pipeline (Production)

Bringing it all together — structlog + OTel + orjson:

```python
def configure_production_logging() -> None:
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            structlog.processors.format_exc_info,
            structlog.processors.StackInfoRenderer(),
            add_otel_context,                        # Inject trace_id + span_id
            structlog.processors.JSONRenderer(serializer=orjson.dumps),
        ],
        logger_factory=structlog.BytesLoggerFactory(sys.stdout.buffer),
        wrapper_class=structlog.make_filtering_bound_logger(
            import_logging_levels=True,
        ),
        cache_logger_on_first_use=True,
    )
```

---

## Performance: Telemetry Must Not Be the Bottleneck

- **`BatchSpanProcessor`** always — async export in background thread, configurable queue size and batch delay
- **`orjson.dumps` or `msgspec.json.encode`** for log serialization — 3-10x faster than stdlib json
- **`BytesLoggerFactory`** eliminates bytes-to-string-to-bytes encoding round-trip
- **Tail-based sampling** at the OTel Collector — collect locally, decide what to keep after trace completes. Keeps 100% of error traces while sampling 5-10% of successful traffic
- **`cache_logger_on_first_use=True`** avoids repeated logger construction
- **Histogram bucket density** around SLO targets — too many buckets waste memory; too few destroy percentile accuracy
- **Prometheus scrape interval** 15-30s is standard — sub-second scraping creates unnecessary load

---

## Cross-References

- **`mx-py-core`** — error handling hierarchy (`ServiceError` base), `__all__` exports, typing patterns
- **`mx-py-web`** — FastAPI middleware patterns, DI for injecting tracers/loggers, endpoint structure
- **`mx-py-perf`** — profiling workflows (py-spy, cProfile), uvloop for lower latency, data structure selection for hot paths

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No print() Debugging
**You will be tempted to:** Use `print()` or stdlib `logging.info()` with f-strings because "it's just a quick debug."
**Why that fails:** Unstructured text cannot be parsed by log aggregators (Datadog, Loki, ELK). Cannot filter, search, or correlate. Cannot attach trace context. Becomes permanent tech debt the moment it ships.
**The right way:** `structlog.get_logger()` exclusively. Dev uses `ConsoleRenderer` (just as readable). Prod uses `JSONRenderer`. No exceptions.

### Rule 2: No SimpleSpanProcessor in Production
**You will be tempted to:** Use `SimpleSpanProcessor` because "BatchSpanProcessor is more complex to configure."
**Why that fails:** SimpleSpanProcessor makes a synchronous network call on every span end. In an async ASGI application, this blocks the event loop. Latency increases linearly with span count. Under load, the application becomes unresponsive.
**The right way:** `BatchSpanProcessor` with tuned `max_queue_size`, `schedule_delay_millis`, and `max_export_batch_size`. The 4-line configuration difference prevents production incidents.

### Rule 3: No High-Cardinality Prometheus Labels
**You will be tempted to:** Add `user_id`, `request_id`, or resolved URL paths as Prometheus labels because "we need per-user latency."
**Why that fails:** Every unique label combination creates a new time series in memory. 100K users x 5 methods x 10 status codes = 5M time series. Prometheus OOM-kills itself. This is the number one cause of Prometheus outages.
**The right way:** Per-user data goes in logs and traces (structlog, OTel). Metrics use bounded dimensions only — HTTP method, parameterized endpoint, status code bucket, service name.

### Rule 4: No 100% Sample Rate in Production
**You will be tempted to:** Set `traces_sample_rate=1.0` or skip sampling entirely because "we need to see everything."
**Why that fails:** Generating, serializing, and exporting spans for every request scales linearly with traffic. At 10K RPS, this means 10K span exports per second — crushing CPU, network, and APM quotas. Health check and metrics endpoint traces are pure waste.
**The right way:** `traces_sampler` function with per-endpoint rates. 0.0 for health checks. 0.05-0.25 for standard endpoints. Tail-based sampling at the Collector for 100% error trace retention.

### Rule 5: No Pushgateway for Services
**You will be tempted to:** Use Prometheus Pushgateway for a web service or worker because "push is simpler than configuring scrape targets."
**Why that fails:** Pushgateway loses the `up` metric (no instance health). Metrics become zombies that never expire after the service restarts. Pushgateway becomes a single point of failure. The Prometheus documentation explicitly warns against this.
**The right way:** Expose `/metrics` endpoint. Let Prometheus scrape it. Pushgateway is exclusively for ephemeral batch jobs (cron, ETL) that terminate before a scrape cycle.
