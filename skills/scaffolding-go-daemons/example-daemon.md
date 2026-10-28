# Example daemon: `example.com/daemon`

One complete daemon that follows the Go daemon rules: it dials its server over gRPC with TLS, registers with a one-time token and resumes with a key, keeps the stream alive with heartbeats, reconnects with backoff and gives up after `ORPHAN_AFTER`, reports disk usage every interval, and runs the commands its server sends in their own process groups. It builds, passes golangci-lint with the configuration in `rules/go/conventions.md` (`GOOS=linux`), the tests with `-race -shuffle=on` and goleak, govulncheck, and `buf lint` and `buf breaking`.

The project also has `.golangci.yml` from `rules/go/conventions.md`, `tools/go.mod` with buf, `protoc-gen-go`, `protoc-gen-go-grpc` and govulncheck (`rules/go/tooling.md`), and `gen/link/v1/`, which `make generate` writes and is not shown. Its runtime dependencies are `google.golang.org/grpc`, `google.golang.org/protobuf`, `github.com/caarlos0/env/v11` and `golang.org/x/sync`; its tests add `github.com/stretchr/testify` and `go.uber.org/goleak`.

## proto/link/v1/link.proto

```proto
syntax = "proto3";

package link.v1;

option go_package = "example.com/daemon/gen/link/v1;linkv1";

// LinkService is the server's side of the one connection a daemon opens.
service LinkService {
  // Connect is opened by the daemon; its first message is a Hello.
  rpc Connect(stream ConnectRequest) returns (stream ConnectResponse);
}

message ConnectRequest {
  oneof msg {
    Hello hello = 1;
    Heartbeat heartbeat = 2;
    Report report = 3;
    CommandResult command_result = 4;
  }
}

message ConnectResponse {
  oneof msg {
    Welcome welcome = 1;
    RunCommand run_command = 2;
    Heartbeat heartbeat = 3;
  }
}

message Hello {
  string daemon_id = 1;
  // token registers a new daemon once; resume_key reconnects one that has registered.
  string token = 2;
  string resume_key = 3;
  uint32 protocol_major = 4;
  string version = 5;
}

message Welcome {
  string resume_key = 1;
}

message Heartbeat {}

message Report {
  uint64 disk_used_bytes = 1;
  uint64 disk_total_bytes = 2;
}

message RunCommand {
  string op_id = 1;
  repeated string argv = 2;
  map<string, string> env = 3;
  uint32 timeout_ms = 4;
}

message CommandResult {
  string op_id = 1;
  int32 exit_code = 2;
  bytes output = 3;
  bool truncated = 4;
  bool timed_out = 5;
  string error = 6;
}
```

## buf.yaml

```yaml
version: v2
modules:
  - path: proto
lint:
  use:
    - STANDARD
breaking:
  use:
    - FILE
```

## buf.gen.yaml

```yaml
version: v2
clean: true
plugins:
  - local: [go, tool, -modfile=tools/go.mod, protoc-gen-go]
    out: gen
    opt: paths=source_relative
  - local: [go, tool, -modfile=tools/go.mod, protoc-gen-go-grpc]
    out: gen
    opt: paths=source_relative
```

## Makefile

```makefile
VERSION ?= dev
TOOL := go tool -modfile=tools/go.mod
LDFLAGS := -s -w -X main.version=$(VERSION)
PLATFORMS := linux/amd64 linux/arm64

.PHONY: run generate lint test vuln build release

run: ## the app never reads .env itself, so the shell loads it first
	set -a && . ./.env && set +a && go run .

generate:
	$(TOOL) buf lint
	$(TOOL) buf generate

lint: ## the daemon runs on Linux, so lint sees the Linux build
	GOOS=linux golangci-lint run

test:
	go test -race -shuffle=on ./...

vuln:
	$(TOOL) govulncheck ./...

build:
	CGO_ENABLED=0 go build -trimpath -ldflags "$(LDFLAGS)" -o bin/daemon .

release: ## one static binary per platform and their checksums, in dist/
	rm -rf dist && mkdir -p dist
	for p in $(PLATFORMS); do \
		CGO_ENABLED=0 GOOS=$${p%/*} GOARCH=$${p#*/} go build -trimpath -ldflags "$(LDFLAGS)" -o dist/daemon_$${p%/*}_$${p#*/} . || exit 1; \
	done
	cd dist && sha256sum daemon_* > checksums.txt
```

## main.go

