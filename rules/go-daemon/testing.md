---
paths:
  - "**/*_test.go"
---

# Go daemon tests

A daemon's goroutines, its server and its clock are what its tests must control. The habits underneath are the Go server's:

- The standard `testing` package with testify: `require` for checks the test cannot continue without, `assert` for the rest. A test sits beside its source and uses the package from outside (`package report_test`), unless it must reach an unexported function such as a job's `loop`.
- The function names the subject; each behavior is a `t.Run` whose name, an English sentence, states what must hold. Contexts come from `t.Context()`.
- Fakes are written by hand in the test files that use them, each with `var _ Sender = (*fakeSender)(nil)` so a changed interface breaks the build; no mock generators.
- CI runs `go test -race -shuffle=on ./...`. No `time.Sleep` to wait: a test polls with `require.Eventually`.

## Leaked goroutines

```go
// internal/command/runner_test.go
func TestMain(m *testing.M) {
	goleak.VerifyTestMain(m) // a goroutine left behind is a process left behind
}
```

- **Every package that starts goroutines checks for leaks** with `go.uber.org/goleak` in its `TestMain`. A `Run` that returns before its goroutines have stopped passes every other test and fails this one.
- A test that starts `Run` stops it in its own cleanup and waits for it to return. Waiting on a value the test has already read blocks forever, so the helper keeps the result:

```go
// internal/infrastructure/link/link_test.go
// run starts c.Run and returns a function that waits for it to return. The test's cleanup stops it.
func run(t *testing.T, c *link.Client) (wait func() error) {
	t.Helper()
	ctx, cancel := context.WithCancel(t.Context())
	var err error
	done := make(chan struct{})
	go func() {
		defer close(done)
		err = c.Run(ctx)
	}()
	t.Cleanup(func() {
		cancel()
		<-done
	})
	return func() error {
		<-done
		return err
	}
}
```

## The server

```go
// internal/infrastructure/link/link_test.go
// start serves srv over an in-memory listener and returns a client of it. The server stops when the test ends.
func start(t *testing.T, srv *fakeServer, token string, orphanAfter time.Duration) (*link.Client, *bufconn.Listener) {
	t.Helper()
	lis := bufconn.Listen(1 << 20)
	gs := grpc.NewServer()
	linkv1.RegisterLinkServiceServer(gs, srv)
	go func() { _ = gs.Serve(lis) }()
	t.Cleanup(gs.Stop)

	conn, err := grpc.NewClient("passthrough:///bufnet",
		grpc.WithContextDialer(func(ctx context.Context, _ string) (net.Conn, error) { return lis.DialContext(ctx) }),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	require.NoError(t, err)
	t.Cleanup(func() { _ = conn.Close() })
	c := link.New(conn, link.Config{
		DaemonID:          "daemon-1",
		Token:             token,
		Version:           "test",
		HeartbeatInterval: 50 * time.Millisecond,
		ServerTimeout:     200 * time.Millisecond, // four heartbeats: only an answering server keeps the session
		OrphanAfter:       orphanAfter,
	}, slog.New(slog.DiscardHandler))
	return c, lis
}
```

- **The connection is tested against a fake server over `bufconn`**, an in-memory listener: the real generated client, the real stream and the real status codes, with no port and no network. The fake server embeds the generated `Unimplemented…Server` and decides with fields what each test needs: refuse the token, drop the first stream, stay silent.
- **`passthrough:///` is required with `grpc.NewClient`**: its default resolver is DNS, which would try to resolve `bufnet`.
- **`insecure.NewCredentials()` belongs here and nowhere else** (`rules/go-daemon/outbound.md`).
- **Closing the listener** is how a test makes the server unreachable.
- What to cover: registering with the token and resuming with the key after a dropped stream, the session staying up while heartbeats are answered, a session ending and reconnecting when the server keeps the stream open but stops answering, messages passing both ways, a refusal ending `Run` with its sentinel, and `Run` giving up after `ORPHAN_AFTER`.
- **Intervals in tests are milliseconds**, chosen in the test's config, and checks poll with `require.Eventually`; what must not happen is checked with `assert.Never` over a few intervals.

## Time

- **A periodic job takes its ticks as a channel** (`rules/go-daemon/lifecycle.md`), and its test, in the same package, sends them:

```go
// internal/report/report_test.go
ticks := make(chan time.Time)
ctx, cancel := context.WithCancel(t.Context())
done := make(chan error, 1)
go func() { done <- r.loop(ctx, ticks) }()

require.Eventually(t, func() bool { return send.count() == 1 }, time.Second, 5*time.Millisecond)
ticks <- time.Now()
require.Eventually(t, func() bool { return send.count() == 2 }, time.Second, 5*time.Millisecond)
cancel()

require.NoError(t, <-done)
```

- A loop that waits on `time.After` or a ticker inside it cannot be tested this way and ends up tested with `time.Sleep`; pass the channel in instead.

## Child processes

- **The runner is tested with real processes**: `sh -c` with a script that prints, exits with a code, sleeps or reads an environment variable. Starting, stopping and reading processes is the code under test; a fake process would test nothing.
- What to cover: the exit code and output, a variable set in the daemon's environment (`t.Setenv`) not reaching the command, output cut at the limit while the command finishes, a command that starts a child stopped as a group within the grace period, and a command refused when every slot is busy.
- These tests run on the platforms the daemon builds for; a test that needs Linux (`/proc`, cgroups) carries a `//go:build linux` constraint.

## What to test

| Code | Test it | How |
|---|---|---|
| A job's decisions: what it sends, when it refuses, how it reports a failure | Yes | Construct with a fake of what it sends to |
| A periodic job's schedule | Yes | Ticks through a channel |
| The connection: registering, heartbeats, reconnecting, giving up | Yes | A fake server over `bufconn` |
| The child process runner | Yes | Real processes |
| Configuration checks a tag cannot express | Yes | `t.Setenv`, then `config.Load` |
| `app.New` and `main` | No | They only wire; the jobs and the connection are tested |
| Generated code in `gen/` | No | It is generated (`rules/go-daemon/contract.md`) |
