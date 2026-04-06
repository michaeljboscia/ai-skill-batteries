---
name: mx-go-services
description: Go services integration — NATS JetStream publish/subscribe with pull consumers, Temporal workflow determinism rules (workflow.Go/Channel/Selector/Now), activity heartbeating, workflow versioning, gRPC service definitions, Saga compensation pattern, signals and queries, child workflows.
---

# Go Services — NATS, Temporal & gRPC for AI Coding Agents

**Load when integrating message queues, workflow engines, or RPC frameworks in Go.**

## When to also load
- Core Go patterns → `mx-go-core`
- Async patterns for service workers → `mx-go-concurrency`
- HTTP alongside gRPC → `mx-go-http`
- Service metrics → `mx-go-observability`
- Database in activities → `mx-go-data`

---

## Level 1: NATS JetStream

### Connect and Create Stream

```go
nc, err := nats.Connect(nats.DefaultURL,
    nats.MaxReconnects(-1),
    nats.ReconnectWait(2*time.Second),
    nats.DisconnectErrHandler(func(nc *nats.Conn, err error) {
        slog.Warn("NATS disconnected", slog.String("error", err.Error()))
    }),
    nats.ReconnectHandler(func(nc *nats.Conn) {
        slog.Info("NATS reconnected", slog.String("url", nc.ConnectedUrl()))
    }),
)
if err != nil {
    return fmt.Errorf("connect NATS: %w", err)
}
defer nc.Close()

js, err := jetstream.New(nc)
if err != nil {
    return fmt.Errorf("create JetStream: %w", err)
}

// Create or update stream
_, err = js.CreateOrUpdateStream(ctx, jetstream.StreamConfig{
    Name:      "ORDERS",
    Subjects:  []string{"orders.>"},
    Retention: jetstream.WorkQueuePolicy,
    MaxAge:    24 * time.Hour,
    Storage:   jetstream.FileStorage,
    Replicas:  3,
})
```

### Hierarchical Subjects

```
orders.created       — new order events
orders.payment.success
orders.payment.failed
orders.shipped
orders.>             — wildcard: all order events
```

### Pull Consumer — Scalable Work Queue

```go
consumer, err := js.CreateOrUpdateConsumer(ctx, "ORDERS", jetstream.ConsumerConfig{
    Durable:       "order-processor",
    FilterSubject: "orders.created",
    AckPolicy:     jetstream.AckExplicitPolicy,
    MaxDeliver:    3,  // retry up to 3 times
    AckWait:       30 * time.Second,
})
if err != nil {
    return fmt.Errorf("create consumer: %w", err)
}

// Process messages
for {
    msgs, err := consumer.Fetch(10, jetstream.FetchMaxWait(5*time.Second))
    if err != nil {
        if errors.Is(err, context.DeadlineExceeded) {
            continue  // no messages, retry
        }
        return fmt.Errorf("fetch: %w", err)
    }

    for msg := range msgs.Messages() {
        if err := processOrder(ctx, msg.Data()); err != nil {
            slog.Error("process failed",
                slog.String("subject", msg.Subject()),
                slog.String("error", err.Error()),
            )
            msg.Nak()  // negative ack, will be redelivered
            continue
        }
        msg.Ack()
    }
}
```

### Publishing

```go
// Publish with deduplication
ack, err := js.Publish(ctx, "orders.created", orderJSON,
    jetstream.WithMsgID(orderID),  // dedup within window
)
if err != nil {
    return fmt.Errorf("publish order: %w", err)
}
slog.Info("published", slog.Uint64("seq", ack.Sequence))
```

---

## Level 2: Temporal Workflows

### CRITICAL: Workflow Determinism Rules

Workflow code MUST be deterministic — it replays from history on restart.

