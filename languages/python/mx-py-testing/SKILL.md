---
name: mx-py-testing
description: Python testing with pytest — fixtures, mocking, parametrize, property-based testing with Hypothesis, async testing, conftest.py hierarchy, factory-boy, pytest-xdist parallel execution.
---

# Python Testing — pytest, Fixtures, Mocking & Property-Based Testing for AI Coding Agents

**This skill loads for ANY Python test work.** It defines how to write, structure, and scale pytest test suites.

## When to also load
- `mx-py-core` — co-loads for ANY Python work (typing, error handling, module structure)
- `mx-py-web` — when testing FastAPI endpoints (dependency overrides, AsyncClient)
- `mx-py-database` — when writing DB fixtures (session-scoped engines, transaction rollback)
- `mx-py-perf` — when profiling test suite execution time

---

## Level 1: Fixtures, Parametrize & Assertions (Beginner)

### Fixture Scopes — Choose the Cheapest Correct Scope

| Scope | Lifecycle | Use for |
|-------|-----------|---------|
| `function` (default) | Created/destroyed per test | Mutable state, DB transactions |
| `class` | Once per test class | Shared read-only class state |
| `module` | Once per `.py` file | Module-level config |
| `package` | Once per directory with `__init__.py` | Package-level resources |
| `session` | Once per entire test run | DB engine, Docker containers, expensive I/O |

**Rule: Start at `function` scope. Only widen when profiling proves it's a bottleneck.**

### Yield Fixtures for Guaranteed Cleanup

```python
@pytest.fixture(scope="session")
def db_engine():
    engine = psycopg.connect("dbname=test user=postgres")
    yield engine
    engine.close()  # Teardown runs even if tests fail

@pytest.fixture(scope="function")
def db_transaction(db_engine):
    with db_engine.transaction() as tx:
        yield tx
        tx.rollback()  # Pristine state for next test
```

Teardown executes in reverse dependency order. Never use `addfinalizer` — `yield` is the standard.

### Fixture Factories — Dynamic Instance Creation

```python
@pytest.fixture
def user_factory() -> Callable[..., dict]:
    created = []
    def _create(username: str, role: str = "guest") -> dict:
        user = {"username": username, "role": role}
        created.append(user)
        return user
    yield _create
    for u in created:
        pass  # cleanup here

def test_multiple_users(user_factory):
    admin = user_factory("admin", role="admin")
    guest = user_factory("visitor")
    assert admin["role"] == "admin"
```

Use factories when a test needs multiple instances or dynamic configuration.

### Parametrize — Separate Test Logic from Test Data

```python
@pytest.mark.parametrize("input_val, expected", [
    ("hello", 5),
    ("", 0),
    ("  spaces  ", 10),
], ids=["normal", "empty", "with-spaces"])
def test_string_length(input_val, expected):
    assert len(input_val) == expected
```

**Stacked parametrize = Cartesian product:**
```python
@pytest.mark.parametrize("x", [0, 1])
@pytest.mark.parametrize("y", [2, 3])
def test_product(x, y):
    # Runs 4 times: (0,2), (0,3), (1,2), (1,3)
    assert x + y >= 2
```

**Indirect parametrize — route params through a fixture:**
```python
@pytest.fixture
def db_connection(request):
    db_type = request.param
    conn = create_connection(db_type)
    yield conn
    conn.close()

@pytest.mark.parametrize("db_connection", ["postgres", "sqlite"], indirect=True)
def test_query(db_connection):
    assert db_connection.execute("SELECT 1")
```

### Assertion Patterns

```python
# Exact match
assert result == expected

# Exception testing
with pytest.raises(ValueError, match=r"invalid.*format"):
    parse_input("garbage")

# Approximate float comparison
assert result == pytest.approx(3.14, abs=1e-2)

# Collection membership
assert "admin" in roles
assert set(result) == {"a", "b", "c"}
```

**Never use `assert True` or `assert result is not None` as the only assertion.** Assert the actual expected value.

---

## Level 2: Mocking, conftest.py & Async Testing (Intermediate)

### Mocking Decision Table

