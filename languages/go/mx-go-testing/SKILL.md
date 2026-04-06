---
name: mx-go-testing
description: Go testing — table-driven tests with t.Run, t.Parallel, t.Helper, testify assert vs require, testcontainers for integration tests, native fuzzing with FuzzXxx, golden files, test fixtures, TestMain setup/teardown, race detection in CI, benchmark patterns.
---

# Go Testing — Test Patterns for AI Coding Agents

**Load when writing tests, benchmarks, or fuzzing targets in Go.**

## When to also load
- Core Go patterns → `mx-go-core`
- Race detection details → `mx-go-concurrency`
- Benchmarking/profiling → `mx-go-perf`
- Integration test containers → `mx-go-data` (for database tests)

---

## Level 1: Table-Driven Tests

### The Standard Pattern

```go
func TestParseConfig(t *testing.T) {
    tests := []struct {
        name    string
        input   string
        want    Config
        wantErr bool
    }{
        {
            name:  "valid yaml",
            input: "port: 8080\nhost: localhost",
            want:  Config{Port: 8080, Host: "localhost"},
        },
        {
            name:    "invalid yaml",
            input:   ":::invalid",
            wantErr: true,
        },
        {
            name:  "empty defaults",
            input: "",
            want:  Config{Port: 3000, Host: "0.0.0.0"},  // defaults
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got, err := ParseConfig([]byte(tt.input))
            if tt.wantErr {
                require.Error(t, err)
                return
            }
            require.NoError(t, err)
            assert.Equal(t, tt.want, got)
        })
    }
}
```

### Parallel Tests

```go
func TestFetchUser(t *testing.T) {
    tests := map[string]struct {  // map for unordered, better IDE nav
        id      string
        wantErr bool
    }{
        "existing user":     {id: "user-1"},
        "nonexistent user":  {id: "missing", wantErr: true},
        "empty id":          {id: "", wantErr: true},
    }

    for name, tt := range tests {
        t.Run(name, func(t *testing.T) {
            t.Parallel()  // safe when tests don't share mutable state
            got, err := svc.FetchUser(context.Background(), tt.id)
            if tt.wantErr {
                require.Error(t, err)
                return
            }
            require.NoError(t, err)
            assert.NotEmpty(t, got.Name)
        })
    }
}
```

### Test Helpers — Always Use t.Helper()

```go
func assertJSONEqual(t *testing.T, expected, actual string) {
    t.Helper()  // error points to caller, not this function
    var e, a any
    require.NoError(t, json.Unmarshal([]byte(expected), &e))
    require.NoError(t, json.Unmarshal([]byte(actual), &a))
    assert.Equal(t, e, a)
}
```

### testify — assert vs require

| Function | On Failure | Use When |
|----------|-----------|----------|
| `assert.Equal` | Test continues | Non-critical check, want to see all failures |
| `require.Equal` | Test stops immediately | Precondition — further checks would panic/mislead |
| `require.NoError` | Test stops | Error check before using the result |
| `assert.ElementsMatch` | Test continues | Unordered slice comparison |

```go
// GOOD — require for preconditions, assert for validations
func TestCreateOrder(t *testing.T) {
    order, err := svc.Create(ctx, req)
    require.NoError(t, err)        // stop if error — order is nil
    require.NotNil(t, order)       // stop if nil — fields would panic

    assert.Equal(t, "pending", order.Status)  // continue on failure
    assert.Greater(t, order.Total, 0)         // see all failures
    assert.WithinDuration(t, time.Now(), order.CreatedAt, time.Second)
}
```

---

## Level 2: Integration Tests

### TestMain for Setup/Teardown

```go
var testDB *pgxpool.Pool

func TestMain(m *testing.M) {
    // Setup
    ctx := context.Background()
    container, err := postgres.Run(ctx, "postgres:16",
        postgres.WithDatabase("testdb"),
        testcontainers.WithWaitStrategy(
            wait.ForListeningPort("5432/tcp").WithStartupTimeout(30*time.Second),
        ),
    )
    if err != nil {
        log.Fatal(err)
    }

    connStr, err := container.ConnectionString(ctx, "sslmode=disable")
    if err != nil {
        log.Fatal(err)
    }

    testDB, err = pgxpool.New(ctx, connStr)
    if err != nil {
        log.Fatal(err)
    }

    // Run migrations
    runMigrations(connStr)

    // Run tests
    code := m.Run()

    // Teardown
    testDB.Close()
    container.Terminate(ctx)
    os.Exit(code)
}
```

### State Reset Between Tests

```go
func cleanDB(t *testing.T) {
    t.Helper()
    _, err := testDB.Exec(context.Background(),
        "TRUNCATE users, orders, payments RESTART IDENTITY CASCADE")
    require.NoError(t, err)
}

func TestUserCRUD(t *testing.T) {
    cleanDB(t)  // fresh state for each test
    // ...
}
```

### Build Tags for Integration Tests

```go
//go:build integration

package store_test

// Only runs with: go test -tags integration ./...
func TestDatabaseIntegration(t *testing.T) {
    // ...
}
```

---

## Level 3: Fuzzing and Advanced Patterns

### Native Fuzzing (Go 1.18+)

