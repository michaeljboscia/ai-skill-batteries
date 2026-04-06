---
name: mx-py-data
description: Python data processing — Pandas, Polars, serialization, file I/O, Pydantic validation, Arrow, Parquet. Use when handling DataFrames, validation boundaries, columnar storage, or bulk data transformations.
---

# Python Data Processing — Polars, Pandas, Pydantic v2, Arrow & Serialization

**This skill loads when working with DataFrames, data validation, file I/O, or serialization.**

## When to also load
- `mx-py-core` — always co-loads (dataclass vs Pydantic decision table lives there)
- `mx-py-perf` — co-loads for ANY Python work (profiling, Arrow zero-copy, memory)
- `mx-py-database` — when data flows to/from SQL (SQLAlchemy 2.0, connection pooling)
- `mx-py-observability` — co-loads for ANY Python work (structlog, OTel)

---

## Level 1: Foundations (Beginner)

### Polars Lazy Evaluation: scan -> chain -> collect

Polars builds a query plan DAG. Nothing executes until `.collect()`. The optimizer rewrites the plan — predicate pushdown, projection pushdown, common subplan elimination — before touching data.

```python
import polars as pl

# GOOD: scan registers the file but reads nothing
result = (
    pl.scan_parquet("events.parquet")
    .filter(pl.col("status") == "ERROR")
    .select(["timestamp", "user_id", "error_code"])
    .group_by("error_code")
    .agg(pl.len().alias("count"))
    .collect()  # Optimizer runs here — only needed columns/rows leave disk
)
```

**BAD: Eager execution wastes RAM on intermediate frames**
```python
# BAD: read_parquet loads everything immediately
df = pl.read_parquet("events.parquet")        # Full file in RAM
df = df.filter(pl.col("status") == "ERROR")   # New intermediate frame
df = df.select(["timestamp", "user_id", "error_code"])  # Another copy
```

**Rule:** Default to `scan_*` + `.collect()`. Use `read_*` only for tiny datasets in interactive exploration.

### Pydantic v2: Boundary Validation

Pydantic validates untrusted data at system edges. Rust core makes it 5-50x faster than v1.

```python
from pydantic import BaseModel, SecretStr, ConfigDict, field_validator, computed_field

class IncomingOrder(BaseModel):
    model_config = ConfigDict(strict=True)  # Rejects "123" for int fields

    order_id: int
    amount: float
    currency: str
    api_key: SecretStr  # Masked in logs and .model_dump()

    @field_validator("currency")
    @classmethod
    def normalize_currency(cls, v: str) -> str:
        v = v.upper()
        if v not in {"USD", "EUR", "GBP"}:
            raise ValueError(f"Unsupported currency: {v}")
        return v

    @computed_field
    @property
    def amount_cents(self) -> int:
        return int(self.amount * 100)

# GOOD: Parses bytes directly via Rust — no intermediate dict
order = IncomingOrder.model_validate_json(raw_bytes)

# GOOD: Skip validation for trusted internal data (e.g., from own DB)
trusted = IncomingOrder.model_construct(order_id=1, amount=9.99, currency="USD")
```

**Key v2 migration points:**
- `model_validate()` replaces `parse_obj()`
- `model_validate_json()` replaces `parse_raw()` — parses directly, no `json.loads` needed
- `@field_validator` replaces `@validator`
- `@model_validator` replaces `@root_validator`
- `model_config = ConfigDict(...)` replaces inner `Config` class
- `model_construct()` bypasses validation — ONLY for trusted data

### Vectorization Over Loops

Performance hierarchy for both Polars and Pandas:

| Approach | Relative Speed | Use when |
|----------|---------------|----------|
| Vectorized column ops | 1x (fastest) | Always the first choice |
| `.map()` on Series | ~5-10x slower | Simple element transforms |
| `.apply(axis=1)` | ~50-100x slower | Avoid — not truly vectorized |
| `itertuples()` | ~200x slower | Never for data ops |
| `iterrows()` | ~500-1000x slower | **Never. Period.** |

```python
# BAD: Python loop disguised as DataFrame operation
df["profit"] = df.apply(lambda row: row["revenue"] - row["cost"], axis=1)

# GOOD: Vectorized — runs in C/Rust, not Python
df["profit"] = df["revenue"] - df["cost"]
```

