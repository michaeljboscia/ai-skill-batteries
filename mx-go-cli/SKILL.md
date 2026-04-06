---
name: mx-go-cli
description: Go CLI and subprocess management — Cobra commands with RunE, flag design, Viper config layering, os/exec subprocess lifecycle, process groups with Setpgid, signal handling with signal.NotifyContext, graceful termination, SIGTERM vs SIGKILL, orphan prevention.
---

# Go CLI & Process Management — Commands and Subprocesses for AI Coding Agents

**Load when building CLI tools with Cobra, managing subprocesses, or handling OS signals.**

## When to also load
- Core Go patterns → `mx-go-core`
- Signal-aware goroutines → `mx-go-concurrency`
- HTTP server graceful shutdown → `mx-go-http`

---

## Level 1: Cobra CLI Fundamentals

### Command Structure — RunE Over Run

```go
// BAD — Run swallows errors
var rootCmd = &cobra.Command{
    Use:   "myapp",
    Run: func(cmd *cobra.Command, args []string) {
        if err := doStuff(); err != nil {
            fmt.Fprintf(os.Stderr, "error: %v\n", err)
            os.Exit(1)  // skips defers, no cleanup
        }
    },
}

// GOOD — RunE propagates errors cleanly
var rootCmd = &cobra.Command{
    Use:           "myapp",
    SilenceUsage:  true,   // don't print usage on app errors
    SilenceErrors: true,   // we handle error display
    RunE: func(cmd *cobra.Command, args []string) error {
        return doStuff()
    },
}

func main() {
    if err := rootCmd.Execute(); err != nil {
        fmt.Fprintf(os.Stderr, "error: %v\n", err)
        os.Exit(1)
    }
}
```

### Flag Design

```go
func init() {
    // Persistent flags — inherited by all subcommands
    rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file path")
    rootCmd.PersistentFlags().BoolVar(&verbose, "verbose", false, "enable verbose output")

    // Local flags — this command only
    serveCmd.Flags().IntVar(&port, "port", 8080, "server port")
    serveCmd.Flags().DurationVar(&timeout, "timeout", 30*time.Second, "request timeout")

    // Required flags
    serveCmd.MarkFlagRequired("port")
}
```

### Command Organization

```
cmd/
├── root.go        // rootCmd + global flags
├── serve.go       // serveCmd
├── migrate.go     // migrateCmd
└── version.go     // versionCmd
```

**Keep command depth shallow:** `app → resource → action` (3 levels max).

### Viper Config Layering

```go
// Priority: flags > env > config file > defaults
func initConfig() {
    if cfgFile != "" {
        viper.SetConfigFile(cfgFile)
    } else {
        viper.SetConfigName("config")
        viper.SetConfigType("yaml")
        viper.AddConfigPath(".")
        viper.AddConfigPath("$HOME/.myapp")
    }

    viper.SetEnvPrefix("MYAPP")        // MYAPP_PORT, MYAPP_DB_HOST
    viper.AutomaticEnv()
    viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))

    if err := viper.ReadInConfig(); err != nil {
        if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
            slog.Error("config error", slog.String("error", err.Error()))
        }
    }
}
```

---

## Level 2: Subprocess Management

### Basic Execution with Context

```go
// GOOD — context-controlled with combined output
ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
defer cancel()

cmd := exec.CommandContext(ctx, "ffmpeg", "-i", input, "-o", output)
out, err := cmd.CombinedOutput()
if err != nil {
    return fmt.Errorf("ffmpeg failed: %w\noutput: %s", err, out)
}
```

### Process Groups — Kill the Entire Tree

```go
// BAD — only kills direct child, grandchildren become orphans
cmd := exec.Command("bash", "-c", "node server.js")
cmd.Process.Kill()  // node may spawn workers — they survive

// GOOD — process group kills entire tree
cmd := exec.Command("bash", "-c", "node server.js")
cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

if err := cmd.Start(); err != nil {
    return fmt.Errorf("start: %w", err)
}

// Kill entire process group (negative PID)
pgid := cmd.Process.Pid
syscall.Kill(-pgid, syscall.SIGTERM)
```

### Graceful Termination Pattern

```go
func runWithGracefulStop(ctx context.Context, name string, args ...string) error {
    cmd := exec.Command(name, args...)
    cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
    cmd.Stdout = os.Stdout
    cmd.Stderr = os.Stderr

    if err := cmd.Start(); err != nil {
        return fmt.Errorf("start %s: %w", name, err)
    }

    // Wait for context cancellation or process exit
    done := make(chan error, 1)
    go func() { done <- cmd.Wait() }()

    select {
    case err := <-done:
        return err  // process exited on its own
    case <-ctx.Done():
        // Graceful: SIGTERM → wait → SIGKILL
        pgid := cmd.Process.Pid
        syscall.Kill(-pgid, syscall.SIGTERM)

        select {
        case <-done:
            return ctx.Err()
        case <-time.After(5 * time.Second):
            syscall.Kill(-pgid, syscall.SIGKILL)
            <-done
            return ctx.Err()
        }
    }
}
```

