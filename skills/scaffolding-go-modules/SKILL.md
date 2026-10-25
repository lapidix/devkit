---
name: scaffolding-go-modules
description: Use when adding a new domain module to a Go server that follows the Go server rules, or when creating an `internal/modules/{domain}/` package tree with its aggregate, use cases and adapters.
---

# Scaffolding Go modules

The structure and conventions live in the Go rules (`rules/go/*.md`, `rules/go-server/*.md`), which load as you touch the matching files. Read `rules/go-server/architecture.md`, `domain.md`, `application.md` and `adapters.md` before step 3, and the database rules (`rules/database/conventions.md`, `postgres.md`, `sqlc.md`) before step 3.10. `example-module.md` in this folder is one complete module to copy from.

The rule files named here are in the project's `.claude/rules/{area}/` (`rules/frontend/testing.md` is `.claude/rules/frontend/testing.md`). When the project lacks one, read the copy that ships with this skill, in the `rules/` folder two levels above this skill's folder, and say in your report that the project does not have it; the `installing-rules` skill copies it in.

## Steps

1. **Inputs.** Collect, from the spec or the user:
   - the module name (one lowercase word, the package name of its root) and its aggregate root: fields, which are value objects, and the value lists (statuses, reasons)
   - the invariants: what must hold when the aggregate is created and at each state change
   - each operation: whether it writes or reads, its input and its result, and the errors it can return (with the kind of each)
   - what it needs from outside: another module (and which public use case of it), a technical capability, a setting
   - the HTTP routes, if the module is exposed, and who may call each one (public, a role, any authenticated user)

   Done when every operation has an input, a result (or none) and its errors, every outside need names the port it becomes, and every route names who may call it.

2. **Shared pieces.** Check that what the module will import exists: `internal/shared/domainerr`, `ids` and `page`; `internal/common/apiresponse` with `Install` called in `app.New`; `internal/common/middleware`, with `api.UseMiddleware(middleware.Auth(…))` and `middleware.Unmatched` wired in `app.New` (without the auth middleware every route is open and `middleware.Public` means nothing); `internal/infrastructure/database` (`DB`, `Conn`, `Run`, `IsUniqueViolation`) and `dbtest`; `sqlc.yaml` with `omit_unused_structs` and `tools/go.mod` with sqlc, goose and govulncheck; `internal/archtest`. If one is missing, stop and report it; adding it is a separate change.

3. **Files**, in this order, so each file's imports already exist when you write it:
   1. `domain/constants.go`: each value list as a string type, its constants and the slice that lists them
   2. `domain/errors.go`: one `Err{D}{Reason}` per error, `domainerr.New(kind, "{MODULE}_{REASON}")`
   3. `domain/{value}.go`: each value object, with `New{V}`, `Restore{V}` and value receivers
   4. `domain/{d}.go`: the aggregate (unexported fields, `{D}Snapshot`, `Register{D}` or the domain's verb, `Restore{D}`, `Snapshot()`, state changes taking `now`)
   5. `domain/repository.go`: the aggregate root's repository interface
   6. `application/ports.go`: every other outside need, and `TransactionRunner` when a use case makes several writes that must succeed together
   7. `application/{verb}_{d}.go`: one per operation, with its command or query, its result, the struct, `New…` and `Execute`
   8. `testkit/testkit.go`: `{D}(overrides ...func(*domain.{D}Snapshot))` built through `Restore{D}`
   9. tests: `domain/*_test.go`, `application/fakes_test.go` and one `{verb}_{d}_test.go` per use case, in `package …_test`
   10. the migration (`migrations/{timestamp}_create_{table}.sql`), `queries.sql`, the module's entry in `sqlc.yaml`, then `make generate`
   11. `adapters/out/persistence/mapper.go` and its test (same package), then `{d}_repository.go`; a database test only for what the database decides (`rules/go-server/testing.md`), through `dbtest`
   12. `adapters/out/{target}/`: one per remaining port, each with `var _ application.{Port} = (*{Impl})(nil)`. An adapter for another module holds that module's use case through a small unexported interface, and gets a test when it makes a decision
   13. `adapters/in/httpapi/request.go`, `response.go`, then `handler.go` with `Register(api)`
   14. `{d}.go` in the module root: type aliases and error variables for what other modules use (leave the file out when nothing is public)
   15. `internal/app/{d}.go`: builds the repository, adapters, use cases and handler

   Done when every file in the list exists and `go build ./...` passes.

4. **Register.** In `app.New`, build the module and call its handler's `Register(api)`. For each module the new one calls, check that its root package re-exports what the adapter needs: the use case, its query and result types, the value lists the result uses, the errors it returns. Add what is missing to that module's root package and name each addition in your report. Done when the routes are registered and every adapter compiles against the other modules' root packages only.

5. **Verify.** Run `make generate` (no diff beyond the new module's code), `make lint`, `make test` with `TEST_DATABASE_URL` set when a database is available (migrations applied with goose first), `go test ./internal/archtest/`, and `make vuln`. huma checks route registrations only when the server starts, so start it (`make run`) and call each new route once, with and without a token. Done when every check passes and every new route answers as its operation says, and your report names each check that could not run and why.

## Common mistakes

| Mistake | Fix |
|---|---|
| A use case returns `*domain.User` | Return a plain result built from `Snapshot()` |
| A handler checks the error to pick a status | Return the use case's error unchanged; the huma error override maps it |
| A use case imports another module | Declare a port in `application/ports.go` and implement it in `adapters/out/{module}/` |
| `Restore{D}` calls `New{V}` | Use `Restore{V}`; stored values are trusted, or a tightened rule breaks old rows |
| The domain calls `time.Now()` | Take `now time.Time`; the use case gets a clock in its constructor |
| The handler passes the request struct to the use case | Pick each field the command needs |
| A request body struct without `_ struct{} \`additionalProperties:"true"\`` | Add it; huma rejects unknown fields otherwise |
| An `enum:"…"` tag repeats a domain list | Implement `huma.SchemaProvider` from the domain's slice |
| A repository queries the pool, or the transaction closure's parameter is `txCtx` | Query through `r.db.Conn(ctx)` and name the parameter `ctx` |
| A constructor returns an interface | Return the concrete type; the caller converts |
| The module root builds its adapters | Composition belongs in `internal/app/{d}.go`; the root imports only its application and domain |
| A test makes a "unique" value from the head of a UUIDv7 | The head is a timestamp; take the random tail |
| A handler calls `huma.Error401Unauthorized` or reads the token itself | Read `middleware.PrincipalFrom(ctx)`; a refusal is a domain error from the use case |
| A create route answers 200, or returns the whole resource | `DefaultStatus: http.StatusCreated` and `apiresponse.Created(ctx, id)` |
| An adapter holds another module's use case as a concrete pointer | Declare an unexported interface with the one method it calls |
