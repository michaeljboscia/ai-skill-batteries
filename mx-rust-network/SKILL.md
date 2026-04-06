---
name: mx-rust-network
description: Use when building HTTP servers, WebSocket streaming, SSE, or HTTP clients in Rust. Covers axum web framework, Tower middleware, WebSocket with broadcast channels, Server-Sent Events, reqwest HTTP client, connection pooling, and the bytes crate for zero-copy buffers. Also use when the user mentions 'axum', 'hyper', 'tower', 'middleware', 'WebSocket', 'SSE', 'server-sent events', 'reqwest', 'HTTP client', 'HTTP server', 'REST API', 'Bytes', 'BytesMut', 'connection pool', 'rate limit', 'CORS', or 'IntoResponse'.
---

# Rust Network I/O — Axum, WebSocket, SSE & HTTP Client Patterns

**Loads when building web services, streaming to clients, or making outbound HTTP requests.**

## When to also load
- Async patterns → `mx-rust-async`
- Error handling → `mx-rust-core`
- JSON serialization → `mx-rust-data`

---

## Level 1: Axum Fundamentals (Beginner)

### Minimal Axum Server

```rust
use axum::{routing::get, Router, Json};
use std::sync::Arc;

struct AppState { db: DatabasePool }

#[tokio::main]
async fn main() {
    let state = Arc::new(AppState { db: connect_db().await });
    
    let app = Router::new()
        .route("/health", get(|| async { "OK" }))
        .route("/users", get(list_users))
        .with_state(state);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

async fn list_users(State(state): State<Arc<AppState>>) -> Json<Vec<User>> {
    Json(state.db.get_users().await)
}
```

### Error Handling: Custom AppError + IntoResponse

```rust
use axum::{http::StatusCode, response::{IntoResponse, Response}, Json};
use serde::Serialize;

#[derive(thiserror::Error, Debug)]
pub enum AppError {
    #[error("not found: {0}")]
    NotFound(String),
    #[error("bad request: {0}")]
    BadRequest(String),
    #[error(transparent)]
    Internal(#[from] anyhow::Error),
}

#[derive(Serialize)]
struct ErrorBody { error: String, code: u16 }

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, msg) = match &self {
            AppError::NotFound(m) => (StatusCode::NOT_FOUND, m.clone()),
            AppError::BadRequest(m) => (StatusCode::BAD_REQUEST, m.clone()),
            AppError::Internal(e) => {
                tracing::error!(error = %e, "internal error");
                (StatusCode::INTERNAL_SERVER_ERROR, "internal error".into())
            }
        };
        (status, Json(ErrorBody { error: msg, code: status.as_u16() })).into_response()
    }
}

// Handlers return Result<T, AppError> — errors auto-convert to JSON responses
async fn get_user(Path(id): Path<u64>) -> Result<Json<User>, AppError> {
    let user = find_user(id).ok_or(AppError::NotFound(format!("user {id}")))?;
    Ok(Json(user))
}
```

**NEVER expose raw `anyhow::Error` to clients.** Always sanitize in `IntoResponse`.

### Tower Middleware Stack (Production Order)

Apply via `ServiceBuilder` — layers execute top-to-bottom on request, bottom-to-top on response:

```rust
use tower::ServiceBuilder;
use tower_http::{trace::TraceLayer, cors::CorsLayer, compression::CompressionLayer};

let middleware = ServiceBuilder::new()
    .layer(TraceLayer::new_for_http())    // 1. Outermost: log everything
    .layer(CatchPanicLayer::new())         // 2. Convert panics to 500
    .layer(TimeoutLayer::new(Duration::from_secs(15))) // 3. Global timeout
    .layer(cors)                           // 4. CORS preflight
    .layer(CompressionLayer::new())        // 5. Compress responses
    .layer(auth_middleware);               // 6. Innermost: auth

let app = Router::new().route("/", get(handler)).layer(middleware);
```

**Order matters.** Security layers before business logic. Tracing wraps everything.

---

## Level 2: Real-Time Streaming (Intermediate)

### SSE vs WebSocket Decision