| Scenario | Tool | NOT |
|----------|------|-----|
| Env vars, simple attribute overrides | `monkeypatch.setattr` / `monkeypatch.setenv` | `mock.patch` (overkill) |
| External API calls, class stubbing | `mock.patch(autospec=True)` | `mock.patch()` without autospec |
| Async coroutines | `AsyncMock` | `MagicMock` (not awaitable) |
| Complex call assertions (`assert_called_with`) | `mock.patch` | `monkeypatch` (no call tracking) |
| Internal domain logic, pure functions | **No mocks — test the real thing** | Any mock |
| DB interactions with fast ephemeral DB | **No mocks — use real DB** | Mocking the ORM |

### monkeypatch vs unittest.mock

```python
# monkeypatch — simple, auto-reverts, no decorators
def test_env_var(monkeypatch):
    monkeypatch.setenv("API_KEY", "test-key-123")
    assert os.environ["API_KEY"] == "test-key-123"
```

```python
# mock.patch — ALWAYS use autospec=True
from unittest.mock import patch

@patch("myapp.services.payment.StripeClient", autospec=True)
def test_charge(mock_client):
    instance = mock_client.return_value
    instance.charge.return_value = {"id": "ch_123", "status": "succeeded"}
    result = process_payment(amount=5000)
    instance.charge.assert_called_once_with(amount=5000, currency="usd")
```

**Patch where the object is USED, not where it is defined.** If `payment.py` imports `StripeClient` from `clients.stripe`, patch `myapp.services.payment.StripeClient`, NOT `myapp.clients.stripe.StripeClient`.

### create_autospec — Signature Validation

Without `autospec`, `MagicMock` silently accepts any method name and any arguments. Tests pass, production crashes.

```python
mock_email = create_autospec(EmailService)
mock_email.send(to="user@test.com", typo_arg="oops")  # RAISES TypeError
```

### AsyncMock for Coroutines

```python
from unittest.mock import AsyncMock, patch

@patch("myapp.services.email.send_notification", new_callable=AsyncMock)
async def test_async_notify(mock_send):
    mock_send.return_value = {"delivered": True}

    result = await notify_user("user@test.com", "Welcome")

    mock_send.assert_awaited_once_with("user@test.com", "Welcome")
    assert result["delivered"] is True
```

### conftest.py Hierarchy

Pytest discovers fixtures by walking up the directory tree. No imports needed.

```
tests/
  conftest.py          # Session-scoped: DB engine, Docker, app config
  unit/conftest.py     # Unit-specific: lightweight fakes, monkeypatches
  integration/conftest.py  # Integration-specific: real DB, httpx client
  e2e/conftest.py      # E2E-specific: browser fixtures, seed data
```

Nested conftest.py can override parent fixtures -- `integration/conftest.py` can redefine `db_engine` to use a real database while `unit/conftest.py` uses in-memory SQLite.

**`autouse=True` — use sparingly.** Only for truly universal setup (cache clearing, logging). It hides dependencies.

### Async Testing with pytest-asyncio

```ini
# pyproject.toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
asyncio_default_fixture_loop_scope = "session"
```

```python
import pytest_asyncio
from httpx import AsyncClient, ASGITransport

@pytest_asyncio.fixture(scope="session")
async def async_client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client

@pytest.mark.asyncio
async def test_health(async_client: AsyncClient):
    response = await async_client.get("/api/v1/health")
    assert response.status_code == 200
```

**Use `httpx.AsyncClient` with `ASGITransport`, NOT `TestClient` for async tests.** `TestClient` runs async code in a background sync thread, causing event loop mismatches. Async fixtures MUST use `@pytest_asyncio.fixture`, not `@pytest.fixture`.

### FastAPI Dependency Overrides

```python
@pytest_asyncio.fixture
async def client_with_mock_db(async_client):
    async def mock_db():
        async with test_session() as session:
            yield session
    app.dependency_overrides[get_db_session] = mock_db
    yield async_client
    app.dependency_overrides.clear()  # ALWAYS clear — prevents state leakage
```

See `mx-py-web` for full FastAPI testing patterns including auth overrides.