### Go 1.22+ Cmd.Interrupt Field

```go
// Go 1.22+: customize signal on context cancel (default is SIGKILL)
cmd := exec.CommandContext(ctx, "server")
cmd.Cancel = func() error {
    return cmd.Process.Signal(syscall.SIGTERM)  // SIGTERM instead of SIGKILL
}
cmd.WaitDelay = 5 * time.Second  // time between SIGTERM and SIGKILL
```

---

## Level 3: Signal Handling

### Parent Process Signal Handling

```go
func main() {
    ctx, stop := signal.NotifyContext(context.Background(),
        syscall.SIGINT, syscall.SIGTERM)
    defer stop()

    // Pass ctx to all long-running operations
    if err := run(ctx); err != nil && err != context.Canceled {
        slog.Error("fatal", slog.String("error", err.Error()))
        os.Exit(1)
    }
}

func run(ctx context.Context) error {
    // ctx.Done() fires on SIGINT/SIGTERM
    // All child contexts inherit cancellation
    g, ctx := errgroup.WithContext(ctx)

    g.Go(func() error { return startServer(ctx) })
    g.Go(func() error { return startWorker(ctx) })

    return g.Wait()
}
```

### Output Format Support

```go
// Support multiple output formats for machine/human consumption
var outputFormat string

func init() {
    rootCmd.PersistentFlags().StringVarP(&outputFormat, "output", "o", "table", "output format (table|json|yaml)")
}

func printOutput(data any) error {
    switch outputFormat {
    case "json":
        enc := json.NewEncoder(os.Stdout)
        enc.SetIndent("", "  ")
        return enc.Encode(data)
    case "yaml":
        out, err := yaml.Marshal(data)
        if err != nil { return err }
        fmt.Print(string(out))
        return nil
    default:
        return printTable(data)
    }
}
```

---

## Performance: Make It Fast

### Subprocess Startup

- Avoid shell wrappers when possible: `exec.Command("git", "status")` not `exec.Command("bash", "-c", "git status")`
- Reuse long-running subprocesses instead of spawning per-operation
- For high-throughput: communicate via stdin/stdout pipes instead of temp files

### Resource Cleanup

```go
// Always cmd.Wait() after cmd.Start() — releases OS resources
if err := cmd.Start(); err != nil { return err }
defer cmd.Wait()  // even if you kill the process
```

---

## Observability: Know It's Working

### Subprocess Monitoring

```go
// Log process lifecycle events
slog.Info("subprocess started",
    slog.String("cmd", name),
    slog.Int("pid", cmd.Process.Pid),
)

err := cmd.Wait()
exitCode := 0
if exitErr, ok := err.(*exec.ExitError); ok {
    exitCode = exitErr.ExitCode()
}
slog.Info("subprocess exited",
    slog.String("cmd", name),
    slog.Int("pid", cmd.Process.Pid),
    slog.Int("exit_code", exitCode),
    slog.Duration("duration", time.Since(start)),
)
```

### Signal Logging

```go
// Log which signal triggered shutdown
ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
defer stop()
<-ctx.Done()
slog.Info("received signal, shutting down", slog.String("signal", ctx.Err().Error()))
```

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Always Use RunE, Never Run
**You will be tempted to:** Use `Run` and handle errors with `fmt.Fprintf + os.Exit(1)`.
**Why that fails:** `os.Exit` skips all deferred cleanup. Database connections, temp files, log flushes — all abandoned. RunE propagates errors to the root command where they're handled once.
**The right way:** `RunE` on every command. Handle the error in `main()`.

### Rule 2: Kill the Process Group, Not Just the Child
**You will be tempted to:** Call `cmd.Process.Kill()` to stop a subprocess.
**Why that fails:** Kill only hits the direct child. If that child spawned workers (Node, Python, shell scripts), the workers become orphans that run forever.
**The right way:** `SysProcAttr{Setpgid: true}` + `syscall.Kill(-pgid, signal)` to kill the entire tree.

### Rule 3: exec.CommandContext Sends SIGKILL by Default
**You will be tempted to:** Use `exec.CommandContext` and assume it sends SIGTERM on context cancel.
**Why that fails:** It sends SIGKILL — immediate, ungraceful death. The subprocess gets no chance to clean up, flush buffers, or close connections.
**The right way:** Go 1.22+: set `cmd.Cancel` to send SIGTERM with `cmd.WaitDelay` for SIGKILL fallback. Pre-1.22: handle context cancellation manually with the graceful termination pattern.

### Rule 4: Always cmd.Wait() After cmd.Start()
**You will be tempted to:** Start a process and forget to Wait().
**Why that fails:** Without Wait(), the child process becomes a zombie. OS resources (PIDs, file descriptors) leak. Eventually the system runs out of PIDs.
**The right way:** `defer cmd.Wait()` immediately after a successful `cmd.Start()`.