| FORBIDDEN in Workflows | USE INSTEAD |
|----------------------|-------------|
| `go func(){}()` | `workflow.Go(ctx, func(ctx workflow.Context){})` |
| `chan T` | `workflow.Channel` |
| `select {}` | `workflow.Selector` |
| `context.Context` | `workflow.Context` |
| `time.Now()` | `workflow.Now(ctx)` |
| `time.Sleep()` | `workflow.Sleep(ctx, d)` |
| `time.After()` | `workflow.NewTimer(ctx, d)` |
| `uuid.New()` | `workflow.SideEffect(ctx, func() any { return uuid.New() })` |
| `rand.Int()` | `workflow.SideEffect(ctx, func() any { return rand.Int() })` |
| `map` iteration (non-deterministic order) | Sort keys first or use `workflow.SideEffect` |
| Standard logger | `workflow.GetLogger(ctx)` |
| Standard metrics | `workflow.GetMetricsHandler(ctx)` |

### Workflow Definition

```go
func OrderWorkflow(ctx workflow.Context, order Order) (OrderResult, error) {
    logger := workflow.GetLogger(ctx)
    logger.Info("starting order workflow", "orderID", order.ID)

    // Activity options
    actCtx := workflow.WithActivityOptions(ctx, workflow.ActivityOptions{
        StartToCloseTimeout: 30 * time.Second,
        RetryPolicy: &temporal.RetryPolicy{
            InitialInterval:    time.Second,
            BackoffCoefficient: 2.0,
            MaximumInterval:    time.Minute,
            MaximumAttempts:    3,
        },
    })

    // Execute activities sequentially
    var paymentResult PaymentResult
    if err := workflow.ExecuteActivity(actCtx, activities.ChargePayment, order).Get(ctx, &paymentResult); err != nil {
        return OrderResult{}, fmt.Errorf("charge payment: %w", err)
    }

    var shipResult ShipResult
    if err := workflow.ExecuteActivity(actCtx, activities.ShipOrder, order).Get(ctx, &shipResult); err != nil {
        // Saga: compensate by refunding
        _ = workflow.ExecuteActivity(actCtx, activities.RefundPayment, paymentResult).Get(ctx, nil)
        return OrderResult{}, fmt.Errorf("ship order: %w", err)
    }

    return OrderResult{
        PaymentID:  paymentResult.ID,
        TrackingNo: shipResult.TrackingNo,
    }, nil
}
```

### Activities — Standard Go Allowed

```go
// Activities CAN use standard Go: goroutines, channels, loggers, etc.
// Parameters and returns MUST be serializable

type Activities struct {
    db    *pgxpool.Pool   // shared resources via struct
    nats  *nats.Conn
}

func (a *Activities) ChargePayment(ctx context.Context, order Order) (PaymentResult, error) {
    // Standard context.Context here (NOT workflow.Context)
    // Can use any Go library normally

    result, err := a.processPayment(ctx, order)
    if err != nil {
        return PaymentResult{}, fmt.Errorf("charge: %w", err)
    }
    return result, nil
}

// Heartbeating for long-running activities
func (a *Activities) ProcessLargeFile(ctx context.Context, fileID string) error {
    for i, chunk := range chunks {
        select {
        case <-ctx.Done():
            return ctx.Err()
        default:
            processChunk(chunk)
            activity.RecordHeartbeat(ctx, i)  // report progress
        }
    }
    return nil
}
```

### Workflow Versioning (Safe Deployments)

```go
func MyWorkflow(ctx workflow.Context) error {
    // Version 1 → Version 2: changed activity
    v := workflow.GetVersion(ctx, "change-activity", workflow.DefaultVersion, 1)

    if v == workflow.DefaultVersion {
        // Old path — for workflows started before this change
        workflow.ExecuteActivity(ctx, OldActivity).Get(ctx, nil)
    } else {
        // New path — for workflows started after deployment
        workflow.ExecuteActivity(ctx, NewActivity).Get(ctx, nil)
    }

    return nil
}
```

### Signals and Queries

