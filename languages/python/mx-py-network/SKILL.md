---
name: mx-py-network
description: Python HTTP client patterns — httpx, requests, retries, auth, rate limiting, webhooks, WebSocket, SSE. Use when making HTTP calls, consuming APIs, or building resilient network clients.
---

# Python HTTP Client Patterns — httpx, Retries, Auth & Streaming for AI Coding Agents

**This skill loads when writing any Python code that makes HTTP requests, consumes external APIs, or handles real-time streaming.**

## When to also load
- `mx-py-core` — always co-load (typing, error handling, module structure)
- `mx-py-async` — when using asyncio patterns beyond basic await (TaskGroup, Semaphore, channels)
- `mx-py-web` — when building the server side (FastAPI endpoints, middleware, SSE serving)

---

## Level 1: httpx Client Lifecycle, Timeouts & Basic Retry (Beginner)

### Decision Table: Which HTTP Client?

| Scenario | Use | NOT |
|----------|-----|-----|
| Any async code (FastAPI, scripts with asyncio) | `httpx.AsyncClient` | `requests` (blocks event loop) |
| Simple sync scripts, no concurrency | `httpx.Client` or `requests` | `urllib3` directly |
| OAuth2 token lifecycle | `authlib.AsyncOAuth2Client` | Manual Bearer header construction |
| Bulk parallel fetching with rate limits | `httpx.AsyncClient` + `aiometer` | `asyncio.gather` without throttle |

### AsyncClient Lifecycle — Context Manager Required

```python
import httpx

LIMITS = httpx.Limits(
    max_connections=100,
    max_keepalive_connections=20,
    keepalive_expiry=30.0,
)

TIMEOUT = httpx.Timeout(
    connect=5.0,   # TCP handshake — fail fast on unreachable hosts
    read=30.0,     # Wait for response body — tune per endpoint
    write=5.0,     # Send request body
    pool=2.0,      # Wait for available connection from pool
)

async def main():
    async with httpx.AsyncClient(
        base_url="https://api.example.com/v2",
        limits=LIMITS,
        timeout=TIMEOUT,
        http2=True,
        headers={"User-Agent": "MyService/1.0"},
    ) as client:
        resp = await client.get("/users/123")
        resp.raise_for_status()
        return resp.json()
```

**Key rules:**
- `async with` ensures connections are released and sockets closed on exit.
- `base_url` scopes the pool to one domain — optimal for microservice-to-microservice calls.
- `http2=True` multiplexes requests over a single TCP connection, cutting TLS handshake overhead.

### BAD: Global timeout with no granularity
```python
# timeout=5.0 means 5s per phase — a request can block up to 20s total
client = httpx.AsyncClient(timeout=5.0)

# timeout=None disables ALL timeouts — creates zombie coroutines on upstream outage
client = httpx.AsyncClient(timeout=None)  # NEVER DO THIS
```

### GOOD: Granular timeouts with per-request overrides
```python
DEFAULT_TIMEOUT = httpx.Timeout(connect=3.0, read=10.0, write=5.0, pool=2.0)
client = httpx.AsyncClient(timeout=DEFAULT_TIMEOUT)

# Override for a slow report endpoint
resp = await client.get(
    "/reports/annual",
    timeout=httpx.Timeout(connect=3.0, read=120.0, write=5.0, pool=2.0),
)
```

### Basic Retry with tenacity

```python
import logging
from tenacity import (
    retry,
    stop_after_attempt,
    wait_exponential_jitter,
    retry_if_exception_type,
    before_sleep_log,
    RetryError,
)

logger = logging.getLogger(__name__)

@retry(
    stop=stop_after_attempt(4),
    wait=wait_exponential_jitter(initial=1.0, max=15.0, jitter=2.0),
    retry=retry_if_exception_type((httpx.ConnectError, httpx.ReadTimeout)),
    before_sleep=before_sleep_log(logger, logging.WARNING),
    reraise=True,
)
async def fetch_with_retry(client: httpx.AsyncClient, path: str) -> dict:
    resp = await client.get(path)
    resp.raise_for_status()
    return resp.json()
```

**tenacity essentials:**
- `stop_after_attempt` — ALWAYS set. No stop = infinite retry = self-DDoS.
- `wait_exponential_jitter` — prevents thundering herd. Preferred over `wait_exponential`.
- `before_sleep_log` — logs every retry attempt with delay. Free observability.
- `reraise=True` — raises the original exception after all retries fail, not `RetryError`.
- Only retry transient errors: connection failures, timeouts, 429, 502/503/504.

---

