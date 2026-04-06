---
name: mx-rust-systems
description: Use when managing subprocesses, PTYs, signals, process groups, or OS interfaces in Rust. Covers portable-pty, tokio::process, signal handling, graceful shutdown, supervisor pattern, zombie prevention, and process tree management. Also use when the user mentions 'subprocess', 'spawn', 'PTY', 'pseudo-terminal', 'SIGTERM', 'SIGINT', 'signal', 'process group', 'setsid', 'zombie', 'kill_on_drop', 'supervisor', 'watchdog', 'health check', 'graceful shutdown', 'daemon', or 'child process'.
---

# Rust Systems Programming — Subprocess & OS Interface Patterns

**Loads when spawning processes, managing PTYs, handling signals, or building daemons.** The triumvirate daemon manages 3 persistent CLI subprocesses — this skill covers every pattern needed for that.

## When to also load
- Async task management → `mx-rust-async`
- Language fundamentals → `mx-rust-core`
- WebSocket streaming of subprocess output → `mx-rust-network`

---

## Level 1: Subprocess Basics (Beginner)

### tokio::process::Command

```rust
use tokio::process::Command;
use std::process::Stdio;

let mut child = Command::new("claude")
    .arg("--model").arg("opus")
    .stdin(Stdio::piped())
    .stdout(Stdio::piped())
    .stderr(Stdio::piped())
    .kill_on_drop(true)  // Auto-kill if handle dropped
    .spawn()?;

// Take ownership of stdin/stdout handles
let stdin = child.stdin.take().expect("stdin not piped");
let stdout = child.stdout.take().expect("stdout not piped");
```

**Always set `kill_on_drop(true)`** for managed subprocesses. Without it, orphaned processes survive the daemon.

**Always `.take()` stdin/stdout** immediately after spawn. Borrowing through `&mut child` later causes borrow conflicts.

### Reading Subprocess Output

```rust
use tokio::io::{AsyncBufReadExt, BufReader};

let reader = BufReader::new(stdout);
let mut lines = reader.lines();

while let Some(line) = lines.next_line().await? {
    println!("[agent] {}", line);
}
```

### Reading from N Subprocesses Simultaneously

Use `tokio::select!` or `StreamExt::merge`:

```rust
use tokio_stream::StreamExt;

// Option A: merge streams
let mut merged = tokio_stream::StreamExt::merge(stream1, stream2);
while let Some(item) = merged.next().await {
    match item {
        // process interleaved output
    }
}

// Option B: select! in a loop
loop {
    tokio::select! {
        Some(line) = agent1_lines.next_line() => { /* ... */ }
        Some(line) = agent2_lines.next_line() => { /* ... */ }
        else => break,
    }
}
```

For the `tokio-process-stream` crate, each child becomes a `Stream<Item = Item::Stdout | Item::Stderr | Item::Done>`.

---

## Level 2: PTY Management (Intermediate)

### Why PTYs Are Needed

Plain pipes break interactive programs. Programs call `isatty()` and disable colors, prompts, and streaming output when not connected to a terminal. **Use PTYs for any CLI tool that produces interactive output.**

### portable-pty Pattern

```rust
use portable_pty::{CommandBuilder, NativePtySystem, PtySize, PtySystem};
use std::io::Read;
use tokio::sync::mpsc;

let pty_system = NativePtySystem::default();
let pair = pty_system.openpty(PtySize {
    rows: 24, cols: 80,
    pixel_width: 0, pixel_height: 0,
})?;

let mut cmd = CommandBuilder::new("claude");
cmd.args(["--model", "opus"]);

let _child = pair.slave.spawn_command(cmd)?;
drop(pair.slave);  // CRITICAL: drop slave in parent for EOF detection

let mut reader = pair.master.try_clone_reader()?;
let (tx, rx) = mpsc::channel(1024);

// PTY reads are BLOCKING — use a dedicated OS thread, NOT tokio::spawn
std::thread::spawn(move || {
    let mut buf = vec![0u8; 4096];
    loop {
        match reader.read(&mut buf) {
            Ok(0) => break,  // EOF
            Ok(n) => {
                if tx.blocking_send(buf[..n].to_vec()).is_err() {
                    break;  // Receiver dropped
                }
            }
            Err(_) => break,  // EIO on Linux when PTY closes
        }
    }
});
```

**CRITICAL: Drop the PTY slave in the parent process.** If you keep it, the OS never sends EOF to the master when the child exits. The reader thread hangs forever.

**CRITICAL: Use `std::thread::spawn`, NOT `tokio::spawn`.** PTY reads are blocking I/O. Blocking on a tokio worker thread starves the entire runtime.

### Writing to PTY (stdin)

```rust
use std::io::Write;

let mut writer = pair.master.take_writer()?;

// Writing to master sends input to the child's stdin
writer.write_all(b"hello world\n")?;
writer.flush()?;
```

---

## Level 3: Process Lifecycle & Supervision (Advanced)

### Process Groups and Signal Isolation

```rust
use tokio::process::Command;
use std::os::unix::process::CommandExt;

let child = Command::new("agent")
    .process_group(0)  // New process group (child is leader)
    .spawn()?;
```

