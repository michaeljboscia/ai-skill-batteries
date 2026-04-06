---
name: mx-go-observability
description: Use when writing any Go code. Co-loads with mx-go-core by default. Go observability — slog structured logging with JSONHandler/TextHandler, slog.With child loggers, OpenTelemetry traces/metrics/logs, TracerProvider/MeterProvider setup, otelhttp middleware, Prometheus metrics exposition, otelslog bridge for trace correlation, span attributes, sampling strategies, cardinality control. Also use when the user mentions 'slog', 'logging', 'tracing', 'metrics', 'Prometheus', 'OpenTelemetry', 'health check', 'observability', or any Go monitoring setup.
---

# Go Observability — Logs, Traces & Metrics for AI Coding Agents

**This skill co-loads with mx-go-core for ANY Go work.** It prevents the most common AI failure: shipping Go code without structured logging, never setting up tracing, using `fmt.Println` in production, and declaring work done without knowing if it is healthy.

## When to also load
- Core Go patterns → `mx-go-core`
- HTTP middleware for tracing → `mx-go-http`
- Runtime metrics → `mx-go-perf`
- Service-to-service tracing → `mx-go-services`

---

## Level 1: Structured Logging with slog

### Production Setup

```go
func initLogger(env string) *slog.Logger {
    var handler slog.Handler

    switch env {
    case "production":
        handler = slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
            Level: slog.LevelInfo,
            ReplaceAttr: func(groups []string, a slog.Attr) slog.Attr {
                // Redact sensitive fields
                if a.Key == "password" || a.Key == "token" || a.Key == "secret" {
                    a.Value = slog.StringValue("[REDACTED]")
                }
                return a
            },
        })
    default:
        handler = slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{
            Level:     slog.LevelDebug,
            AddSource: true,  // file:line in dev (perf impact in prod)
        })
    }

    logger := slog.New(handler)
    slog.SetDefault(logger)
    return logger
}
```

### Typed Attributes — Avoid interface{}

```go
// BAD — slog.Any forces interface{} boxing (allocates)
slog.Info("request", "method", r.Method, "status", code)

// GOOD — typed helpers avoid allocations
slog.Info("request",
    slog.String("method", r.Method),
    slog.Int("status", code),
    slog.Duration("latency", elapsed),
    slog.String("request_id", reqID),
)
```

### Child Loggers with Context

```go
// Logger.With() creates a child logger with persistent fields
func handleRequest(logger *slog.Logger, r *http.Request) {
    reqLogger := logger.With(
        slog.String("request_id", middleware.GetReqID(r.Context())),
        slog.String("method", r.Method),
        slog.String("path", r.URL.Path),
    )

    reqLogger.Info("request started")
    // ... process ...
    reqLogger.Info("request completed", slog.Int("status", code))
}
```

### Dynamic Log Levels

```go
// Change log level at runtime (production troubleshooting)
var logLevel slog.LevelVar
logLevel.Set(slog.LevelInfo)

handler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
    Level: &logLevel,
})

// HTTP endpoint to change level
http.HandleFunc("/debug/log-level", func(w http.ResponseWriter, r *http.Request) {
    level := r.URL.Query().Get("level")
    switch level {
    case "debug":
        logLevel.Set(slog.LevelDebug)
    case "info":
        logLevel.Set(slog.LevelInfo)
    case "warn":
        logLevel.Set(slog.LevelWarn)
    case "error":
        logLevel.Set(slog.LevelError)
    default:
        http.Error(w, "invalid level", http.StatusBadRequest)
        return
    }
    fmt.Fprintf(w, "log level set to %s", level)
})
```

### Lazy Evaluation for Expensive Log Args

```go
// BAD — expensive call runs even if log level filters it
slog.Debug("state", slog.String("dump", expensiveDump()))

// GOOD — check if level is enabled first
if logger.Enabled(ctx, slog.LevelDebug) {
    slog.Debug("state", slog.String("dump", expensiveDump()))
}

// GOOD — LogValuer interface for lazy evaluation
type lazyDump struct{ state *State }
func (d lazyDump) LogValue() slog.Value {
    return slog.StringValue(d.state.Dump())
}
slog.Debug("state", slog.Any("dump", lazyDump{state}))
```

---

## Level 2: OpenTelemetry Setup

