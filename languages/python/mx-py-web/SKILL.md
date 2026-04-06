---
name: mx-py-web
description: FastAPI production patterns — FastAPI, Pydantic models, middleware, dependency injection, CORS, JWT, OAuth2. Use when building or modifying any FastAPI application.
---

# FastAPI Production Patterns — Routing, Security, Real-Time & Deployment for AI Coding Agents

**This skill loads for ANY FastAPI work.** It defines the production patterns every FastAPI application must follow.

## When to also load
- `mx-py-core` — co-loads for ANY Python work (typing, dataclasses, error handling)
- `mx-py-async` — when writing async endpoints, background tasks, event loop management
- `mx-py-database` — when connecting SQLAlchemy, connection pools, migrations
- `mx-py-network` — when calling external APIs with httpx, OAuth2 client flows
- `mx-py-testing` — when writing FastAPI test suites, dependency overrides, AsyncClient

---

## Level 1: Project Structure & Dependency Injection (Beginner)

### Production Directory Layout

```text
app/
├── __init__.py
├── main.py             # App factory ONLY — no business logic
├── api/
│   ├── dependencies.py # Reusable DI functions (get_db, get_current_user)
│   └── v1/
│       ├── router.py   # Central v1 router aggregating all endpoint modules
│       └── endpoints/
│           ├── auth.py
│           └── users.py
├── core/
│   ├── config.py       # Pydantic BaseSettings — all env vars
│   ├── security.py     # JWT encode/decode, password hashing
│   └── exceptions.py   # Global exception handlers
├── models/             # SQLAlchemy ORM models (database tables)
│   └── user.py
├── schemas/            # Pydantic models (request/response validation)
│   └── user.py
├── services/           # Business logic — framework-agnostic
│   └── user_service.py
└── crud/               # Data access layer — raw DB queries
    └── user_crud.py
```

**Layer boundaries are strict:**
- **Routers** validate input via Pydantic schemas, delegate to services. No SQL. No business rules.
- **Services** contain business logic. Call CRUD layer. Framework-agnostic where possible.
- **CRUD** executes database queries. No HTTP concepts. No Pydantic request models.
- **Schemas vs Models** are never the same class. Pydantic at API boundary, SQLAlchemy for persistence.

### The `main.py` Factory

`main.py` instantiates the app, registers middleware, attaches lifespan, includes routers. Nothing else.

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI
from starlette.middleware.cors import CORSMiddleware
from app.api.v1.router import api_router
from app.core.config import settings
from app.core.exceptions import add_exception_handlers

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: initialize pools, warm caches
    yield
    # Shutdown: dispose engine, flush queues

app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    lifespan=lifespan,
    # Disable Swagger in production
    openapi_url=f"{settings.API_V1_STR}/openapi.json" if settings.ENVIRONMENT != "production" else None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.BACKEND_CORS_ORIGINS,  # NEVER ["*"]
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)
add_exception_handlers(app)
app.include_router(api_router, prefix=settings.API_V1_STR)
```

### Dependency Injection: Yield Pattern for DB Sessions

`Depends()` is the backbone of FastAPI resource management. Database sessions use the yield pattern for guaranteed cleanup.

```python
# app/api/dependencies.py
from typing import AsyncGenerator
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.database import AsyncSessionLocal

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()
```

**Key behaviors:**
- Code before `yield` runs before the endpoint. Code after runs after the response.
- FastAPI caches dependencies per request — multiple sub-dependencies requesting `get_db` receive the same session.
- `finally` block executes even on unhandled exceptions. Zero resource leakage.

### `async def` vs `def` Decision

| Operation type | Declare as | Why |
|---------------|-----------|-----|
| I/O-bound (DB, HTTP, file) with async lib | `async def` | Yields to event loop on `await` |
| CPU-bound (image processing, heavy math) | `def` | FastAPI auto-runs in threadpool |
| Sync library (requests, sync SQLAlchemy) | `def` | Threadpool isolation protects event loop |
| Sync call inside `async def` | **BUG** | Blocks entire ASGI worker |

```python
# CORRECT: async I/O
@router.get("/users/{id}")
async def get_user(id: int, db: AsyncSession = Depends(get_db)):
    return await crud.user.get(db, id=id)