## Level 2: OAuth2/JWT Auth, Rate Limiting & Circuit Breaker (Intermediate)

### OAuth2 with Authlib — Automatic Token Refresh

```python
from authlib.integrations.httpx_client import AsyncOAuth2Client

async def create_oauth_client() -> AsyncOAuth2Client:
    """Credentials loaded from env vars or secrets vault — never hardcoded."""
    client = AsyncOAuth2Client(
        client_id=os.environ["OAUTH_CLIENT_ID"],
        client_secret=os.environ["OAUTH_CLIENT_SECRET"],  # noqa: fake example
        token_endpoint="https://auth.provider.com/oauth/token",
        token_endpoint_auth_method="client_secret_post",
        grant_type="client_credentials",
    )
    # Fetch initial token — Authlib auto-refreshes on expiry
    await client.fetch_token(client.metadata["token_endpoint"])
    return client

async def call_protected_api():
    async with await create_oauth_client() as client:
        # Authorization: Bearer <token> injected automatically
        resp = await client.get("https://api.protected.example.com/data")
        resp.raise_for_status()
        return resp.json()
```

**Auth rules:**
- Authlib inherits from `httpx.AsyncClient` — you get connection pooling and timeouts for free.
- Short-lived access tokens (15-30 min) + refresh tokens. Rotate refresh tokens on every use.
- Asymmetric signing (RS256/ES256) for distributed systems. HS256 only for single-service.
- NEVER log tokens in plaintext. NEVER include tokens in error messages.
- Store secrets in environment variables or a secrets vault, never in source.

### Rate Limiting — Semaphore vs. aiometer

Connection limits (`httpx.Limits`) control socket concurrency. Rate limiting controls requests-per-second. They are different concerns.

```python
import asyncio
import functools
import aiometer
import httpx

async def fetch_item(client: httpx.AsyncClient, item_id: int) -> dict:
    resp = await client.get(f"/items/{item_id}")
    if resp.status_code == 429:
        retry_after = float(resp.headers.get("Retry-After", 1.0))
        await asyncio.sleep(retry_after)
        resp = await client.get(f"/items/{item_id}")
    resp.raise_for_status()
    return resp.json()

async def batch_fetch(item_ids: list[int]) -> list[dict]:
    async with httpx.AsyncClient(base_url="https://api.example.com") as client:
        fetch = functools.partial(fetch_item, client)
        async with aiometer.amap(
            fetch,
            item_ids,
            max_at_once=10,       # Concurrency cap (Semaphore equivalent)
            max_per_second=5.0,   # Throughput cap (respects API quota)
        ) as results:
            return [r async for r in results]
```

**When to use which:**
- `asyncio.Semaphore` — simple cap on concurrent inflight requests. Good for internal services.
- `aiometer` — when the API has an explicit rate limit (e.g., "50 requests/sec"). Controls both concurrency AND throughput.
- NEVER use bare `asyncio.gather` over hundreds of tasks without throttling. That is a self-inflicted DDoS.

### Circuit Breaker Pattern

When an upstream service is persistently failing, retrying only makes it worse. A circuit breaker short-circuits requests after repeated failures.

```python
import pybreaker
import httpx

# Opens after 5 consecutive failures. Half-opens after 30s for a probe request.
api_breaker = pybreaker.CircuitBreaker(
    fail_max=5,
    reset_timeout=30,
    exclude=[lambda e: isinstance(e, httpx.HTTPStatusError)
             and e.response.status_code < 500],
)

def is_transient(exc: Exception) -> bool:
    if isinstance(exc, httpx.HTTPStatusError):
        return exc.response.status_code in {429, 502, 503, 504}
    return isinstance(exc, (httpx.ConnectError, httpx.ReadTimeout))

@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential_jitter(initial=1.0, max=10.0),
    retry=retry_if_exception_type((httpx.ConnectError, httpx.ReadTimeout)),
    before_sleep=before_sleep_log(logger, logging.WARNING),
    reraise=True,
)
@api_breaker
async def resilient_call(client: httpx.AsyncClient, path: str) -> dict:
    resp = await client.get(path)
    resp.raise_for_status()
    return resp.json()
```

**Circuit breaker states:** Closed (normal) -> Open (rejecting) -> Half-Open (probing). Monitor state transitions for alerting.

---

## Level 3: WebSocket Clients, SSE Consumers & Webhook Handling (Advanced)

### WebSocket Client with Reconnection

