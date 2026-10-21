---
paths:
  - "**/internal/config/**"
  - "**/internal/libs/logger/**"
  - "**/internal/app/**"
  - "**/main.go"
---

# Go server runtime: configuration and observability

## Configuration

```go
// internal/config/config.go
type Config struct {
	Port             int        `env:"PORT" envDefault:"8080"`
	DatabaseURL      string     `env:"DATABASE_URL,required"`
	DatabasePoolSize int32      `env:"DATABASE_POOL_SIZE" envDefault:"10"`
	ServiceTimeZone  string     `env:"SERVICE_TIME_ZONE" envDefault:"Asia/Seoul"`
	CORSOrigins      []string   `env:"CORS_ORIGINS" envSeparator:","`
	LogFormat        string     `env:"LOG_FORMAT" envDefault:"json"`
	LogLevel         slog.Level `env:"LOG_LEVEL" envDefault:"info"`
	APIDocsEnabled   bool       `env:"API_DOCS_ENABLED" envDefault:"false"`
	PaymentAPIKey    string     `env:"PAYMENT_API_KEY"` // optional integration

	ServiceLocation *time.Location `env:"-"` // filled by Load from ServiceTimeZone
}

func Load() (Config, error) {
	cfg, err := env.ParseAs[Config]()
	if err != nil {
		return Config{}, fmt.Errorf("parse env: %w", err)
	}
	cfg.ServiceLocation, err = time.LoadLocation(cfg.ServiceTimeZone)
	if err != nil {
		return Config{}, fmt.Errorf("SERVICE_TIME_ZONE %q: %w", cfg.ServiceTimeZone, err)
	}
	return cfg, nil
}
```

- **Environment variables only**, parsed by `caarlos0/env`. Tags give each variable's name, whether it is required and its default; checks and conversions a tag cannot express follow the parse in `Load`, such as turning `SERVICE_TIME_ZONE` into the `*time.Location` that day boundaries use (`rules/go-server/application.md`).
- **Validated at boot.** A wrong or missing required value makes `Load` fail and `main` exit, so a bad deployment fails when it starts. No value silently falls back to a default.
- **Read in one place.** Only `internal/config` reads the environment. `main` loads the `Config` once and `app.New` hands each constructor the values it needs; there is no global config variable. The one exception is test setup, which reads `TEST_DATABASE_URL` and `CI` itself (`rules/go-server/testing.md`).
- **The app never reads `.env`.** Deployments inject the variables; locally, `make run` loads the file into the shell first (`rules/go/tooling.md`).
- **Use cases never read configuration.** A setting a use case needs is a value in its constructor (`rules/go-server/application.md`).
- **Optional integrations are optional in the struct.** When one is missing, the server still starts and its adapter returns an error when called. Values the server cannot run without stay `required`.
- **A large structured setting** (a rules table, per-feature lists) that does not fit a variable lives in a YAML file whose path comes from the environment (`RULES_FILE`). Secrets stay in variables.

## Logs

```go
// internal/libs/logger/logger.go
func New(w io.Writer, format string, level slog.Level) *slog.Logger { // main passes os.Stdout, tests a buffer
	opts := &slog.HandlerOptions{Level: level}
	var h slog.Handler = slog.NewJSONHandler(w, opts)
	if format == "text" {
		h = slog.NewTextHandler(w, opts)
	}
	return slog.New(requestHandler{h})
}

// requestHandler adds the request's id and user to every line logged with a ...Context method.
type requestHandler struct{ slog.Handler }

func (h requestHandler) Handle(ctx context.Context, r slog.Record) error {
	info := requestinfo.From(ctx)
	if info.ID != "" {
		r.AddAttrs(slog.String("requestId", info.ID))
	}
	if info.UserID != "" {
		r.AddAttrs(slog.String("userId", info.UserID))
	}
	return h.Handler.Handle(ctx, r)
}
// WithAttrs and WithGroup wrap the result the same way, so derived loggers keep both.
```

- **`log/slog`**, JSON in production; `LOG_FORMAT=text` for reading locally.
- **The logger is injected** through constructors from `app.New`, never taken from `slog.Default()`.
- **Every call is a `…Context(ctx, …)` method**, so the handler can add the `requestId` and the user from the context (`requestinfo`, filled by the middleware in `rules/go-server/http.md`). One response a user received leads straight to its log lines.
- **A message is a fixed short phrase; changing values are attributes** with camelCase keys: `logger.InfoContext(ctx, "user withdrawn", slog.String("userId", id))`. A value formatted into the message makes every occurrence a different message, which defeats search and counting.
- `sloglint` enforces the three rules above and `forbidigo` bans `fmt.Print*` and the standard `log` package (`rules/go/conventions.md`).
- **One request line per request**: method, route, status, duration in milliseconds, `requestId`, user id. Never the body (`rules/go-server/http.md`).
- **Levels.**

  | Level | For |
  |---|---|
  | `error` | Unexpected errors (500) only |
  | `warn` | Handled but unusual: a retried external call, a fallback taken |
  | `info` | Request lines and meaningful business events |

  A domain error (404, 409 …) is a normal response, not an `error`.
- **No secrets.** Passwords, tokens and personal data never reach a log line.

## Errors, health and metrics

- **Error tracking** (Sentry or similar) receives unexpected errors (500) only.
- **Health.** `/api/health` is public, splits liveness (the process answers) from readiness (the database answers, `db.Ping`), and reports the build version. During shutdown, readiness fails first.
- **Metrics** are the project's choice. When a project collects them, they include request count, status code and duration, not only the runtime defaults.
- **The version** is injected at build time, logged at startup and returned by health.

## main

```go
func main() {
	os.Exit(run())
}

// run returns the exit code, so its defers finish before os.Exit ends the process.
func run() int {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg, err := config.Load()
	if err != nil {
		slog.ErrorContext(ctx, "load config", slog.Any("err", err))
		return 1
	}
	lg := logger.New(os.Stdout, cfg.LogFormat, cfg.LogLevel)
	a, err := app.New(ctx, cfg, lg, version)
	if err != nil {
		lg.ErrorContext(ctx, "start", slog.Any("err", err))
		return 1
	}
	lg.InfoContext(ctx, "started", slog.String("version", version), slog.Int("port", cfg.Port))
	if err := a.Run(ctx); err != nil {
		lg.ErrorContext(ctx, "run", slog.Any("err", err))
		return 1
	}
	return 0
}
```
