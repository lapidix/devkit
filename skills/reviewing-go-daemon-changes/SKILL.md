---
name: reviewing-go-daemon-changes
description: Use when reviewing changes to a Go daemon against the Go daemon rules, before opening a PR that touches a daemon's Go code, contract or release files, or when asked whether daemon code follows the conventions.
---

# Reviewing Go daemon changes

A convention review: does the changed code follow `rules/go/*.md` and `rules/go-daemon/*.md`? Bugs are another review's job. Mechanical checks run first; the judgment checks in `checklist.md` need you to read the code. A Go server is reviewed with `reviewing-go-changes` instead.

The rule files named here are in the project's `.claude/rules/{area}/` (`rules/frontend/testing.md` is `.claude/rules/frontend/testing.md`). When the project lacks one, read the copy that ships with this skill, in the `rules/` folder two levels above this skill's folder, and say in your report that the project does not have it; the `installing-rules` skill copies it in.

## Steps

1. **Scope.** From the daemon's folder, list the changed files and, for each, the rule files that cover it (each rule's `paths:`).
   ```bash
   BASE=origin/main   # the PR's base; with no remote, the local base branch (main)
   FILES=$(git diff --relative --name-only --diff-filter=ACMR "$BASE"...HEAD -- '*.go' | grep -v '^gen/')
   PROTO_FILES=$(git diff --relative --name-only --diff-filter=ACMR "$BASE"...HEAD -- '*.proto' 'buf.yaml' 'buf.gen.yaml')
   GEN_FILES=$(git diff --relative --name-only --diff-filter=ACMR "$BASE"...HEAD -- 'gen/*')
   RELEASE_FILES=$(git diff --relative --name-only --diff-filter=ACMR "$BASE"...HEAD -- Makefile Dockerfile CHANGELOG.md '.github/workflows/*')
   ```
   `--relative` keeps the paths relative to the daemon's folder in a monorepo. When the user names files or a folder instead, use those. Done when every file in the four lists has its rule files listed.

2. **Tools.** Record each command and its result; a check that cannot run goes in the report with the reason.
   - `make lint`, which runs as the platform the daemon ships for (`GOOS=linux`). golangci-lint already covers formatting, imports, `%v` wrapping, logging calls, contexts stored in structs and interface returns, so the greps below skip those.
   - `make test`, with `-race -shuffle=on`; goleak fails a package that leaves a goroutine behind. List the tests that were skipped (`go test -v ./... 2>&1 | grep -- '--- SKIP'`) and report them under "not checked".
   - `make generate` then `git diff --exit-code`, and `go mod tidy` then `git diff --exit-code` (and the same in `tools/`). Run them on a clean tree and restore it afterwards (`git checkout -- .`).
   - When `PROTO_FILES` is not empty: `go tool -modfile=tools/go.mod buf breaking --against ".git#branch=$BASE"`. A breaking change in a minor release is a finding (`rules/go-daemon/contract.md`).
   - `make vuln`.

