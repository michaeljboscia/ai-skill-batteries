---
name: mx-go-core
description: Go fundamentals — error handling with %w wrapping, consumer-side interfaces, struct composition, functional options, generics, naming conventions, module layout, zero values, nil safety, receiver methods. Use for ANY Go code.
---

# Go Core Fundamentals — Idiomatic Patterns for AI Coding Agents

**Load this skill whenever writing Go code. It covers the patterns every Go file needs.**

## When to also load
- Goroutines/channels/sync → `mx-go-concurrency`
- HTTP servers/clients → `mx-go-http`
- Subprocesses/CLI → `mx-go-cli`
- Database/SQL → `mx-go-data`
- Tests → `mx-go-testing`
- Build/deploy → `mx-go-project`
- Profiling/benchmarks → `mx-go-perf`
- Logging/tracing/metrics → `mx-go-observability`
- NATS/Temporal/gRPC → `mx-go-services`

---

## Level 1: Patterns That Always Work

### Error Handling — Always Wrap with %w

```go
// BAD — chain breaks, errors.Is/As won't work
if err != nil {
    return fmt.Errorf("failed to open file: %v", err)
}

// GOOD — preserves error chain
if err != nil {
    return fmt.Errorf("open config %s: %w", path, err)
}
```

**Rules:**
- Always `%w`, never `%v` for error wrapping
- Error messages: lowercase, no trailing punctuation, add context
- Handle errors ONCE — log OR return, never both
- Sentinel errors sparingly — they become public API. Prefix with `Err`
- `errors.Is` for sentinel matching, `errors.As` for type extraction

### Zero Values — Use Them

Go initializes all variables to their zero value. Design structs so zero value is useful.

```go
// BAD — constructor just to set defaults that match zero values
func NewBuffer() *Buffer {
    return &Buffer{offset: 0, closed: false}
}

// GOOD — zero value is ready to use (like bytes.Buffer, sync.Mutex)
var buf bytes.Buffer
buf.WriteString("hello")
```

### Nil Safety

```go
// BAD — nil map assignment panics
var m map[string]int
m["key"] = 1  // panic: assignment to entry in nil map

// GOOD — always initialize maps
m := make(map[string]int)
m["key"] = 1

// GOOD — nil slice is safe (append works on nil)
var s []string
s = append(s, "hello")  // works fine
```

### Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Package | lowercase, single word, no underscores | `http`, `json`, `user` |
| Exported | PascalCase | `ParseConfig`, `ErrNotFound` |
| Unexported | camelCase | `parseLine`, `errInternal` |
| Receiver | 1-2 letter abbreviation | `(s *Server)`, `(c *Client)` |
| Acronym | consistent caps | `userID`, `httpURL`, `apiKey` |
| Constants | MixedCaps (NOT SCREAMING_SNAKE) | `maxRetries`, `DefaultTimeout` |
| Interface | -er suffix for single-method | `Reader`, `Writer`, `Stringer` |

**Never use `self`, `this`, or `me` as receiver names.**

### Defer — Correct Placement

```go
// BAD — defer before error check, panics on nil resp
resp, err := http.Get(url)
defer resp.Body.Close()
if err != nil { return err }

// GOOD — check error first, then defer
resp, err := http.Get(url)
if err != nil {
    return fmt.Errorf("GET %s: %w", url, err)
}
defer resp.Body.Close()
```

---

## Level 2: Design Patterns

### Consumer-Side Interfaces

```go
// BAD — interface defined by the producer (Java-style)
// in package user:
type UserService interface {
    GetByID(id string) (*User, error)
    Create(u *User) error
}
type service struct { db *sql.DB }
func (s *service) GetByID(id string) (*User, error) { ... }

// GOOD — interface defined by the consumer
// in package order:
type UserGetter interface {  // only what THIS consumer needs
    GetByID(id string) (*user.User, error)
}
type OrderService struct {
    users UserGetter  // accepts the interface
}
```

**Decision tree:**

| Need | Use |
|------|-----|
| Different behavior behind same contract | Interface |
| Same logic across different types | Generics |
| 1-2 methods the consumer needs | Interface (small, consumer-side) |
| Rich type with many methods | Return the struct, let consumer define interface |

### Functional Options Pattern

```go
type Server struct {
    addr    string
    timeout time.Duration
    logger  *slog.Logger
}

type Option func(*Server)

func WithTimeout(d time.Duration) Option {
    return func(s *Server) { s.timeout = d }
}

func WithLogger(l *slog.Logger) Option {
    return func(s *Server) { s.logger = l }
}

func NewServer(addr string, opts ...Option) *Server {
    s := &Server{
        addr:    addr,
        timeout: 30 * time.Second,  // sensible default
        logger:  slog.Default(),
    }
    for _, opt := range opts {
        opt(s)
    }
    return s
}

// Usage:
srv := NewServer(":8080", WithTimeout(10*time.Second), WithLogger(myLogger))
```

**When to use functional options vs config struct:**

| Scenario | Pattern |
|----------|---------|
| Many optional params, evolving API | Functional options |
| Few params, stable API | Config struct |
| Must validate combinations | Config struct with Validate() |
| Library consumed by external teams | Functional options (additive) |

### Struct Embedding — Composition

```go
// Embedding promotes methods to outer struct
type Logger struct {
    *slog.Logger
}

// Outer struct gets all slog.Logger methods automatically
// But watch for: method name conflicts, nil embedded pointer panics

// BAD — embedding for data reuse only
type Request struct {
    Config  // embeds entire Config — leaks fields to API
}

// GOOD — embed for behavior (is-a with methods)
type TimeoutReader struct {
    io.Reader              // promotes Read method
    timeout time.Duration
}
```

