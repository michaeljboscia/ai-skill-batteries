---
name: mx-go-http
description: Go HTTP — server setup with graceful shutdown, timeouts (Read/Write/Idle/Handler), chi router middleware chains, JSON encoding/decoding, custom http.Client with connection pooling, response body close patterns, CORS, error handling middleware, health checks.
---

# Go HTTP — Servers, Clients & Middleware for AI Coding Agents

**Load when building HTTP servers, REST APIs, or making HTTP requests in Go.**

## When to also load
- Core Go patterns → `mx-go-core`
- Concurrent request handling → `mx-go-concurrency`
- Distributed tracing → `mx-go-observability`
- Database-backed handlers → `mx-go-data`

---

## Level 1: Server Fundamentals

### Graceful Shutdown — The Only Correct Pattern

```go
func main() {
    srv := &http.Server{
        Addr:              ":8080",
        Handler:           newRouter(),
        ReadTimeout:       5 * time.Second,
        ReadHeaderTimeout: 2 * time.Second,
        WriteTimeout:      10 * time.Second,
        IdleTimeout:       60 * time.Second,
    }

    // Start server in goroutine
    go func() {
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            slog.Error("server failed", slog.String("error", err.Error()))
            os.Exit(1)
        }
    }()

    // Block until signal
    ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
    defer stop()
    <-ctx.Done()

    // Graceful shutdown with timeout
    shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
    defer cancel()

    slog.Info("shutting down server")
    if err := srv.Shutdown(shutdownCtx); err != nil {
        slog.Error("shutdown error", slog.String("error", err.Error()))
    }

    // Clean up resources AFTER server shutdown
    db.Close()
    slog.Info("server stopped")
}
```

### Timeout Configuration

| Timeout | Purpose | Recommended |
|---------|---------|-------------|
| `ReadTimeout` | Total time to read entire request | 5-10s |
| `ReadHeaderTimeout` | Time to read headers only | 1-3s |
| `WriteTimeout` | Time from end of request read to end of response write | 10-30s |
| `IdleTimeout` | Time between keep-alive requests | 30-120s |
| `http.TimeoutHandler` | Per-handler timeout (middleware) | Varies by endpoint |

```go
// Per-handler timeout for slow endpoints
slowHandler := http.TimeoutHandler(uploadHandler, 60*time.Second, "upload timed out")
```

### JSON Request/Response

```go
func handleCreateUser(w http.ResponseWriter, r *http.Request) {
    var req CreateUserRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        writeError(w, http.StatusBadRequest, "invalid JSON")
        return
    }

    user, err := svc.CreateUser(r.Context(), req)
    if err != nil {
        writeError(w, http.StatusInternalServerError, "create failed")
        return
    }

    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(http.StatusCreated)
    json.NewEncoder(w).Encode(user)
}

// Consistent error response
func writeError(w http.ResponseWriter, code int, msg string) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(code)
    json.NewEncoder(w).Encode(map[string]string{"error": msg})
}
```

---

## Level 2: Chi Router & Middleware

### Router Setup with Middleware Chain

```go
func newRouter() http.Handler {
    r := chi.NewRouter()

    // Global middleware — order matters
    r.Use(middleware.RequestID)       // first: assign ID
    r.Use(middleware.RealIP)          // before logging
    r.Use(requestLogger)              // structured logging
    r.Use(middleware.Recoverer)       // catch panics → 500
    r.Use(middleware.Timeout(30 * time.Second))

    // Health check (no auth)
    r.Get("/health", healthHandler)

    // API routes with auth
    r.Route("/api/v1", func(r chi.Router) {
        r.Use(authMiddleware)

        r.Route("/users", func(r chi.Router) {
            r.Get("/", listUsers)
            r.Post("/", createUser)
            r.Route("/{userID}", func(r chi.Router) {
                r.Get("/", getUser)
                r.Put("/", updateUser)
                r.Delete("/", deleteUser)
            })
        })
    })

    return r
}
```

### Custom Middleware Pattern

```go
// Chi middleware signature: func(next http.Handler) http.Handler
func authMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        token := r.Header.Get("Authorization")
        if token == "" {
            writeError(w, http.StatusUnauthorized, "missing token")
            return  // don't call next
        }

        userID, err := validateToken(token)
        if err != nil {
            writeError(w, http.StatusUnauthorized, "invalid token")
            return
        }

        ctx := context.WithValue(r.Context(), userIDKey, userID)
        next.ServeHTTP(w, r.WithContext(ctx))
    })
}
```

### Error Handling Handler Type

```go
// Custom handler type that returns errors
type appHandler func(w http.ResponseWriter, r *http.Request) error

func (fn appHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
    if err := fn(w, r); err != nil {
        var appErr *AppError
        if errors.As(err, &appErr) {
            writeError(w, appErr.Code, appErr.Message)
        } else {
            slog.Error("unhandled error",
                slog.String("error", err.Error()),
                slog.String("path", r.URL.Path),
            )
            writeError(w, http.StatusInternalServerError, "internal error")
        }
    }
}

// Usage in routes:
r.Method("GET", "/users/{id}", appHandler(getUser))
```

---

## Level 3: HTTP Client — Production Patterns

### Custom Client — Never Use DefaultClient

