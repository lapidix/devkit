---
name: reviewing-go-changes
description: Use when reviewing Go server changes against the Go rules, before opening a PR that touches Go code, or when asked whether Go code follows the conventions.
---

# Reviewing Go changes

A convention review: does the changed code follow `rules/go/*.md`, `rules/go-server/*.md`, `rules/api/contract.md` and `rules/database/*.md`? Bugs are another review's job. Mechanical checks run first; the judgment checks in `checklist.md` need you to read the code.

The rule files named here are in the project's `.claude/rules/{area}/` (`rules/frontend/testing.md` is `.claude/rules/frontend/testing.md`). When the project lacks one and this skill came from the lapidix-skills plugin, read it from `${CLAUDE_PLUGIN_ROOT}/rules/` instead and say in your report that the project does not have it; the `installing-rules` skill copies it in.

## Steps

1. **Scope.** From the Go app's folder, list the changed files and, for each, the rule files that cover it (each rule's `paths:`).
   ```bash
   BASE=origin/main   # the PR's base; with no remote, the local base branch (main)
   FILES=$(git diff --relative --name-only --diff-filter=ACMR "$BASE"...HEAD -- '*.go' | grep -v '/sqlcgen/')
   DB_FILES=$(git diff --relative --name-only --diff-filter=ACMR "$BASE"...HEAD -- '*.sql' '*sqlc.yaml' '*migrations/*.json')
   GEN_FILES=$(git diff --relative --name-only --diff-filter=ACMR "$BASE"...HEAD -- '*sqlcgen/*')
   ```
   `--relative` keeps the paths relative to the app's folder in a monorepo. When the user names files or a folder instead, use those. Of the database rules, apply `conventions.md`, the engine's file and the project's tool file only: `postgres.md` and `sqlc.md`, or `mongodb.md` and `mongo-go-driver.md`. Done when every file in `FILES` and `DB_FILES` has its rule files listed.

2. **Tools.** Record each command and its result; a check that cannot run goes in the report with the reason.
   - `make lint`. golangci-lint already covers formatting, imports, `%v` wrapping, logging calls, contexts stored in structs and interface returns, so the greps below skip those.
   - `make test`, which includes `internal/archtest`, with `TEST_DATABASE_URL` set when a database is available. List the tests that were skipped (`go test -v ./... 2>&1 | grep -- '--- SKIP'`) and report them under "not checked".
   - `make generate` then `git diff --exit-code`, and `go mod tidy` then `git diff --exit-code` (and the same in `tools/`). Run them on a clean tree and restore it afterwards (`git checkout -- .`). A failing `make generate` is itself a finding: the queries and the migrations disagree.
   - `make vuln`.

