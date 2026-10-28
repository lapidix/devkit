---
paths:
  - "**/*.go"
---

# Go daemon child processes

A daemon that runs commands — its server's, a script's, a tool's — is responsible for everything they start and everything they can see. This file is how it starts them, gives them an environment, reads their output and stops them.

## Starting

```go
// internal/command/runner.go
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
```

- **`exec.CommandContext` with a deadline, always.** Every command has a timeout, the request's or the configured maximum, whichever is shorter; a command without one outlives the work it was for.
- **An argument list, not a shell string.** The command is `argv`; a shell runs only when the caller asks for one (`["sh", "-c", script]`), so the daemon never builds a command line by concatenation.
- **`gosec` reports G204 on the one call that runs a variable command.** It is the daemon's job, so that call carries the one `//nolint:gosec` with its reason (`rules/go/conventions.md`); a second one elsewhere is a second place commands come from, and gets reviewed as such.
- **Each command gets its own process group** (`Setpgid`), so stopping it reaches every process it started. Killing only the first process leaves its children running, holding the output pipes and the CPU.

## Stopping

- **`Cancel` sends SIGTERM to the whole group** when the context ends, so a command can clean up.
- **`WaitDelay` bounds the wait after that.** When it expires, `Wait` kills the first process and closes the pipes; without it, a grandchild that keeps a pipe open makes `Wait` hang forever.
- **After `Run` returns, the group is sent SIGKILL**, which removes whatever survived SIGTERM. The error is ignored: an empty group is the usual case.
- These calls are Unix-only (`syscall.Kill`, `Setpgid`). A daemon that runs on Linux is linted as Linux, `GOOS=linux golangci-lint run`, so its checks match the build that runs (`rules/go-daemon/release.md`).

## Environment

```go
// internal/command/runner.go
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
```

- **`cmd.Env` is always set.** When it is nil, the child inherits the daemon's whole environment: its server address, its credentials, every variable its supervisor set. The base is fixed in code, the request adds its own values, and nothing else passes.
- **Secrets the daemon itself needs are removed from its environment at startup** (`rules/go-daemon/runtime.md`), so no later change to how a command is started can pass them on. `/proc/{daemon pid}/environ` still shows the environment the process started with, and any process of the same user can read it: a secret that must stay hidden from commands is used once and dead by the time they run (`rules/go-daemon/outbound.md`), or the commands run as another user.
- **The working directory is set** to the daemon's work area, never left as the daemon's own.

## Output

```go
// internal/command/runner.go
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

- **Output is capped while it is captured**, never read whole and cut afterwards: a command that prints forever would exhaust the daemon's memory first.
- **`Write` reports every byte as written**, kept or not. A count shorter than the input makes `Run` return `io.ErrShortWrite` instead of the command's exit status, so the result loses the one thing it was for.
- **The result says it was cut** (`truncated`), so the server does not mistake partial output for the whole.
- Stdout and stderr share one writer when the server wants them interleaved; `exec` then writes from one goroutine at a time, so the writer needs no lock. Separate writers, when the server wants the streams apart, are written concurrently and each needs its own cap.

## Result

| Outcome | Reported as |
|---|---|
| The command ran and exited | `exit_code` from `exec.ExitError.ExitCode()` (0 on success) |
| It was stopped by its deadline | `timed_out` true, `exit_code` -1 |
| It could not start (no such file, not executable) | `error` with the cause, `exit_code` -1 |
| The daemon refused it (every slot busy, an empty argv) | `error` with the reason, `exit_code` -1 |

A non-zero exit is the command's result, not the daemon's failure: it is reported, not logged as an error (`rules/go-daemon/runtime.md`).
