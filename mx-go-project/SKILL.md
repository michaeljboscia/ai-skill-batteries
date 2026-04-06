---
name: mx-go-project
description: Go project setup — golangci-lint configuration, multi-stage Docker builds with scratch/distroless, CGO_ENABLED=0 static binaries, ldflags for version injection, Makefile targets, CI pipeline with race detection, go.work workspaces, dependency management, .gitignore patterns.
---

# Go Project — Build, Lint & Deploy for AI Coding Agents

**Load when setting up a Go project, configuring CI, building Docker images, or managing dependencies.**

## When to also load
- Core Go patterns → `mx-go-core`
- Test configuration → `mx-go-testing`
- Profiling build performance → `mx-go-perf`

---

## Level 1: Project Scaffold

### Minimal Go Project

```
myapp/
├── cmd/
│   └── myapp/
│       └── main.go
├── internal/
│   ├── server/
│   │   └── server.go
│   └── store/
│       └── store.go
├── go.mod
├── go.sum
├── .golangci.yml
├── Makefile
├── Dockerfile
└── .gitignore
```

### go.mod Initialization

```bash
go mod init github.com/org/myapp
```

### .gitignore

```gitignore
# Binaries
/bin/
*.exe
*.exe~
*.dll
*.so
*.dylib

# Test
*.test
coverage.out

# Go workspace
go.work
go.work.sum

# IDE
.idea/
.vscode/
*.swp

# OS
.DS_Store
Thumbs.db

# Environment
.env
.env.local
```

### Version Injection with ldflags

```go
// main.go
var (
    version = "dev"
    commit  = "none"
    date    = "unknown"
)

func main() {
    slog.Info("starting",
        slog.String("version", version),
        slog.String("commit", commit),
    )
}
```

```bash
# Build with version info
go build -ldflags="-X main.version=1.2.3 -X main.commit=$(git rev-parse --short HEAD) -X main.date=$(date -u +%Y-%m-%dT%H:%M:%SZ)" ./cmd/myapp
```

---

## Level 2: Linting & CI

### golangci-lint Configuration

```yaml
# .golangci.yml
version: "2"
linters:
  enable:
    - errcheck        # unchecked errors
    - govet           # suspicious constructs
    - staticcheck     # advanced static analysis
    - unused          # unused code
    - gosimple        # simplifications
    - ineffassign     # ineffective assignments
    - gocritic        # opinionated checks
    - revive          # extensible linter
    - misspell        # spelling
    - nolintlint      # bad nolint directives
    - exportloopref   # loop variable capture (pre-1.22)
    - bodyclose       # unclosed HTTP response bodies
    - errname         # error naming conventions
    - errorlint       # error wrapping best practices

issues:
  exclude-rules:
    - path: _test\.go
      linters:
        - errcheck     # test error checking is looser
  max-issues-per-linter: 50

formatters:
  enable:
    - gofmt
    - goimports

run:
  timeout: 5m
```

### Makefile

```makefile
.PHONY: build test lint docker clean

APP_NAME := myapp
VERSION := $(shell git describe --tags --always --dirty)
COMMIT := $(shell git rev-parse --short HEAD)
LDFLAGS := -ldflags="-X main.version=$(VERSION) -X main.commit=$(COMMIT) -w -s"

build:
	CGO_ENABLED=0 go build $(LDFLAGS) -o bin/$(APP_NAME) ./cmd/$(APP_NAME)

test:
	go test -v -race -coverprofile=coverage.out ./...

lint:
	golangci-lint run ./...

docker:
	docker build -t $(APP_NAME):$(VERSION) .

clean:
	rm -rf bin/ coverage.out
```

### CI Pipeline (GitHub Actions)

```yaml
name: CI
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version-file: go.mod

      - name: Lint
        uses: golangci/golangci-lint-action@v6
        with:
          version: v1.62  # pin version for reproducibility

      - name: Test
        run: go test -v -race -coverprofile=coverage.out ./...

      - name: Build
        run: CGO_ENABLED=0 go build -o /dev/null ./cmd/...
```

---

## Level 3: Docker & Deployment

### Multi-Stage Dockerfile

```dockerfile
# Stage 1: Build
FROM golang:1.23-alpine AS builder

WORKDIR /app

# Cache dependencies
COPY go.mod go.sum ./
RUN go mod download

# Build static binary
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-w -s" \
    -o /app/server \
    ./cmd/server

# Stage 2: Runtime
FROM gcr.io/distroless/static:nonroot

COPY --from=builder /app/server /server

USER nonroot:nonroot
EXPOSE 8080

ENTRYPOINT ["/server"]
```