```go
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"example.com/daemon/internal/app"
	"example.com/daemon/internal/config"
	"example.com/daemon/internal/libs/logger"
)

var version = "dev" // set by -ldflags "-X main.version=…"

func main() {
	os.Exit(run())
}

// run returns the exit code, so its defers finish before os.Exit ends the process.
func run() int {
	if len(os.Args) == 2 && os.Args[1] == "version" {
		if _, err := fmt.Fprintln(os.Stdout, version); err != nil {
			return 1
		}
		return 0
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg, err := config.Load()
	if err != nil {
		slog.ErrorContext(ctx, "load config", slog.Any("err", err))
		return 1
	}
	lg := logger.New(os.Stderr, cfg.LogFormat, cfg.LogLevel)
	a, err := app.New(cfg, lg, version)
	if err != nil {
		lg.ErrorContext(ctx, "start", slog.Any("err", err))
		return 1
	}
	lg.InfoContext(ctx, "started", slog.String("version", version), slog.String("daemonId", cfg.DaemonID))
	if err := a.Run(ctx); err != nil {
		lg.ErrorContext(ctx, "run", slog.Any("err", err))
		return 1
	}
	lg.InfoContext(ctx, "stopped")
	return 0
}
```

## internal/config/config.go

```go
package config

import (
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/caarlos0/env/v11"
)

type Config struct {
	DaemonID          string        `env:"DAEMON_ID,required"`
	DaemonToken       string        `env:"DAEMON_TOKEN,required,unset"` // unset: child processes never inherit it
	ServerAddr        string        `env:"SERVER_ADDR,required"`
	ServerCAFile      string        `env:"SERVER_CA_FILE,required"`
	HeartbeatInterval time.Duration `env:"HEARTBEAT_INTERVAL" envDefault:"15s"`
	ServerTimeout     time.Duration `env:"SERVER_TIMEOUT" envDefault:"45s"`
	OrphanAfter       time.Duration `env:"ORPHAN_AFTER" envDefault:"30s"`
	ReportInterval    time.Duration `env:"REPORT_INTERVAL" envDefault:"1m"`
	ReportPath        string        `env:"REPORT_PATH" envDefault:"/"`
	WorkDir           string        `env:"WORK_DIR" envDefault:"/workspace"`
	MaxCommands       int           `env:"MAX_COMMANDS" envDefault:"4"`
	MaxCommandTime    time.Duration `env:"MAX_COMMAND_TIME" envDefault:"30m"`
	OutputLimit       int           `env:"OUTPUT_LIMIT" envDefault:"1048576"`
	LogFormat         string        `env:"LOG_FORMAT" envDefault:"json"`
	LogLevel          slog.Level    `env:"LOG_LEVEL" envDefault:"info"`
}

func Load() (Config, error) {
	cfg, err := env.ParseAs[Config]()
	if err != nil {
		return Config{}, fmt.Errorf("parse env: %w", err)
	}
	positive := map[string]time.Duration{
		"HEARTBEAT_INTERVAL": cfg.HeartbeatInterval,
		"SERVER_TIMEOUT":     cfg.ServerTimeout,
		"ORPHAN_AFTER":       cfg.OrphanAfter,
		"REPORT_INTERVAL":    cfg.ReportInterval,
		"MAX_COMMAND_TIME":   cfg.MaxCommandTime,
	}
	for name, d := range positive {
		if d <= 0 {
			return Config{}, fmt.Errorf("%s %s: must be positive", name, d)
		}
	}
	if cfg.ServerTimeout <= cfg.HeartbeatInterval {
		return Config{}, errors.New("SERVER_TIMEOUT must be longer than HEARTBEAT_INTERVAL")
	}
	if cfg.MaxCommands < 1 || cfg.OutputLimit < 1 {
		return Config{}, errors.New("MAX_COMMANDS and OUTPUT_LIMIT must be at least 1")
	}
	return cfg, nil
}
```

## internal/config/config_test.go

```go
package config_test

import (
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"example.com/daemon/internal/config"
)

func TestLoad(t *testing.T) {
	t.Run("reads the token and removes it from the environment", func(t *testing.T) {
		t.Setenv("DAEMON_ID", "d-1")
		t.Setenv("DAEMON_TOKEN", "secret")
		t.Setenv("SERVER_ADDR", "server:443")
		t.Setenv("SERVER_CA_FILE", "/ca.pem")

		cfg, err := config.Load()

		require.NoError(t, err)
		assert.Equal(t, "secret", cfg.DaemonToken)
		_, ok := os.LookupEnv("DAEMON_TOKEN")
		assert.False(t, ok)
	})

	t.Run("fails when the server timeout is not longer than the heartbeat", func(t *testing.T) {
		t.Setenv("DAEMON_ID", "d-1")
		t.Setenv("DAEMON_TOKEN", "secret")
		t.Setenv("SERVER_ADDR", "server:443")
		t.Setenv("SERVER_CA_FILE", "/ca.pem")
		t.Setenv("SERVER_TIMEOUT", "10s")

		_, err := config.Load()

		require.Error(t, err)
	})
}
```