3. **Grep checks.** Run every command below. Read each hit: comments, strings and legitimate exceptions can match.

   ```bash
   # g PATTERN [PATH_REGEX]: grep FILES, optionally only paths matching PATH_REGEX; gp: the same, test files left out
   g() { printf '%s\n' "$FILES" | grep -E "${2:-.}" | xargs grep -nE "$1" /dev/null; }
   gp() { printf '%s\n' "$FILES" | grep -v '_test\.go$' | grep -E "${2:-.}" | xargs grep -nE "$1" /dev/null; }

   gp 'errors\.New\(|fmt\.Errorf\(' '/modules/[^/]+/domain/'              # an ad-hoc error in the domain; declare an Err{D}{Reason} sentinel (go-server/domain.md)
   gp 'errors\.New\(' '/modules/[^/]+/application/'                      # an ad-hoc error in a use case; return a domain error (go-server/application.md)
   gp 'time\.Now\(' '/modules/[^/]+/(domain|application)/'               # the domain takes now; a use case uses its clock (go-server/application.md)
   g 'errors\.(Is|As)\(|http\.Status' '/adapters/in/'                   # a handler choosing statuses; return the error unchanged (go-server/http.md)
   g 'huma\.Error[0-9]' '/adapters/in/'                                 # an HTTP error built in a handler; it loses the requestId (go-server/http.md)
   g 'go func' '/adapters/in/'                                          # a goroutine started by a handler (go/concurrency.md)
   gp 'context\.(Background|TODO)\(\)' '(^|/)internal/(modules|common|infrastructure)/'   # cancellation cut off mid-request; huma's NewError fallback is the known exception (go/concurrency.md)
   g '\*context\.Context'                                               # a context passed by pointer (go/concurrency.md)
   g 'func \([a-z]+ \*?[A-Za-z]+\) Get[A-Z]'                             # a Get getter; huma's required GetStatus is not one (go/conventions.md)
   g 'type [A-Za-z]+Interface interface|type I[A-Z][A-Za-z]* interface'  # an Interface suffix or I prefix (go/conventions.md)
   gp 'panic\(|log\.Fatal|os\.Exit\(' '(^|/)internal/'                    # only main panics or exits (go/conventions.md)
   g 'fmt\.Errorf\("failed to'                                           # "failed to" piles up across layers (go/conventions.md)
   g 'func\([a-zA-Z_]+ context\.Context\) error' | grep -v 'func(ctx context'   # a transaction closure not named ctx (go-server/application.md)
   g '\.pool\b|pgxpool\.' '/adapters/out/'                               # a repository querying the pool instead of db.Conn(ctx) (database/sqlc.md)
   g 'enum:"' '/adapters/in/'                                           # an enum list repeated in a tag; use the domain's slice (go-server/adapters.md)
   g 'os\.Getenv\(' | grep -vE '(^|/)internal/config/|/dbtest/'           # environment read outside config (go-server/runtime.md)
   g 'mockery|gomock|"github.com/stretchr/testify/mock"' '_test\.go$'    # generated mocks; write fakes by hand (go-server/testing.md)
   g 'time\.Sleep\(' '_test\.go$'                                        # sleeping to wait (go-server/testing.md)
   g 'ids\.New\(\)\[:' '_test\.go$'                                      # the timestamp head of a UUIDv7 used as a unique value (go-server/testing.md)

   # test names not in English (go-server/testing.md)
   printf '%s\n' "$FILES" | grep '_test\.go$' | xargs perl -ne 'print "$ARGV:$.: $_" if /t\.Run\("[^"]*[^\x00-\x7F]/; close ARGV if eof' /dev/null

   # request bodies without the unknown-field line within their first three lines (go-server/adapters.md)
   printf '%s\n' "$FILES" | grep '/adapters/in/' | xargs awk '/Body struct \{/{f=FILENAME; l=FNR; ok=0; for (i = 0; i < 3; i++) if ((getline line) > 0 && line ~ /additionalProperties/) ok=1; if (!ok) print f":"l": body without additionalProperties"}' /dev/null

   # outbound adapters without a compile-time port check (go/conventions.md)
   printf '%s\n' "$FILES" | grep '/adapters/out/' | grep -vE '_test\.go$|mapper\.go$|document\.go$' |
     while read -r f; do grep -q '^var _ ' "$f" || echo "$f: no var _ check, or a type that implements no port and belongs elsewhere"; done

   # decision code changed without a test file beside it; whether the new code is tested is a checklist item (go-server/testing.md)
   printf '%s\n' "$FILES" | grep -E '/modules/[^/]+/(domain|application)/[^/]+\.go$|/persistence/mapper\.go$' | grep -v '_test\.go$' |
     grep -vE '/(constants|errors|ports|repository)\.go$' |
     while read -r f; do [ -f "${f%.go}_test.go" ] || echo "$f: no ${f##*/} test beside it"; done

   # queries changed without regenerating (database/sqlc.md)
   printf '%s\n' "$DB_FILES" | grep -q 'queries\.sql$' && [ -z "$GEN_FILES" ] && echo "queries.sql changed but no sqlcgen file did"

   # destructive migrations: release 2 of expand → contract only, or a new column with a default (database/conventions.md)
   printf '%s\n' "$DB_FILES" | grep -E '\.sql$' | xargs grep -niE 'DROP (COLUMN|TABLE)|RENAME|SET NOT NULL|ALTER COLUMN .* TYPE|ADD COLUMN .*NOT NULL' /dev/null
   printf '%s\n' "$DB_FILES" | grep -E '\.json$' | xargs grep -niE '"(drop|dropIndexes|renameCollection)"|\$unset|\$rename' /dev/null
   # for each hit, grep the column or field in queries.sql, the mapper and the domain: one the code still uses cannot go yet

   # a list sorted by one key; end it with the id (database/conventions.md)
   printf '%s\n' "$DB_FILES" | grep -E 'queries\.sql$' | xargs grep -niE 'ORDER BY [a-z_.]+( (ASC|DESC))?\s*($|LIMIT|OFFSET|;)' /dev/null
   ```

   Done when every command has run and every hit is classified as a violation or a false positive.

4. **Judgment checks.** For each changed file, go through the sections of `checklist.md` for the rule files it is covered by. Done when every applicable item has been checked for every file.

5. **Report.** Write it in the user's language:
   - first, the findings that matter most: broken boundaries (dependency direction, a use case reaching another module, the domain leaking out), errors and HTTP, transactions and contexts, goroutine lifetimes, schema changes the code does not follow, security, missing tests
   - findings grouped by file, one row each: `file:line | rule (file and section) | fix`, ordered within a file from boundaries and security, through conventions, to wording. One root cause is one row that lists each line it touches, whichever greps and checklist items found it. A file with no findings is listed as clean
   - the tool results from step 2, each with its command
   - what was not checked, and why, including skipped tests

   Done when every file in scope appears in the report and every finding names the rule it breaks.
