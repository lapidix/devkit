---
paths:
  - "**/internal/infrastructure/**"
---

# Go daemon connections

A daemon opens every connection itself and keeps none open for others to reach it. Each connection lives in its own `internal/infrastructure/{target}` package, which dials, registers, reconnects and moves messages, and knows no job (`rules/go-daemon/architecture.md`).

## Dialing

```go
// internal/infrastructure/link/link.go
// Dial creates the connection without connecting; the first stream connects it.
func Dial(addr string, creds credentials.TransportCredentials) (*grpc.ClientConn, error) {
	conn, err := grpc.NewClient(addr, grpc.WithTransportCredentials(creds))
	if err != nil {
		return nil, fmt.Errorf("dial %s: %w", addr, err)
	}
	return conn, nil
}
```

```go
// internal/app/app.go
creds, err := credentials.NewClientTLSFromFile(cfg.ServerCAFile, "")
if err != nil {
	return nil, fmt.Errorf("load server CA: %w", err)
}
conn, err := link.Dial(cfg.ServerAddr, creds)
```

- **`grpc.NewClient`, not `grpc.Dial` or `DialContext`**: the old functions are deprecated, and their `WithBlock` made startup wait on a server that may come up later. `NewClient` connects on the first call, and the session loop below handles a server that is not there yet.
- **TLS is always verified.** The server's CA comes from the configuration; `insecure.NewCredentials()` appears only in tests, against an in-memory server (`rules/go-daemon/testing.md`). A daemon that skips verification hands its credentials to whoever answers on the address.
- **`app.New` creates the connection and `app.Run` closes it**, after every component that uses it has returned (`rules/go-daemon/lifecycle.md`). The package that uses it receives it through its constructor.
- **An HTTP client has a timeout, every request a context, and every response body is closed.** `noctx` and `bodyclose` report the last two (`rules/go/conventions.md`). The `http.Client`'s `Timeout` bounds the whole exchange, reading the body included, so a call whose context has no deadline still ends.

## Registering

- **The first message on a new stream says who the daemon is**: its id, the protocol major version it speaks (`rules/go-daemon/contract.md`) and its build version, with a credential.
- **A credential handed to the daemon at start is used once.** The server answers the first registration with a resume key, and every later reconnect sends that key instead. A token that has been used cannot register a second daemon, so one copied out of the environment is worth nothing.
- **The answer to the first message has a deadline**, even though the stream has none: `time.AfterFunc(timeout, cancel)` around the first `Recv`. A server that accepts the connection and never answers would otherwise hold the daemon forever.
- **A refusal ends the daemon.** `codes.Unauthenticated` and `codes.PermissionDenied` become a sentinel error (`ErrRejected`) that `Run` returns at once instead of retrying.

## Long-lived streams

```go
// internal/infrastructure/link/link.go
// watch ends the session when the server has been silent for ServerTimeout. It runs apart from send,
// so a Send blocked on a peer that stopped reading does not stop the check.
func (c *Client) watch(ctx context.Context, lastRecv *atomic.Int64) error {
	ticker := time.NewTicker(c.cfg.HeartbeatInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
			if silent := time.Since(time.Unix(0, lastRecv.Load())); silent > c.cfg.ServerTimeout {
				return fmt.Errorf("server silent for %s", silent.Round(time.Second))
			}
		}
	}
}

// send is the stream's only writer: gRPC allows one goroutine at a time to send on a stream.
func (c *Client) send(ctx context.Context, stream linkv1.LinkService_ConnectClient) error {
	ticker := time.NewTicker(c.cfg.HeartbeatInterval)
	defer ticker.Stop()
	heartbeat := &linkv1.ConnectRequest{Msg: &linkv1.ConnectRequest_Heartbeat{Heartbeat: &linkv1.Heartbeat{}}}
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case o := <-c.outbox:
			err := stream.Send(o.msg)
			o.done <- err
			if err != nil {
				return fmt.Errorf("send: %w", err)
			}
		case <-ticker.C:
			if err := stream.Send(heartbeat); err != nil {
				return fmt.Errorf("send heartbeat: %w", err)
			}
		}
	}
}
```

