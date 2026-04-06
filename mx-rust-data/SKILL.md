---
name: mx-rust-data
description: Use when working with JSON, serialization, databases, configuration, or parsing in Rust. Covers serde derive attributes, serde_json streaming, simd-json, sqlx/rusqlite with SQLite WAL mode, the config crate for layered configuration, dotenvy, and nom/winnow parser combinators. Also use when the user mentions 'serde', 'JSON', 'serialize', 'deserialize', 'SQLite', 'sqlx', 'rusqlite', 'WAL', 'config', 'TOML', 'YAML', '.env', 'dotenvy', 'nom', 'winnow', 'parser', 'streaming', or 'zero-copy parsing'.
---

# Rust Data & Serialization — Serde, SQLite, Config & Parsing Patterns

**Loads when handling data serialization, database access, configuration, or text parsing.**

## When to also load
- Language fundamentals → `mx-rust-core`
- Network protocol buffers → `mx-rust-network`

---

## Level 1: Serde Essentials (Beginner)

### Key Derive Attributes

```rust
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]  // All fields → camelCase in JSON
pub struct AgentConfig {
    pub agent_name: String,           // → "agentName"
    
    #[serde(rename = "_id")]          // Override: exact name
    pub internal_id: String,
    
    #[serde(default)]                 // Missing field → Default::default()
    pub retry_count: u32,
    
    #[serde(default = "default_timeout")]
    pub timeout_ms: u64,
    
    #[serde(skip)]                    // Never serialize/deserialize
    pub runtime_state: bool,
    
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,  // Omit if None
    
    #[serde(flatten)]                 // Inline nested struct fields
    pub metadata: Metadata,
}

fn default_timeout() -> u64 { 5000 }
```

### Enum Representations

```rust
// Default: externally tagged → {"Request": {"id": "123"}}
enum Message { Request { id: String }, Response { result: String } }

// Internally tagged → {"type": "Request", "id": "123"}
#[serde(tag = "type")]
enum Message { Request { id: String }, Response { result: String } }

// Untagged — tries each variant in order
#[serde(untagged)]
enum Value { Number(f64), Text(String), Bool(bool) }
```

Use `#[serde(tag = "type")]` for API messages. Use `#[serde(untagged)]` sparingly — error messages are ambiguous.

---

## Level 2: Database & Config (Intermediate)

### SQLite: sqlx vs rusqlite

| Need | Use | Why |
|------|-----|-----|
| Async daemon with tokio | `sqlx` | Async-native, compile-time query checks |
| Sync CLI tool, no tokio | `rusqlite` | Lower overhead, direct SQLite API |

### SQLite WAL Mode + Single Writer Pattern

```rust
use sqlx::sqlite::{SqliteConnectOptions, SqliteJournalMode, SqliteSynchronous};

let opts = SqliteConnectOptions::new()
    .filename("daemon.db")
    .journal_mode(SqliteJournalMode::Wal)    // Multiple readers + 1 writer
    .synchronous(SqliteSynchronous::Normal)   // Safe in WAL, 2-3x faster
    .foreign_keys(true)
    .create_if_missing(true);

// Reader pool: many concurrent reads
let reader_pool = SqlitePool::connect_with(opts.clone().read_only(true)).await?;

// Writer: single connection, wrapped in async Mutex to queue writes
let writer = Arc::new(tokio::sync::Mutex::new(opts.connect().await?));
```

**NEVER use a general pool for writes.** Multiple writers contend for SQLite's exclusive write lock → `SQLITE_BUSY` → lock starvation.

### Layered Configuration

```rust
use config::{Config, Environment, File};

let config = Config::builder()
    .add_source(File::with_name("config/default"))     // Base
    .add_source(File::with_name(&format!("config/{}", env)))  // Environment-specific
    .add_source(File::with_name("config/local").required(false)) // Uncommitted overrides
    .add_source(Environment::with_prefix("APP").separator("__")) // APP_DATABASE__URL → database.url
    .build()?;

let app_config: AppConfig = config.try_deserialize()?;
```

Use `dotenvy::dotenv().ok()` at startup to load `.env` files for development. Never commit `.env` to git.

---

## Level 3: Streaming & Parsing (Advanced)

### JSON Streaming for Large Data

```rust
use serde::Deserialize;
use serde_json::Deserializer;
use std::io::BufReader;

// Stream of independent JSON objects (NDJSON)
let reader = BufReader::new(file);  // ALWAYS wrap in BufReader
let stream = Deserializer::from_reader(reader).into_iter::<LogEntry>();

for entry in stream {
    match entry {
        Ok(log) => process(log),
        Err(e) => eprintln!("Parse error: {}", e),
    }
}
```

**`from_reader` without `BufReader` is catastrophically slow** — excessive syscalls.

For extreme throughput: `simd-json` (SIMD-accelerated, x86_64) or `sonic-rs` (even faster, requires `-C target-cpu=native`).

### winnow Parser Combinators (Preferred over nom in 2025)

```rust
use winnow::{ascii::{alpha1, digit1, space0}, PResult, Parser};

#[derive(Debug)]
struct Record<'a> { name: &'a str, id: u32 }  // Zero-copy: borrows from input

fn parse_record<'a>(input: &mut &'a str) -> PResult<Record<'a>> {
    let _ = "NAME:".parse_next(input)?;
    let _ = space0.parse_next(input)?;
    let name = alpha1.parse_next(input)?;
    let _ = " ID:".parse_next(input)?;
    let _ = space0.parse_next(input)?;
    let id: u32 = digit1.try_map(str::parse).parse_next(input)?;
    Ok(Record { name, id })
}
```

Zero-copy: output `&str` borrows from input buffer. No allocations.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No General Connection Pool for SQLite Writes
**The right way:** Single writer connection + async Mutex. Reader pool for SELECTs.

### Rule 2: No from_reader Without BufReader
**The right way:** Always `BufReader::new(source)` before `serde_json::from_reader`.

### Rule 3: No Hardcoded Config Values
**The right way:** Layered config (defaults < files < env vars). Validate at startup.