## internal/libs/opinfo/opinfo.go

```go
package opinfo

import "context"

type ctxKey struct{}

// With returns a context that carries the id of the work item it serves.
func With(ctx context.Context, opID string) context.Context {
	return context.WithValue(ctx, ctxKey{}, opID)
}

func From(ctx context.Context) string {
	id, _ := ctx.Value(ctxKey{}).(string)
	return id
}
```

## internal/libs/logger/logger.go

```go
package logger

import (
	"context"
	"io"
	"log/slog"

	"example.com/daemon/internal/libs/opinfo"
)

func New(w io.Writer, format string, level slog.Level) *slog.Logger { // main passes os.Stderr, tests a buffer
	opts := &slog.HandlerOptions{Level: level}
	var h slog.Handler = slog.NewJSONHandler(w, opts)
	if format == "text" {
		h = slog.NewTextHandler(w, opts)
	}
	return slog.New(opHandler{h})
}

// opHandler adds the id of the work item in the context to every line logged with a ...Context method.
type opHandler struct{ slog.Handler }

func (h opHandler) Handle(ctx context.Context, r slog.Record) error {
	if id := opinfo.From(ctx); id != "" {
		r.AddAttrs(slog.String("opId", id))
	}
	return h.Handler.Handle(ctx, r)
}

func (h opHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	return opHandler{h.Handler.WithAttrs(attrs)}
}

func (h opHandler) WithGroup(name string) slog.Handler {
	return opHandler{h.Handler.WithGroup(name)}
}
```

## internal/infrastructure/link/link.go

```go
package link

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"math/rand/v2"
	"sync/atomic"
	"time"

	"golang.org/x/sync/errgroup"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/status"

	linkv1 "example.com/daemon/gen/link/v1"
)

// ProtocolMajor is sent in Hello; the server refuses a daemon whose major differs from its own.
const ProtocolMajor = 1

const (
	minBackoff = time.Second
	maxBackoff = 30 * time.Second
)

var (
	ErrRejected   = errors.New("server rejected the daemon")
	ErrServerGone = errors.New("no server for longer than the orphan timeout")
)

type Config struct {
	DaemonID          string
	Token             string
	Version           string
	HeartbeatInterval time.Duration
	ServerTimeout     time.Duration // no message from the server for this long ends the session
	OrphanAfter       time.Duration // no session for this long ends Run
}

// Client is the daemon's one connection to its server. It registers, keeps the stream alive
// with heartbeats, reconnects with backoff, and passes each command from the server to Commands.
type Client struct {
	svc       linkv1.LinkServiceClient
	cfg       Config
	lg        *slog.Logger
	commands  chan *linkv1.RunCommand
	outbox    chan outgoing
	resumeKey string // read and written only by Run's goroutine
}

type outgoing struct {
	msg  *linkv1.ConnectRequest
	done chan error
}

// Dial creates the connection without connecting; the first stream connects it.
func Dial(addr string, creds credentials.TransportCredentials) (*grpc.ClientConn, error) {
	conn, err := grpc.NewClient(addr, grpc.WithTransportCredentials(creds))
	if err != nil {
		return nil, fmt.Errorf("dial %s: %w", addr, err)
	}
	return conn, nil
}

func New(conn *grpc.ClientConn, cfg Config, lg *slog.Logger) *Client {
	return &Client{
		svc:      linkv1.NewLinkServiceClient(conn),
		cfg:      cfg,
		lg:       lg,
		commands: make(chan *linkv1.RunCommand),
		outbox:   make(chan outgoing),
	}
}

// Commands delivers the server's commands, one at a time, to the job that runs them.
func (c *Client) Commands() <-chan *linkv1.RunCommand {
	return c.commands
}

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

// Run keeps a session open until ctx is cancelled. It returns ErrRejected when the server refuses
// the daemon, and ErrServerGone when no session has stayed up for OrphanAfter.
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

// session opens one stream and serves it until it fails. registered reports whether the server accepted the daemon.
func (c *Client) session(ctx context.Context) (registered bool, err error) {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	stream, err := c.svc.Connect(ctx)
	if err != nil {
		return false, fmt.Errorf("open stream: %w", err)
	}
	if err := stream.Send(c.hello()); err != nil {
		return false, fmt.Errorf("send hello: %w", err)
	}
	timer := time.AfterFunc(c.cfg.ServerTimeout, cancel) // a stream has no deadline; the answer to Hello does
	first, err := stream.Recv()
	timer.Stop()
	if err != nil {
		if code := status.Code(err); code == codes.Unauthenticated || code == codes.PermissionDenied {
			return false, fmt.Errorf("%w: %w", ErrRejected, err)
		}
		return false, fmt.Errorf("register: %w", err)
	}
	welcome := first.GetWelcome()
	if welcome == nil {
		return false, fmt.Errorf("register: first message is %T, not a welcome", first.GetMsg())
	}
	c.resumeKey = welcome.GetResumeKey()
	c.lg.InfoContext(ctx, "registered")

	var lastRecv atomic.Int64
	lastRecv.Store(time.Now().UnixNano())
	g, gctx := errgroup.WithContext(ctx)
	// The stream was opened under ctx, so cancelling gctx alone would wake neither a blocked Recv nor a
	// blocked Send: when one goroutine fails, end the stream itself.
	stop := context.AfterFunc(gctx, cancel)
	defer stop()
	g.Go(func() error { return c.receive(gctx, stream, &lastRecv) })
	g.Go(func() error { return c.send(gctx, stream) })
	g.Go(func() error { return c.watch(gctx, &lastRecv) })
	return true, g.Wait()
}

func (c *Client) hello() *linkv1.ConnectRequest {
	h := &linkv1.Hello{DaemonId: c.cfg.DaemonID, ProtocolMajor: ProtocolMajor, Version: c.cfg.Version}
	if c.resumeKey != "" {
		h.ResumeKey = c.resumeKey
	} else {
		h.Token = c.cfg.Token
	}
	return &linkv1.ConnectRequest{Msg: &linkv1.ConnectRequest_Hello{Hello: h}}
}

// receive is the stream's only reader.
func (c *Client) receive(ctx context.Context, stream linkv1.LinkService_ConnectClient, lastRecv *atomic.Int64) error {
	for {
		msg, err := stream.Recv()
		if err != nil {
			return fmt.Errorf("receive: %w", err)
		}
		lastRecv.Store(time.Now().UnixNano())
		if cmd := msg.GetRunCommand(); cmd != nil {
			select {
			case c.commands <- cmd:
			case <-ctx.Done():
				return ctx.Err()
			}
		}
	}
}

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

## internal/infrastructure/link/link_test.go

```go
package link_test

