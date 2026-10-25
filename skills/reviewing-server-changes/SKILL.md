---
name: reviewing-server-changes
description: Use when reviewing server changes against the server rules, before opening a PR that touches server code, or when asked whether server code follows the conventions.
---

# Reviewing server changes

A convention review: does the changed code follow `rules/server/*.md`, `rules/api/contract.md`, `rules/database/*.md` and `rules/typescript/conventions.md`? Bugs are another review's job. Mechanical checks run first; the judgment checks in `checklist.md` need you to read the code.

The rule files named here are in the project's `.claude/rules/{area}/` (`rules/frontend/testing.md` is `.claude/rules/frontend/testing.md`). When the project lacks one, read the copy that ships with this skill, in the `rules/` folder two levels above this skill's folder, and say in your report that the project does not have it; the `installing-rules` skill copies it in.

## Steps

1. **Scope.** List the changed server files and, for each, the rule files that cover it (each rule's `paths:`).
   ```bash
   BASE=origin/main   # the PR's base; with no remote, the local base branch (main)
   FILES=$(git diff --name-only --diff-filter=ACMR "$BASE"...HEAD -- '*.ts' | grep -E '(^|/)src/')
   DB_FILES=$(git diff --name-only --diff-filter=ACMR "$BASE"...HEAD -- '*.prisma' '*.sql')   # schema and migrations (rules/database/)
   ```
   In a monorepo, keep only the server app's paths. When the user names files or a folder instead, use those. The list is for your own use in step 4. Done when every file in `FILES` and `DB_FILES` has its rule files listed.

   A server rule applies to all server code, even where its `paths:` would not load it while writing (`runtime.md` forbids `console` in a module too).

2. **Tools.** Run the project's `check:arch`, `check-types` and test scripts from `package.json`, and `biome check` on `FILES`. Record each command and its result. A check that cannot run goes in the report with the reason.

3. **Grep checks.** Run every command below. Read each hit: comments, strings and legitimate exceptions can match.

   ```bash
   # g PATTERN [PATH_REGEX]: grep FILES, optionally only paths matching PATH_REGEX
   g() { printf '%s\n' "$FILES" | grep -E "${2:-.}" | xargs grep -nE "$1" /dev/null; }

   g '\b[A-Z][A-Za-z]*Exception\b' '/modules/[^/]+/(domain|application)/'   # HTTP exceptions in the core; throw a DomainError (application.md)
   g 'throw new Error\(' '/modules/[^/]+/(domain|application)/'            # a plain Error in the core; throw a DomainError (domain.md)
   g 'new Date\(' '/modules/[^/]+/domain/'                                  # the domain takes now as an argument; a test fixing its now is fine (domain.md)
   g 'new Date\(' '/modules/[^/]+/application/'                             # only execute's default now and tests fixing a now are fine (application.md)
   g 'try *\{|catch *\(' '/adapters/in/'                                     # controllers leave errors to the exception filter (http-api.md)
   g '\.\.\.(body|dto|params|query)\b' '/adapters/in/'                      # a request DTO spread into a command (adapters.md)
   g '@Res\(' '/adapters/in/'                                                # a handwritten response bypasses the standard response (http-api.md)
   g "@Inject\( *['\"]" '\.ts$'                                              # string tokens; ports are abstract classes (nestjs.md)
   g 'ConfigService|envFilePath' '\.ts$'                                     # configuration comes from ENV, not a config module (runtime.md)
   g 'console\.(log|info|warn|error|debug)\(' '\.ts$'                         # console instead of the logger (runtime.md)
   g '(log|logger)\.[a-z]+\(.*(password|token|secret)' '\.ts$'                # a secret passed to the logger (runtime.md)
   g 'toHaveBeenCalledWith' '/adapters/out/persistence/.*\.test\.ts$'        # asserting a mocked ORM's arguments (testing.md)
   g 'as unknown as' '\.test\.ts$'                                           # cast instead of satisfies (testing.md)
   printf '%s\n' "$FILES" | grep '\.test\.ts$' | xargs perl -ne 'print "$ARGV:$.: $_" if /\bit\(\s*['"'"'"][^'"'"'"]*[^\x00-\x7F]/; close ARGV if eof' /dev/null   # a test name not in English (testing.md)
   g 'export \*' '/modules/[^/]+/index\.ts$'                                 # the public API is an explicit list (architecture.md)
   g "\bfetch\(|from ['\"]axios" '/modules/'                                   # an external API called without its arthron client (adapters.md)
   g "globalThis\.fetch *=|stubGlobal\( *['\"]fetch|spyOn\(globalThis, *['\"]fetch" '\.test\.ts$'   # a stubbed global fetch; pass a fake fetch to the client (testing.md)
   printf '%s\n' "$FILES" | grep -E '(^|/)src/infrastructure/http/[^/]+\.client\.ts$' |
     while read -r f; do grep -q 'timeout(' "$f" || echo "$f: no timeout()"; done   # an external client without a timeout (adapters.md)
   printf '%s\n' "$FILES" | grep -v 'env\.config\.ts$' | xargs grep -nE 'process\.env' /dev/null   # environment read outside env.config.ts (runtime.md)
   printf '%s\n' "$FILES" | grep -E '/adapters/in/' | xargs grep -nE "from ['\"][^'\"]*/domain/" /dev/null | grep -v '\.const['"'"'"]'   # inbound adapters import only {d}.const.ts from the domain (architecture.md)
   g "orderBy: *\{ *[A-Za-z]+: *'(asc|desc)' *\}|\.sort\( *\{ *[A-Za-z]+: *-?1 *\} *\)" '/adapters/out/persistence/'   # a list sorted by one key; end the sort with the id (database/conventions.md)
   printf '%s\n' "$DB_FILES" | grep -E '\.sql$' | xargs grep -niE 'DROP (COLUMN|TABLE)|RENAME|SET NOT NULL|ALTER COLUMN .* TYPE|ADD COLUMN .*NOT NULL' /dev/null   # a destructive change: it must be release 2 of expand → contract, or the new column needs a default (database/conventions.md)

   # changed decision code without a test beside it (testing.md)
   printf '%s\n' "$FILES" | grep -E '\.(usecase|entity|vo|mapper)\.ts$' |
     while read -r f; do [ -f "${f%.ts}.test.ts" ] || echo "$f: no ${f##*/} test"; done

   # modules in scope without an index.ts or a {d}.module.ts (architecture.md, nestjs.md)
   printf '%s\n' "$FILES" | sed -nE 's#^((.*/)?src/modules/[^/]+)/.*#\1#p' | sort -u |
     while read -r d; do
       [ -f "$d/index.ts" ] || echo "$d: no index.ts"
       [ -f "$d/${d##*/}.module.ts" ] || echo "$d: no ${d##*/}.module.ts"
     done
   ```

   Done when every command has run and every hit is classified as a violation or a false positive.

4. **Judgment checks.** For each changed file, go through the sections of `checklist.md` for the rule files it is covered by. Done when every applicable item has been checked for every file.

5. **Report.** Write it in the user's language:
   - first, the findings that matter most: broken boundaries (dependency direction, a use case reaching another module, the domain leaking out), errors and HTTP, transactions, security, missing tests
   - findings grouped by file, one row each: `file:line | rule (file and section) | fix`, ordered within a file from boundaries and security, through conventions, to wording. A grep hit and a checklist item about the same line are one row. A finding about a whole module (a missing `index.ts`) uses the module folder as its location; one that spans files lists each `file:line`. A file with no findings is listed as clean
   - the tool results from step 2, each with its command
   - what was not checked, and why

   Done when every file in scope appears in the report and every finding names the rule it breaks.