---

## Level 2: Expressions & Pandas Modernization (Intermediate)

### Polars Expressions DSL

Expressions are the core of Polars. Every transformation compiles to a parallelizable, SIMD-capable plan.

**`col`, `when/then/otherwise`:**
```python
import polars as pl

df = df.with_columns(
    # Conditional logic without Python lambdas
    pl.when(pl.col("price") > 100)
    .then(pl.col("price") * 0.9)
    .otherwise(pl.col("price"))
    .alias("final_price"),

    # Multiple columns in one with_columns call
    pl.col("name").str.to_uppercase().alias("NAME"),
    (pl.col("qty") * pl.col("price")).alias("line_total"),
)
```

**Window functions (`over`)** — grouped computation without collapsing rows:
```python
df = df.with_columns(
    # Average price per category (like SQL OVER PARTITION BY)
    pl.col("price").mean().over("category").alias("avg_cat_price"),

    # Rank within each group
    pl.col("revenue").rank(descending=True).over("region").alias("region_rank"),

    # Running sum partitioned by user
    pl.col("amount").cum_sum().over("user_id").alias("running_total"),
)
```

**Structs and Lists** — native nested types (no `object` dtype):
```python
# Pack columns into a struct
df = df.with_columns(
    pl.struct(["city", "state"]).alias("location")
)

# Explode list column into rows
df_exploded = df.explode("tags")

# Unnest struct back to columns
df_flat = df.unnest("location")
```

**Datetime processing** — timezone-aware, multi-threaded:
```python
df = df.with_columns(
    pl.col("ts_str")
    .str.strptime(pl.Datetime, format="%Y-%m-%d %H:%M:%S")
    .dt.replace_time_zone("UTC")
    .alias("timestamp"),
).with_columns(
    pl.col("timestamp").dt.offset_by("1mo").alias("next_month")
)
```

### Pandas 3.0: Copy-on-Write & Modern Patterns

Pandas 3.0 makes Copy-on-Write (CoW) the sole mode. Key changes:

```python
import pandas as pd

# Chained assignment now raises — this is GOOD, it was always broken
# df[df["A"] > 0]["B"] = 1  # ChainedAssignmentError

# GOOD: Use .loc for conditional assignment
df.loc[df["A"] > 0, "B"] = 1

# GOOD: eval/query for C-speed on large DataFrames (>10K rows)
result = df.query("revenue > @threshold and region == 'US'")
df["profit"] = df.eval("revenue - cost")

# GOOD: Arrow-backed dtypes for zero-copy interop
df = pd.read_parquet("data.parquet", dtype_backend="pyarrow")
```

**dtype optimization matters:**
```python
# BAD: Default float64 everywhere
df = pd.read_csv("data.csv")

# GOOD: Specify dtypes, use categories for low-cardinality strings
df = pd.read_csv("data.csv", dtype={
    "amount": "float32",
    "category": "category",
    "name": "string[pyarrow]",  # Arrow string, not object
}, usecols=["amount", "category", "name"])  # Never load columns you don't need
```

---

## Level 3: File I/O, Serialization & Arrow Interop (Advanced)

### Parquet I/O with PyArrow

PyArrow is the 2025 standard for Parquet. Three critical optimizations:

1. **Column projection** — only read columns you need (skips others at disk level)
2. **Predicate pushdown** — filter via row group statistics before decoding
3. **ZSTD compression** — best ratio+speed balance for storage and egress

```python
import pyarrow.parquet as pq
import pyarrow.dataset as ds
import pyarrow.compute as pc

# WRITING: ZSTD compression with reasonable row groups
pq.write_table(
    table,
    "output.parquet",
    compression="zstd",
    compression_level=6,
    row_group_size=256 * 1024 * 1024,  # 256MB uncompressed per group
)

# READING: Dataset API for pushdown + projection
dataset = ds.dataset("s3://lake/transactions/", format="parquet")
scanner = dataset.scanner(
    columns=["user_id", "revenue"],                # Projection: only these columns
    filter=pc.field("country") == "US",            # Pushdown: skip non-matching row groups
)
table = scanner.to_table()

# POLARS: Same optimizations built into scan_parquet
result = (
    pl.scan_parquet("s3://lake/transactions/")
    .filter(pl.col("country") == "US")
    .select(["user_id", "revenue"])
    .collect()
)
```