import (
	"context"
	"log/slog"
	"net"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/goleak"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/status"
	"google.golang.org/grpc/test/bufconn"

	linkv1 "example.com/daemon/gen/link/v1"
	"example.com/daemon/internal/infrastructure/link"
)

func TestMain(m *testing.M) {
	goleak.VerifyTestMain(m)
}

// fakeServer accepts the token "good" and the resume key it handed out, and echoes heartbeats.
type fakeServer struct {
	linkv1.UnimplementedLinkServiceServer
	commands  chan *linkv1.RunCommand
	dropFirst bool // ends the first stream right after the welcome
	silent    bool // answers nothing after the first welcome, but keeps the stream open

	mu       sync.Mutex
	hellos   []*linkv1.Hello
	received []*linkv1.ConnectRequest
}

func (s *fakeServer) Connect(stream linkv1.LinkService_ConnectServer) error {
	first, err := stream.Recv()
	if err != nil {
		return err
	}
	hello := first.GetHello()
	s.mu.Lock()
	s.hellos = append(s.hellos, hello)
	n := len(s.hellos)
	s.mu.Unlock()
	if hello.GetToken() != "good" && hello.GetResumeKey() != "key-1" {
		return status.Error(codes.Unauthenticated, "unknown daemon")
	}
	if err := stream.Send(&linkv1.ConnectResponse{Msg: &linkv1.ConnectResponse_Welcome{Welcome: &linkv1.Welcome{ResumeKey: "key-1"}}}); err != nil {
		return err
	}
	if s.dropFirst && n == 1 {
		return status.Error(codes.Unavailable, "restarting")
	}
	heartbeats := make(chan struct{}, 1)
	recvErr := make(chan error, 1)
	go func() { // the stream's only reader; replies go through the loop below, its only writer
		for {
			msg, err := stream.Recv()
			if err != nil {
				recvErr <- err
				return
			}
			s.mu.Lock()
			s.received = append(s.received, msg)
			s.mu.Unlock()
			if msg.GetHeartbeat() != nil {
				select {
				case heartbeats <- struct{}{}:
				default: // one answer pending is enough
				}
			}
		}
	}()
	for {
		var reply *linkv1.ConnectResponse
		select {
		case cmd := <-s.commands:
			reply = &linkv1.ConnectResponse{Msg: &linkv1.ConnectResponse_RunCommand{RunCommand: cmd}}
		case <-heartbeats:
			if s.silent && n == 1 {
				continue
			}
			reply = &linkv1.ConnectResponse{Msg: &linkv1.ConnectResponse_Heartbeat{Heartbeat: &linkv1.Heartbeat{}}}
		case err := <-recvErr:
			return err
		}
		if err := stream.Send(reply); err != nil {
			return err
		}
	}
}