# CORRECT: CPU-bound in plain def — auto-threadpooled
@router.post("/reports/generate")
def generate_report(params: ReportParams):
    return heavy_cpu_computation(params)  # Blocks thread, NOT event loop

# BUG: sync call in async def — freezes the entire worker
@router.get("/broken")
async def broken():
    time.sleep(5)  # ALL concurrent requests stall
```

---

## Level 2: Security, CORS & Rate Limiting (Intermediate)

### OAuth2 + JWT Authentication Chain

**CRITICAL: Use `PyJWT` or `authlib`. NEVER `python-jose`.** python-jose is abandoned (no updates since 2021, unpatched CVE-2024-33664).

```python
# app/core/security.py
import jwt  # PyJWT — `pip install PyJWT`
from datetime import datetime, timedelta, timezone
from app.core.config import settings

def create_access_token(subject: str | int, expires_delta: timedelta | None = None) -> str:
    expire = datetime.now(timezone.utc) + (expires_delta or timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode = {"exp": expire, "sub": str(subject), "type": "access"}
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
```

```python
# app/api/dependencies.py
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
import jwt
from app.core.config import settings

oauth2_scheme = OAuth2PasswordBearer(tokenUrl=f"{settings.API_V1_STR}/auth/login")

async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db),
):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        user_id: str | None = payload.get("sub")
        if user_id is None:
            raise credentials_exception
    except jwt.PyJWTError:
        raise credentials_exception
    user = await crud.user.get(db, id=user_id)
    if not user:
        raise credentials_exception
    return user
```

### RBAC via Nested Dependencies

Dependencies can depend on other dependencies. Use this for role-based access control.

```python
from app.schemas.user import User

def require_role(required_role: str):
    def role_checker(current_user: User = Depends(get_current_user)) -> User:
        if required_role not in current_user.roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Requires {required_role} role",
            )
        return current_user
    return role_checker

# Usage — endpoint only accessible to admins
@router.delete("/users/{user_id}")
async def delete_user(user_id: int, admin: User = Depends(require_role("admin"))):
    ...
```

### CORS Production Configuration

**NEVER use `allow_origins=["*"]` in production.** Wildcard origins allow any malicious site to make cross-origin requests. When `allow_credentials=True`, the CORS spec explicitly forbids `"*"`.

```python
# app/core/config.py
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    BACKEND_CORS_ORIGINS: list[str] = [
        "https://myapp.com",
        "https://admin.myapp.com",
    ]
    # Loaded from .env — never hardcoded in source
```

Specify exact domains with protocol. Enumerate allowed methods explicitly — not `["*"]`. Restrict `allow_headers` to what the frontend actually sends.

### Rate Limiting with SlowAPI

```python
# app/core/rate_limit.py
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from fastapi import FastAPI

limiter = Limiter(key_func=get_remote_address, default_limits=["100/minute"])

def setup_rate_limiting(app: FastAPI):
    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Per-endpoint override for sensitive routes
@router.post("/auth/login")
@limiter.limit("5/minute")
async def login(request: Request, credentials: OAuth2PasswordRequestForm = Depends()):
    ...
```

For distributed deployments, configure SlowAPI with Redis backend so rate limits are shared across Uvicorn workers.

---

## Level 3: Real-Time, Deployment & Observability (Advanced)

### Server-Sent Events (SSE)

SSE is unidirectional server-to-client over HTTP. Use for LLM token streaming, live dashboards, notifications. Lighter than WebSockets. Native browser reconnection via `EventSource`.

```python
from fastapi import APIRouter
from fastapi.responses import StreamingResponse
import asyncio

router = APIRouter()

async def event_generator():
    counter = 0
    try:
        while True:
            counter += 1
            yield f"id: {counter}\ndata: {{\"msg\": \"event {counter}\"}}\n\n"
            await asyncio.sleep(1)
    except asyncio.CancelledError:
        pass  # Client disconnected — clean up