---

## Level 3: Advanced Patterns

### Generics — When and How

```go
// Generic function — same logic, different types
func Map[T, U any](s []T, f func(T) U) []U {
    result := make([]U, len(s))
    for i, v := range s {
        result[i] = f(v)
    }
    return result
}

// Type constraints
func Max[T interface{ ~int | ~float64 | ~string }](a, b T) T {
    if a > b { return a }
    return b
}

// Use cmp.Ordered for numeric/string comparison (Go 1.21+)
func Max[T cmp.Ordered](a, b T) T {
    if a > b { return a }
    return b
}
```

**Decision: generics vs interface vs concrete:**

| Signal | Use |
|--------|-----|
| Container types (Stack, Queue, Set) | Generics |
| Algorithm over ordered/comparable | Generics with constraints |
| Polymorphic behavior | Interface |
| Single concrete type | Concrete (don't abstract) |
| "If you only call a method, use an interface" | Interface |

### Module Organization

```
project/
├── cmd/
│   └── myapp/
│       └── main.go          # thin: wire deps + start
├── internal/
│   ├── server/              # compiler-enforced private
│   │   └── server.go
│   └── store/
│       └── store.go
├── go.mod
└── go.sum
```

**Rules:**
- `cmd/`: one subdir per binary, `main` is thin (wire + start)
- `internal/`: compiler-enforced privacy — cannot be imported externally
- Start flat (main.go + go.mod), add structure as complexity grows
- Every directory = one package. All `.go` files in a dir share the package name
- Tests live next to code (`_test.go` in same directory)
- Avoid `pkg/` unless you genuinely have a reusable public library
- Never `util`, `common`, `helpers` — these are naming failures

---

## Performance: Make It Fast

### Slice Preallocation

```go
// BAD — grows dynamically, multiple allocations
var result []string
for _, item := range items {
    result = append(result, item.Name)
}

// GOOD — preallocate known capacity
result := make([]string, 0, len(items))
for _, item := range items {
    result = append(result, item.Name)
}
```

### strings.Builder for Concatenation

```go
// BAD — O(n^2) string concatenation in loops
s := ""
for _, part := range parts {
    s += part + ","
}

// GOOD — O(n) with Builder
var b strings.Builder
b.Grow(estimatedSize)  // optional: prevent reallocation
for _, part := range parts {
    b.WriteString(part)
    b.WriteByte(',')
}
result := b.String()
```

### Stack vs Heap — Keep Allocations Local

```go
// BAD — escapes to heap (pointer returned)
func newConfig() *Config {
    c := Config{Timeout: 30}
    return &c  // escapes
}

// GOOD — stays on stack if caller doesn't store pointer
func newConfig() Config {
    return Config{Timeout: 30}  // value, no escape
}
```

Check escape analysis: `go build -gcflags "-m" ./...`

---

## Observability: Know It's Working

### Structured Logging with slog

```go
// Setup (production)
logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
    Level: slog.LevelInfo,
}))
slog.SetDefault(logger)

// Usage — typed attributes avoid allocations
slog.Info("request handled",
    slog.String("method", r.Method),
    slog.Int("status", code),
    slog.Duration("latency", elapsed),
)

// Child logger with context
reqLogger := logger.With(
    slog.String("request_id", reqID),
    slog.String("user_id", userID),
)
reqLogger.Info("processing order", slog.String("order_id", orderID))
```

See `mx-go-observability` for full slog configuration, OpenTelemetry integration, and metrics.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Always %w, Never %v for Error Wrapping
**You will be tempted to:** Use `%v` because "it still shows the error message."
**Why that fails:** `%v` converts the error to a string. `errors.Is()` and `errors.As()` stop working. Callers can't match sentinel errors or extract typed errors up the chain.
**The right way:** `fmt.Errorf("context: %w", err)` — always.

### Rule 2: Interfaces Belong to the Consumer
**You will be tempted to:** Define a `Service` interface next to the implementation, Java-style.
**Why that fails:** Producer-side interfaces force every consumer to depend on the full interface, even if they only need one method. Changes to the interface break all consumers.
**The right way:** Return the concrete struct. Let each consumer define a 1-2 method interface for what IT needs.

### Rule 3: Never Use self/this as Receiver Name
**You will be tempted to:** Use `self` or `this` because it's familiar from Python/JS/Rust.
**Why that fails:** Violates Go convention. Every Go developer will flag it in review. The convention is a 1-2 letter abbreviation of the type name.
**The right way:** `(s *Server)`, `(c *Client)`, `(h *Handler)`.

### Rule 4: Don't Return Interfaces
**You will be tempted to:** Return an interface "for flexibility" or "to allow mocking."
**Why that fails:** Returning an interface is preemptive abstraction. It limits the caller — they can only use methods in the interface, even if the concrete type has more. It also prevents adding methods later without breaking the interface.
**The right way:** "Accept interfaces, return structs." Let the caller define the interface they need.

### Rule 5: Initialize Maps Before Use
**You will be tempted to:** Declare `var m map[K]V` and assign to it directly.
**Why that fails:** Assignment to a nil map panics at runtime. Unlike slices (where `append` handles nil), maps require explicit initialization.
**The right way:** `m := make(map[K]V)` or `m := map[K]V{}`. Always.