func (s *fakeServer) helloCount() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.hellos)
}

func (s *fakeServer) results() []*linkv1.CommandResult {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []*linkv1.CommandResult
	for _, m := range s.received {
		if r := m.GetCommandResult(); r != nil {
			out = append(out, r)
		}
	}
	return out
}

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

func TestClientRun(t *testing.T) {
	t.Run("registers with the token, then reconnects with the resume key", func(t *testing.T) {
		srv := &fakeServer{commands: make(chan *linkv1.RunCommand), dropFirst: true}
		c, _ := start(t, srv, "good", time.Minute)

		run(t, c)

		require.Eventually(t, func() bool { return srv.helloCount() == 2 }, 3*time.Second, 10*time.Millisecond)
		srv.mu.Lock()
		defer srv.mu.Unlock()
		assert.Equal(t, "good", srv.hellos[0].GetToken())
		assert.Empty(t, srv.hellos[1].GetToken(), "the token is used once")
		assert.Equal(t, "key-1", srv.hellos[1].GetResumeKey())
	})

	t.Run("keeps a session open while the server answers heartbeats", func(t *testing.T) {
		srv := &fakeServer{commands: make(chan *linkv1.RunCommand)}
		c, _ := start(t, srv, "good", time.Minute)
		run(t, c)

		require.Eventually(t, func() bool { return srv.helloCount() == 1 }, time.Second, 10*time.Millisecond)
		assert.Never(t, func() bool { return srv.helloCount() > 1 }, 600*time.Millisecond, 50*time.Millisecond)
	})

	t.Run("ends a session the server stops answering and reconnects", func(t *testing.T) {
		srv := &fakeServer{commands: make(chan *linkv1.RunCommand), silent: true}
		c, _ := start(t, srv, "good", time.Minute)

		run(t, c)

		require.Eventually(t, func() bool { return srv.helloCount() == 2 }, 3*time.Second, 10*time.Millisecond)
	})

	t.Run("passes the server's commands on and sends the results back", func(t *testing.T) {
		srv := &fakeServer{commands: make(chan *linkv1.RunCommand)}
		c, _ := start(t, srv, "good", time.Minute)
		run(t, c)

		srv.commands <- &linkv1.RunCommand{OpId: "op-1", Argv: []string{"true"}}
		cmd := <-c.Commands()
		err := c.Send(t.Context(), &linkv1.ConnectRequest{Msg: &linkv1.ConnectRequest_CommandResult{CommandResult: &linkv1.CommandResult{OpId: cmd.GetOpId()}}})

		require.NoError(t, err)
		require.Eventually(t, func() bool { return len(srv.results()) == 1 }, time.Second, 10*time.Millisecond)
		assert.Equal(t, "op-1", srv.results()[0].GetOpId())
	})

	t.Run("stops with ErrRejected when the server refuses the token", func(t *testing.T) {
		srv := &fakeServer{commands: make(chan *linkv1.RunCommand)}
		c, _ := start(t, srv, "bad", time.Minute)

		wait := run(t, c)

		require.ErrorIs(t, wait(), link.ErrRejected)
	})

	t.Run("stops with ErrServerGone when no server answers for OrphanAfter", func(t *testing.T) {
		srv := &fakeServer{commands: make(chan *linkv1.RunCommand)}
		c, lis := start(t, srv, "good", 100*time.Millisecond)
		require.NoError(t, lis.Close())

		wait := run(t, c)

		require.ErrorIs(t, wait(), link.ErrServerGone)
	})

	t.Run("gives up at OrphanAfter, not a backoff later", func(t *testing.T) {
		srv := &fakeServer{commands: make(chan *linkv1.RunCommand)}
		c, lis := start(t, srv, "good", 2500*time.Millisecond) // past the 1s and 2s backoff ceilings
		require.NoError(t, lis.Close())

		began := time.Now()
		wait := run(t, c)

		require.ErrorIs(t, wait(), link.ErrServerGone)
		assert.Less(t, time.Since(began), 3*time.Second)
	})
}
```

## internal/report/report.go

```go
package report