@router.get("/events/stream")
async def stream_events():
    return StreamingResponse(event_generator(), media_type="text/event-stream")
```

**SSE format rules:** Each message needs `data: ` prefix and `\n\n` suffix. Use `id:` field for client resumption. Use `retry:` field to control reconnection interval.

### WebSocket Lifecycle + Auth

Browser WebSocket API does not support custom headers in the handshake. Auth options:
1. **Query parameter** — `ws://api.com/ws?token=XYZ` (risk: token in proxy logs)
2. **Initial message** — connect unauthenticated, require `{"auth": "JWT"}` as first message, close if invalid
3. **Subprotocol header** — encode token in `Sec-WebSocket-Protocol`

```python
from fastapi import WebSocket, WebSocketDisconnect, Depends

async def get_ws_user(websocket: WebSocket):
    token = websocket.query_params.get("token")
    if not token:
        await websocket.close(code=1008)
        return None
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        return payload.get("sub")
    except jwt.PyJWTError:
        await websocket.close(code=1008)
        return None

@router.websocket("/ws/chat")
async def chat_ws(websocket: WebSocket, user_id: str = Depends(get_ws_user)):
    if not user_id:
        return
    await websocket.accept()
    try:
        while True:
            data = await websocket.receive_text()
            await websocket.send_text(f"Echo from {user_id}: {data}")
    except WebSocketDisconnect:
        pass  # Remove from connection manager, cleanup
```

Track connected clients in a `set()`. Discard on disconnect to prevent memory leaks. Use `websockets.broadcast()` for multi-client messaging.

### Production Deployment

**Gunicorn + Uvicorn (bare metal / Docker without orchestration):**
```bash
gunicorn app.main:app --workers 4 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000
```

**Kubernetes:** Single Uvicorn worker per container. Let K8s handle replication via pod replicas.

**Docker (multi-stage, non-root):**
```dockerfile
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip wheel --no-cache-dir --no-deps --wheel-dir /app/wheels -r requirements.txt

FROM python:3.12-slim
WORKDIR /app
RUN addgroup --system app && adduser --system --group appuser
COPY --from=builder /app/wheels /wheels
RUN pip install --no-cache /wheels/*
COPY ./app ./app
RUN chown -R appuser:app /app
USER appuser
EXPOSE 8000
CMD ["gunicorn", "app.main:app", "--workers", "4", "--worker-class", "uvicorn.workers.UvicornWorker", "--bind", "0.0.0.0:8000"]
```

Behind a TLS proxy (Nginx, Traefik, Caddy): launch Uvicorn with `--proxy-headers` and `--forwarded-allow-ips` for correct HTTPS URL generation.

### Lifespan Events

Use the `lifespan` context manager (not deprecated `@app.on_event`). Initialize singletons on startup, dispose on shutdown.

```python
from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup — create pools, warm caches, load ML models
    app.state.redis = await aioredis.from_url(settings.REDIS_URL)
    yield
    # Shutdown — dispose connections, flush buffers
    await app.state.redis.close()
    await engine.dispose()
```

### Health Endpoints (Liveness vs Readiness)

```python
@router.get("/health/live", status_code=200)
async def liveness():
    """K8s liveness probe — is the process alive?"""
    return {"status": "ok"}

@router.get("/health/ready", status_code=200)
async def readiness(db: AsyncSession = Depends(get_db)):
    """K8s readiness probe — can it serve traffic? Checks DB connectivity."""
    await db.execute(text("SELECT 1"))
    return {"status": "ready"}
```

Liveness = process is running (no dependency checks). Readiness = can accept traffic (checks DB, Redis, etc.). Load balancers and K8s use these differently.

### Global Exception Handlers

Never return stack traces to clients. Log internally, return sanitized response.

```python
# app/core/exceptions.py
import structlog
from fastapi import FastAPI, Request, status
from fastapi.responses import JSONResponse

logger = structlog.get_logger()

def add_exception_handlers(app: FastAPI):
    @app.exception_handler(Exception)
    async def global_handler(request: Request, exc: Exception):
        logger.error("unhandled_exception", path=request.url.path, error=repr(exc), exc_info=True)
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content={"detail": "Internal server error"},
        )
```