---

## Level 3: Property-Based Testing, Factories & Parallel Execution (Advanced)

### Hypothesis — Property-Based Testing

Parametrize tests known examples. Hypothesis explores the unknown input space.

| Use Hypothesis when | Use parametrize when |
|---------------------|---------------------|
| Exploring edge cases you haven't thought of | Testing known business rules with specific values |
| Verifying invariants (roundtrip, idempotency) | Testing error cases with specific invalid inputs |
| Refactoring — proving behavioral equivalence | Testing a small, finite set of configurations |

### @given and Core Strategies

```python
from hypothesis import given, strategies as st

@given(st.lists(st.integers()))
def test_sort_preserves_length(lst):
    result = sorted(lst)
    assert len(result) == len(lst)
    assert all(result[i] <= result[i + 1] for i in range(len(result) - 1))
```

Hypothesis automatically shrinks failing inputs to the minimal reproducible case.

### st.from_type and Pydantic Integration

```python
from hypothesis import given, strategies as st
from pydantic import BaseModel

class OrderSchema(BaseModel):
    product_id: int
    quantity: int
    price: float

@given(st.builds(OrderSchema))
def test_order_serialization_roundtrip(order):
    """Hypothesis generates valid OrderSchema instances automatically."""
    json_str = order.model_dump_json()
    restored = OrderSchema.model_validate_json(json_str)
    assert restored == order
```

`st.from_type()` infers strategies from type annotations. `st.builds()` constructs model instances.

### Stateful Testing with RuleBasedStateMachine

```python
from hypothesis.stateful import RuleBasedStateMachine, rule, invariant

class CartMachine(RuleBasedStateMachine):
    def __init__(self):
        super().__init__()
        self.cart = ShoppingCart()
        self.expected = []

    @rule(item=st.text(min_size=1), qty=st.integers(min_value=1, max_value=10))
    def add_item(self, item, qty):
        self.cart.add(item, qty)
        self.expected.append((item, qty))

    @invariant()
    def items_match(self):
        assert self.cart.total_items() == sum(q for _, q in self.expected)

TestCart = CartMachine.TestCase  # Pytest discovers this
```

Stateful tests verify invariants across multi-step operation sequences.

### Hypothesis Settings Profiles

```python
from hypothesis import settings, Phase

# Fast for local dev
settings.register_profile("dev", max_examples=10, deadline=500)
# Thorough for CI
settings.register_profile("ci", max_examples=500, deadline=None)

# Select via: pytest --hypothesis-profile=ci
settings.load_profile("dev")  # default
```

### factory-boy — Realistic Test Data

```python
import factory

class UserFactory(factory.Factory):
    class Meta:
        model = User
    username = factory.Sequence(lambda n: f"user_{n}")
    email = factory.LazyAttribute(lambda o: f"{o.username}@test.com")
    role = "member"

class OrderFactory(factory.Factory):
    class Meta:
        model = Order
    user = factory.SubFactory(UserFactory)
    total = factory.Faker("pydecimal", left_digits=3, right_digits=2, positive=True)
```

For SQLAlchemy: `factory.alchemy.SQLAlchemyModelFactory`. For Pydantic: `st.builds(MyModel)` from Hypothesis.

### Parallel Execution with pytest-xdist

```bash
pytest -n auto                   # Auto-detect cores
pytest -n auto --dist loadfile   # Keep same-file tests on same worker
```

**Requirements:** Tests MUST be fully isolated. No shared mutable state (files, globals, DB rows). Use `tmp_path` for temp dirs, transaction rollback for DB tests. `--dist loadfile` keeps module-scoped fixtures on the same worker.

---

## Performance: Fast Feedback Loops