```go
// BAD — no timeouts, goroutine leak on slow servers
resp, err := http.Get("https://api.example.com/data")

// GOOD — custom client with explicit timeouts
client := &http.Client{
    Timeout: 10 * time.Second,
    Transport: &http.Transport{
        DialContext:           (&net.Dialer{Timeout: 5 * time.Second}).DialContext,
        TLSHandshakeTimeout:  5 * time.Second,
        ResponseHeaderTimeout: 5 * time.Second,
        MaxIdleConnsPerHost:   20,  // default 2 is way too low
        IdleConnTimeout:       90 * time.Second,
    },
}
```

### Response Body — Close Correctly

```go
// BAD — defer before error check, panics if resp is nil
resp, err := client.Get(url)
defer resp.Body.Close()
if err != nil { return err }

// GOOD — check error first, then defer close
resp, err := client.Get(url)
if err != nil {
    return fmt.Errorf("GET %s: %w", url, err)
}
defer resp.Body.Close()

// Read body
body, err := io.ReadAll(resp.Body)  // OK for small responses (<1MB)

// For large responses or when you don't need the body:
io.Copy(io.Discard, resp.Body)  // drain for connection reuse
```

### Defer in Loops — Extract to Function

```go
// BAD — defer accumulates, bodies not closed until function returns
for _, url := range urls {
    resp, err := client.Get(url)
    if err != nil { continue }
    defer resp.Body.Close()  // won't close until outer function returns!
    // ...
}

// GOOD — extract to function so defer fires per iteration
for _, url := range urls {
    if err := fetchOne(client, url); err != nil {
        slog.Warn("fetch failed", slog.String("url", url), slog.String("error", err.Error()))
    }
}

func fetchOne(client *http.Client, url string) error {
    resp, err := client.Get(url)
    if err != nil {
        return fmt.Errorf("GET %s: %w", url, err)
    }
    defer resp.Body.Close()
    // process response...
    return nil
}
```

---

## Performance: Make It Fast

### Connection Pooling

```go
// Reuse client instances — create once, share everywhere
// Creating per-request kills connection pooling
type APIClient struct {
    client *http.Client  // shared, long-lived
    base   string
}

func NewAPIClient(base string) *APIClient {
    return &APIClient{
        client: &http.Client{
            Timeout: 10 * time.Second,
            Transport: &http.Transport{
                MaxIdleConnsPerHost: 50,  // match expected concurrency
                IdleConnTimeout:    90 * time.Second,
            },
        },
        base: base,
    }
}
```

### Server Timeout Tuning for K8s

```
K8s terminationGracePeriodSeconds: 30s (default)
├── Server shutdown timeout: 15s (leave margin)
│   ├── In-flight requests complete
│   └── Idle connections close
└── Resource cleanup: remaining time
```

---

## Observability: Know It's Working

### Request Logging Middleware

```go
func requestLogger(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)

        next.ServeHTTP(ww, r)

        slog.Info("request",
            slog.String("method", r.Method),
            slog.String("path", r.URL.Path),
            slog.Int("status", ww.Status()),
            slog.Duration("latency", time.Since(start)),
            slog.Int("bytes", ww.BytesWritten()),
            slog.String("request_id", middleware.GetReqID(r.Context())),
        )
    })
}
```

### Health Check Endpoint

```go
func healthHandler(w http.ResponseWriter, r *http.Request) {
    // Check dependencies
    if err := db.PingContext(r.Context()); err != nil {
        w.WriteHeader(http.StatusServiceUnavailable)
        json.NewEncoder(w).Encode(map[string]string{"status": "unhealthy", "db": err.Error()})
        return
    }
    w.WriteHeader(http.StatusOK)
    json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}
```

See `mx-go-observability` for OpenTelemetry HTTP instrumentation with `otelhttp`.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Use http.DefaultClient
**You will be tempted to:** Use `http.Get()` or `http.Post()` for "quick" requests.
**Why that fails:** DefaultClient has zero timeouts. A slow or unresponsive server blocks the goroutine forever. In production, this causes goroutine leaks that compound until OOM.
**The right way:** Always create a custom `&http.Client{Timeout: 10*time.Second}` with explicit Transport settings.

### Rule 2: Check Error Before Defer Close
**You will be tempted to:** Write `defer resp.Body.Close()` on the line right after the request.
**Why that fails:** If the request errors, `resp` is nil. `defer resp.Body.Close()` panics with nil pointer dereference.
**The right way:** `if err != nil { return err }` FIRST, then `defer resp.Body.Close()`.

### Rule 3: Set All Four Server Timeouts
**You will be tempted to:** Only set `ReadTimeout` and `WriteTimeout`, or skip timeouts entirely.
**Why that fails:** Missing `ReadHeaderTimeout` allows Slowloris attacks. Missing `IdleTimeout` wastes connections. A zero-timeout server is a DoS target.
**The right way:** Set `ReadTimeout`, `ReadHeaderTimeout`, `WriteTimeout`, and `IdleTimeout` on every `http.Server`.

### Rule 4: Never Expose Internal Errors to Clients
**You will be tempted to:** Return `err.Error()` in the JSON response for "debugging."
**Why that fails:** Internal errors leak implementation details — database names, file paths, stack traces. This is an information disclosure vulnerability.
**The right way:** Log the full error server-side. Return a generic message to the client. Use error codes for client-side handling.

### Rule 5: Drain Response Body for Connection Reuse
**You will be tempted to:** Just close the body without reading it.
**Why that fails:** HTTP keep-alive requires the body to be fully read. Closing without draining prevents connection reuse, forcing new TCP+TLS handshakes for every request.
**The right way:** `io.Copy(io.Discard, resp.Body)` before close if you don't need the content.