For expected errors (not found, forbidden), raise `HTTPException` with proper status codes. Override `RequestValidationError` handler to match your API's error format.

---

## Performance: Make It Fast

- **`async def` for I/O**, `def` for CPU — wrong choice blocks event loop or wastes threadpool
- **Disable Swagger in production** — `openapi_url=None` removes `/docs`, `/redoc`, `/openapi.json`
- **Single Uvicorn worker per K8s pod** — let the orchestrator scale horizontally
- **Gunicorn workers = 2 * CPU cores + 1** for bare-metal deployments
- **Connection pooling** — one `async_sessionmaker` per app, not per request. See `mx-py-database`
- **Response model filtering** — use `response_model` parameter to avoid serializing internal fields
- **Background tasks** — `BackgroundTasks` for lightweight fire-and-forget; Celery/ARQ for heavy/persistent

See `mx-py-async` for event loop patterns and `mx-py-database` for pool tuning.

---

## Observability: Know It's Working

- **Global exception handler** catches all unhandled errors, logs full traceback internally, returns sanitized response
- **Structured error responses** — consistent `{"detail": "..."}` format across all error codes
- **Health endpoints** — separate liveness (process alive) from readiness (dependencies healthy)
- **Request ID middleware** — generate UUID per request, attach to all log entries via `contextvars`
- **No stack traces to clients** — `HTTPException` for expected errors, global handler for unexpected
- **Dependency overrides** in tests — `app.dependency_overrides[get_db] = override_get_db`

See `mx-py-observability` for structlog, OpenTelemetry, and Sentry integration patterns.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Wildcard CORS
**You will be tempted to:** Set `allow_origins=["*"]` because "it works in development" or "we'll fix it later."
**Why that fails:** Any malicious site can make cross-origin requests to your API. With `allow_credentials=True`, the CORS spec forbids `"*"` entirely — browsers silently block the request. Attackers can exfiltrate user data via CSRF.
**The right way:** Explicit origin list from environment variables. Enumerate methods and headers explicitly.

### Rule 2: python-jose for JWT
**You will be tempted to:** Use `python-jose` because the FastAPI tutorial uses it or because it's in existing code.
**Why that fails:** Abandoned since 2021. Unpatched CVE-2024-33664. No maintainer. Security vulnerabilities compound silently.
**The right way:** `PyJWT` (`pip install PyJWT`) for straightforward JWT. `authlib` for full OAuth2 client+server flows. Both are actively maintained.

### Rule 3: Sync in `async def`
**You will be tempted to:** Call `requests.get()`, `time.sleep()`, or sync SQLAlchemy inside an `async def` endpoint because "it's just one call."
**Why that fails:** Blocks the entire ASGI event loop. Every concurrent request on that worker freezes. One slow endpoint kills the whole server.
**The right way:** Use `def` for sync operations (auto-threadpooled). Use `async def` only with `await`-compatible async libraries. If you must call sync code from async, use `asyncio.to_thread()`.

### Rule 4: Public Swagger in Production
**You will be tempted to:** Leave `/docs` and `/openapi.json` enabled in production for "debugging convenience."
**Why that fails:** Exposes complete API topology, endpoint signatures, request/response schemas, and authentication flows to attackers. Free reconnaissance.
**The right way:** `openapi_url=None` when `ENVIRONMENT == "production"`. Use a separate staging environment for interactive API exploration.

### Rule 5: No Dependency Injection
**You will be tempted to:** Manually instantiate DB sessions in endpoints, pass global variables, or import singletons directly because "DI is overhead for a small app."
**Why that fails:** Destroys testability — no way to mock or override dependencies. Tightly couples endpoints to infrastructure. Connection leaks when cleanup is forgotten.
**The right way:** `Depends()` for all request-scoped resources. Yield dependencies for guaranteed cleanup. `app.dependency_overrides` for testing. This is non-negotiable regardless of app size.
