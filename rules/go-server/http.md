---
paths:
  - "**/adapters/in/httpapi/**"
  - "**/internal/common/**"
  - "**/internal/app/**"
---

# HTTP in a Go server

The contract — standard response, lists, the error table, paths, defenses — is `rules/api/contract.md`. This file is how a Go server implements it with huma on the standard `net/http` mux. huma generates the OpenAPI document from the same request structs that it validates, so validation, types and docs have one source.

## Setup

```go
// internal/app/app.go
apiresponse.Install(logger)
humaConfig := huma.DefaultConfig("server", version)
humaConfig.CreateHooks = nil // drops the $schema key huma adds to every body
humaConfig.SchemasPath = ""  // the /schemas route would answer outside /api and outside authentication
humaConfig.DocsPath, humaConfig.OpenAPIPath = "", ""
if cfg.APIDocsEnabled { // development and staging only
	humaConfig.DocsPath, humaConfig.OpenAPIPath = "/api/docs", "/api/openapi"
}
mux := http.NewServeMux()
api := humago.New(mux, humaConfig)
api.UseMiddleware(middleware.Auth(api, authenticate))
user.handler.Register(api)

router := middleware.Unmatched(mux)
handler := middleware.RequestID(middleware.RequestLog(logger)(middleware.Recover(logger)(router)))
```

## Standard response

Successes go through `internal/common/apiresponse`:

```go
type Body[T any] struct {
	Result    T       `json:"result"`
	Message   *string `json:"message"`
	Timestamp string  `json:"timestamp"`
	RequestID string  `json:"requestId"`
	ErrorCode *string `json:"errorCode"`
}

type Output[T any] struct {
	Body Body[T]
}

func OK[T any](ctx context.Context, result T) *Output[T]                // fills timestamp and requestId
func Created(ctx context.Context, id string) *Output[CreatedResult]      // result: { id }
func Empty(ctx context.Context) *Output[*struct{}]                       // result: null
func FromPage[T, R any](p page.Result[T], toItem func(T) R) Page[R]
```

- A handler returns `apiresponse.OK(ctx, NewUserResponse(result)), nil`. The output type is generic, so the OpenAPI document shows each route's real shape.
- A create route registers with `DefaultStatus: http.StatusCreated` and returns `apiresponse.Created(ctx, id)`. Other `POST` actions set `DefaultStatus: http.StatusOK`.

## Errors

Every error huma produces — a handler's returned error, a validation failure, a body over the limit — goes through `huma.NewErrorWithContext`. `apiresponse.Install` replaces it once, at startup, with the contract's mapping:

```go
func New(ctx context.Context, logger *slog.Logger, status int, msg string, errs ...error) *ErrorResponse {
	var de *domainerr.Error
	for _, err := range errs {
		if errors.As(err, &de) { // wrapped domain errors too
			return build(ctx, kindStatus[de.Kind], de.Code, de.Code, nil)
		}
	}
	if fields := fieldsOf(errs); len(fields) > 0 || status == http.StatusUnprocessableEntity {
		return build(ctx, http.StatusBadRequest, "VALIDATION_FAILED", msg, &ValidationResult{Fields: fields})
	}
	if status >= http.StatusInternalServerError {
		logger.ErrorContext(ctx, "unexpected error", slog.Any("err", errors.Join(errs...)))
		return build(ctx, http.StatusInternalServerError, "INTERNAL_ERROR", "internal error", nil)
	}
	return build(ctx, status, statusCode(status), msg, nil)
}
```

- Handlers return the use case's error unchanged; nothing in a module converts errors to statuses.
- **Handlers never call `huma.Error401Unauthorized` and its siblings.** huma builds those through `huma.NewError`, which has no request, so the response loses its `requestId`. A handler returns a domain error instead.
- huma reports validation failures as 422; the mapping turns them into the contract's 400 `VALIDATION_FAILED`. Each field's `path` drops huma's location prefix (`body.reason` → `reason`).
- `ErrorResponse` is the standard response with an unexported status and `GetStatus()`; huma writes the value itself as the body.
- An unexpected error is logged here, once, with the request's id, and its text never reaches the client.
- Errors outside huma use `apiresponse.Write(w, r, status)` for the same shape. Its status-name table includes 500 → `INTERNAL_ERROR`, so a recovered panic answers like any other unexpected error.

## Middleware

Standard `net/http` middleware wraps the router; huma middleware runs inside it, where the matched operation is known:

```
requestId → request log → panic recovery → security headers → CORS → unmatched routes → [huma] authentication and roles → rate limit → handler
```

- **requestId** is the outermost layer, so every layer inside it, the panic recovery included, sees the id. It takes `X-Request-Id` or creates one, echoes the header, and puts a `requestinfo.Info` in the context (`internal/libs/requestinfo`).
- **The request log** writes one line per request after the inner layers return: method, route pattern (`r.Pattern`), status, duration, `requestId`, user id. `net/http` hands no status back, so it wraps the `ResponseWriter` to record the one written. The user id comes from the same `requestinfo.Info`, which authentication fills in further in.
- **Panic recovery** sits inside the request log. Go drops the connection when a handler panics; the recovery writes a 500 standard response, which still carries the `requestId` and still gets its request line, and logs the panic once.
- **Unmatched routes**: `middleware.Unmatched(mux)` answers a request no route matches with the standard response — 404, or 405 with `Allow` when the path exists for another method. A catch-all `"/"` route would turn every 405 into a 404.
- **Authentication and roles** are one huma middleware (`api.UseMiddleware`). It reads the matched operation's metadata: a route registered through `middleware.Public(op)` passes, every other route needs a principal, and `middleware.Roles(op, "admin")` also needs the role. A failure is `huma.WriteErr(api, ctx, 401 or 403, …)`, which goes through the same error mapping. On success it records the user id in `requestinfo` and puts the principal in the context.
- **A handler reads the user** with `middleware.PrincipalFrom(ctx)`. On a route that is not public the middleware has already guaranteed it.
- **Body size**: huma enforces `MaxBodyBytes` on every operation, 1 MB unless the operation sets its own; an upload route sets its own.
- **Rate limits** wrap only the routes that can be abused.

## Server

```go
server := &http.Server{
	Addr:              fmt.Sprintf(":%d", cfg.Port),
	Handler:           handler,
	ReadHeaderTimeout: 5 * time.Second,
	ReadTimeout:       15 * time.Second,
	WriteTimeout:      15 * time.Second,
	IdleTimeout:       60 * time.Second,
}
```

- Every timeout is set. Their zero value is "no limit", which lets a client that sends headers slowly hold connections forever (slowloris); `gosec` flags a missing `ReadHeaderTimeout`.
- `app.Run` serves it and calls `Shutdown` with a timeout when the context ends (`rules/go/concurrency.md`).
- `/api/health` is registered with `middleware.Public` and splits liveness from readiness (`rules/go-server/runtime.md`).
- huma checks route registrations only when `app.New` runs, so a new route is confirmed by starting the server once (`make run`) and calling it.
