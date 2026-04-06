---
name: mx-py-core
description: Python core patterns — typing, dataclasses, protocols, error handling, module structure, __all__, imports. Use when writing any Python code.
---

# Python Core Patterns — Typing, Data Modeling & Architecture for AI Coding Agents

**This skill loads for ANY Python work.** It defines the foundational patterns every Python file must follow.

## When to also load
- `mx-py-perf` — co-loads for ANY Python work (performance patterns)
- `mx-py-observability` — co-loads for ANY Python work (logging/tracing)
- `mx-py-data` — when handling Pydantic validation or Pandas/Polars
- `mx-py-project` — when setting up pyproject.toml, uv, ruff

---

## Level 1: Data Modeling — The Right Container (Beginner)

### Decision Table: Which Data Structure?

| Scenario | Use | NOT |
|----------|-----|-----|
| Internal trusted domain objects | `dataclass` | Pydantic (unnecessary overhead) |
| Immutable simple records (2-5 fields) | `NamedTuple` | dict with string keys |
| Untrusted external data (API, JSON, env) | `Pydantic v2 BaseModel` | dataclass (no validation) |
| High-perf internal with validation | `attrs` with `define(slots=True)` | Pydantic (coercion overhead) |
| Configuration from env vars | `pydantic-settings BaseSettings` | os.environ manually |

### BAD: dataclass for untrusted input
```python
@dataclass
class UserRequest:
    user_id: int
    email: str

# user_id silently accepts string "99" — crashes downstream
request = UserRequest(**json.loads(payload))
```

### GOOD: Pydantic at boundaries, dataclass internally
```python
from pydantic import BaseModel, EmailStr

class UserRequest(BaseModel):
    user_id: int       # Coerces "99" → 99
    email: EmailStr    # Validates format

@dataclass(slots=True, frozen=True)
class UserDomain:
    id: int
    email: str
```

### dataclass Essentials
```python
@dataclass(slots=True)      # 40-50% less memory, faster attribute access (3.10+)
class Point:
    x: float
    y: float
    tags: list[str] = field(default_factory=list)  # NEVER use mutable default directly

@dataclass(frozen=True)      # Immutable → hashable → safe as dict key
class Config:
    host: str
    port: int = 8080
```

---

## Level 2: Protocols, Typing & Interfaces (Intermediate)

### Protocol vs ABC Decision

| Need | Use Protocol | Use ABC |
|------|-------------|---------|
| Third-party class you can't modify | Yes | No |
| Loose coupling, easy mocking | Yes | — |
| Shared default implementations | No | Yes |
| Runtime enforcement of methods | No (weak) | Yes |

```python
from typing import Protocol

class Repository(Protocol):
    async def get(self, id: str) -> dict: ...
    async def save(self, entity: dict) -> None: ...

# Any class with matching methods satisfies this — no inheritance needed
```

**`@runtime_checkable` gotcha:** Only checks method/attribute *existence*, NOT signatures. Don't rely on it for validation.

### Type Narrowing (Python 3.13+)

| Tool | Narrows `if` branch | Narrows `else` branch | Use when |
|------|---------------------|----------------------|----------|
| `isinstance()` | Yes | Yes | Built-in type checks |
| `TypeGuard` | Yes | **No** | Invariant container casting |
| `TypeIs` (3.13+) | Yes | **Yes** | Standard validation branching |

```python
from typing import TypeIs  # or typing_extensions

def is_valid_name(val: str | None) -> TypeIs[str]:
    return val is not None and len(val) > 0

def greet(name: str | None):
    if is_valid_name(name):
        print(name.upper())    # type checker knows: str
    else:
        print("Anonymous")     # type checker knows: None
```

### Essential Typing Patterns
```python
from typing import TypeVar, ParamSpec, Callable
from functools import wraps

P = ParamSpec("P")  # Captures *args, **kwargs of wrapped function
R = TypeVar("R")

def retry_decorator(func: Callable[P, R]) -> Callable[P, R]:
    """Preserves the exact signature of the wrapped function."""
    @wraps(func)
    def wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
        return func(*args, **kwargs)
    return wrapper
```

**Never use `Any` unless interfacing with untyped C extensions.** It infects everything it touches — any function consuming `Any` data loses all type safety.

---

## Level 3: Error Handling & Module Architecture (Advanced)

### Error Handling Rules

1. **Custom exceptions inherit from `Exception`**, never `BaseException`
2. **Name them `*Error`**: `InvalidConfigError`, `RecordNotFoundError`
3. **Chain with `from`**: `raise NewError("msg") from original_error`
4. **Never bare `except:`** — catches `SystemExit` + `KeyboardInterrupt`
5. **`except Exception:` only at app boundaries** (API handler, CLI entry)
6. **Use `logger.exception()`** in except blocks (auto-includes traceback)