3. **Grep checks.** Run every command below. Read each hit: comments, strings and legitimate exceptions can match.

   ```bash
   # g PATTERN [PATH_REGEX]: grep FILES, optionally only paths matching PATH_REGEX; gp: the same, test files left out
   g() { printf '%s\n' "$FILES" | grep -E "${2:-.}" | xargs grep -nE "$1" /dev/null; }
   gp() { printf '%s\n' "$FILES" | grep -v '_test\.go$' | grep -E "${2:-.}" | xargs grep -nE "$1" /dev/null; }

   gp 'func \([a-z]+ \*?[A-Za-z]+\) (Start|Stop)\(\)'                    # a Start/Stop pair instead of Run(ctx) (go-daemon/lifecycle.md)
   gp 'context\.(Background|TODO)\(\)' '(^|/)internal/'                  # a root context below main (go/concurrency.md)
   g '\*context\.Context'                                               # a context passed by pointer (go/concurrency.md)
   gp 'time\.Sleep\('                                                   # sleeping in a loop; use a ticker and a ticks channel (go-daemon/lifecycle.md)
   gp 'grpc\.(Dial|DialContext)\(|grpc\.WithBlock\('                     # the deprecated dial; use grpc.NewClient (go-daemon/outbound.md)
   gp 'insecure\.NewCredentials\(\)|InsecureSkipVerify: *true'           # an unverified connection outside tests (go-daemon/outbound.md)
   gp 'keepalive\.ClientParameters'                                     # client keepalive; the server's EnforcementPolicy must change with it (go-daemon/outbound.md)
   gp 'exec\.Command\('                                                 # a command without a context and deadline (go-daemon/subprocess.md)
   gp 'nolint:gosec'                                                    # each gosec exception: is its reason one a reviewer accepts? (go-daemon/subprocess.md)
   gp 'os\.Getenv\(|os\.LookupEnv\(' | grep -vE '(^|/)internal/config/'   # environment read outside config (go-daemon/runtime.md)
   gp 'os\.Stdout' | grep -v '^main\.go:'                               # logs on stdout; they go to stderr (go-daemon/runtime.md)
   gp 'panic\(|log\.Fatal|os\.Exit\(' '(^|/)internal/'                    # only main panics or exits (go/conventions.md)
   g 'fmt\.Errorf\("failed to'                                           # "failed to" piles up across layers (go/conventions.md)
   g 'mockery|gomock|"github.com/stretchr/testify/mock"' '_test\.go$'    # generated mocks; write fakes by hand (go-daemon/testing.md)
   g 'time\.Sleep\(' '_test\.go$'                                        # sleeping to wait; poll with Eventually (go-daemon/testing.md)
   g 'net\.Listen\(' '_test\.go$'                                        # a real port in a test; use bufconn (go-daemon/testing.md)

   # exec.Cmd values whose Env is never set: the child inherits the daemon's whole environment (go-daemon/subprocess.md)
   printf '%s\n' "$FILES" | grep -v '_test\.go$' | while read -r f; do
     grep -q 'exec\.CommandContext(' "$f" && ! grep -q '\.Env = ' "$f" && echo "$f: a command started without an explicit Env"
     grep -q 'exec\.CommandContext(' "$f" && ! grep -q 'Setpgid' "$f" && echo "$f: a command started without its own process group"
     grep -q 'exec\.CommandContext(' "$f" && ! grep -q 'WaitDelay' "$f" && echo "$f: a command started without WaitDelay"
   done

   # packages that start goroutines without a goleak check; app only wires and has no tests (go-daemon/testing.md)
   printf '%s\n' "$FILES" | grep -v '_test\.go$' | grep -vE '(^|/)internal/app/' | xargs grep -lE 'go func|errgroup|\.Go\(' /dev/null | xargs -n1 dirname | sort -u |
     while read -r d; do grep -qs 'goleak.VerifyTestMain' "$d"/*_test.go || echo "$d: starts goroutines, no goleak check"; done

   # job packages importing a connection or another job; only gen/ and internal/libs/ are allowed (go-daemon/architecture.md)
   printf '%s\n' "$FILES" | grep -E '(^|/)internal/[^/]+/' | grep -vE '(^|/)internal/(app|config|infrastructure|libs)/' |
     xargs grep -nE '^\s+("|[a-z0-9]+ ")[^"]+/internal/' /dev/null | grep -vE '/internal/libs/'

   # the contract changed without regenerating, or gen/ edited by hand (go-daemon/contract.md)
   [ -n "$PROTO_FILES" ] && [ -z "$GEN_FILES" ] && echo "proto changed but no gen file did"
   [ -n "$GEN_FILES" ] && [ -z "$PROTO_FILES" ] && echo "gen changed but no proto did: generated code edited by hand?"

   # a contract or configuration change without a CHANGELOG entry (go-daemon/release.md)
   { [ -n "$PROTO_FILES" ] || printf '%s\n' "$FILES" | grep -q '^internal/config/'; } &&
     ! printf '%s\n' "$RELEASE_FILES" | grep -q 'CHANGELOG.md' && echo "contract or config changed, CHANGELOG.md did not"
   ```

   Done when every command has run and every hit is classified as a violation or a false positive.

4. **Judgment checks.** For each changed file, go through the sections of `checklist.md` for the rule files it is covered by. Done when every applicable item has been checked for every file.

5. **Report.** Write it in the user's language:
   - first, the findings that matter most: goroutines nobody waits for, a connection without TLS or heartbeats, a credential that can be reused or inherited, a child process that escapes its deadline or its group, a breaking contract change in a minor release, missing tests
   - findings grouped by file, one row each: `file:line | rule (file and section) | fix`, ordered within a file from lifecycle and security, through conventions, to wording. One root cause is one row that lists each line it touches, whichever greps and checklist items found it. A file with no findings is listed as clean
   - the tool results from step 2, each with its command
   - what was not checked, and why, including skipped tests

   Done when every file in scope appears in the report and every finding names the rule it breaks.