`process_group(0)` isolates the child from the parent's signal group. Ctrl-C won't kill the child directly — the daemon controls its lifecycle.

### Killing a Process Tree

Killing a parent doesn't kill grandchildren. Kill the entire process group:

```rust
use nix::sys::signal::{kill, Signal};
use nix::unistd::Pid;

// Kill all processes in the group (negative PID)
kill(Pid::from_raw(-(child_pid as i32)), Signal::SIGTERM)?;
```

Or use the `kill_tree` crate for cross-platform recursive termination.

### Zombie Prevention

**Rust std lib does NOT auto-reap children on drop.** Tokio reaps on "best-effort" basis.

```rust
// ALWAYS explicitly wait for children
match child.try_wait()? {
    Some(status) => println!("Exited: {}", status),
    None => println!("Still running"),
}

// Or await completion
let status = child.wait().await?;
```

### Supervisor Pattern

```rust
use std::time::Duration;
use tokio::time::sleep;

async fn supervise_agent(name: &str) {
    let mut restart_count = 0u32;
    
    loop {
        let child = spawn_agent(name).await;
        let status = child.wait().await;
        
        match status {
            Ok(s) if s.success() => {
                tracing::info!(agent = name, "agent exited cleanly");
                break;
            }
            result => {
                restart_count += 1;
                let backoff = Duration::from_millis(
                    500 * 2u64.pow(restart_count.min(6))  // Max ~32s
                );
                tracing::warn!(
                    agent = name,
                    restart = restart_count,
                    backoff = ?backoff,
                    result = ?result,
                    "agent crashed, restarting"
                );
                sleep(backoff).await;
            }
        }
    }
}
```

For production, consider the `task-supervisor` crate which provides:
- Auto-restart with exponential backoff
- Dynamic control via `SupervisorHandle`
- Health-check intervals and dead-task thresholds
- Tasks must impl `Clone` (mutations lost on restart — use `Arc` for shared state)

### Graceful Shutdown Sequence

```rust
use tokio::signal;
use tokio_util::sync::CancellationToken;

let token = CancellationToken::new();

// 1. Listen for signals
let shutdown_token = token.clone();
tokio::spawn(async move {
    let ctrl_c = signal::ctrl_c();
    let mut sigterm = signal::unix::signal(
        signal::unix::SignalKind::terminate()
    ).unwrap();
    
    tokio::select! {
        _ = ctrl_c => {}
        _ = sigterm.recv() => {}
    }
    
    tracing::info!("Shutdown signal received");
    shutdown_token.cancel();
});

// 2. All worker tasks check the token
// (see mx-rust-async for CancellationToken patterns)

// 3. After cancel, wait for tasks to drain with timeout
tokio::select! {
    _ = join_set.shutdown() => {
        tracing::info!("All tasks shut down cleanly");
    }
    _ = tokio::time::sleep(Duration::from_secs(10)) => {
        tracing::warn!("Shutdown timeout, forcing exit");
    }
}
```

For the double Ctrl-C pattern (first = graceful, second = force):
- Use the `tokio-graceful-shutdown` crate with subsystem handles
- Or track signal count manually

### Watchdog for Runtime Freezes

The `nano-watchdog` crate runs on a **separate OS thread** — it can detect when the tokio runtime itself is frozen (deadlock, starvation).

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No tokio::spawn for PTY Reads

**You will be tempted to:** `tokio::spawn(async { reader.read(...) })` for PTY reading.
**Why that fails:** PTY reads are blocking syscalls. They block the tokio worker thread, starving ALL other async tasks.
**The right way:** `std::thread::spawn` with `tx.blocking_send()` for the bridge.

### Rule 2: No Forgetting to Drop PTY Slave

**You will be tempted to:** Keep the `pair.slave` handle alive "in case we need it later."
**Why that fails:** The OS keeps the slave file descriptor open. The master reader never gets EOF. The reader thread runs forever.
**The right way:** `drop(pair.slave)` immediately after `spawn_command()`.

### Rule 3: No Bare `kill(pid)` for Process Trees

**You will be tempted to:** `child.kill()` and assume all descendants die too.
**Why that fails:** Only the direct child is killed. Grandchild processes become orphans, leaking resources.
**The right way:** `kill(-pgid, SIGTERM)` to signal the entire process group, or use `kill_tree` crate.

### Rule 4: No fork() in Multi-Threaded Tokio

**You will be tempted to:** Call `fork()` directly for daemonization.
**Why that fails:** `fork()` in a multi-threaded process copies only the calling thread. Mutexes held by other threads remain locked forever in the child. Undefined behavior.
**The right way:** Use `tokio::process::Command` which forks + immediately execs. For daemonization, use systemd or container orchestration instead of manual `fork()`.

### Rule 5: No Unreachable Child Waits

**You will be tempted to:** Spawn a child and never call `wait()` or `try_wait()`.
**Why that fails:** The child becomes a zombie process, holding a PID entry in the kernel process table. Enough zombies exhaust the PID space.
**The right way:** Always `child.wait().await` in the supervisor loop, or use `kill_on_drop(true)`.