**Compression decision:**

| Compression | Use case | Tradeoff |
|-------------|----------|----------|
| ZSTD | Default for cold/warm data | Best ratio, low CPU |
| Snappy | Hot data, high-frequency reads | Fastest decode, larger files |
| GZIP | Maximum compression archival | Highest CPU cost |

**Partition strategy:** Partition by columns you frequently filter on. Avoid over-partitioning (thousands of tiny files kill metadata overhead).

### Serialization: msgspec vs orjson Decision Table

| Need | Use | Why |
|------|-----|-----|
| Decode + validate JSON | `msgspec` | 10-80x faster than stdlib. Zero-overhead `Struct` validation |
| Decode JSON, no schema | `orjson` | Rust-based, great for large float arrays |
| Complex API boundary validation | `Pydantic v2` | Ecosystem standard, rich validators, `model_validate_json` |
| MessagePack / binary protocols | `msgspec` | Multi-format: JSON, MessagePack, YAML, TOML |
| `json.loads` / `json.dumps` | **Never in production** | Allocates massive intermediate Python objects, triggers GC pauses |

```python
import msgspec

# Define a zero-overhead struct (5-60x faster than dataclass)
class Event(msgspec.Struct):
    event_id: str
    timestamp: float
    payload: dict

# Decode + validate in one pass
decoder = msgspec.json.Decoder(Event)
event = decoder.decode(raw_bytes)

# Encode — faster than orjson for structured types
encoder = msgspec.json.Encoder()
encoded = encoder.encode(event)
```

### Streaming Mode for Larger-than-RAM Data

```python
# Polars streaming processes data in batches, spills to disk when needed
result = (
    pl.scan_parquet("massive_dataset/")
    .filter(pl.col("year") >= 2024)
    .group_by("region")
    .agg(pl.col("revenue").sum())
    .collect(engine="streaming")  # Morsel-driven parallelism
)

# sink_parquet writes directly without materializing full result
(
    pl.scan_parquet("raw_logs/")
    .filter(pl.col("level") == "ERROR")
    .select(["ts", "message", "service"])
    .sink_parquet("error_logs.parquet", compression="zstd")
)
```

### Arrow Interop: Zero-Copy Between Frameworks

```python
import polars as pl
import pandas as pd
import pyarrow as pa

# Polars -> Arrow -> Pandas (zero-copy when possible)
polars_df = pl.scan_parquet("features.parquet").filter(...).collect()
arrow_table = polars_df.to_arrow()       # Zero-copy: shared memory
pandas_df = arrow_table.to_pandas()       # Zero-copy with Arrow-backed dtypes

# Pandas -> Arrow -> Polars
arrow_from_pd = pa.Table.from_pandas(pandas_df)
polars_from_pd = pl.from_arrow(arrow_from_pd)

# Direct Polars <-> Pandas
pandas_df = polars_df.to_pandas()         # Convenience, uses Arrow internally
polars_df = pl.from_pandas(pandas_df)
```

**Rule:** Stay in Arrow as long as possible. Every conversion to Python objects is a cliff.

---

## Polars vs Pandas Decision Table

| Scenario | Use | Rationale |
|----------|-----|-----------|
| ETL pipelines, heavy aggregations | **Polars** | Multi-threaded, query optimizer, 10-100x faster |
| Datasets larger than RAM | **Polars** | Streaming mode handles out-of-core transparently |
| Complex nested data (JSON, lists) | **Polars** | Native Arrow structs/lists, no `object` dtype |
| ML ecosystem (scikit-learn, XGBoost) | **Pandas** | Most ML libs expect Pandas/NumPy input |
| Interactive exploration, small data | **Pandas** | Richest API, vast community, low overhead |
| Visualization (matplotlib, seaborn) | **Pandas** | Direct integration, no conversion needed |
| Hybrid: ETL then ML | **Both** | Polars for transforms, Arrow zero-copy to Pandas for modeling |

---

## Performance: Make It Fast

