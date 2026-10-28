# Judgment checklist

Apply the sections whose rule files cover the file under review. Each item names its rule file; the rule has the detail and the reason.

## Every Go file (`go/conventions.md`)

- File names are snake_case and name the content, not the role; the package name is the folder name and shadows no standard library package.
- Initialisms are all caps or all lower, the package name is not repeated in its identifiers, getters have no `Get`, interfaces are `-er` or role nouns, receivers are one or two letters and the same on every method.
- Interfaces are declared by the package that uses them, with only the methods it calls. Constructors return concrete types; each implementation has `var _ Port = (*Impl)(nil)`.
- Errors from outside are wrapped with the operation, the subject's id and `%w`; they are logged or returned, never both; nothing returns `(nil, nil)`; `panic`, `log.Fatal` and `os.Exit` appear only in `main`.
- Comments say why, in English; a `//nolint` names its linter and its reason.

## Contexts and goroutines (`go/concurrency.md`, `go-daemon/lifecycle.md`)

- `ctx` is the first parameter of anything that does I/O or blocks, is never stored in a struct, and `context.Background()` appears only in `main` and tests; `context.WithoutCancel` only where work must outlive a cancelled context, with a timeout.
- Every long-running component has one `Run(ctx) error` that returns when its work has stopped: `nil` on cancellation, an error when it cannot go on. No `Start`/`Stop` pairs.
- `app.Run` owns every component under one errgroup, stops the jobs before the connections that carry their results, and closes what `app.New` created after everything using it has returned.
- A periodic job runs once at start, takes its ticks as a channel, never overlaps itself, and logs a failed run instead of returning.
- Work from the server is bounded by a slot count, refused at once with a reason when every slot is busy, answered on every path, and each item recovers its own panic.

## Structure (`go-daemon/architecture.md`)

- The file sits where its job belongs: a job in `internal/{job}/`, a connection in `internal/infrastructure/{target}/`, settings in `internal/config/`, composition only in `internal/app/`.
- A job imports neither a connection nor another job; it declares the interface it sends through. The generated contract is the only vocabulary they share.
- A job package is named for what it does, never `monitor`, `worker` or `service`; one with invariants of its own is split into `domain/` and `application/`, and one without is not.

## Connections (`go-daemon/outbound.md`)

- `grpc.NewClient` with TLS credentials from the configuration; an HTTP client with a timeout and a context on every request.
- The first message identifies the daemon with its id, protocol major and build version; a one-time credential is replaced by a resume key after the first registration; the answer to it has a deadline.
- A refusal (`Unauthenticated`, `PermissionDenied`) ends `Run` with its sentinel instead of a retry.
- The stream has one reader and one writer goroutine under one errgroup; everyone else sends through `Send(ctx, msg)`.
- Heartbeats go both ways, and silence longer than the server timeout ends the session, checked in its own goroutine rather than behind the writer's `Send`; gRPC keepalive, if set, comes with the server's enforcement policy.
- When one of the session's goroutines fails, the stream itself is cancelled (`context.AfterFunc` on the group's context), so a reader blocked in `Recv` or a writer blocked in `Send` returns.
- Reconnects back off exponentially with full jitter, reset after a registered session, and give up after `ORPHAN_AFTER` when the daemon exists only for its server, with the last wait cut at that deadline.

## Child processes (`go-daemon/subprocess.md`)

- `exec.CommandContext` with a deadline, an argument list rather than a built command line, and the one `//nolint:gosec` at the call that runs a variable command.
- `Env` is set explicitly from a fixed base and the request's values; `Dir` is the daemon's work area.
- The command has its own process group, `Cancel` sends SIGTERM to the group, `WaitDelay` bounds the wait, and the group gets SIGKILL after `Run` returns.
- Output is capped while captured, the writer reports every byte as written, and the result says when it was cut.
- A non-zero exit, a timeout, a failure to start and a refusal are each reported as the table in the rule says.

## Runtime (`go-daemon/runtime.md`)

- Only `internal/config` reads the environment; `Load` checks every interval and limit and how they relate; a secret has `unset`.
- Logs go to stderr through the injected logger with `…Context` methods, carry the work item's id, and never include a command's output, its environment or a secret; a command's non-zero exit is not logged as an error.
- The version is logged at startup, sent when registering and printed by `version`; `main` exits 0 only after a clean stop.

## Contract (`go-daemon/contract.md`)

- The change only adds within a major: new fields with new numbers, new messages, new `oneof` members; a removed field's number and name are reserved.
- A breaking change is a new package (`v2`) served beside the old one, with the protocol major in the first message.
- `gen/` changes come from `make generate`, never by hand, and come with the `.proto` change that caused them.

## Release (`go-daemon/release.md`)

- A contract, configuration or behavior change has its `CHANGELOG.md` entry under the version it will ship in, and the version follows the rule's semver table.
- `PLATFORMS` lists where the daemon runs; binaries are static and released with checksums; a consumer pins a version and its checksum.

## Tests (`go-daemon/testing.md`)

- Every package that starts goroutines checks for leaks with goleak; every test that starts `Run` stops it and waits for it in its cleanup.
- Connections are tested against a fake server over `bufconn`; a periodic job through a ticks channel; a runner with real processes.
- Code changed in this diff that makes a decision is tested in the same change, with `t.Run` names that state the behavior in English, `require.Eventually` and `assert.Never` instead of `time.Sleep`.