### TracerProvider + MeterProvider

```go
func initOTel(ctx context.Context, serviceName string) (func(), error) {
    res, err := resource.New(ctx,
        resource.WithAttributes(
            semconv.ServiceName(serviceName),
            semconv.ServiceVersion(version),
        ),
    )
    if err != nil {
        return nil, fmt.Errorf("create resource: %w", err)
    }

    // Traces → OTLP exporter
    traceExporter, err := otlptracegrpc.New(ctx)
    if err != nil {
        return nil, fmt.Errorf("create trace exporter: %w", err)
    }

    tp := sdktrace.NewTracerProvider(
        sdktrace.WithBatcher(traceExporter),
        sdktrace.WithResource(res),
        sdktrace.WithSampler(sdktrace.ParentBased(
            sdktrace.TraceIDRatioBased(0.1),  // sample 10%
        )),
    )
    otel.SetTracerProvider(tp)
    otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
        propagation.TraceContext{},
        propagation.Baggage{},
    ))

    // Metrics → Prometheus exporter
    metricExporter, err := prometheus.New()
    if err != nil {
        return nil, fmt.Errorf("create metric exporter: %w", err)
    }

    mp := sdkmetric.NewMeterProvider(
        sdkmetric.WithReader(metricExporter),
        sdkmetric.WithResource(res),
    )
    otel.SetMeterProvider(mp)

    // Shutdown function
    shutdown := func() {
        ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
        defer cancel()
        tp.Shutdown(ctx)
        mp.Shutdown(ctx)
    }

    return shutdown, nil
}
```

### HTTP Instrumentation with otelhttp

```go
// Wrap router for automatic span creation
handler := otelhttp.NewHandler(router, "server",
    otelhttp.WithMessageEvents(otelhttp.ReadEvents, otelhttp.WriteEvents),
)

// Client-side instrumentation
client := &http.Client{
    Transport: otelhttp.NewTransport(http.DefaultTransport),
}
```

### Creating Spans

```go
func processOrder(ctx context.Context, orderID string) error {
    tracer := otel.Tracer("order-service")
    ctx, span := tracer.Start(ctx, "processOrder")
    defer span.End()

    // Add attributes (NOT in span name — cardinality!)
    span.SetAttributes(
        attribute.String("order.id", orderID),
        attribute.String("order.type", "standard"),
    )

    // Record errors properly
    if err := validateOrder(ctx, orderID); err != nil {
        span.RecordError(err)
        span.SetStatus(codes.Error, err.Error())
        return fmt.Errorf("validate order: %w", err)
    }

    span.SetStatus(codes.Ok, "")
    return nil
}
```

### Log-Trace Correlation with otelslog

```go
// Bridge slog → OTel: auto-injects traceId/spanId into logs
import "go.opentelemetry.io/contrib/bridges/otelslog"

handler := otelslog.NewHandler("my-service")
logger := slog.New(handler)

// Now every log line includes trace context automatically
// {"msg": "processing", "traceId": "abc123", "spanId": "def456"}
```

---

## Level 3: Metrics & Alerting

### Prometheus Metrics

```go
meter := otel.Meter("my-service")

// Counter — monotonically increasing
requestCount, _ := meter.Int64Counter("http_requests_total",
    metric.WithDescription("Total HTTP requests"),
)

// Histogram — distribution of values
requestDuration, _ := meter.Float64Histogram("http_request_duration_seconds",
    metric.WithDescription("HTTP request duration"),
    metric.WithUnit("s"),
)

// Recording
func metricsMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)

        next.ServeHTTP(ww, r)

        attrs := metric.WithAttributes(
            attribute.String("method", r.Method),
            attribute.String("path", r.URL.Path),
            attribute.Int("status", ww.Status()),
        )
        requestCount.Add(r.Context(), 1, attrs)
        requestDuration.Record(r.Context(), time.Since(start).Seconds(), attrs)
    })
}
```

### Expose Prometheus Endpoint

```go
import "github.com/prometheus/client_golang/prometheus/promhttp"

// Serve metrics on separate port
go func() {
    mux := http.NewServeMux()
    mux.Handle("/metrics", promhttp.Handler())
    http.ListenAndServe(":9090", mux)
}()
```

### OTel Collector (Sidecar)

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317