```python
# GOOD: Domain exception hierarchy
class ServiceError(Exception):
    """Base for all service errors."""

class NotFoundError(ServiceError):
    """Entity does not exist."""

class ValidationError(ServiceError):
    """Business rule violated."""

# GOOD: Chained re-raise preserving context
try:
    result = await db.fetch(id)
except DatabaseError as e:
    raise NotFoundError(f"User {id} not found") from e
```

### ExceptionGroup (Python 3.11+)
```python
async def process_batch():
    try:
        async with asyncio.TaskGroup() as tg:
            tg.create_task(task_a())
            tg.create_task(task_b())
    except* ValueError as eg:
        for e in eg.exceptions:
            logger.error(f"Validation: {e}")
    except* ConnectionError as eg:
        for e in eg.exceptions:
            logger.error(f"Network: {e}")
```

### Module Structure Rules

**Every module MUST have `__all__`:**
```python
# mypackage/utils.py
__all__ = ["public_function", "PublicClass"]

import sys  # Without __all__, wildcard import leaks `sys`

def _internal_helper(): ...
def public_function(): ...
class PublicClass: ...
```

**Import ordering** (ruff handles this automatically):
```python
# 1. Standard library
import os
from pathlib import Path

# 2. Third-party
import httpx
from pydantic import BaseModel

# 3. Local
from .models import User
from .services import UserService
```

**Circular import resolution:**
```python
from __future__ import annotations  # Defers annotation evaluation
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .graph import Graph  # Only imported for type checkers, not at runtime

class Node:
    def __init__(self, parent: Graph): ...
```

---

## Performance: Make It Fast

- **`slots=True`** on dataclasses for millions of instances (40-50% memory savings)
- **`frozen=True`** enables hashability — use as dict keys and set members
- **`NamedTuple`** over dict for structured records (C-backed, immutable)
- **`collections.deque`** for FIFO queues (`O(1)` vs list's `O(n)` for left operations)
- **`set`** for membership testing (`O(1)` vs list's `O(n)`)
- **`defaultdict`** over manual `if key not in dict` patterns
- **`Counter`** for counting instead of manual loops

See `mx-py-perf` for profiling workflows and full data structure decision table.

---

## Observability: Know It's Working

- **Type hints ARE observability** — they're the first line of defense a type checker uses to catch bugs before runtime
- Run `mypy --strict` or `pyright` in CI — no exceptions
- Use `reveal_type()` during development to verify type narrowing works
- `assert_type()` (typing module) for static assertions that types are what you expect
- Enable `ruff` rule `UP` (pyupgrade) to auto-modernize type annotations

See `mx-py-observability` for structlog, OTel, and Sentry patterns.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: The `Any` Cop-out
**You will be tempted to:** Use `Any` or `dict[str, Any]` for dynamic/recursive JSON structures to "get it compiling quickly."
**Why that fails:** `Any` disables the type checker completely. The infection spreads — every consumer of that data also loses safety. Leads to `KeyError`/`AttributeError` crashes in production.
**The right way:** Use `Pydantic` models for semi-structured data, or `TypedDict`/recursive type aliases. Reserve `Any` only for untyped C-extension interfaces.

### Rule 2: Bare Except / Overly Broad Catches
**You will be tempted to:** Wrap network code in `except Exception: pass` because "10 different things could go wrong."
**Why that fails:** Masks `NameError` (typos), `TypeError` (wrong args). Makes the app un-debuggable. `except BaseException` catches `KeyboardInterrupt` — program becomes un-killable.
**The right way:** Catch specific exceptions. Map upstream errors into domain-specific exception hierarchy. Use `from` for chaining.

### Rule 3: No `__all__`, No Module Boundaries
**You will be tempted to:** Skip `__all__` because "everything is public in Python anyway."
**Why that fails:** Wildcard imports leak `sys`, `os`, `json` into caller namespace. Destroys IDE autocomplete. Creates invisible coupling to internal dependencies.
**The right way:** Every module and `__init__.py` declares `__all__`. Treat modules as strict black boxes with explicit APIs.

### Rule 4: Pydantic for Everything
**You will be tempted to:** Use `BaseModel` for internal domain objects because "validation is always good."
**Why that fails:** Pydantic's coercion and validation has CPU overhead. Using it for hot-path internal data (passed between functions you control) wastes cycles.
**The right way:** Pydantic at system boundaries (API ingress, file loading). `dataclass(slots=True)` or `attrs` internally.

### Rule 5: God Modules
**You will be tempted to:** Put all logic in one file because "context windows are limited."
**Why that fails:** Breaks Single Responsibility, makes unit testing impossible, guarantees circular import hell past 1,000 lines.
**The right way:** Separate `protocols.py`, `models.py`, `services.py`, `api.py`. Use `src/` layout from day one.