- **Polars over Pandas for any ETL pipeline** — multi-threaded, lazy, optimizer
- **Arrow-backed dtypes in Pandas** — `dtype_backend="pyarrow"` for zero-copy interop
- **Never load all columns** — always specify column projection in `scan_parquet`, `read_parquet`, `read_csv`
- **ZSTD for Parquet** — best compression-to-speed ratio for analytical workloads
- **msgspec for hot-path JSON** — 10-80x faster than stdlib, zero-overhead validation
- **`model_validate_json()` over `json.loads()` + `model_validate()`** — skips intermediate dict
- **`model_construct()` for trusted data** — zero validation overhead in internal loops
- **Polars `collect_all()` for multiple queries** — common subplan elimination shares computation
- **Dictionary encoding** for low-cardinality string columns in Parquet

See `mx-py-perf` for profiling workflows and memory optimization patterns.

---

## Observability: Know Your Data Is Correct

- **Schema validation at every boundary** — validate incoming JSON/CSV/API data before it enters the pipeline
- **Data quality checks after transforms** — null counts, value ranges, cardinality checks
- **Log row counts at pipeline stages** — catch silent data loss early
- **Use `.explain()` on Polars LazyFrames** — verify the optimizer pushes predicates/projections where expected
- **Pydantic `ValidationError` surfacing** — structured error output tells you exactly which field failed and why
- **Arrow schema comparison** — verify input schema matches expected schema before processing

See `mx-py-observability` for structlog, OTel, and Sentry patterns.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: iterrows() Is Never Acceptable
**You will be tempted to:** Use `iterrows()` or row-by-row Python loops because "the logic is complex" or "it's only a few thousand rows."
**Why that fails:** Row iteration in a columnar engine is 500-1000x slower than vectorized ops. It breaks Arrow's memory layout, bypasses SIMD, and forces Python object allocation for every cell. "A few thousand rows" becomes millions next quarter.
**The right way:** Polars expressions (`when/then`, `over`, `explode`, `unnest`, `fold`). Pandas vectorized ops, `.str` accessor, logical conditions. If you truly cannot express it vectorized, use `map_batches()` in Polars or `np.vectorize()` as last resort.

### Rule 2: Loading All Columns from Parquet/CSV
**You will be tempted to:** Call `read_parquet("file.parquet")` or `pd.read_csv("file.csv")` without specifying columns because "I might need them later."
**Why that fails:** Columnar formats exist so you can skip columns at the I/O layer. Loading 100 columns when you need 3 wastes disk bandwidth, RAM, and destroys cache locality. On cloud storage, you pay for every byte transferred.
**The right way:** Always specify `columns=` (Polars/PyArrow) or `usecols=` (Pandas). Use `scan_parquet` with `.select()` to let the optimizer handle projection.

### Rule 3: Pydantic for Internal Data Processing
**You will be tempted to:** Pass Pydantic models through analytical pipelines because "validation everywhere is safer."
**Why that fails:** Pydantic's coercion and validation has meaningful CPU overhead. Aggregating over lists of Pydantic objects instead of columnar data is orders of magnitude slower. Memory fragments into per-object Python heap allocations instead of contiguous Arrow buffers.
**The right way:** Validate at system boundaries (API ingress, file loading, external service responses). Extract to Arrow/Polars immediately after validation. Use `dataclass(slots=True)` or plain dicts internally. See `mx-py-core` for the full dataclass vs Pydantic decision table.

### Rule 4: stdlib json in Production Hot Paths
**You will be tempted to:** Use `json.loads()` / `json.dumps()` because "it's in the standard library" and "we don't want extra dependencies."
**Why that fails:** stdlib json allocates massive intermediate Python objects per parse, triggering GC pauses under load. It has zero schema validation — you parse first, then validate separately, doubling the work.
**The right way:** `msgspec` for high-throughput decode+validate. `orjson` for unstructured fast decode. `Pydantic v2 model_validate_json()` for boundary validation (parses via Rust, no intermediate dict).

### Rule 5: No Schema Validation at Data Boundaries
**You will be tempted to:** Trust incoming data from APIs, files, or message queues because "the upstream system is reliable" or "we control both sides."
**Why that fails:** Upstream schemas change without notice. CSV files arrive with swapped columns. API responses add nullable fields. Silent data corruption propagates through your entire pipeline before anyone notices.
**The right way:** Validate schema at every ingress point. Use Pydantic `strict=True` for API data. Verify Arrow schemas match expectations before processing Parquet. Add null-count and value-range assertions after critical transforms.
