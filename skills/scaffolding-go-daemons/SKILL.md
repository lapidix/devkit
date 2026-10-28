---
name: scaffolding-go-daemons
description: Use when creating a new Go daemon — a long-running program with no inbound port that dials out to its server — or when adding a job or a connection to one that follows the Go daemon rules.
---

# Scaffolding Go daemons

The structure and conventions live in the Go rules (`rules/go/*.md`, `rules/go-daemon/*.md`), which load as you touch the matching files. Read `rules/go-daemon/architecture.md`, `lifecycle.md` and `outbound.md` before step 3, `subprocess.md` before a job that starts processes, and `contract.md` before step 3.1. `example-daemon.md` in this folder is one complete daemon to copy from.

The rule files named here are in the project's `.claude/rules/{area}/` (`rules/frontend/testing.md` is `.claude/rules/frontend/testing.md`). When the project lacks one, read the copy that ships with this skill, in the `rules/` folder two levels above this skill's folder, and say in your report that the project does not have it; the `installing-rules` skill copies it in.

## Steps

1. **Inputs.** Collect, from the spec or the user:
   - what the daemon is for, and whether it is useless without its server (it then exits after `ORPHAN_AFTER`) or also works alone (it retries forever)
   - each job: periodic (its interval) or driven by the server (its messages, its result, its concurrency limit), and whether it starts processes
   - each system it talks to: the server (gRPC with a contract, or an HTTP API), and any other (a node's RPC, a chat API)
   - how it proves who it is: a one-time token, a client certificate, an API key
   - where it runs: the platforms, and whether it is its own image or a binary another image copies in

   Done when every job has a trigger, an input and an output, every connection has a transport and a credential, and the platforms are named.

2. **Repository.** For a new daemon: `go.mod` with the `go` line on the newest patch, `tools/go.mod` with govulncheck (and buf, `protoc-gen-go`, `protoc-gen-go-grpc` when there is a contract), `.golangci.yml` from `rules/go/conventions.md`, and the `Makefile` from `rules/go-daemon/release.md` with its `PLATFORMS`. For an existing one, check that these exist; if one is missing, stop and report it, adding it is a separate change. Done when `make lint` and `make test` run, even with nothing to check.

3. **Files**, in this order, so each file's imports already exist when you write it:
   1. the contract, when the server speaks gRPC: `proto/{package}/v1/{package}.proto`, `buf.yaml`, `buf.gen.yaml`, then `make generate` (`rules/go-daemon/contract.md`)
   2. `internal/config/config.go`: every setting with its variable, default and `required`; a secret with `unset`; `Load` checks every interval and limit and how they relate
   3. `internal/libs/logger` and `internal/libs/opinfo`: copy them from the example, then rename `opId` if the server calls its work items something else
   4. `internal/infrastructure/{target}/`: one per connection, with `Dial`, `New`, `Run(ctx)` and a `Send` for the jobs; the stream's one reader and one writer, heartbeats, the backoff loop, and the sentinels `ErrRejected` and `ErrServerGone`
   5. `internal/{job}/`: one per job, each declaring the interface it sends through, with `Run(ctx)`; a periodic job with a `loop(ctx, ticks)`; a job driven by the server with a slot count, a refusal, and a recovered panic per item
   6. tests beside each: `TestMain` with goleak in every package that starts goroutines, a fake server over `bufconn` for each gRPC connection, ticks through a channel, real processes for a runner (`rules/go-daemon/testing.md`)
   7. `internal/app/app.go`: `New` creates the connections and the jobs; `Run` stops the jobs first and the connection last, and closes what `New` created
   8. `main.go`: `os.Exit(run())`, the `version` command, signals, `config.Load`, the logger on stderr, `app.New`, `app.Run`

   Done when every file in the list exists and `go build ./...` passes.

4. **Adding to an existing daemon.** A new job is step 3.5 and 3.6, then one line in `app.New` and one `g.Go` in `app.Run`. A new message is a new field or `oneof` member in the contract (a minor change, `rules/go-daemon/contract.md`), `make generate`, then the job that sends or handles it. A new connection is step 3.4 and its test. Done when the daemon builds and the new piece's tests pass.

5. **Verify.** Run `make generate` (no diff beyond the new code), `make lint` (as the platform the daemon runs on), `make test`, `make vuln`, and `buf breaking --against '.git#branch=main'` when the contract changed. Then run the binary once: `{binary} version` prints the version, and with its variables set against a running server (or with a wrong `SERVER_ADDR`) it logs `started`, then `registered` or `link down`, and stops with code 0 on Ctrl-C. Done when every check passes and the run behaves as described, and your report names each check that could not run and why.

## Common mistakes

| Mistake | Fix |
|---|---|
| `Start()` starts a goroutine and `Stop()` closes a channel | One `Run(ctx) error` that returns when its work has stopped |
| The constructor calls `context.WithCancel(context.Background())` | Take the context in `Run`; `main`'s signal context is the root |
| A job imports the connection's package | Declare a one-method interface in the job; `app` passes the connection in |
| `grpc.Dial(…, grpc.WithBlock())` | `grpc.NewClient`; the session loop handles a server that is not up yet |
| `insecure.NewCredentials()` outside a test | TLS with the server's CA from the configuration |
| Several goroutines call `stream.Send` | One writer goroutine; others send through `Send(ctx, msg)` |
| A deadline on the stream | Heartbeats both ways and a silence timeout |
| Retrying after `Unauthenticated` | Return `ErrRejected`; a refused credential stays refused |
| A loop with `time.Sleep(interval)` | A ticker in `Run`, and a `loop(ctx, ticks)` the test drives |
| Work queued when every slot is busy | Refuse it at once with a reason; the server decides |
| `exec.Command` with no context, no `Env`, no process group | `exec.CommandContext`, an explicit `Env`, `Setpgid`, `Cancel` and `WaitDelay` |
| A capped writer that returns a short count | Return `len(p)`; a short count fails the command with `io.ErrShortWrite` |
| The last results lost at shutdown | Stop the jobs before the connection; send on `context.WithoutCancel` with a timeout |
| Logs on stdout | stderr; stdout is a one-shot command's result |