import (
	"context"
	"fmt"
	"log/slog"
	"syscall"
	"time"

	linkv1 "example.com/daemon/gen/link/v1"
)

// Sender delivers a message to the server.
type Sender interface {
	Send(ctx context.Context, msg *linkv1.ConnectRequest) error
}

// Reporter sends the disk usage of one path to the server: once at start, then every interval.
type Reporter struct {
	send  Sender
	path  string
	every time.Duration
	lg    *slog.Logger
}

func NewReporter(send Sender, path string, every time.Duration, lg *slog.Logger) *Reporter {
	return &Reporter{send: send, path: path, every: every, lg: lg}
}

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

func (r *Reporter) report(ctx context.Context) error {
	var st syscall.Statfs_t
	if err := syscall.Statfs(r.path, &st); err != nil {
		return fmt.Errorf("statfs %s: %w", r.path, err)
	}
	blockSize := uint64(st.Bsize) //nolint:gosec // Bsize is never negative
	total, free := st.Blocks*blockSize, st.Bfree*blockSize
	msg := &linkv1.ConnectRequest{Msg: &linkv1.ConnectRequest_Report{Report: &linkv1.Report{
		DiskUsedBytes:  total - free,
		DiskTotalBytes: total,
	}}}
	if err := r.send.Send(ctx, msg); err != nil {
		return fmt.Errorf("send report: %w", err)
	}
	return nil
}
```

## internal/report/report_test.go

```go
package report

import (
	"context"
	"log/slog"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/goleak"

	linkv1 "example.com/daemon/gen/link/v1"
)

func TestMain(m *testing.M) {
	goleak.VerifyTestMain(m)
}

type fakeSender struct {
	mu      sync.Mutex
	reports []*linkv1.Report
}

var _ Sender = (*fakeSender)(nil)

func (f *fakeSender) Send(_ context.Context, msg *linkv1.ConnectRequest) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.reports = append(f.reports, msg.GetReport())
	return nil
}

func (f *fakeSender) count() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.reports)
}

func TestReporterLoop(t *testing.T) {
	t.Run("reports at start and on every tick until cancelled", func(t *testing.T) {
		send := &fakeSender{}
		r := NewReporter(send, t.TempDir(), time.Hour, slog.New(slog.DiscardHandler))
		ticks := make(chan time.Time)
		ctx, cancel := context.WithCancel(t.Context())
		done := make(chan error, 1)
		go func() { done <- r.loop(ctx, ticks) }()

		require.Eventually(t, func() bool { return send.count() == 1 }, time.Second, 5*time.Millisecond)
		ticks <- time.Now()
		require.Eventually(t, func() bool { return send.count() == 2 }, time.Second, 5*time.Millisecond)
		cancel()

		require.NoError(t, <-done)
		assert.Positive(t, send.reports[0].GetDiskTotalBytes())
	})
}
```

## internal/command/runner.go

```go
package command

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"maps"
	"os/exec"
	"slices"
	"sync"
	"syscall"
	"time"

	linkv1 "example.com/daemon/gen/link/v1"
	"example.com/daemon/internal/libs/opinfo"
)

const (
	killGrace   = 5 * time.Second // between SIGTERM and SIGKILL
	resultGrace = 5 * time.Second // for the last results sent during shutdown
)

// Sender delivers a message to the server.
type Sender interface {
	Send(ctx context.Context, msg *linkv1.ConnectRequest) error
}

type Config struct {
	WorkDir     string
	MaxCommands int
	MaxTime     time.Duration
	OutputLimit int
}

// Runner runs the server's commands, at most MaxCommands at a time, and sends each result back.
type Runner struct {
	commands <-chan *linkv1.RunCommand
	send     Sender
	cfg      Config
	lg       *slog.Logger
	slots    chan struct{}
}

func NewRunner(commands <-chan *linkv1.RunCommand, send Sender, cfg Config, lg *slog.Logger) *Runner {
	return &Runner{commands: commands, send: send, cfg: cfg, lg: lg, slots: make(chan struct{}, cfg.MaxCommands)}
}

// Run takes commands until ctx is cancelled, then waits for the ones still running; cancelling
// ctx stops their processes. A command that arrives when every slot is busy is refused, not queued.
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

