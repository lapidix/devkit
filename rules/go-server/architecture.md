---
paths:
  - "**/internal/**"
  - "**/main.go"
---

# Go server architecture

The same hexagonal, domain-first server as `rules/server/architecture.md`, written the Go way. The domain and the use cases know no framework; everything that touches the outside world is an adapter at the edge. Go-wide rules are in `rules/go/`.

## Structure

```
main.go                          process concerns only: signals, config, logger, app.New, app.Run, exit code
migrations/                      goose migrations, the schema's one source (rules/database/sqlc.md)
sqlc.yaml
tools/go.mod                     sqlc, goose (rules/go/tooling.md)
internal/
├── app/                         the only composition root: app.go (New, Run), one file per module (user.go)
├── config/                      env loading (rules/go-server/runtime.md)
├── modules/                     one folder per domain
│   └── user/
│       ├── user.go              public API: what other modules may use
│       ├── domain/              aggregates, value objects, domain errors, the aggregate's repository port
│       ├── application/         use cases (one file each) and ports.go
│       ├── adapters/
│       │   ├── in/              what calls into the app: httpapi/ (handlers, requests, responses), schedule/, …
│       │   └── out/             what the app calls: persistence/ (repository, mapper, queries, sqlcgen/), auth/ (another module), …
│       └── testkit/             test data (testkit.User), imported only by this module's tests
├── shared/                      base types every module shares: domainerr, ids, page
├── infrastructure/              technical clients that know no domain: database (pool, transactions), HTTP clients
├── common/                      HTTP glue: apiresponse, middleware
├── libs/                        domain-free libraries: logger, requestinfo
└── archtest/                    the architecture test (rules/go-server/testing.md)
```

- `internal/` makes every package importable only from this module: Go's recommended layout for a server, and protection for the day the repository gains a second module.
- With one binary, `main.go` sits at the root. With several, each gets `cmd/{name}/main.go`.
- Every adapter sits under `in/` or `out/`, so a new kind of adapter needs no new folder rule.
- Why domain first: a change to one feature stays in one folder. A tree split by layer first spreads one change over several folders, and the spread grows with every domain.

## Packages

- `domain/` and `application/` are one package each, with no subfolders; files tell use cases and ports apart (`rules/go/conventions.md`).
- Each adapter folder is its own package named for its technology or target: `httpapi`, `persistence`, `auth`. None shadows a standard library package, which is why it is `httpapi` and not `http`.
- Inside a module no alias is needed: there is one `domain` and one `application`. A file importing two packages with the same name aliases them `{module}{package}`: `userapplication`, `orderhttpapi`.
- An adapter folder named after another module (`adapters/out/auth/`) has that module's package name, so it imports the module root as `{module}module`: `authmodule`.

## Technical clients and adapters

| Code | Knows a domain | Lives in |
|---|---|---|
| A technical client: the database pool and transaction runner, an HTTP client, configuration | No | `internal/infrastructure/`, `internal/config/` |
| An adapter: implements one module's port and knows its data (`persistence.UserRepository`, its mapper) | Yes | `internal/modules/{d}/adapters/out/` |

The adapter receives the client through its constructor.

## Dependency direction

| From | May import |
|---|---|
| `domain` | the standard library and `internal/shared` |
| `application` | its own `domain`, `internal/shared`, the standard library |
| `adapters/in` | its own `application`, `internal/shared`, `internal/common`, `internal/libs`, huma; from its own `domain`, only value lists (constants, their types, the slices that list them) |
| `adapters/out` | its own `application` and `domain`, `internal/shared`, `internal/infrastructure`, `internal/libs`, drivers, another module's root package |
| module root (`user.go`) | its own `application` and `domain` |
| `shared`, `infrastructure`, `common`, `libs` | never `modules` or `app` |
| `app` | everything |

- Go packages cannot see into one package and leave the rest of it closed, so "value lists only" is checked by type, not by import.
- `adapters/in` and `adapters/out` never import each other, and use cases never import another module.
- `internal/archtest` enforces this table; its template is in the `setting-up-architecture-checks` skill. Import cycles need no rule: the compiler rejects them.

## How a request flows

```
 [client] POST /api/users/{id}/withdraw                  [client] 2xx + standard response
          │                                                        ▲
 middleware  panic recovery, requestId, request log      apiresponse.OK  { result, message, timestamp, requestId, errorCode }
          ▼                                                        ▲
 huma        authentication, request struct + validation  handler  NewUserResponse(result), on reads
          ▼                                                        ▲
 handler     request → WithdrawUserCommand                         │
          ▼                                                        │
 use case    ──────────────────────────────────────────▶ use case returns its result
          │                                                        ▲
          ▼                                                        │
 adapters/out  query → sqlcgen row → mapper → domain.RestoreUser   │
          │                                                        │
          └──────────▶ domain  u.Withdraw(now) ────────────────────┘
                       invariants, state change; saving goes back through Snapshot() → mapper

 any error (validation, a domain error, an unexpected error) → the huma error override: kind → status,
 { result: null, message, timestamp, requestId, errorCode }
```

## Modules talking to each other

A use case that needs another module declares its own port in `application/ports.go`, in its own words. An adapter in `adapters/out/{module}/` implements it by calling the other module's public use case.

```go
// internal/modules/user/user.go — what other modules may use, nothing else
package user

type (
	GetUserDetail       = application.GetUserDetail // a type alias: app passes the same value on
	GetUserDetailQuery  = application.GetUserDetailQuery
	GetUserDetailResult = application.GetUserDetailResult
)

var ErrUserNotFound = domain.ErrUserNotFound // the same value, so errors.Is still matches
```

- The module root re-exports the public use cases, their query and result types, the value lists those results use (`UserStatusWithdrawn`), and the domain errors they return. Entities, repositories and adapters stay inside.
- Never inject another module's use case into a use case. The use case depends only on its own port, tests replace that port, and a change in the other module touches one adapter.
- **Composition happens only in `internal/app`.** Each module has a file there (`app/user.go`) that builds its repository, adapters and use cases; `app.New` connects the modules and `app.Run` owns the lifecycle (`rules/go/concurrency.md`). A module never wires itself: Go rejects import cycles, so two modules that each wired themselves and called each other could not compile.
- When two modules would call each other, the one higher in the flow reads what the lower one needs and passes it in.