```go
func ApprovalWorkflow(ctx workflow.Context, request Request) error {
    // Signal channel for external input
    approvalCh := workflow.GetSignalChannel(ctx, "approval")
    var approved bool

    // Wait for signal or timeout
    selector := workflow.NewSelector(ctx)
    selector.AddReceive(approvalCh, func(ch workflow.ReceiveChannel, more bool) {
        ch.Receive(ctx, &approved)
    })
    selector.AddReceive(workflow.NewTimer(ctx, 24*time.Hour).GetChannel(), func(ch workflow.ReceiveChannel, more bool) {
        approved = false  // timeout → reject
    })
    selector.Select(ctx)

    if !approved {
        return fmt.Errorf("approval denied or timed out")
    }

    return workflow.ExecuteActivity(ctx, ProcessApproved, request).Get(ctx, nil)
}

// Query — read-only, MUST NOT mutate state
func init() {
    workflow.RegisterQueryHandler(ctx, "status", func() (string, error) {
        return currentStatus, nil  // read-only
    })
}
```

---

## Level 3: Worker and Integration Patterns

### Temporal Worker Setup

```go
func main() {
    c, err := client.Dial(client.Options{
        HostPort:  "localhost:7233",
        Namespace: "production",
    })
    if err != nil {
        log.Fatal(err)
    }
    defer c.Close()

    w := worker.New(c, "order-task-queue", worker.Options{
        MaxConcurrentActivityExecutionSize:     10,
        MaxConcurrentWorkflowTaskExecutionSize: 5,
    })

    // Register workflows and activities
    w.RegisterWorkflow(OrderWorkflow)
    w.RegisterWorkflow(ApprovalWorkflow)

    acts := &Activities{db: pool, nats: nc}
    w.RegisterActivity(acts)

    if err := w.Run(worker.InterruptCh()); err != nil {
        log.Fatal(err)
    }
}
```

### Saga Pattern with Compensation

```go
func SagaWorkflow(ctx workflow.Context, order Order) error {
    var compensations []func(workflow.Context) error

    // Step 1: Reserve inventory
    err := workflow.ExecuteActivity(ctx, ReserveInventory, order).Get(ctx, nil)
    if err != nil {
        return err
    }
    compensations = append(compensations, func(ctx workflow.Context) error {
        return workflow.ExecuteActivity(ctx, ReleaseInventory, order).Get(ctx, nil)
    })

    // Step 2: Charge payment
    err = workflow.ExecuteActivity(ctx, ChargePayment, order).Get(ctx, nil)
    if err != nil {
        return compensate(ctx, compensations)
    }
    compensations = append(compensations, func(ctx workflow.Context) error {
        return workflow.ExecuteActivity(ctx, RefundPayment, order).Get(ctx, nil)
    })

    // Step 3: Ship
    err = workflow.ExecuteActivity(ctx, ShipOrder, order).Get(ctx, nil)
    if err != nil {
        return compensate(ctx, compensations)
    }

    return nil
}

func compensate(ctx workflow.Context, compensations []func(workflow.Context) error) error {
    // Run compensations in reverse order
    for i := len(compensations) - 1; i >= 0; i-- {
        if err := compensations[i](ctx); err != nil {
            workflow.GetLogger(ctx).Error("compensation failed", "error", err)
            // Log but continue — best effort
        }
    }
    return fmt.Errorf("saga compensated")
}
```

### NATS → Temporal → gRPC Integration

```go
// Pattern: NATS event triggers Temporal workflow, activities use gRPC
func handleNATSMessage(ctx context.Context, msg jetstream.Msg) error {
    var event OrderEvent
    if err := json.Unmarshal(msg.Data(), &event); err != nil {
        return fmt.Errorf("unmarshal: %w", err)
    }

    // Start Temporal workflow
    run, err := temporalClient.ExecuteWorkflow(ctx,
        client.StartWorkflowOptions{
            ID:        "order-" + event.OrderID,
            TaskQueue: "order-task-queue",
        },
        OrderWorkflow,
        event.Order,
    )
    if err != nil {
        return fmt.Errorf("start workflow: %w", err)
    }

    slog.Info("workflow started",
        slog.String("workflow_id", run.GetID()),
        slog.String("run_id", run.GetRunID()),
    )
    return nil
}
```