// run recovers its own panic: one bad command fails alone instead of ending every other command with the process.
func (r *Runner) run(ctx context.Context, cmd *linkv1.RunCommand) (res *linkv1.CommandResult) {
	res = &linkv1.CommandResult{OpId: cmd.GetOpId(), ExitCode: -1}
	defer func() {
		if p := recover(); p != nil {
			r.lg.ErrorContext(ctx, "command panicked", slog.Any("panic", p))
			res.Error = "internal error"
		}
	}()
	if len(cmd.GetArgv()) == 0 {
		res.Error = "empty argv"
		return res
	}
	timeout := time.Duration(cmd.GetTimeoutMs()) * time.Millisecond
	if timeout <= 0 || timeout > r.cfg.MaxTime {
		timeout = r.cfg.MaxTime
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	out := &cappedBuffer{limit: r.cfg.OutputLimit}
	argv := cmd.GetArgv()
	c := exec.CommandContext(ctx, argv[0], argv[1:]...) //nolint:gosec // running the server's command is this daemon's job
	c.Dir = r.cfg.WorkDir
	c.Env = environ(r.cfg.WorkDir, cmd.GetEnv())
	c.Stdout, c.Stderr = out, out // the same writer, so exec writes to it from one goroutine at a time
	c.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	c.Cancel = func() error { return syscall.Kill(-c.Process.Pid, syscall.SIGTERM) }
	c.WaitDelay = killGrace
	err := c.Run()
	if c.Process != nil {
		_ = syscall.Kill(-c.Process.Pid, syscall.SIGKILL) // whatever the command left behind in its group
	}

	res.Output, res.Truncated = out.buf, out.truncated
	res.TimedOut = errors.Is(ctx.Err(), context.DeadlineExceeded)
	var exitErr *exec.ExitError
	switch {
	case err == nil:
		res.ExitCode = 0
	case errors.As(err, &exitErr):
		res.ExitCode = int32(exitErr.ExitCode()) //nolint:gosec // exit codes fit in int32
	default:
		res.Error = fmt.Sprintf("start: %v", err)
	}
	return res
}

func (r *Runner) reply(ctx context.Context, res *linkv1.CommandResult) {
	// A result produced while shutting down still goes out: ctx is cancelled by then.
	ctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), resultGrace)
	defer cancel()
	msg := &linkv1.ConnectRequest{Msg: &linkv1.ConnectRequest_CommandResult{CommandResult: res}}
	if err := r.send.Send(ctx, msg); err != nil {
		r.lg.WarnContext(opinfo.With(ctx, res.GetOpId()), "result not sent", slog.Any("err", err))
	}
}

// environ is the whole environment of a command: a fixed base and the request's values.
// The daemon's own environment is never inherited; a nil Env would pass all of it on.
func environ(home string, extra map[string]string) []string {
	vars := map[string]string{
		"PATH":   "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
		"HOME":   home,
		"LANG":   "C.UTF-8",
		"TMPDIR": "/tmp",
	}
	maps.Copy(vars, extra)
	env := make([]string, 0, len(vars))
	for _, k := range slices.Sorted(maps.Keys(vars)) {
		env = append(env, k+"="+vars[k])
	}
	return env
}

// cappedBuffer keeps the first limit bytes and reports whether it dropped any. It never
// returns an error, so a command that writes too much keeps running instead of dying on a broken pipe.
type cappedBuffer struct {
	buf       []byte
	limit     int
	truncated bool
}

func (b *cappedBuffer) Write(p []byte) (int, error) {
	n := len(p) // reported whole: a short count is an error to io.Copy
	if room := b.limit - len(b.buf); n > room {
		b.truncated = true
		p = p[:max(room, 0)]
	}
	b.buf = append(b.buf, p...)
	return n, nil
}
```

## internal/command/runner_test.go

```go
package command

import (
	"context"
	"log/slog"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/goleak"

	linkv1 "example.com/daemon/gen/link/v1"
)

func TestMain(m *testing.M) {
	goleak.VerifyTestMain(m) // a goroutine left behind is a process left behind
}

type fakeSender struct {
	mu   sync.Mutex
	sent []*linkv1.ConnectRequest
}

var _ Sender = (*fakeSender)(nil)

func (f *fakeSender) Send(_ context.Context, msg *linkv1.ConnectRequest) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.sent = append(f.sent, msg)
	return nil
}

func (f *fakeSender) results() []*linkv1.CommandResult {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []*linkv1.CommandResult
	for _, m := range f.sent {
		if r := m.GetCommandResult(); r != nil {
			out = append(out, r)
		}
	}
	return out
}

func newRunner(t *testing.T, commands chan *linkv1.RunCommand, send Sender, overrides ...func(*Config)) *Runner {
	t.Helper()
	cfg := Config{WorkDir: t.TempDir(), MaxCommands: 2, MaxTime: time.Minute, OutputLimit: 1 << 20}
	for _, o := range overrides {
		o(&cfg)
	}
	return NewRunner(commands, send, cfg, slog.New(slog.DiscardHandler))
}