- **A stream has no deadline; heartbeats keep it honest.** The daemon sends one every `HEARTBEAT_INTERVAL` and the server answers each; a side that hears nothing for `SERVER_TIMEOUT` ends the session. A deadline on the stream would end healthy sessions, and without heartbeats a half-open connection looks alive until the next send fails, which on a quiet stream may be never.
- **Silence is checked in its own goroutine**, not in the writer's loop. A `Send` blocks when the peer stops reading and the flow-control window fills, and a check behind it would wait as long.
- **Application heartbeats, not gRPC keepalive alone.** A client keepalive more frequent than the server's enforcement policy allows (5 minutes by default) makes the server close the connection with `ENHANCE_YOUR_CALM`; when a project sets keepalive, it sets the server's `keepalive.EnforcementPolicy` in the same change.
- **One reader and one writer per stream.** gRPC lets one goroutine at a time call `Send` and one call `Recv`. The connection owns both goroutines; everyone else sends through a method that hands the message to the writer and returns its result:

```go
// internal/infrastructure/link/link.go
// Send returns once the message has been handed to the stream, waiting through a reconnect if one is under way.
func (c *Client) Send(ctx context.Context, msg *linkv1.ConnectRequest) error {
	o := outgoing{msg: msg, done: make(chan error, 1)}
	select {
	case c.outbox <- o:
	case <-ctx.Done():
		return ctx.Err()
	}
	select {
	case err := <-o.done:
		return err
	case <-ctx.Done():
		return ctx.Err()
	}
}
```

- **The session's goroutines run under one `errgroup`, and the first to fail ends the stream.** The stream is opened under the session's context, not the group's, so cancelling the group's context wakes neither a reader blocked in `Recv` nor a writer blocked in `Send`, and `Wait` never returns. `context.AfterFunc` cancels the stream when the group's context ends:

```go
// internal/infrastructure/link/link.go
g, gctx := errgroup.WithContext(ctx)
// The stream was opened under ctx, so cancelling gctx alone would wake neither a blocked Recv nor a
// blocked Send: when one goroutine fails, end the stream itself.
stop := context.AfterFunc(gctx, cancel)
defer stop()
g.Go(func() error { return c.receive(gctx, stream, &lastRecv) })
g.Go(func() error { return c.send(gctx, stream) })
g.Go(func() error { return c.watch(gctx, &lastRecv) })
return true, g.Wait()
```

## Reconnecting

```go
// internal/infrastructure/link/link.go
func (c *Client) Run(ctx context.Context) error {
	lastUp := time.Now()
	wait := minBackoff
	for {
		registered, err := c.session(ctx)
		if ctx.Err() != nil {
			return nil
		}
		if errors.Is(err, ErrRejected) {
			return err
		}
		if registered {
			lastUp = time.Now()
			wait = minBackoff
		}
		left := c.cfg.OrphanAfter - time.Since(lastUp)
		if left <= 0 {
			return fmt.Errorf("%w: %w", ErrServerGone, err)
		}
		// The last wait ends at the orphan deadline, so the daemon gives up on time, not a backoff later.
		delay := min(rand.N(wait), left) //nolint:gosec // jitter spreads reconnects; it guards nothing
		c.lg.WarnContext(ctx, "link down", slog.Any("err", err), slog.Duration("retryIn", delay))
		wait = min(wait*2, maxBackoff)
		select {
		case <-time.After(delay):
		case <-ctx.Done():
			return nil
		}
	}
}
```

- **Exponential backoff with full jitter**: the ceiling doubles from one second to a cap, and each wait is a random duration below it. When a server restarts, its daemons then come back spread out instead of all at once.
- **A session that registered resets the backoff**; one that never registered does not, so a server that accepts connections and fails every registration is not hammered.
- **Giving up** is `ErrServerGone` after `ORPHAN_AFTER` without a registered session, for a daemon that exists to serve its server (`rules/go-daemon/lifecycle.md`). The last wait is cut at that deadline: with the 30-second cap, an uncut wait could keep a 30-second orphan timeout going for about a minute.