```go
func FuzzParseJSON(f *testing.F) {
    // Seed corpus
    f.Add([]byte(`{"name": "test"}`))
    f.Add([]byte(`{}`))
    f.Add([]byte(`[]`))
    f.Add([]byte(``))

    f.Fuzz(func(t *testing.T, data []byte) {
        var result map[string]any
        err := json.Unmarshal(data, &result)
        if err != nil {
            return  // invalid input is fine
        }

        // Round-trip: if it parses, it should re-encode
        encoded, err := json.Marshal(result)
        require.NoError(t, err)

        var result2 map[string]any
        require.NoError(t, json.Unmarshal(encoded, &result2))
    })
}
```

```bash
# Run fuzzer
go test -fuzz=FuzzParseJSON -fuzztime=30s ./...

# Saved failures become regression tests automatically
```

### Golden Files

```go
func TestRenderTemplate(t *testing.T) {
    got := renderTemplate(data)

    golden := filepath.Join("testdata", t.Name()+".golden")
    if *update {  // -update flag
        os.WriteFile(golden, []byte(got), 0644)
    }

    expected, err := os.ReadFile(golden)
    require.NoError(t, err)
    assert.Equal(t, string(expected), got)
}
```

### HTTP Handler Testing

```go
func TestGetUser(t *testing.T) {
    // Setup
    svc := &mockUserService{
        users: map[string]*User{"1": {ID: "1", Name: "Alice"}},
    }
    handler := NewHandler(svc)

    // Create request
    req := httptest.NewRequest("GET", "/users/1", nil)
    rctx := chi.NewRouteContext()
    rctx.URLParams.Add("userID", "1")
    req = req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))

    // Record response
    rec := httptest.NewRecorder()
    handler.GetUser(rec, req)

    // Verify
    require.Equal(t, http.StatusOK, rec.Code)

    var got User
    require.NoError(t, json.NewDecoder(rec.Body).Decode(&got))
    assert.Equal(t, "Alice", got.Name)
}
```

---

## Performance: Make It Fast

### Test Parallelism

```bash
# Run tests with race detector (mandatory in CI)
go test -race -count=1 ./...

# Parallel packages (default: GOMAXPROCS)
go test -parallel 8 ./...

# Skip slow tests in development
go test -short ./...
```

```go
func TestSlowIntegration(t *testing.T) {
    if testing.Short() {
        t.Skip("skipping integration test in short mode")
    }
    // ...
}
```

### Benchmark Pattern

```go
func BenchmarkParseConfig(b *testing.B) {
    data := loadTestData(b)
    b.ResetTimer()  // exclude setup from timing

    for b.Loop() {  // Go 1.24+ (replaces for i := 0; i < b.N; i++)
        ParseConfig(data)
    }
}

// Run: go test -bench=BenchmarkParseConfig -benchmem ./...
// Output: ns/op, B/op, allocs/op
```

---

## Observability: Know It's Working

### CI Configuration

```yaml
# GitHub Actions
- name: Test
  run: go test -v -race -coverprofile=coverage.out ./...

- name: Coverage
  run: go tool cover -func=coverage.out
```

### Test Coverage Targets

| Type | Target | How |
|------|--------|-----|
| Unit tests | >80% line coverage | `go test -cover` |
| Integration | Key paths tested | testcontainers |
| Race detection | Zero races | `go test -race` in CI |
| Fuzz | Corpus growing | Periodic fuzz runs |

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Always Run -race in CI
**You will be tempted to:** Skip `-race` because "tests are slow enough already."
**Why that fails:** Data races are the #1 source of non-deterministic production bugs in Go. They're invisible without the race detector. A test suite that passes without `-race` proves nothing about concurrency safety.
**The right way:** `go test -race ./...` in every CI run. Accept the 2-20x slowdown.

### Rule 2: require for Preconditions, assert for Checks
**You will be tempted to:** Use `assert` everywhere because "tests should show all failures."
**Why that fails:** If `assert.NoError(t, err)` continues and you then access `result.Name`, you get a nil pointer panic — which crashes the entire test binary, not just this test.
**The right way:** `require.NoError` and `require.NotNil` for anything that would cause a panic if wrong. `assert` for the actual value checks.

### Rule 3: t.Helper() in Every Test Helper
**You will be tempted to:** Skip `t.Helper()` because "it's just a small function."
**Why that fails:** Without it, test failures report the line inside the helper function, not where the helper was called. Debugging becomes "which test called this helper?" instead of seeing the actual failing line.
**The right way:** First line of every test helper function is `t.Helper()`.

### Rule 4: Clean State Between Integration Tests
**You will be tempted to:** Let tests share database state because "the order doesn't matter."
**Why that fails:** Test isolation is a lie without cleanup. Test A inserts data that makes Test B pass/fail differently. Reordering tests produces different results. Flaky tests destroy CI trust.
**The right way:** TRUNCATE tables or reset state before each test. Start testcontainers once in TestMain, reset between tests.

### Rule 5: Fuzz Targets Must Not Use Global State
**You will be tempted to:** Access package-level variables from fuzz targets.
**Why that fails:** Fuzz targets run in parallel across multiple workers. Shared mutable state causes data races. The race detector will catch this, but only after wasted debugging time.
**The right way:** Fuzz functions should be pure — input in, assertion out, no side effects.
