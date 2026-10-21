---
paths:
  - "**/*.go"
---

# Go context and goroutines

## context

A `context.Context` carries one request's cancellation, deadline and request-scoped values from function to function. When the client disconnects or the deadline passes, the queries and calls running under it stop too.

- **It is always the first parameter, named `ctx`**, on every function that does I/O or may block: `func (r *UserRepository) FindByID(ctx context.Context, id string)`.
- **It is never stored in a struct.** A stored context outlives the call it belonged to, and nobody can tell when it is cancelled. A long-running component receives it when it starts: `Run(ctx)`. It is never passed as a pointer, and never `nil`. `containedctx` catches a stored one.
- **`context.Background()` is created only at roots**: `main`, tests, and work that must outlive the request, such as shutdown, which takes a fresh context with a timeout because the request's is already done. Creating one in the middle of a request cuts the cancellation off there.
- **Calls that leave the process have a deadline.** The HTTP server's request timeout is the default; an adapter shortens it with `context.WithTimeout` for a call that must be faster. Without a deadline, a silent peer makes the call wait forever.
- **Values in a context are request-scoped only**: the request id, the authenticated user, the open transaction. Never dependencies or optional parameters. The package that owns a value puts it in and takes it out, under a key type no other package can name:

```go
type ctxKey struct{}

func With(ctx context.Context, id string) context.Context { return context.WithValue(ctx, ctxKey{}, id) }

func From(ctx context.Context) string {
	id, _ := ctx.Value(ctxKey{}).(string)
	return id
}
```

## Goroutines

- **Every goroutine has an owner, which cancels it and waits for it.** The goroutine ends when its context is cancelled; the owner waits with `errgroup` (`golang.org/x/sync/errgroup`). A goroutine nobody waits for is still running when its resources close.
- **A request handler never starts a goroutine and forgets it.** Its context is cancelled when the response is sent, which cuts the work off halfway or leaves it running unseen. Work that continues after the response belongs to a background worker the composition root owns (a queue, an outbox).
- **Fan-out is bounded**: `g.SetLimit(n)` on the errgroup. It also returns the first error.
- **A panic in a goroutine you started ends the process**; the HTTP recovery middleware only covers handlers. A worker loop that processes items one by one recovers per item and logs, so one bad item does not stop the rest. Other goroutines do not recover: a process that dies and restarts is better than one that keeps running in an unknown state.
- **Shared state is guarded** by a mutex or owned by one goroutine; `go test -race` runs in CI (`rules/go/tooling.md`).

## Lifecycle and shutdown

One component owns the program's lifecycle; in a server that is `app.Run` (`rules/go-server/architecture.md`).

```go
// main.go
ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
defer stop()
```

```go
// the owner
func (a *App) Run(ctx context.Context) error {
	g, ctx := errgroup.WithContext(ctx) // one failure stops the rest
	g.Go(func() error { return a.serve(ctx) })
	g.Go(func() error { return a.worker.Run(ctx) })
	err := g.Wait()
	a.db.Close() // closed last, after everything that uses it has stopped
	return err
}
```

- **Shutdown order**: stop accepting requests → let in-flight requests finish within a timeout (`http.Server.Shutdown`) → stop workers → close resources.
- On Kubernetes, readiness fails as soon as the stop signal arrives, so the load balancer sends new requests elsewhere first.
- **Whoever creates a resource closes it, after every goroutine using it has stopped.** A component that closes a client in its own `Start` (`defer client.Close()`) closes it while the goroutine it started still uses it.