---

## Performance: Make It Fast

### NATS Performance

| Tuning | How |
|--------|-----|
| Batch fetch | `consumer.Fetch(100)` — fewer round trips |
| Pull over push | Pull consumers scale better across workers |
| Subject hierarchy | Narrow subjects reduce fan-out |
| FileStorage for durability | MemoryStorage for speed (non-critical data) |

### Temporal Performance

| Tuning | How |
|--------|-----|
| Worker concurrency | `MaxConcurrentActivityExecutionSize` based on resource capacity |
| Activity timeouts | Tight `StartToCloseTimeout` prevents stuck activities |
| Heartbeat interval | Every 10-30s for long activities |
| Workflow history | Keep under 10K events — use ContinueAsNew for long-running |

---

## Observability: Know It's Working

### NATS Monitoring

```go
// Track message processing metrics
slog.Info("message processed",
    slog.String("subject", msg.Subject()),
    slog.Duration("processing_time", elapsed),
    slog.Int("pending", consumer.CachedInfo().NumPending),
    slog.Int("redelivered", int(msg.Headers().Get("Nats-Num-Delivered"))),
)
```

### Temporal Observability

```go
// Temporal client with OTel integration
c, err := client.Dial(client.Options{
    HostPort: "localhost:7233",
    Logger:   temporalSlogAdapter(logger),
    // Temporal SDK auto-emits metrics: workflow_completed, activity_execution_failed, etc.
})
```

**Key Temporal metrics:**
- `workflow_completed` / `workflow_failed` — success rate
- `activity_execution_latency` — slow activities
- `workflow_task_schedule_to_start_latency` — worker capacity
- `activity_schedule_to_start_latency` — task queue backup

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: NEVER Use Standard Go Concurrency in Temporal Workflows
**You will be tempted to:** Use `go func()`, `chan`, `select`, or `time.Now()` in workflow code because "it's simpler."
**Why that fails:** Temporal replays workflow code from event history. Standard Go concurrency is non-deterministic — goroutine scheduling, channel timing, system clock all change between replays. The workflow corrupts and becomes unreplayable.
**The right way:** `workflow.Go`, `workflow.Channel`, `workflow.Selector`, `workflow.Now(ctx)` — always. Use the `workflowcheck` linter to catch violations.

### Rule 2: Activities MUST Be Idempotent
**You will be tempted to:** Write activities that assume exactly-once execution.
**Why that fails:** Temporal retries activities on failure. If `ChargePayment` charges but fails to return the result (network issue), it retries — double charge. Activities MUST handle being called multiple times for the same input.
**The right way:** Idempotency keys, deduplication checks, or database unique constraints to prevent duplicate effects.

### Rule 3: Queries Must Never Mutate State
**You will be tempted to:** Update a status field or counter inside a query handler.
**Why that fails:** Queries execute on the current workflow state without recording events. Mutations during queries aren't persisted in history. On replay, the mutation is lost — the workflow diverges from its recorded history.
**The right way:** Queries are read-only. Use signals to mutate workflow state.

### Rule 4: Always Ack/Nak NATS Messages
**You will be tempted to:** Let messages time out instead of explicitly Nak-ing on error.
**Why that fails:** AckWait timeout (default 30s) delays redelivery. The message sits in limbo while another worker could be processing it. Explicit Nak triggers immediate redelivery.
**The right way:** `msg.Ack()` on success, `msg.Nak()` on retryable error, `msg.Term()` on permanent failure.

### Rule 5: Use workflow.SideEffect for Non-Deterministic Values
**You will be tempted to:** Call `uuid.New()` or `rand.Int()` directly in workflow code.
**Why that fails:** These produce different values on replay. The workflow diverges from history — Temporal marks it as non-deterministic and blocks execution.
**The right way:** `workflow.SideEffect(ctx, func(ctx workflow.Context) any { return uuid.New().String() })` — the value is stored in history and reused on replay.
