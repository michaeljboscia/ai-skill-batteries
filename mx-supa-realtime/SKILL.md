---
name: mx-supa-realtime
description: Use when implementing Supabase Realtime subscriptions, WebSocket channels, broadcast, presence, or postgres_changes listeners. Also use when the user mentions 'realtime', 'channel', 'subscribe', 'postgres_changes', 'broadcast', 'presence', 'WebSocket', 'REPLICA IDENTITY', 'supabase_realtime publication', 'private channel', or 'realtime.messages'.
---

# Supabase Realtime — Subscriptions & Channels for AI Coding Agents

**This skill loads for ANY Supabase Realtime work.** It prevents the most common AI failures: subscribing to all tables, never cleaning up channels, using postgres_changes for high-frequency events, and ignoring subscription limits.

## When to also load
- Client SDK subscription cleanup → `mx-supa-client`
- RLS for private channels → `mx-supa-auth`
- Performance monitoring → `mx-supa-observability`

---

## Level 1: Feature Selection (Beginner)

### Three features — choose the right one

| Feature | Data persisted? | RLS check per event? | Best for |
|---------|----------------|---------------------|----------|
| `postgres_changes` | Yes (DB rows) | YES (per user, per event) | Chat messages, order updates, comments |
| `broadcast` | No (ephemeral) | No (channel-level auth only) | Cursors, typing indicators, game state |
| `presence` | No (in-memory state) | No (channel-level auth only) | Online users, "who's here" |

**Decision:** Is the data in the database? → `postgres_changes`. Ephemeral/high-frequency? → `broadcast`. Tracking who's connected? → `presence`.

### Channel naming convention

`scope:id:entity` — e.g., `room:123:messages`, `workspace:abc:cursors`, `game:456:moves`

### Always clean up subscriptions

```typescript
useEffect(() => {
  const channel = supabase
    .channel('room:123:messages')
    .on('postgres_changes',
      { event: 'INSERT', schema: 'public', table: 'messages', filter: 'room_id=eq.123' },
      (payload) => setMessages(prev => [...prev, payload.new])
    )
    .subscribe()

  return () => supabase.removeChannel(channel) // MANDATORY
}, [])
```

---

## Level 2: Configuration & Filters (Intermediate)

### postgres_changes filter syntax

Only ONE filter condition per subscription:
```typescript
// GOOD: Single server-side filter
.on('postgres_changes', {
  event: 'INSERT',
  schema: 'public',
  table: 'messages',
  filter: 'room_id=eq.123'  // Only one condition allowed
}, callback)
```

For multiple AND conditions, filter client-side:
```typescript
.on('postgres_changes', {
  event: 'UPDATE',
  schema: 'public',
  table: 'tasks',
  filter: 'org_id=eq.5'  // Most restrictive filter server-side
}, (payload) => {
  // Secondary filter client-side
  if (payload.new.status === 'active') {
    handleActiveTask(payload.new)
  }
})
```

### REPLICA IDENTITY FULL for old record access

By default, UPDATE/DELETE events only send the new record (or just the PK for DELETE). To get the OLD record:

```sql
ALTER TABLE public.tasks REPLICA IDENTITY FULL;
```

**Security note:** DELETE events under RLS only return the primary key regardless — cannot evaluate USING clause on deleted row.

### Private channels for production

```typescript
const channel = supabase.channel('room:123:messages', {
  config: { private: true }  // Enforces Realtime Authorization
})
```

Requires RLS policies on `realtime.messages`:
```sql
ALTER TABLE realtime.messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Auth users can read channel" ON realtime.messages
FOR SELECT TO authenticated
USING ((SELECT realtime.topic()) LIKE 'room:%');

CREATE POLICY "Auth users can write channel" ON realtime.messages
FOR INSERT TO authenticated
WITH CHECK ((SELECT realtime.topic()) LIKE 'room:%');
```

### Broadcast for high-frequency events

```typescript
// Sending (no DB write)
channel.send({ type: 'broadcast', event: 'cursor-move', payload: { x: 100, y: 200 } })

// Receiving
channel.on('broadcast', { event: 'cursor-move' }, (payload) => {
  updateCursor(payload.payload)
})
```

Can also send via HTTP REST API or database triggers (via `realtime.send()`).

### Presence for online status

