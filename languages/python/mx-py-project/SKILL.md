---
name: mx-py-project
description: Python project setup — packaging, pyproject.toml, uv, ruff, virtual envs, distribution, pip, poetry migration. Use when initializing a project, configuring build tools, or publishing to PyPI.
---

# Python Project Setup — uv, Ruff, pyproject.toml & Distribution for AI Coding Agents

**This skill loads when setting up a Python project, configuring dependencies, or publishing packages.** It defines the modern toolchain: `uv` replaces pip/virtualenv/pyenv/poetry, `ruff` replaces flake8/black/isort, and `pyproject.toml` is the single source of truth.

## When to also load
- `mx-py-core` — co-loads for ANY Python work (typing, dataclasses, error handling)
- `mx-py-testing` — when writing tests, configuring pytest, or setting up test infrastructure
- `mx-py-perf` — when profiling or optimizing Python performance
- `mx-py-observability` — when adding logging, tracing, or monitoring

---

## Level 1: Project Initialization & Dependency Management (Beginner)

### Starting a New Project

```bash
# Application (flat layout — scripts, services, CLIs)
uv init my_app
cd my_app

# Library (src/ layout — publishable packages)
uv init --lib my_library
cd my_library
```

`uv init` generates: `pyproject.toml`, `.python-version`, `README.md`, `.gitignore`, and a starter module. On first `uv sync` or `uv run`, it auto-creates `.venv` and `uv.lock`.

### Dependency Management

```bash
# Add runtime dependency
uv add httpx

# Add with version constraint
uv add "pydantic>=2.5.0,<3.0.0"

# Add dev dependency (PEP 735 dependency groups)
uv add --dev pytest

# Add to a named group
uv add --group docs mkdocs-material

# Add optional dependency (extras)
uv add --optional ml torch scikit-learn

# Remove (auto-prunes orphaned transitive deps)
uv remove httpx
```

### Running Code

**Never manually activate `.venv`.** Use `uv run` instead — it ensures the environment matches the lockfile exactly.

```bash
uv run python main.py        # Run a script
uv run pytest tests/          # Run tests
uv run ruff check .           # Run linter
uv run mypy src/              # Run type checker
```

`uv run` checks `.venv` exists, verifies `uv.lock` matches `pyproject.toml`, syncs if needed, then executes. This eliminates "it works on my machine" entirely.

### Syncing Environments

```bash
uv sync                    # Install deps + dev group + editable project
uv sync --no-dev           # Production only (no dev group)
uv sync --group docs       # Include specific group
uv sync --locked           # Fail if uv.lock is stale (CI mode)
uv sync --frozen           # Fail if pyproject.toml changed without re-lock
```

### Python Version Management

```bash
uv python list             # Show available versions
uv python install 3.12     # Download + install CPython 3.12
uv python pin 3.12         # Pin project to 3.12 (writes .python-version)
```

If `.python-version` says `3.12` and it's missing, `uv sync` downloads it automatically. No pyenv needed.

### pyproject.toml Basics

```toml
[project]
name = "my-project"
version = "0.1.0"
description = "What this project does"
readme = "README.md"
requires-python = ">=3.11"
license = { text = "MIT" }
authors = [
    { name = "Your Name", email = "you@example.com" }
]
dependencies = [
    "httpx>=0.27.0",
    "pydantic>=2.5.0,<3.0.0",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

Every project MUST have `[build-system]`. Without it, tools silently fall back to legacy setuptools.

---

## Level 2: Ruff Configuration, Dependency Groups & Project Layout (Intermediate)

### Ruff Configuration

Ruff replaces flake8 + black + isort + pyupgrade + bandit in one tool. All config lives in `pyproject.toml`.

```toml
[tool.ruff]
line-length = 88
target-version = "py311"

[tool.ruff.lint]
extend-select = [
    "I",    # isort — import sorting
    "UP",   # pyupgrade — modernize syntax (Union → |, Optional → X | None)
    "B",    # flake8-bugbear — common bugs and design issues
    "C4",   # flake8-comprehensions — optimize comprehensions
    "SIM",  # flake8-simplify — simplify complex expressions
    "S",    # flake8-bandit — security checks
    "N",    # pep8-naming — naming conventions
]
ignore = ["S101"]  # Allow assert (used in tests)

