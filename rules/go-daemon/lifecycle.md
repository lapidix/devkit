---
paths:
  - "**/internal/**"
  - "**/main.go"
---

# Go daemon lifecycle: jobs, limits and shutdown

`rules/go/concurrency.md` holds for every goroutine here. This file is what a daemon adds: it has no request to bound its work, so every job states when it starts, how much it takes on, and how it stops.

## One Run per component

Every long-running component has one method, `Run(ctx context.Context) error`. It does its work until `ctx` is cancelled, waits for whatever it started, and returns: `nil` when it was cancelled, an error when it cannot go on.

```go
// a component that starts a goroutine and returns cannot be waited for
func (m *Monitor) Start() error {
	go func() { … }() // nobody waits for this goroutine
	return nil
}
func (m *Monitor) Stop() { close(m.done) } // returns before the goroutine has stopped
```

- **No `Start`/`Stop` pairs.** `Stop` returns before the work it stops has finished, so a caller that closes a client after `Stop` closes it under a running goroutine. `Run` returns only when its work is done, and the owner closes what it created after that (`rules/go/concurrency.md`).
- **No context in the struct.** A component that creates `context.WithCancel(context.Background())` in its constructor has cut itself off from the signal `main` received; it gets its context from `Run`.
- **`app.Run` is the one owner**: it runs every component under one `errgroup`, so one that fails stops the rest, and it closes the connections it created once all of them have returned.

## Periodic jobs

```go
// internal/report/report.go
func (r *Reporter) Run(ctx context.Context) error {
	ticker := time.NewTicker(r.every)
	defer ticker.Stop()
	return r.loop(ctx, ticker.C)
}

// loop takes its ticks as a channel, so tests drive it without waiting.
// A failed report is logged and the next tick tries again: one bad sample does not stop the job.
func (r *Reporter) loop(ctx context.Context, ticks <-chan time.Time) error {
	for {
		if err := r.report(ctx); err != nil && ctx.Err() == nil {
			r.lg.WarnContext(ctx, "report failed", slog.Any("err", err))
		}
		select {
		case <-ctx.Done():
			return nil
		case <-ticks:
		}
	}
}
```

- **The first run happens at start**, not one interval later: a daemon restarted every few minutes would otherwise never report.
- **Runs never overlap.** The loop does one run at a time, and a `time.Ticker` drops ticks while the receiver is busy, so a slow run delays the next instead of piling up behind it.
- **A failed run is logged and retried on the next tick**; only a failure that makes every later run fail too (the job's configuration is wrong) is returned. The interval comes from the configuration and is checked there (`rules/go-daemon/runtime.md`).

## Work the server sends

```go
// internal/command/runner.go
func (r *Runner) Run(ctx context.Context) error {
	var wg sync.WaitGroup
	for {
		select {
		case <-ctx.Done():
			wg.Wait()
			return nil
		case cmd := <-r.commands:
			select {
			case r.slots <- struct{}{}:
			default:
				r.reply(ctx, &linkv1.CommandResult{OpId: cmd.GetOpId(), ExitCode: -1, Error: "busy"})
				continue
			}
			wg.Go(func() {
				defer func() { <-r.slots }()
				r.reply(ctx, r.run(opinfo.With(ctx, cmd.GetOpId()), cmd))
			})
		}
	}
}
```

- **Concurrency is bounded by a slot count from the configuration.** An item that arrives when every slot is busy is refused at once, with a reason the server can read; it is not queued. The server knows its other daemons and its own deadlines, so it decides whether to retry, wait or send the item elsewhere; a queue inside the daemon hides that it is overloaded until items time out in it.
- **Every item gets an answer**: its result, a refusal, or an error. The server never has to infer a failure from silence.
- **Each item recovers its own panic** and reports it as that item's failure, the exception `rules/go/concurrency.md` makes for loops that process items one by one:

```go
// internal/command/runner.go
func (r *Runner) run(ctx context.Context, cmd *linkv1.RunCommand) (res *linkv1.CommandResult) {
	res = &linkv1.CommandResult{OpId: cmd.GetOpId(), ExitCode: -1}
	defer func() {
		if p := recover(); p != nil {
			r.lg.ErrorContext(ctx, "command panicked", slog.Any("panic", p))
			res.Error = "internal error"
		}
	}()
	…
}
```

## Shutdown

```go
// internal/app/app.go
// Run returns when ctx is cancelled or the link gives up. The jobs stop first and the link last,
// so the results the jobs send while stopping still reach the server.
func (a *App) Run(ctx context.Context) error {
	linkCtx, stopLink := context.WithCancel(context.WithoutCancel(ctx))
	defer stopLink()
	linkDone := make(chan error, 1)
	go func() { linkDone <- a.link.Run(linkCtx) }() // waited for below, on every path

	var linkErr error
	linkEnded := false
	g, ctx := errgroup.WithContext(ctx)
	g.Go(func() error { return a.reporter.Run(ctx) })
	g.Go(func() error { return a.runner.Run(ctx) })
	g.Go(func() error {
		select {
		case linkErr = <-linkDone: // the server is gone or refused us: stop the jobs
			linkEnded = true
			return linkErr
		case <-ctx.Done():
			return nil
		}
	})
	err := g.Wait()
	if !linkEnded {
		stopLink()
		linkErr = <-linkDone
	}
	closeErr := a.conn.Close() // created in New, closed after the link has stopped using it
	return errors.Join(err, linkErr, closeErr)
}
```

- **Order**: stop taking new work → cancel the work in progress, which stops its processes → send each item's last result → stop the connection → close what `app.New` created → exit. The connection outlives the jobs because it carries their last results; `context.WithoutCancel` gives it a context the signal does not cancel.
- **A result produced during shutdown is sent on `context.WithoutCancel(ctx)` with a short timeout**: the job's own context is already cancelled, and without the timeout a dead server would hold the shutdown open.
- **The whole shutdown fits the supervisor's grace period** (30 seconds by default in Kubernetes, `TimeoutStopSec` under systemd), after which the process is killed. The longest step is usually a child process given time to exit (`rules/go-daemon/subprocess.md`).

## When the server is gone

- **A daemon that exists to serve one server exits when that server has been unreachable for a configured time** (`ORPHAN_AFTER`), with code 1. Its work is useless without the server, and a supervisor that restarts it, or a platform that removes it, does better than a process retrying forever.
- **A daemon that also works alone** (a monitor that still alerts locally) keeps retrying with backoff and logs each failure at `warn` (`rules/go-daemon/outbound.md`).
- **A refusal is final.** When the server rejects the daemon's credentials, retrying cannot change the answer, so `Run` returns at once.