- **Fixture scope optimization:** Profile with `pytest --durations=20` to find slow fixtures. Promote expensive fixtures to `session` scope when they're read-only.
- **pytest-xdist:** `-n auto` across CPU cores. Tests must be isolated. `--dist loadfile` for module-scoped fixtures.
- **Test DB per session:** Create schema once (`session` scope), wrap each test in a rolled-back transaction (`function` scope). Never recreate the DB per test.
- **Marker-based selection:** `pytest -m "not slow"` skips heavy tests during local dev. `pytest -m integration` runs only integration tests in CI.
- **`--last-failed` / `--failed-first`:** Re-run only failures. Cuts iteration time dramatically.
- **`-x` flag:** Stop on first failure during local dev. Don't waste time running 500 tests when the first one is broken.
- **`--co` (collect-only):** Verify test discovery without executing. Catches import errors instantly.

---

## Observability: Know Your Tests Are Working

### Coverage Configuration

```ini
# pyproject.toml
[tool.pytest.ini_options]
addopts = "--cov=src --cov-report=term-missing --cov-fail-under=80"
markers = ["slow: tests taking >5s", "integration: requires external services", "e2e: browser tests"]

[tool.coverage.run]
branch = true
source = ["src"]

[tool.coverage.report]
exclude_lines = ["pragma: no cover", "if TYPE_CHECKING:", "if __name__ == .__main__."]
```

Coverage measures which lines execute, not whether tests are meaningful. 100% coverage with weak assertions is worthless.

### CI Reporting

```bash
pytest --junitxml=reports/junit.xml                      # CI dashboards
pytest --cov=src --cov-report=xml:reports/coverage.xml   # Codecov/Coveralls
pytest -m "not slow and not e2e"                         # Fast local feedback
```

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: The Over-Mocking Trap
**You will be tempted to:** Mock the database, the ORM, the serializer, and every dependency so "unit tests run fast."
**Why that fails:** The test becomes a tautology — it only proves the mock was called with the arguments you told it to expect. Production crashes because the real DB query returns a different shape than the mock. You have 200 passing tests and a broken app.
**The right way:** Mock only at external boundaries (third-party APIs, payment gateways, email services). Use real databases (via Docker/testcontainers or transaction rollback) for everything else. If you must mock, use `autospec=True` so signature changes break the test.

### Rule 2: Testing Implementation, Not Behavior
**You will be tempted to:** Assert that a specific private method was called, or verify the exact sequence of internal function calls.
**Why that fails:** Any refactoring — extracting a method, renaming an internal, changing execution order — breaks the test even though behavior is unchanged. Tests become change-prevention systems, not bug-prevention systems.
**The right way:** Assert on observable outputs: return values, HTTP responses, DB state changes, side effects on external systems. A test should survive any internal refactor that preserves the public contract.

### Rule 3: Brittle Assertions and Rotten Green Tests
**You will be tempted to:** Assert exact error message strings, hardcode timestamps, or write `assert result is not None` as the only check.
**Why that fails:** Exact string assertions break when copy changes. `is not None` passes for any truthy garbage. A "rotten green test" is one whose assertions never actually execute (e.g., iterating over an empty collection) — it passes but tests nothing.
**The right way:** Assert structural correctness (`isinstance`, dict keys, status codes) and critical substrings (`match=r"invalid.*format"`). Every test path must hit at least one meaningful assertion that can actually fail.

### Rule 4: No Fixture Reuse Without Isolation
**You will be tempted to:** Create a session-scoped fixture that mutates state and share it across tests without resetting.
**Why that fails:** Test B fails only when Test A runs first. Test order becomes a hidden dependency. `pytest-xdist` randomizes order and exposes the rot, but only if you run it.
**The right way:** Mutable fixtures must reset in their `yield` teardown. Immutable data can be session-scoped. If a test mutates shared state, it gets its own function-scoped fixture. No test may depend on another test's execution.

### Rule 5: TestClient for Async FastAPI Tests
**You will be tempted to:** Use `TestClient` because it's simpler and "works fine" for basic endpoint tests.
**Why that fails:** `TestClient` runs the async app in a background sync thread. Any session-scoped async resource (DB pool, cache client) is on a different event loop. You get `RuntimeError: Event loop is closed` or silently wrong behavior where async context managers leak.
**The right way:** Use `httpx.AsyncClient` with `ASGITransport`. Mark tests `@pytest.mark.asyncio`. Use `@pytest_asyncio.fixture` for async fixtures. Same event loop, same context, no surprises.