[tool.ruff.lint.per-file-ignores]
"tests/*" = ["S101"]        # Assertions OK in tests
"__init__.py" = ["F401"]    # Unused imports OK in __init__ (re-exports)

[tool.ruff.lint.isort]
known-first-party = ["my_project"]

[tool.ruff.format]
docstring-code-format = true   # Format code blocks inside docstrings
```

**Commands:**
```bash
uv run ruff check .            # Lint
uv run ruff check --fix .      # Lint + auto-fix safe violations
uv run ruff format .           # Format (Black-compatible)
uv run ruff format --check .   # Check formatting without modifying (CI)
```

**Do NOT ignore E501 manually** — the formatter handles line length. `extend-select` appends to defaults (E + F); use it instead of `select` to inherit future upstream defaults.

### Dependency Groups (PEP 735)

Dependency groups are for local development tools that should never ship with the package.

```toml
[dependency-groups]
dev = [
    "pytest>=8.0.0",
    "pytest-cov>=5.0.0",
    "ruff>=0.11.0",
    "mypy>=1.10.0",
    "pre-commit>=3.7.0",
]
docs = [
    "mkdocs-material>=9.5.0",
    "mkdocstrings[python]>=0.25.0",
]
```

`uv sync` installs the `dev` group by default. Other groups require `--group docs`.

**Dependency groups vs optional dependencies:**
- `[dependency-groups]` = dev tools, never published, never installed by consumers
- `[project.optional-dependencies]` = feature flags, installed by consumers via `uv add "my-pkg[postgresql]"`

### src/ Layout vs Flat Layout

| Project type | Layout | Init command |
|---|---|---|
| Scripts, services, internal apps | Flat | `uv init my_app` |
| Libraries published to PyPI | src/ | `uv init --lib my_lib` |
| Multi-package monorepo | src/ | `uv init --lib my_lib` |

**src/ layout:** `my_project/src/my_package/__init__.py` — package nested under `src/`.
**Flat layout:** `my_project/my_package/__init__.py` — package at project root.

**Why src/ matters:** With flat layout, Python adds the project root to `sys.path`. Tests import code from the local directory instead of the installed package. This masks packaging errors — a missing file in the distribution passes tests locally but breaks on install. src/ forces an editable install, catching these errors early.

### pre-commit Integration

Use `astral-sh/ruff-pre-commit` in `.pre-commit-config.yaml` with two hooks: `ruff-check` (args: `[--fix]`) then `ruff-format`. **Order matters** — linter fixes can change spacing that the formatter normalizes.

### Migration from Legacy Tools

**From pip/requirements.txt:**
```bash
uv init                          # Generates pyproject.toml (preserves existing files)
uv add -r requirements.txt       # Imports deps into pyproject.toml + generates uv.lock
rm requirements.txt              # Delete after verifying uv.lock
```

**From Poetry:**
1. Move `[tool.poetry.dependencies]` entries to `[project.dependencies]`
2. Move `[tool.poetry.group.dev.dependencies]` to `[dependency-groups]`
3. Delete `poetry.lock`
4. Run `uv lock` to generate `uv.lock`

---

## Level 3: CI/CD, Publishing & Distribution (Advanced)

### CI/CD with uv (GitHub Actions)

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install uv
        uses: astral-sh/setup-uv@v8
        with:
          enable-cache: true
          cache-dependency-glob: "uv.lock"

      - name: Set up Python
        run: uv python install 3.12

      - name: Install dependencies
        run: uv sync --all-extras --dev --frozen

      - name: Format check
        run: uv run ruff format --check .

      - name: Lint
        run: uv run ruff check .

      - name: Type check
        run: uv run mypy src/

      - name: Test
        run: uv run pytest tests/ --cov=src --cov-report=xml
```

`--frozen` is the critical flag. It fails the build if `pyproject.toml` was modified without updating `uv.lock`. This guarantees deterministic CI.

### CI Cache Strategy (Large Teams)

