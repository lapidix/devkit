---
paths:
  - "**/internal/config/**"
  - "**/internal/libs/logger/**"
  - "**/internal/libs/opinfo/**"
  - "**/internal/app/**"
  - "**/main.go"
---

# Go daemon runtime: configuration, logs and exit codes

## Configuration

```go
// internal/config/config.go
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

- **Environment variables only**, parsed by `caarlos0/env`. Tags give each variable's name, whether it is required and its default; checks a tag cannot express follow the parse in `Load`.
- **Read in one place and validated at boot.** Only `internal/config` reads the environment; `main` loads the `Config` once and `app.New` hands each constructor the values it needs. A wrong or missing value makes `Load` fail and `main` exit with 1.
- **The daemon never reads `.env`.** Its supervisor or platform injects the variables; locally, `make run` loads the file into the shell first (`rules/go/tooling.md`).
- **Every interval and limit is checked in `Load`**, including how they relate: a server timeout no longer than the heartbeat ends every session. A daemon has no request to fail on a bad value; it would spin or stall silently instead.
- **A secret handed to the daemon at start is read once and removed from the environment** with the `unset` tag option, so nothing the daemon starts later inherits it (`rules/go-daemon/subprocess.md`).
- **A daemon whose settings do not fit variables** (a monitoring agent with per-feature lists) reads them from a YAML file whose path comes from the environment. Secrets stay in variables. A feature that is switched off needs none of its settings; one that is switched on and lacks them fails `Load`.

## Logs

```go
// internal/libs/logger/logger.go
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

```go
// internal/libs/opinfo/opinfo.go
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

- **Logs go to stderr.** Stdout belongs to a one-shot command's result, and a daemon run by a supervisor keeps its streams apart.
- **The work item's id plays the role of the request id**: the job puts the id the server gave the item (`opinfo.With(ctx, cmd.GetOpId())`) into the context, and the handler adds it to every line. One item the server tracks leads straight to its log lines.
- **The logger is injected** through constructors from `app.New`, never taken from `slog.Default()`, and every call is a `…Context(ctx, …)` method so the handler sees the work item's id.
- **A message is a fixed short phrase; changing values are attributes** with camelCase keys. `sloglint` enforces this and `forbidigo` bans `fmt.Print*` and the `log` package (`rules/go/conventions.md`).
- **No secrets, no command output, no environment values** in a log line; the server keeps a command's output if anyone does.
- **Levels.**

  | Level | For |
  |---|---|
  | `error` | The daemon cannot do its job: a panic recovered in a job, the server refusing it, giving up on the server |
  | `warn` | Handled and retried: a dropped connection, a failed report, a result that could not be sent |
  | `info` | Starting, registering, stopping, and the work items the server asked for |

  A command that exits non-zero is a result, not an error of the daemon's.

## Health and version

- **No health endpoint.** A daemon with no inbound port is alive when its server sees its heartbeats (`rules/go-daemon/outbound.md`); a process that hangs stops sending them, and one that crashes is restarted by its supervisor. Open a port for a probe only when the platform requires one, and then bind it to localhost.
- **The version** is injected at build time (`rules/go/tooling.md`), logged at startup, sent to the server when the daemon registers, and printed by `{binary} version`.

## main

```go
// main.go
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

| Exit code | When |
|---|---|
| 0 | Stopped by a signal, after a clean shutdown |
| 1 | The config was wrong, startup failed, or `Run` gave up (the server refused the daemon, or was gone too long) |

A supervisor set to restart on failure (systemd `Restart=on-failure`, a Kubernetes `restartPolicy: OnFailure`) restarts on 1 and leaves 0 alone, so a daemon never exits 0 on a failure it could not recover from.