| Need | Use | Why |
|------|-----|-----|
| Server → Client only (logs, AI generation, dashboards) | **SSE** | Simpler, auto-reconnect, HTTP/2 multiplexing |
| Bidirectional (chat, interactive terminals) | **WebSocket** | Full-duplex required |
| Binary data streaming | **WebSocket** | SSE is text-only (UTF-8) |

### WebSocket with Broadcast

```rust
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use futures_util::{SinkExt, StreamExt};
use tokio::sync::broadcast;

async fn ws_handler(ws: WebSocketUpgrade, State(state): State<Arc<AppState>>) -> impl IntoResponse {
    ws.on_upgrade(|socket| handle_socket(socket, state))
}

async fn handle_socket(socket: WebSocket, state: Arc<AppState>) {
    let (mut sender, mut receiver) = socket.split();
    let mut rx = state.broadcast_tx.subscribe();

    // Send task: forward broadcast messages to this client
    let mut send_task = tokio::spawn(async move {
        while let Ok(msg) = rx.recv().await {
            if sender.send(Message::Text(msg)).await.is_err() { break; }
        }
    });

    // Receive task: forward client messages to broadcast
    let tx = state.broadcast_tx.clone();
    let mut recv_task = tokio::spawn(async move {
        while let Some(Ok(Message::Text(text))) = receiver.next().await {
            let _ = tx.send(text);
        }
    });

    // If either task ends, abort the other (prevents zombie connections)
    tokio::select! {
        _ = &mut send_task => recv_task.abort(),
        _ = &mut recv_task => send_task.abort(),
    }
}
```

Handle `RecvError::Lagged` for slow clients — log and optionally disconnect.

### SSE with Keep-Alive

```rust
use axum::response::sse::{Event, KeepAlive, Sse};
use std::convert::Infallible;

async fn sse_handler() -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
    let stream = tokio_stream::wrappers::IntervalStream::new(
        tokio::time::interval(Duration::from_secs(1))
    )
    .map(|_| Event::default().data(format!("tick: {}", chrono::Utc::now())))
    .map(Ok);

    Sse::new(stream).keep_alive(KeepAlive::new().interval(Duration::from_secs(15)))
}
```

---

## Level 3: HTTP Client & Zero-Copy (Advanced)

### reqwest Production Client

```rust
use reqwest::Client;
use reqwest_middleware::ClientBuilder;
use reqwest_retry::{policies::ExponentialBackoff, RetryTransientMiddleware};

fn build_client() -> reqwest_middleware::ClientWithMiddleware {
    let client = Client::builder()
        .connect_timeout(Duration::from_secs(2))
        .read_timeout(Duration::from_secs(10))
        .timeout(Duration::from_secs(30))        // Total request deadline
        .pool_max_idle_per_host(32)
        .pool_idle_timeout(Duration::from_secs(90))
        .build().unwrap();

    let retry = ExponentialBackoff::builder().build_with_max_retries(3);
    
    ClientBuilder::new(client)
        .with(RetryTransientMiddleware::new_with_policy(retry))
        .build()
}
```

**NEVER create `Client::new()` per request.** It destroys connection pooling. Create once, share via `Arc` or axum `State`.

### Bytes Crate for Zero-Copy

```rust
use bytes::{Bytes, BytesMut, Buf, BufMut};

// BytesMut for building/receiving (mutable)
let mut buf = BytesMut::with_capacity(8192);
stream.read_buf(&mut buf).await?;  // Kernel fills buffer in-place

// split_to is O(1) — no data copy
let frame = buf.split_to(payload_len);

// freeze() converts to immutable, cheaply cloneable Bytes
let shared = frame.freeze();  // Clone = atomic refcount increment
tokio::spawn(async move { process(shared).await });
```

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No reqwest::Client Per Request
**The right way:** Create once at startup, share via state.

### Rule 2: No Vec<u8> Cloning for Network Buffers
**The right way:** `Bytes::freeze()` + `Arc` for zero-copy fan-out.

### Rule 3: No Raw anyhow Strings to Web Clients
**The right way:** `IntoResponse` impl that maps errors to status codes + sanitized JSON.

### Rule 4: No Ignoring Slow WebSocket Clients
**The right way:** Handle `RecvError::Lagged`. Log. Disconnect if persistent.
