---
paths:
  - "**/internal/**"
  - "**/main.go"
  - "**/cmd/**"
---

# Go daemon architecture

A daemon is a long-running Go program with no inbound port: it dials out to the systems it serves and does its jobs on a schedule or on their command. A monitoring agent that reports to a central system and a worker inside a VM that runs its server's commands are daemons. It shares `rules/go/` with the Go server, but not its modules, routes or repositories: it has jobs and connections instead.

## Structure

```
main.go                          process concerns only: signals, config, logger, app.New, app.Run, exit code
proto/                           the contract with the server, when the daemon has one (rules/go-daemon/contract.md)
gen/                             code generated from proto/, committed
tools/go.mod                     buf, its plugins, govulncheck (rules/go/tooling.md)
internal/
├── app/                         the only composition root and the lifecycle owner: app.go (New, Run)
├── config/                      env loading (rules/go-daemon/runtime.md)
├── {job}/                       one package per job the daemon does: report/, command/, probe/
├── infrastructure/              one package per system the daemon talks to: link/ (its server), rpc/, telegram/
└── libs/                        domain-free libraries: logger, opinfo
```

- A **job** is something the daemon is for: sending a report every minute, running a command the server sent. Each has a `Run(ctx) error` that returns when the context is cancelled (`rules/go-daemon/lifecycle.md`).
- An **infrastructure** package owns one connection to the outside: it dials, reconnects and moves messages, and knows no job (`rules/go-daemon/outbound.md`).
- A job's package is named for what it does, one lowercase word (`rules/go/conventions.md`). Never `monitor`, `worker` or `service`: they name a role every package has.
- With one binary, `main.go` sits at the root. With several, each gets `cmd/{name}/main.go`.

## Jobs with business rules

Most jobs collect, forward or execute; their package is one flat folder. A job that keeps state with invariants of its own (a queue of retries that must survive a reconnect, a budget it must not exceed) splits into `domain/` and `application/` inside its folder, with the rules of `rules/go-server/domain.md` and `rules/go-server/application.md`, which such a daemon copies in by file. Split when the rules appear, not before: a split with nothing to protect adds files that only forward calls.

## Dependency direction

| From | May import |
|---|---|
| a job | the standard library, `gen/`, `internal/libs` |
| `infrastructure` | the standard library, `gen/`, `internal/libs`, drivers and clients (gRPC, HTTP) |
| `libs` | the standard library only |
| `app` | everything |

- **A job never imports `infrastructure` or another job.** It declares the interface it calls, with only the methods it uses (`rules/go/conventions.md`), and `app` passes the connection in. A test replaces it with a fake, and a second transport does not touch the job.
- **The generated contract (`gen/`) is the vocabulary jobs and connections share.** A job may build and read its messages; it never imports the gRPC client or server code beside them.
- When a connection and a job would need each other (the link delivers commands, the job sends results back), the connection exposes a channel or a method and `app` hands both sides what they need. Neither constructs the other.

```go
// internal/app/app.go — the link hands commands out and takes results back; the runner sees neither side's type
runner: command.NewRunner(l.Commands(), l, command.Config{…}, lg),
```

## How a command flows

```
 [server] RunCommand                                       [server] CommandResult
          │                                                         ▲
 infrastructure/link   the only reader of the stream                │  the only writer of the stream
          │  Commands() channel                                     │  Send(ctx, msg)
          ▼                                                         │
 command.Runner.Run    a free slot, or "busy" right away ───────────┤
          │                                                         │
          ▼                                                         │
 command.Runner.run    process group, explicit env, capped output ──┘
                       (rules/go-daemon/subprocess.md)
```

## A one-shot command

A program that runs one job and exits (convert an address, print a report) uses the same layout without `Run` loops: `main` loads the config, `app.New` builds the job, and `run` calls it once and returns its exit code. Its result goes to stdout and its logs to stderr (`rules/go-daemon/runtime.md`), so the result can be piped. Subcommands, when there are several, use the standard `flag` package per subcommand; a CLI library earns its place only when the commands nest.
