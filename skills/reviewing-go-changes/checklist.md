# Judgment checklist

Apply the sections whose rule files cover the file under review. Each item names its rule file; the rule has the detail and the reason.

## Every Go file (`go/conventions.md`)

- File names are snake_case and name the content, not the role; the package name is the folder name and shadows no standard library package.
- Initialisms are all caps or all lower, the package name is not repeated in its identifiers, getters have no `Get`, interfaces are `-er` or role nouns, receivers are one or two letters and the same on every method.
- Interfaces are declared by the package that uses them, with only the methods it calls. Constructors return concrete types; each implementation has `var _ Port = (*Impl)(nil)`.
- Stateful types use pointer receivers and small immutable values use value receivers, one kind per type.
- Errors from outside are wrapped with the operation, the subject's id and `%w`; they are logged or returned, never both; nothing returns `(nil, nil)`; `panic`, `log.Fatal` and `os.Exit` appear only in `main`.
- Comments say why, in English; a `//nolint` names its linter and its reason.

## Contexts and goroutines (`go/concurrency.md`)

- `ctx` is the first parameter of anything that does I/O or blocks, is never stored in a struct, and `context.Background()` appears only at roots.
- Calls that leave the process have a deadline.
- Every goroutine has an owner that cancels it and waits for it; no handler starts one and forgets it; fan-out is bounded.
- Resources are closed by their creator, after everything that uses them has stopped.

## Structure (`go-server/architecture.md`)

- The file sits where its job belongs: model in `domain/`, use cases and ports in `application/`, inbound adapters in `adapters/in/`, outbound adapters in `adapters/out/`, domain-free clients in `internal/infrastructure/`, composition only in `internal/app/`.
- Another module is reached through a port and an adapter that calls its root package, never by importing its internals or by a use case importing it.
- The module root re-exports only the use cases other modules call, their query and result types, and the errors they return.

## Domain (`go-server/domain.md`)

- Aggregates have unexported fields, `Register{D}` (or the domain's verb) that checks invariants, `Restore{D}` without checks, `Snapshot()`, and state changes only through methods that take `now`.
- Value objects are structs with `New{V}` and `Restore{V}`; value lists are a string type, its constants and the slice that lists them.
- Errors are `Err{D}{Reason}` sentinels from `domainerr.New` with a `{MODULE}_{REASON}` code and a fitting kind.
- Each error is created by the lowest layer that knows the result is abnormal.

## Application (`go-server/application.md`)

- One struct per operation with one `Execute(ctx, …)`; its command or query and its result live in the same file.
- The result is a plain struct built from `Snapshot()`, never an aggregate or a response type.
- Dependencies, the clock and policy values come through the constructor; no configuration is read.
- Writes that must succeed together run inside `transaction.Run` with a closure parameter named `ctx`; external side effects run after it.

## Inbound adapters and HTTP (`go-server/adapters.md`, `go-server/http.md`, `api/contract.md`)

- One request struct per operation; every body struct has `_ struct{} \`additionalProperties:"true"\``; value lists come from the domain through `SchemaProvider`.
- The handler picks fields into the command, reads the user with `middleware.PrincipalFrom`, returns the use case's error unchanged, and answers with `apiresponse.OK`, `Created` (on a `201` route), `Empty` or `FromPage`; lists are never nil slices; it builds no HTTP error itself.
- Routes need authentication unless registered with `middleware.Public`; roles are declared on the route; abusable routes have rate limits.

## Outbound adapters (`go-server/adapters.md`, `database/sqlc.md`, `database/mongo-go-driver.md`)

- Repositories query through `db.Conn(ctx)`, map rows through the mapper, translate recognized constraint violations and `pgx.ErrNoRows` into domain errors, and wrap the rest.
- An adapter for another module calls that module's root package through a small unexported interface; the root re-exports what it needs.

## Runtime (`go-server/runtime.md`)

- Only `internal/config` reads the environment, and `Load` fails on a wrong value.
- Logs go through the injected logger with `…Context` methods, fixed messages and camelCase attributes, carry the `requestId` and the user, and never include bodies or secrets; domain errors are not logged as `error`.

## Database (`database/conventions.md`, `database/postgres.md`, `database/sqlc.md`, `database/mongo-go-driver.md`)

- Migrations are goose SQL files, or golang-migrate JSON files with MongoDB, named `YYYYMMDDHHMMSS_{verb}_{target}`; a migration only adds unless it is release 2 of expand → contract, and the code no longer uses what it removes; a merged migration is never edited.
- Names, types and constraint names follow the engine rules; `created_at` comes from the aggregate and `updated_at` from the query.
- Every list query ends its sort with the id; each index serves an existing query and carries a comment naming it.
- `sqlcgen` changes come from `make generate`, never by hand, and a change to `queries.sql` comes with them. With MongoDB, every document field has a `bson` tag and side effects stay out of `WithTransaction`'s closure.

## Tests (`go-server/testing.md`)

- Domain, use case and mapper code changed in this diff is tested in the same change — the new function itself, not only its file; database tests cover only what the database decides and use `dbtest`.
- Tests are in `package …_test` unless they need unexported code, use hand-written fakes with `var _` checks, test data from the module's testkit, and `t.Run` names that state the behavior in English.
- No `time.Sleep`; unique values come from the random tail of a UUIDv7.