processors:
  batch:
    timeout: 5s
  tail_sampling:
    decision_wait: 10s
    policies:
      - name: errors
        type: status_code
        status_code: {status_codes: [ERROR]}
      - name: slow
        type: latency
        latency: {threshold_ms: 500}

exporters:
  prometheus:
    endpoint: 0.0.0.0:8889
  otlp/jaeger:
    endpoint: jaeger:4317
    tls:
      insecure: true

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch, tail_sampling]
      exporters: [otlp/jaeger]
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [prometheus]
```

---

## Performance: Make It Fast

### Sampling Strategy

```go
// ParentBased + TraceIDRatioBased — standard production setup
sampler := sdktrace.ParentBased(
    sdktrace.TraceIDRatioBased(0.1),  // 10% of new traces
)
// Child spans inherit parent's sampling decision
// Result: complete traces, not fragmented
```

**~35% CPU overhead with full tracing.** Use sampling to control cost.

| Environment | Sampling Rate |
|------------|---------------|
| Development | 1.0 (100%) |
| Staging | 0.5 (50%) |
| Production | 0.01-0.1 (1-10%) |
| Production + tail sampling | Collector samples errors and slow requests |

### slog Performance

- Use typed helpers (`slog.String`, `slog.Int`) — they avoid `interface{}` allocations
- `Logger.Enabled()` before expensive log arguments
- JSONHandler slightly slower than zerolog/zap in extreme scenarios — benchmark to confirm need

---

## Observability: Know It's Working (Meta)

### The Three Pillars Connected

```
Logs (slog + otelslog bridge)
  ↕ traceId/spanId correlation
Traces (OpenTelemetry)
  ↕ exemplars
Metrics (Prometheus via OTel)
```

### Key Alerts

| Signal | Condition | Action |
|--------|-----------|--------|
| Error rate | >1% of requests | Check traces for error spans |
| Latency p99 | >500ms | Profile with pprof CPU |
| Log volume | 10x normal | Check for log storms (retry loops) |
| Goroutine count | Sustained growth | Check goroutine pprof |
| Connection pool wait | >100ms | Tune pool size (see mx-go-data) |

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Dynamic Values in Span Names
**You will be tempted to:** Use `tracer.Start(ctx, "getUser-"+userID)` for "better debugging."
**Why that fails:** Span names are low-cardinality identifiers. Dynamic values create millions of unique span names, exploding your tracing backend's storage and killing aggregation/filtering.
**The right way:** Fixed span name (`"getUser"`), dynamic values as attributes (`attribute.String("user.id", userID)`).

### Rule 2: Log to stdout/stderr, Not Files
**You will be tempted to:** Write logs to files for "persistence."
**Why that fails:** In containers (K8s, Docker), file logs are lost on restart, can't be aggregated, and fill disk. The runtime (Docker, K8s) already captures stdout/stderr and routes to your log aggregator.
**The right way:** Log to stdout (structured JSON). Let the runtime handle collection and routing.

### Rule 3: Never Log Sensitive Data
**You will be tempted to:** Log full request bodies or headers for "debugging."
**Why that fails:** Passwords, tokens, PII end up in your log aggregator — a compliance violation and security risk. Log retention means sensitive data persists for months.
**The right way:** `ReplaceAttr` in HandlerOptions to redact sensitive fields. Log request IDs and metadata, not payloads.

### Rule 4: RecordError AND SetStatus on Error Spans
**You will be tempted to:** Only call `span.RecordError(err)` when an error occurs.
**Why that fails:** `RecordError` adds an error event to the span, but doesn't mark the span as failed. Your tracing dashboard won't show it as an error. Error-rate dashboards stay green while errors pile up.
**The right way:** Always pair: `span.RecordError(err)` + `span.SetStatus(codes.Error, err.Error())`.

### Rule 5: Use Semantic Conventions for Attribute Names
**You will be tempted to:** Invent your own attribute names like `"request-method"` or `"http_code"`.
**Why that fails:** Non-standard names break cross-service correlation, dashboard templates, and automated analysis. Every OTel-compatible tool expects semantic convention names.
**The right way:** Use `semconv` package: `semconv.HTTPRequestMethodKey`, `semconv.HTTPResponseStatusCodeKey`, etc.
