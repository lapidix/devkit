---
name: auditing-go-daemons
description: Use when checking a whole Go daemon codebase against the Go daemon rules — one written before the rules, inherited, or not reviewed in a while — or when asked what it would take to bring a daemon up to the conventions.
---

# Auditing Go daemons

Checks every file of a daemon against `rules/go/*.md` and `rules/go-daemon/*.md`, then orders the fixes. `reviewing-go-daemon-changes` checks a diff before a PR; this skill checks what is already there, so it reports a plan as well as findings.

The rule files named here are in the project's `.claude/rules/{area}/` (`rules/frontend/testing.md` is `.claude/rules/frontend/testing.md`). When the project lacks one, read the copy that ships with this skill, in the `rules/` folder two levels above this skill's folder, and say in your report that the project does not have it; the `installing-rules` skill copies it in.

## Steps

1. **Scope.** The daemon's folder, or the folders the user names. List every Go file outside `gen/`, the `.proto` files, and the `Makefile`, `Dockerfile` and CI workflows:
   ```bash
   FILES=$(git ls-files '*.go' | grep -v '^gen/')
   PROTO_FILES=$(git ls-files '*.proto' 'buf.yaml' 'buf.gen.yaml')
   GEN_FILES=$(git ls-files 'gen/*')
   RELEASE_FILES=$(git ls-files Makefile Dockerfile CHANGELOG.md '.github/workflows/*')
   ```
   Done when the lists are written down with their counts.

2. **Shape.** Compare the tree with `rules/go-daemon/architecture.md` before reading any file: where `main` is, whether `internal/app` composes everything, which folders are jobs and which are connections, and what does not fit either (`utils/`, `infrastructure/client/…` at the root, a package named `monitor` or `agent`). Map each existing folder to where the rule puts it. Done when every folder has a target, or "stays", or "goes" with the reason.

3. **Tools.** Run what exists and record what does not: `make lint` (or `GOOS=linux golangci-lint run` with the configuration in `rules/go/conventions.md`), `go test -race -shuffle=on ./...`, `govulncheck ./...`, and `buf lint` when there is a contract. A missing `Makefile`, `tools/go.mod` or `.golangci.yml` is itself a finding. Done when each tool's result, or its absence, is recorded.

4. **Grep checks.** Run the grep block from step 3 of the `reviewing-go-daemon-changes` skill (in the `skills/` folder beside this one) with the lists from step 1 instead of a diff. Its last two checks compare a diff and say nothing about a whole tree; skip them, and check instead that `make generate` leaves `gen/` unchanged and that `CHANGELOG.md` exists. Classify every hit. Done when every hit is a violation or a false positive.

5. **Judgment checks.** Go through every section of `checklist.md` in `reviewing-go-daemon-changes` for every file it applies to. In code written before the rules, look first for what the greps cannot see: a goroutine whose owner never waits, a client closed while a goroutine still uses it, a connection with no reconnect, a credential sent on every reconnect. Done when every applicable item has been checked for every file.

6. **Plan.** Order the fixes so each step leaves the daemon building and its tests passing:
   1. **Safety**: TLS verification, credentials that leak (inherited by children, logged, reusable), child processes without a deadline or a group. These are wrong today, whatever the structure.
   2. **Lifecycle**: `Start`/`Stop` pairs and stored contexts become `Run(ctx)` under `app.Run`, with goleak in each package's tests. Do one component per step, its test first.
   3. **Connections**: `grpc.NewClient`, heartbeats, backoff, the resume key, the sentinels.
   4. **Structure**: moving packages to the tree from step 2. Moves come after the behavior changes, so each diff is either a move or a change, never both.
   5. **Tooling and release**: `Makefile`, `tools/go.mod`, `.golangci.yml`, `PLATFORMS`, checksums, `CHANGELOG.md`.
   6. **Conventions**: names, error wrapping, comments, log messages.

   Each step names its files, the rules it satisfies, and how to check it is done. Done when every finding belongs to exactly one step.

7. **Report.** Write it in the user's language:
   - a summary: how many files, how many findings per rule file, and the three that matter most
   - the plan from step 6, step by step
   - the findings grouped by file, one row each: `file:line | rule (file and section) | fix | plan step`
   - the tool results, each with its command, and what could not be checked and why

   Done when every file in scope appears in the report, every finding names its rule and its plan step, and nothing in the code has been changed: the audit reports, and the fixes are separate changes.