func sh(script string) *linkv1.RunCommand {
	return &linkv1.RunCommand{OpId: "op-1", Argv: []string{"sh", "-c", script}}
}

func TestRunnerRun(t *testing.T) {
	t.Run("returns the exit code and the output", func(t *testing.T) {
		r := newRunner(t, nil, &fakeSender{})

		res := r.run(t.Context(), sh("echo hi; exit 3"))

		assert.Equal(t, int32(3), res.GetExitCode())
		assert.Equal(t, "hi\n", string(res.GetOutput()))
	})

	t.Run("gives the command the base and the request environment, never the daemon's", func(t *testing.T) {
		t.Setenv("DAEMON_SECRET", "leaked")
		r := newRunner(t, nil, &fakeSender{})
		cmd := sh(`echo "${DAEMON_SECRET:-none} $GREETING"`)
		cmd.Env = map[string]string{"GREETING": "hello"}

		res := r.run(t.Context(), cmd)

		assert.Equal(t, "none hello\n", string(res.GetOutput()))
	})

	t.Run("keeps the first bytes up to the limit and lets the command finish", func(t *testing.T) {
		r := newRunner(t, nil, &fakeSender{}, func(c *Config) { c.OutputLimit = 5 })

		res := r.run(t.Context(), sh("printf 1234567890; exit 0"))

		assert.Equal(t, "12345", string(res.GetOutput()))
		assert.True(t, res.GetTruncated())
		assert.Equal(t, int32(0), res.GetExitCode())
	})

	t.Run("stops the whole process group when the time is up", func(t *testing.T) {
		r := newRunner(t, nil, &fakeSender{})
		cmd := sh("sleep 30 & sleep 30")
		cmd.TimeoutMs = 200
		start := time.Now()

		res := r.run(t.Context(), cmd)

		assert.True(t, res.GetTimedOut())
		assert.Less(t, time.Since(start), killGrace)
	})

	t.Run("refuses a command when every slot is busy", func(t *testing.T) {
		commands := make(chan *linkv1.RunCommand)
		send := &fakeSender{}
		r := newRunner(t, commands, send, func(c *Config) { c.MaxCommands = 1 })
		ctx, cancel := context.WithCancel(t.Context())
		done := make(chan error, 1)
		go func() { done <- r.Run(ctx) }()

		commands <- &linkv1.RunCommand{OpId: "long", Argv: []string{"sleep", "30"}}
		commands <- &linkv1.RunCommand{OpId: "second", Argv: []string{"true"}}
		require.Eventually(t, func() bool { return len(send.results()) == 1 }, 2*time.Second, 10*time.Millisecond)
		assert.Equal(t, "second", send.results()[0].GetOpId())
		assert.Equal(t, "busy", send.results()[0].GetError())

		cancel()
		require.NoError(t, <-done)
		assert.Len(t, send.results(), 2, "the cancelled command still reports")
	})
}
```

## internal/app/app.go

```go
package app

import (
	"context"
	"errors"
	"fmt"
	"log/slog"

	"golang.org/x/sync/errgroup"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"

	"example.com/daemon/internal/command"
	"example.com/daemon/internal/config"
	"example.com/daemon/internal/infrastructure/link"
	"example.com/daemon/internal/report"
)

type App struct {
	conn     *grpc.ClientConn
	link     *link.Client
	reporter *report.Reporter
	runner   *command.Runner
}

func New(cfg config.Config, lg *slog.Logger, version string) (*App, error) {
	creds, err := credentials.NewClientTLSFromFile(cfg.ServerCAFile, "")
	if err != nil {
		return nil, fmt.Errorf("load server CA: %w", err)
	}
	conn, err := link.Dial(cfg.ServerAddr, creds)
	if err != nil {
		return nil, err
	}
	l := link.New(conn, link.Config{
		DaemonID:          cfg.DaemonID,
		Token:             cfg.DaemonToken,
		Version:           version,
		HeartbeatInterval: cfg.HeartbeatInterval,
		ServerTimeout:     cfg.ServerTimeout,
		OrphanAfter:       cfg.OrphanAfter,
	}, lg)
	return &App{
		conn:     conn,
		link:     l,
		reporter: report.NewReporter(l, cfg.ReportPath, cfg.ReportInterval, lg),
		runner: command.NewRunner(l.Commands(), l, command.Config{
			WorkDir:     cfg.WorkDir,
			MaxCommands: cfg.MaxCommands,
			MaxTime:     cfg.MaxCommandTime,
			OutputLimit: cfg.OutputLimit,
		}, lg),
	}, nil
}

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