```typescript
channel.on('presence', { event: 'sync' }, () => {
  const state = channel.presenceState()
  setOnlineUsers(Object.keys(state))
})

channel.subscribe(async (status) => {
  if (status === 'SUBSCRIBED') {
    await channel.track({ user_id: currentUser.id, online_at: new Date() })
  }
})
```

---

## Level 3: Scaling & Resilience (Advanced)

### Plan limits

| Metric | Free | Pro |
|--------|------|-----|
| Concurrent connections | 200 | 500 |
| Messages/second | 100 | 500 |
| Channel joins/second | 100 | 500 |

Exceeding limits → connections forcefully dropped. Client auto-reconnects when under limit.

### Silent disconnection prevention

Browser background tabs throttle JavaScript timers, killing WebSocket heartbeats:

```typescript
const supabase = createClient(URL, KEY, {
  realtime: {
    worker: true,  // Heartbeat in Web Worker (bypass throttling)
    heartbeatCallback: (status) => {
      if (status === 'disconnected') {
        supabase.realtime.disconnect()
        supabase.realtime.connect()
      }
    }
  }
})
```

### Production checklist

1. **Private channels only** — public channels let anyone spam your quota
2. **Enable Realtime only for needed tables** — `ALTER PUBLICATION supabase_realtime ADD TABLE public.messages` (never `ADD ALL TABLES`)
3. **Minimize UPDATE noise** — separate high-frequency internal columns into non-published tables
4. **Throttle client-side broadcasts** — max 10-15 emissions/second per client
5. **Monitor Realtime Reports** — connection counts, message volumes, RLS execution times

---

## Performance: Make It Fast

1. **broadcast over postgres_changes** for ephemeral high-frequency data
2. **Single server-side filter** per subscription — minimize payload
3. **Client-side debouncing** for cursor/typing events (10-15/sec max)
4. **Private channels** — prevent unauthorized connection spam
5. **Web Workers for heartbeat** — prevent silent disconnections
6. **Selective publication** — only publish tables that clients actually subscribe to

## Observability: Know It's Working

1. **Realtime Reports (Dashboard)** — connection counts, message volumes, RLS execution times
2. **RLS Execution Time** — private channel subscription latency (target < 50ms)
3. **Connection states** — handle SUBSCRIBED, TIMED_OUT, CLOSED, CHANNEL_ERROR
4. **Realtime Inspector** — reproduce and debug connection issues
5. **WebSocket error codes** — too_many_connections, too_many_channels, tenant_events

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No Subscribing to All Tables
**You will be tempted to:** Use `table: '*'` or `event: '*'` for convenience.
**Why that fails:** Every database mutation triggers RLS checks for every subscriber. This destroys database CPU on high-write tables.
**The right way:** Scope subscriptions to exact table + exact event: `{ event: 'INSERT', table: 'messages' }`.

### Rule 2: No postgres_changes for High-Frequency Data
**You will be tempted to:** Store cursor positions in a table and subscribe to postgres_changes.
**Why that fails:** Every cursor move = INSERT + RLS check per subscriber. 50 users × 30 moves/sec = 1,500 DB queries/sec for cursors alone.
**The right way:** Use `broadcast` for ephemeral data. It bypasses the database entirely.

### Rule 3: No Missing Channel Cleanup
**You will be tempted to:** Subscribe without a cleanup function because "the page stays open."
**Why that fails:** Navigation, re-renders, and hot-reload create orphaned channels. Hits ChannelRateLimitReached.
**The right way:** Every `.subscribe()` MUST pair with `return () => supabase.removeChannel(channel)`.

### Rule 4: No Multiple Filter Conditions
**You will be tempted to:** Pass `filter: 'status=eq.active,org_id=eq.5'` expecting AND logic.
**Why that fails:** Only one filter per subscription is supported. Multiple conditions are silently ignored or error.
**The right way:** Use the most selective single filter server-side, evaluate additional conditions client-side with `if` statements.

### Rule 5: No Ignoring Quota Limits
**You will be tempted to:** Deploy without considering connection/message limits.
**Why that fails:** Exceeding limits disconnects ALL users. No graceful degradation — hard cutoff.
**The right way:** Monitor connection counts and message rates. Implement client-side throttling. Use broadcast instead of postgres_changes where possible.