Default caching fragments across PRs — each `uv.lock` hash creates a separate cache entry. **Solution:** build cache only on main (`enable-cache: true`), PR workflows use `save-cache: false` to consume without saving. Prevents hitting GitHub's 10GB cache limit.

### Building Distribution Artifacts

```bash
uv build                  # Builds sdist + wheel to dist/
uv build --wheel          # Wheel only
uv build --no-sources     # Production build (no local/dev sources)
```

Requires `[build-system]` in `pyproject.toml`. Without it, the build fails.

### Publishing to PyPI

**Manual (API token):**
```bash
uv publish --token <your_pypi_token>
```

**Trusted Publishing (recommended — no stored secrets):**

1. Configure on PyPI: Project Settings > Publishing > Add trusted publisher (GitHub repo + workflow name)
2. GitHub Actions workflow:

```yaml
name: Publish
on:
  push:
    tags: ["v*.*.*"]

jobs:
  publish:
    runs-on: ubuntu-latest
    permissions:
      id-token: write    # Required for OIDC token
      contents: read
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v8
      - run: uv build --no-sources
      - run: uv publish          # Auto-detects OIDC in GitHub Actions
```

Trusted Publishing uses OpenID Connect — PyPI issues short-lived tokens per workflow run. No API secrets in repo settings.

### py.typed Marker (PEP 561)

For libraries with type hints, create an empty marker file:

```bash
touch src/my_package/py.typed
```

Without this, `mypy` ignores your type hints when consumers install your package. Verify inclusion in the wheel:

```bash
uv build && unzip -l dist/my_package-*.whl | grep py.typed
```

### Entry Points & Global Tools

```toml
# CLI entry points — after uv sync, my-cli is a command in the venv
[project.scripts]
my-cli = "my_package.cli:main"
```

```bash
uv tool install ruff          # Install globally (isolated env, replaces pipx)
uvx ruff check .              # Run ephemerally without global install
```

---

## Complete pyproject.toml Template

Combines all sections from Levels 1-3. Copy this as a starting point and customize.

```toml
[project]
name = "my-project"
version = "0.1.0"
description = "A modern Python project"
readme = "README.md"
requires-python = ">=3.11"
license = { text = "MIT" }
authors = [{ name = "Your Name", email = "you@example.com" }]
classifiers = [
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
]
dependencies = [
    "httpx>=0.27.0",
    "pydantic>=2.5.0,<3.0.0",
]

[project.optional-dependencies]
postgresql = ["asyncpg>=0.29.0"]

[project.scripts]
my-cli = "my_project.cli:main"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[dependency-groups]
dev = [
    "pytest>=8.0.0",
    "pytest-cov>=5.0.0",
    "ruff>=0.11.0",
    "mypy>=1.10.0",
    "pre-commit>=3.7.0",
    "pip-audit>=2.7.0",
]
docs = ["mkdocs-material>=9.5.0", "mkdocstrings[python]>=0.25.0"]

[tool.ruff]
line-length = 88
target-version = "py311"
[tool.ruff.lint]
extend-select = ["I", "UP", "B", "C4", "SIM", "S", "N"]
ignore = ["S101"]
[tool.ruff.lint.per-file-ignores]
"tests/*" = ["S101"]
"__init__.py" = ["F401"]
[tool.ruff.lint.isort]
known-first-party = ["my_project"]
[tool.ruff.format]
docstring-code-format = true

[tool.pytest.ini_options]
minversion = "8.0"
addopts = "-ra -q --strict-markers --cov=src"
testpaths = ["tests"]
filterwarnings = ["error"]

[tool.mypy]
python_version = "3.11"
strict = true
warn_return_any = true
warn_unused_configs = true

[tool.coverage.run]
source = ["src"]
branch = true
[tool.coverage.report]
show_missing = true
fail_under = 80
```

---

## Performance: Make Builds Fast