```python
import asyncio
import json
import logging
import websockets

logger = logging.getLogger(__name__)

async def websocket_client(
    url: str,
    *,
    initial_delay: float = 1.0,
    max_delay: float = 60.0,
    max_retries: int = 20,
):
    delay = initial_delay
    retries = 0

    while retries < max_retries:
        try:
            async with websockets.connect(
                url,
                additional_headers={"Authorization": "Bearer <token>"},
                ping_interval=20,   # Library auto-sends ping every 20s
                ping_timeout=20,    # Expects pong within 20s
            ) as ws:
                delay = initial_delay  # Reset on successful connect
                retries = 0
                logger.info("WebSocket connected to %s", url)

                async for raw in ws:
                    msg = json.loads(raw)
                    match msg.get("type"):
                        case "data":
                            await handle_data(msg["payload"])
                        case "heartbeat":
                            await ws.send(json.dumps({"type": "heartbeat_ack"}))
                        case _:
                            logger.warning("Unknown message type: %s", msg.get("type"))

        except websockets.ConnectionClosed as e:
            logger.warning("WebSocket closed: code=%s reason=%s", e.code, e.reason)
        except OSError as e:
            logger.error("WebSocket connection failed: %s", e)

        retries += 1
        jitter = delay * 0.1 * (asyncio.get_event_loop().time() % 1)
        sleep_time = min(delay + jitter, max_delay)
        logger.info("Reconnecting in %.1fs (attempt %d/%d)", sleep_time, retries, max_retries)
        await asyncio.sleep(sleep_time)
        delay = min(delay * 2, max_delay)

    logger.error("Max retries reached for WebSocket %s", url)
```

**WebSocket rules:**
- ALWAYS use `async with websockets.connect()` — auto-cleanup prevents socket leaks.
- Handle `ConnectionClosed` explicitly. Silent failure = invisible data loss.
- Exponential backoff with jitter on reconnect. Reset delay on successful connection.
- Use `wss://` in production. Plain `ws://` only for local development.
- Track connected clients in a `set()` on the server side; discard on disconnect.

### SSE Consumer with httpx-sse

```python
import httpx
from httpx_sse import aconnect_sse
import logging

logger = logging.getLogger(__name__)

async def consume_sse(url: str, last_event_id: str | None = None):
    # SSE connections are long-lived — disable read timeout
    timeout = httpx.Timeout(connect=5.0, read=None, write=5.0, pool=5.0)

    async with httpx.AsyncClient(timeout=timeout) as client:
        headers = {"Accept": "text/event-stream"}
        if last_event_id:
            headers["Last-Event-ID"] = last_event_id

        async with aconnect_sse(client, "GET", url, headers=headers) as source:
            async for event in source.aiter_sse():
                logger.info("SSE event=%s id=%s data=%s", event.event, event.id, event.data[:100])
                last_event_id = event.id  # Track for reconnection
```

**SSE rules:**
- `read=None` is the ONE exception to the "no infinite timeouts" rule — SSE connections are intentionally held open.
- `httpx-sse` does NOT auto-reconnect. Wrap in a retry loop using `last_event_id` for resumption.
- Pass `Last-Event-ID` header on reconnect so the server can replay missed events.

### Webhook Handling — HMAC Verification + Idempotency

```python
import hmac
import hashlib
from fastapi import APIRouter, Request, HTTPException, Header

router = APIRouter()
WEBHOOK_SIGNING_KEY = os.environ["WEBHOOK_SIGNING_KEY"].encode()  # from vault

def verify_hmac(body: bytes, signature: str) -> bool:
    expected = hmac.new(WEBHOOK_SIGNING_KEY, body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature)

@router.post("/webhooks/provider")
async def handle_webhook(
    request: Request,
    x_signature: str = Header(...),
    x_idempotency_key: str = Header(...),
):
    body = await request.body()

    # 1. Verify origin authenticity
    if not verify_hmac(body, x_signature):
        raise HTTPException(401, "Invalid signature")

    # 2. Idempotency check — use Redis/Postgres in production, not in-memory set
    if await is_already_processed(x_idempotency_key):
        return {"status": "already_processed"}

    # 3. Process
    try:
        await process_event(body)
        await mark_processed(x_idempotency_key)
        return {"status": "ok"}
    except Exception:
        # Route to DLQ after persistent failure — do NOT retry indefinitely
        await route_to_dlq(body, x_idempotency_key)
        raise HTTPException(500, "Processing failed — queued for retry")
```

