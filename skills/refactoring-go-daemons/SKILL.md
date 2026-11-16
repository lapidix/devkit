---
name: refactoring-go-daemons
description: Use when refactoring an existing Go daemon toward the Go daemon rules, or when carrying out the plan of an `auditing-go-daemons` report.
---

# Refactoring Go daemons

Carries out the plan an `auditing-go-daemons` report ends with, one plan step at a time, so the daemon builds and its tests pass after every commit. The audit says what is wrong and in which order to fix it; this skill pins today's behavior with tests, changes the code, and reviews each step with `reviewing-go-daemon-changes`. Both skills are in the `skills/` folder beside this one. A new daemon is `scaffolding-go-daemons`; a Go, tool or dependency upgrade is `upgrading-go-daemons`.

The rule files named here are in the project's `.claude/rules/{area}/` (`rules/frontend/testing.md` is `.claude/rules/frontend/testing.md`). When the project lacks one, read the copy that ships with this skill, in the `rules/` folder two levels above this skill's folder, and say in your report that the project does not have it; the `installing-rules` skill copies it in.

## Steps

1. **Plan step.** Start from an `auditing-go-daemons` report; when the conversation has none, run that skill first. Take the first unfinished step of its plan, or the one the user names, and keep the plan's order. A plan step is one branch and one pull request, so its reviewer reads one kind of change. List the step's findings (the report's rows for that plan step) and the component each belongs to: a job, a connection, `internal/app`, `main.go`. Done when the plan step is named and each of its findings has its file and its component.

2. **Baseline.** On a clean tree at the branch's base, run the checks from step 2 of `reviewing-go-daemon-changes` and `make build`, and record each result, failures included. A daemon written before the rules often has no `Makefile`, or fails lint under the rules' configuration; it runs what it has (`GOOS=linux golangci-lint run`, `go test -race -shuffle=on ./...`, `go build ./...`). Every commit is held to this record: what built and passed still does, and `GOOS=linux golangci-lint run --new-from-rev=HEAD~` reports nothing, so the findings the daemon already has do not stop a commit and a new one does. A failing build or test is fixed first, as its own change: a step cannot show it kept behavior that is already broken. Done when every result is recorded and the build and the tests pass at the base.

3. **Characterization tests.** Before a component's behavior changes, a characterization test pins what it does today: what it sends for a given input, what it returns, when it stops. It is written against the old code, seen passing there under `-race`, and committed on its own as a `test` commit before the change. It uses the package from outside (`package {job}_test`). Its assertions are the behavior; its calls may change later to fit a changed API (`Start` and `Stop` becoming `Run` under a cancel). Where the old code has no seam the rules' tests need (it dials inside its constructor, it sleeps instead of taking ticks), the test reaches it the way it can, a listener on `127.0.0.1:0` or a short real interval, and a later `test` commit replaces it with the test `rules/go-daemon/testing.md` describes once the seam exists. `internal/app` and `main.go` have no tests (`rules/go-daemon/testing.md`); their characterization is a run of the binary as in step 5 of `scaffolding-go-daemons` (`version`, a wrong `SERVER_ADDR`, a SIGTERM and the exit code), recorded before and after. A race the test exposes is fixed first, in its own `fix` commit. A move needs only the tests that exist. Done when every component whose behavior the step changes has a test or a recorded run that passes on the old code.

4. **Change.** One component per commit, in the plan's order, and each commit is a move or a change, never both. A move changes only paths, package clauses and imports, so its diff reads as a rename. Take the shape from the rule each finding cites and from `example-daemon.md` in `scaffolding-go-daemons`, and change the existing code toward it: a component rewritten from the example loses what the old code handled and the example does not. After each commit, run the baseline's checks and the characterization tests. Lint compares each commit with the one before it, never the branch with its base: once a moved file is rewritten, git sees it as deleted and added, and every finding it had shows up as new. A move counts as a rename only with git's rename detection on, its default. A finding on a line the commit rewrote counts as new and is fixed in that commit. The commit's type (`rules/git/commit.md`):
   - `refactor` when no assertion changed
   - `fix` when an assertion changed or the commit closes a Safety finding, which no test may observe (TLS verification, an inherited environment); its body names the behavior that changed and why
   - `chore`, `build` or `ci` for a Tooling finding, by what it touches

   goleak's `VerifyTestMain` checks the whole package, so it goes into a package's `TestMain` with the commit that converts the last component there that starts goroutines (`rules/go-daemon/testing.md`). Done when every finding of the plan step is closed in code or named with the reason it stays, and every commit holds to the baseline with the type above.

5. **Review.** On the plan step's branch, run `reviewing-go-daemon-changes` with its default `BASE`. Each finding it reports is closed by this step, belongs to a later step of the plan, or is new. A characterization test that waits for a seam a later plan step creates belongs to that step. A new finding is fixed in this step. Done when every finding of the review is closed or belongs to a later plan step.

6. **What reaches others.** Some changes reach the server's owners and whoever deploys the daemon: the contract (a resume key, the protocol major in the first message), a new or renamed setting (the server's CA for TLS), what the binary prints or how it exits, and a moved or removed package another repository imports (only `gen/` is public, `rules/go-daemon/contract.md`). Each gets a `CHANGELOG.md` entry and the version `rules/go-daemon/release.md` gives it; a daemon without `CHANGELOG.md` gets the file in this step. A contract change passes `buf breaking` or becomes a new major package (`rules/go-daemon/contract.md`). It ships through the release step of `upgrading-go-daemons`. Done when every such change has its entry and its version, and the report names who must act.

7. **Report.** Write it in the user's language:
   - the plan step, and each commit with its type and the findings it closed: `file:line | rule (file and section) | commit`
   - the characterization tests and recorded runs, and which tests were replaced by the rules' tests
   - the baseline checks from step 2, each with its result before and after
   - the review from step 5, and the findings left for later plan steps
   - what reaches others from step 6, and who must act

   Done when every finding of the plan step is closed or named with the reason it stays, and the next plan step is named.