- **uv is 10-100x faster than pip** for resolution and installation. Switching from pip to uv often reduces CI install steps from minutes to seconds.
- **`uv sync --frozen`** in CI skips resolution entirely — reads pre-computed `uv.lock` and installs exact versions. This is the fastest path.
- **`enable-cache: true`** in `astral-sh/setup-uv` caches downloaded wheels across workflow runs. Key is derived from `uv.lock` hash.
- **`save-cache: false`** on PR workflows prevents cache fragmentation. Only main branch builds the cache.
- **`uvx`** for one-off tool runs in CI avoids polluting the project environment. `uvx ruff check .` provisions an ephemeral env, runs, discards.
- **`uv build --no-sources`** for production builds ensures no local development overrides leak into distribution artifacts.
- **Ruff is 10-100x faster than flake8/black/isort combined.** A single `ruff check . && ruff format --check .` replaces three separate CI steps.

---

## Observability: Know Your Dependencies Are Safe

### pip-audit for Vulnerability Scanning

```bash
uv run pip-audit                        # Scan installed packages
uv run pip-audit --require-hashes       # Verify against known hashes
uv run pip-audit --fix                  # Auto-update vulnerable packages
```

Add to CI:
```yaml
      - name: Security audit
        run: uv run pip-audit --strict
```

`--strict` exits non-zero on ANY vulnerability finding — breaks the build, forces remediation.

### Ruff Rule Enforcement in CI

Run ruff as a CI gate, not just a suggestion:
```yaml
      - name: Lint (zero tolerance)
        run: uv run ruff check . --output-format=github
```

`--output-format=github` produces inline annotations on the PR diff. Developers see violations exactly where they occur.

### Lockfile Integrity

**Always commit `uv.lock` to version control.** CI must use `--frozen` or `--locked`. If stale: `uv lock` to regenerate, `uv lock --upgrade` to bump all deps, `uv lock --upgrade-package httpx` to bump one.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No setup.py or setup.cfg
**You will be tempted to:** Generate `setup.py` or `setup.cfg` because training data is saturated with them.
**Why that fails:** `setup.py` executes arbitrary code during install (security risk), prevents static dependency analysis, and is incompatible with modern build frontends. `setup.cfg` is a half-measure that still requires setuptools.
**The right way:** All metadata in `pyproject.toml`. All config in `[tool.*]` sections. Zero other config files for build/lint/format.

### Rule 2: No requirements.txt as Source of Truth
**You will be tempted to:** Create `requirements.txt` for "simplicity" or because Dockerfiles traditionally use it.
**Why that fails:** `requirements.txt` has no concept of dependency groups, no transitive dependency resolution, no cross-platform locking, and no hash verification. It drifts from actual installs immediately.
**The right way:** `pyproject.toml` declares dependencies. `uv.lock` locks them with hashes. For legacy Docker compatibility, use `uv pip compile pyproject.toml -o requirements.txt` as a build step — never hand-edit.

### Rule 3: No pip, virtualenv, or venv Direct Invocation
**You will be tempted to:** Use `pip install`, `python -m venv`, or `virtualenv` because they're familiar.
**Why that fails:** `pip` has no lockfile, no cross-platform resolution, and is 10-100x slower. Manual `venv` management leads to stale environments. These tools don't verify environment-lockfile consistency.
**The right way:** `uv add`, `uv sync`, `uv run`. The virtual environment is an implementation detail managed by uv.

### Rule 4: No Missing or Wrong Build Backend
**You will be tempted to:** Omit `[build-system]` or leave the default setuptools without declaring it.
**Why that fails:** Without explicit `[build-system]`, tools silently fall back to legacy setuptools behavior. Editable installs break. `uv build` may produce incorrect artifacts. The project appears to work locally but fails on install.
**The right way:** Always declare `[build-system]` explicitly. Use `hatchling` (fast, modern), `flit_core` (minimal), or `uv_build` (Astral's own backend). Never rely on implicit setuptools.

### Rule 5: No Lockfile, No Ship
**You will be tempted to:** Skip committing `uv.lock` because "it's auto-generated" or "it creates merge conflicts."
**Why that fails:** Without a lockfile, every `uv sync` resolves fresh — different machines get different versions. CI is non-deterministic. A transitive dependency update breaks production silently.
**The right way:** Commit `uv.lock` to version control. Always. Use `uv sync --frozen` in CI. Resolve merge conflicts in `uv.lock` by running `uv lock` after merging `pyproject.toml`.