**Webhook rules:**
- ALWAYS verify HMAC signature before processing. Webhook endpoints are public attack surfaces.
- Use `hmac.compare_digest` (constant-time) to prevent timing attacks. Never use `==`.
- Idempotency keys prevent duplicate processing. Webhooks guarantee at-least-once delivery.
- Store processed keys in Redis/Postgres with TTL, not an in-memory set.
- Route persistent failures to a Dead-Letter Queue. Never retry indefinitely.

---

## Performance: Make It Fast

- **Reuse clients** — one `AsyncClient` per service, not per request. Each new client = DNS + TCP + TLS handshake.
- **HTTP/2** — `http2=True` multiplexes requests over a single connection. Huge win for APIs with many parallel calls.
- **Connection pooling** — `httpx.Limits(max_keepalive_connections=N)` keeps warm connections. Tune `keepalive_expiry` to match server timeout.
- **Rate limit proactively** — use `aiometer` or `Semaphore` BEFORE you get 429s. Reactive backoff is slower than proactive throttling.
- **Stream large responses** — `async with client.stream("GET", url) as resp:` avoids loading entire body into memory.
- **Transport-level retries** — `httpx.AsyncHTTPTransport(retries=2)` handles connection-level failures (TCP reset, DNS timeout) below the application retry layer.

---

## Observability: Know It's Working

- **Retry logging** — `before_sleep_log(logger, logging.WARNING)` on every tenacity decorator. Every retry attempt is a signal.
- **Circuit breaker state** — log Open/Half-Open/Closed transitions. An open circuit = upstream outage.
- **Response timing** — measure `response.elapsed` for latency tracking per endpoint.
- **Status code counters** — track 2xx/4xx/5xx rates. A spike in 429s means your rate limiting is misconfigured.
- **Connection pool exhaustion** — if `pool` timeout fires frequently, increase `max_connections` or investigate slow responses.
- **Token expiry monitoring** — log when OAuth tokens refresh. Frequent refreshes may indicate clock skew or short TTLs.

See `mx-py-observability` for structlog, OTel span integration, and Sentry patterns.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Infinite Timeouts
**You will be tempted to:** Set `timeout=None` because "the upstream is slow and I don't want failures."
**Why that fails:** A hung connection with no timeout becomes a zombie coroutine. It holds a socket, a pool slot, and memory indefinitely. During an upstream outage, every request becomes a zombie. The service runs out of file descriptors and crashes.
**The right way:** Set granular timeouts. If an endpoint is legitimately slow, override `read` for that specific call, not globally. The only exception is SSE/streaming where `read=None` is intentional.

### Rule 2: Using `requests` in Async Code
**You will be tempted to:** Use `requests.get()` inside an `async def` because "it's just one call."
**Why that fails:** `requests` blocks the entire event loop thread. Every other coroutine — database queries, other HTTP calls, WebSocket handlers — freezes until `requests` returns. One synchronous call can deadlock an entire service.
**The right way:** Use `httpx.AsyncClient` in async code. Always. If you must call sync code, use `asyncio.to_thread()`.

### Rule 3: New Client Per Request
**You will be tempted to:** Create `httpx.AsyncClient()` inside a function and close it after one call because "it's cleaner."
**Why that fails:** Every new client performs DNS resolution, TCP handshake, and TLS negotiation. For HTTPS with HTTP/2, that is 2-4 round trips per request instead of zero. Under load, this destroys throughput and overwhelms upstream connection limits.
**The right way:** Create the client once at application startup (or via dependency injection). Pass it to functions. Close it at shutdown.

### Rule 4: Retrying Non-Transient Errors
**You will be tempted to:** Retry on all exceptions because "what if it works the second time?"
**Why that fails:** A `400 Bad Request` will fail identically on every retry — the payload is wrong. A `401 Unauthorized` means the token expired — retrying without refreshing changes nothing. A `404 Not Found` means the resource does not exist. Retrying these wastes time, wastes bandwidth, and masks the real bug.
**The right way:** Retry ONLY transient errors: `httpx.ConnectError`, `httpx.ReadTimeout`, HTTP 429, 502, 503, 504. Let everything else fail immediately.

### Rule 5: No Rate Limiting on External APIs
**You will be tempted to:** Fire `asyncio.gather(*[fetch(id) for id in ids])` over thousands of IDs because "async is fast."
**Why that fails:** You just DDoS'd the API. You get mass 429s, your IP gets banned, and the provider's abuse team sends your company an email. Even if you don't get banned, the thundering herd of retries after the 429 storm makes it worse.
**The right way:** Use `aiometer.amap` with `max_at_once` and `max_per_second`. Or use `asyncio.Semaphore` as a minimum. Respect `Retry-After` headers. Throttle proactively, not reactively.
