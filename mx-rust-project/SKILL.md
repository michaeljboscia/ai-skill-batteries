---
name: mx-rust-project
description: Use when setting up, building, deploying, or maintaining a Rust project. Covers Cargo workspaces, feature flags, build speed optimization (sccache, mold, Cranelift), Clippy configuration, supply chain security (cargo-audit, cargo-vet, cargo-deny), cross-compilation with musl, Docker containerization, and binary size optimization. Also use when the user mentions 'Cargo.toml', 'workspace', 'feature flag', 'build speed', 'sccache', 'mold', 'linker', 'clippy', 'lint', 'cargo audit', 'cargo deny', 'security', 'supply chain', 'cross-compile', 'musl', 'Docker', 'container', 'binary size', 'release profile', 'CI', or 'deployment'.
---

# Rust Project & Build — Workspace, CI, Security & Deployment Patterns

**Loads when setting up a new project, optimizing builds, configuring CI/CD, or deploying.**

## When to also load
- Language fundamentals → `mx-rust-core`
- Testing setup → `mx-rust-testing`

---

## Level 1: Project Setup (Beginner)

### Cargo Workspace Structure

```
workspace_root/
├── Cargo.toml          ← Virtual workspace manifest
├── Cargo.lock          ← Shared across all crates
├── crates/
│   ├── daemon-core/    ← Business logic, domain models
│   ├── daemon-infra/   ← Database, external APIs
│   ├── daemon-api/     ← HTTP/WebSocket server
│   └── daemon-cli/     ← Binary entrypoint
```

```toml
# workspace_root/Cargo.toml
[workspace]
resolver = "3"           # MSRV-aware resolution (Rust 2024 edition)
members = ["crates/*"]

[workspace.dependencies]
tokio = { version = "1.39", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
anyhow = "1.0"
tracing = "0.1"
```

Child crates inherit versions:
```toml
# crates/daemon-api/Cargo.toml
[dependencies]
tokio = { workspace = true }
serde = { workspace = true }
daemon-core = { path = "../daemon-core" }
```

**Split crates when:** compilation is slow, domains are independent, or you need a proc-macro crate.

### Release Profile

```toml
[profile.release]
opt-level = "z"       # Optimize for binary size
lto = "fat"           # Cross-crate optimization
codegen-units = 1     # Single compilation unit (slower build, smaller binary)
panic = "abort"       # No unwinding (smaller binary)
strip = true          # Remove debug symbols
```

### Dev Profile for Speed

```toml
[profile.dev]
opt-level = 0
debug = "line-tables-only"  # Minimal debug info

[profile.dev.package."*"]
opt-level = 3               # Optimize dependencies even in dev
debug = false
```

---

## Level 2: Build Speed & Linting (Intermediate)

### Build Speed Toolkit

| Tool | What It Does | Setup |
|------|-------------|-------|
| `cargo check` | Type-check without codegen | Use instead of `cargo build` during dev |
| `sccache` | Compiler output cache | `RUSTC_WRAPPER=sccache` in env |
| `mold` | Fast linker | `.cargo/config.toml` (see below) |
| Cranelift | Fast codegen backend (nightly) | `.cargo/config.toml` (see below) |

```toml
# .cargo/config.toml

# Fast linker (Linux)
[target.x86_64-unknown-linux-gnu]
linker = "clang"
rustflags = ["-C", "link-arg=-fuse-ld=mold"]

# Cranelift for dev builds (nightly only)
[unstable]
codegen-backend = true

[profile.dev]
codegen-backend = "cranelift"
```

### Clippy Configuration via Cargo.toml

```toml
[workspace.lints.clippy]
# Broad categories at lower priority
all = { level = "warn", priority = -1 }
pedantic = { level = "warn", priority = -1 }
cargo = { level = "warn", priority = -1 }

# Strict denials for production
unwrap_used = { level = "deny", priority = 0 }
expect_used = { level = "deny", priority = 0 }
panic = { level = "deny", priority = 0 }
todo = { level = "deny", priority = 0 }

# Reduce pedantic noise
module_name_repetitions = { level = "allow", priority = 0 }
multiple_crate_versions = { level = "allow", priority = 0 }
```