### Base Image Decision

| Image | Size | Use When |
|-------|------|----------|
| `scratch` | ~0 MB | Minimal, no shell, no CA certs |
| `distroless/static` | ~2 MB | Includes CA certs + passwd (HTTPS works) |
| `distroless/static:nonroot` | ~2 MB | Same + runs as non-root by default |
| `alpine` | ~7 MB | Need shell for debugging |

**For any app making HTTPS calls: use `distroless/static`, not `scratch`.** Scratch has no CA certificates.

### Static Binary Requirements

```dockerfile
# CGO_ENABLED=0 — pure Go, no C dependencies, static binary
# Required for scratch/distroless (no libc)
RUN CGO_ENABLED=0 go build -o /app/server ./cmd/server

# -ldflags="-w -s" — strip debug info and symbol table
# Reduces binary size by ~30%
```

### Go Workspaces (Multi-Module)

```bash
# go.work for local multi-module development
go work init
go work use ./service-a
go work use ./service-b
go work use ./shared-lib
```

```
# go.work
go 1.23

use (
    ./service-a
    ./service-b
    ./shared-lib
)
```

**Don't commit go.work to the repo** — it's for local development. Each module should work independently.

---

## Performance: Make It Fast

### Build Speed

| Technique | Impact | How |
|-----------|--------|-----|
| Docker layer caching | Skip `go mod download` on unchanged deps | COPY go.mod/go.sum first |
| Go build cache | Skip recompilation | Mount cache in Docker or CI |
| `-ldflags="-w -s"` | 30% smaller binary | Strip debug symbols |
| CGO_ENABLED=0 | Faster builds, no C toolchain | Static Go binary |

```dockerfile
# Mount Go build cache in Docker
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    CGO_ENABLED=0 go build -o /app/server ./cmd/server
```

### Dependency Management

```bash
# Tidy unused deps
go mod tidy

# Check for known vulnerabilities
go install golang.org/x/vuln/cmd/govulncheck@latest
govulncheck ./...
```

---

## Observability: Know It's Working

### Build Info at Runtime

```go
import "runtime/debug"

func printBuildInfo() {
    info, ok := debug.ReadBuildInfo()
    if !ok { return }

    slog.Info("build info",
        slog.String("go_version", info.GoVersion),
        slog.String("path", info.Path),
    )
    for _, s := range info.Settings {
        if s.Key == "vcs.revision" || s.Key == "vcs.time" {
            slog.Info("vcs", slog.String(s.Key, s.Value))
        }
    }
}
```

### Docker Health Check

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD ["/server", "-health-check"]
```

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: CGO_ENABLED=0 for Docker
**You will be tempted to:** Skip `CGO_ENABLED=0` because "it builds fine without it."
**Why that fails:** Without it, the binary links against libc. `scratch` and `distroless` don't have libc. The binary crashes at runtime with "not found" — a confusing error that looks like a missing file.
**The right way:** `CGO_ENABLED=0` for every binary that runs in scratch/distroless.

### Rule 2: Pin golangci-lint Version in CI
**You will be tempted to:** Use `latest` for golangci-lint in CI.
**Why that fails:** A new linter version adds rules that fail your build. You're debugging CI failures caused by tool upgrades, not code changes. Builds become non-reproducible.
**The right way:** Pin the exact version. Update deliberately, fix any new warnings, then commit the version bump.

### Rule 3: Copy go.mod/go.sum Before Source Code in Dockerfile
**You will be tempted to:** `COPY . .` and then `go mod download` in one step.
**Why that fails:** Every source code change invalidates the Docker layer cache. `go mod download` runs on every build, even when dependencies haven't changed. Builds take minutes instead of seconds.
**The right way:** `COPY go.mod go.sum ./` → `RUN go mod download` → `COPY . .` → `RUN go build`.

### Rule 4: distroless Over scratch for HTTPS
**You will be tempted to:** Use `scratch` because "it's the smallest."
**Why that fails:** `scratch` has no CA certificates. Any HTTPS request fails with `x509: certificate signed by unknown authority`. You'd need to manually copy `/etc/ssl/certs/ca-certificates.crt`.
**The right way:** `gcr.io/distroless/static:nonroot` — CA certs included, runs as non-root, ~2MB.
