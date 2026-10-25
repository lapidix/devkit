---
name: auditing-entity-slices
description: Use when reviewing or checking `entities/` slices against the entity rules, before opening a PR that touches `entities/`, or when asked whether a slice follows the conventions.
---

# Auditing entity slices

Checks slices against the entity rules (`entities.md`, `entity-data-access.md`). Mechanical checks run first; the judgment checks need you to read the code.

The rule files named here are in the project's `.claude/rules/{area}/` (`rules/frontend/testing.md` is `.claude/rules/frontend/testing.md`). When the project lacks one, read the copy that ships with this skill, in the `rules/` folder two levels above this skill's folder, and say in your report that the project does not have it; the `installing-rules` skill copies it in.

## Steps

1. **Scope.** The slices named by the user, or every `entities/*/` touched in `git diff --name-only <base>...HEAD`, plus every entity that gained an `@x/` file. Outside a git repo, ask which slices to audit.
2. **Architecture check.** Run the project's dependency-cruiser command. If the project has no architecture check or its config lacks the entity rules, say so in the report; the `setting-up-architecture-checks` skill installs them. The entity rules enforce domain purity, DTO and mapper isolation, `@x` consumers, the public API and test-only testkits.
3. **Grep checks.** Run every command below on every slice in scope. Read each hit: comments, strings and tests can match without being violations.
4. **Judgment checks.** Read the slice and apply every item in the list below.
5. **Report.** Group by slice, one row per violation: `file:line | rule | fix`. A clean slice is reported as clean.

Done when every check has run on every slice in scope and every hit is classified as a violation or a false positive.

## Grep checks

Every command below prints nothing for a slice that follows the rules; each hit is a candidate violation. Errors are discarded because a slice may lack a folder (no `infrastructure/`, no `@x/`), which is not a violation.

```bash
S=src/entities/user     # one slice in scope; repeat per slice

grep -n 'export \*' "$S/index.ts" 2>/dev/null                                  # export * in the public API
grep -nE 'dto|mapper|url\.const|testkit|@x' "$S/index.ts" 2>/dev/null          # internals in the public API
grep -rnE '^(export )?class ' "$S/domain" 2>/dev/null                          # classes in domain (error classes are outside this rule)
grep -nE 'try \{|catch|console\.|toast' "$S"/infrastructure/api/*.adapter.ts 2>/dev/null   # error handling in the adapter
grep -nE 'encodeURIComponent|`/' "$S"/infrastructure/api/*.adapter.ts 2>/dev/null         # paths built in the adapter instead of URLS
grep -nE '\.json[<(]|\.result\b' "$S"/infrastructure/api/*.adapter.ts 2>/dev/null          # a body opened in the adapter; use unwrap
for k in $(grep -hoE "^ *[A-Za-z]+: *'[^']*\{" "$S"/infrastructure/api/*.url.const.ts 2>/dev/null | sed -E 's/^ *([A-Za-z]+):.*/\1/'); do
  grep -nE "URLS\.$k\b" "$S"/infrastructure/api/*.adapter.ts 2>/dev/null | grep -v pathParams
done                                                                            # a template with a placeholder called without pathParams: arthron sends {id} as written
grep -n '\${' "$S"/infrastructure/api/*.url.const.ts 2>/dev/null               # interpolation in URL templates; use {param}
grep -nE "id: .*\?\? ['\"]" "$S"/infrastructure/mapper/*.ts 2>/dev/null        # fabricated ids; use required()
grep -rnE '(Adapter|Service)Type\b' "$S" 2>/dev/null                           # Type suffix on factory types
grep -rn 'Omit<' "$S/@x" 2>/dev/null                                           # Omit in cross-entity APIs; use Pick

# Whole app, once
grep -rnE "\.dto['\"]" --include='*.ts' --include='*.tsx' src | grep -v '/infrastructure/'   # DTOs used outside infrastructure
grep -rn '/testkit' --include='*.ts' --include='*.tsx' src | grep -vE '\.test\.tsx?:'        # testkit in production code
grep -rnE 'queryKey: \[' --include='*.ts' --include='*.tsx' src                               # inline query keys
grep -rnE "from ['\"]arthron" --include='*.ts' --include='*.tsx' src | grep -v '/shared/libs/http/'   # arthron imported outside shared/libs/http
```

## Judgment checks

- Each slice is an entity: it has an id and the app tracks its changes. Things only displayed inside another entity are reference types, not slices.
- Behavior functions in `domain/` use only the entity and their arguments: no React, I/O or translation.
- Each value object has a validation rule. Standard rules live in `shared/vo/`, product rules in the owning entity.
- DTO types match the API contract: fields the server guarantees are required.
- Adapter outputs are entities, `PageResult<Entity>`, `Pick<Entity, 'id'>` from a create, or `void`.
- The adapter test checks the URL of each method whose template has a placeholder.
- The mapper guards essential fields with `required()`, keeps optional fields as `null` unless "absent" equals "empty", converts instants to epoch milliseconds, and produces no display strings.
- Query keys include every input that changes the response, scope headers included.
- Each `@x/{consumer}.ts` is imported only by that consumer, exports only types, value objects, unions and pure functions, and re-exports shapes shared by several consumers from the owner's `domain/`.
- Components in `ui/` take everything through props: no data hooks, mutations or stores.