Child crates inherit: `[lints] workspace = true`

---

## Level 3: Security & Deployment (Advanced)

### Supply Chain Security

| Tool | Purpose | CI Command |
|------|---------|------------|
| `cargo audit` | Check CVEs against RustSec DB | `cargo audit --deny warnings` |
| `cargo-vet` | Verify crates are audited by trusted entities | `cargo vet` |
| `cargo-deny` | Licenses + bans + advisories + sources | `cargo deny check all` |

```toml
# deny.toml
[advisories]
vulnerability = "deny"
unmaintained = "warn"

[licenses]
unlicensed = "deny"
allow = ["MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause"]
copyleft = "deny"

[bans]
multiple-versions = "warn"
wildcards = "allow"
```

**Trusted Publishing** on crates.io: use OIDC (no long-lived API tokens). GitHub Actions exchanges JWT for ephemeral publish token.

### Cross-Compilation + Docker

```bash
# Add musl target for static linking
rustup target add x86_64-unknown-linux-musl

# Build static binary
cargo build --release --target x86_64-unknown-linux-musl
```

**OpenSSL fix:** Use `openssl = { features = ["vendored"] }` or switch to `rustls`.

**musl allocator is slow** — add `jemallocator` for production workloads.

### Multi-Stage Dockerfile

```dockerfile
# Stage 1: Build
FROM rust:1.80-alpine AS builder
WORKDIR /app
RUN apk add --no-cache musl-dev
RUN cargo install --locked cargo-chef

COPY . .
RUN cargo chef prepare --recipe-path recipe.json

# Stage 2: Cook dependencies (cached layer)
FROM rust:1.80-alpine AS cook
WORKDIR /app
RUN apk add --no-cache musl-dev
RUN cargo install --locked cargo-chef
COPY --from=builder /app/recipe.json recipe.json
RUN cargo chef cook --release --target x86_64-unknown-linux-musl --recipe-path recipe.json

# Stage 3: Build application
COPY . .
RUN cargo build --release --target x86_64-unknown-linux-musl

# Stage 4: Minimal runtime
FROM scratch
COPY --from=cook /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=cook /app/target/x86_64-unknown-linux-musl/release/daemon /daemon
USER 10001
ENTRYPOINT ["/daemon"]
```

Key elements:
- `cargo-chef` caches dependency compilation across builds
- `FROM scratch` — empty image, no shell, minimal attack surface
- CA certs copied for HTTPS
- Non-root user (UID 10001)
- Static musl binary — zero runtime dependencies

### Binary Size Reduction Checklist

1. `opt-level = "z"` (size over speed)
2. `lto = "fat"` (dead code elimination)
3. `strip = true` (remove symbols)
4. `panic = "abort"` (no unwinding)
5. `codegen-units = 1` (better cross-crate optimization)
6. UPX compression (optional, 50-70% reduction, slight startup cost)

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Skipping cargo-deny in CI
**You will be tempted to:** Skip license and vulnerability checks because "we'll audit later."
**The right way:** `cargo deny check all` in CI. Block PRs that introduce vulnerabilities.

### Rule 2: No Publishing with Long-Lived API Tokens
**The right way:** Trusted Publishing with OIDC. Ephemeral tokens only.

### Rule 3: No Deploying Without strip + lto
**You will be tempted to:** Ship debug builds because "release takes too long to compile."
**The right way:** Release builds with full optimization for production. Dev builds with Cranelift for speed.

### Rule 4: No Dynamic Linking in Containers
**You will be tempted to:** Use `FROM debian:slim` because "musl is complicated."
**The right way:** Static musl binary → `FROM scratch`. Zero dependencies. Minimal attack surface.
