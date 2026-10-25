---
name: setting-up-architecture-checks
description: Use when adding or repairing an architecture check — dependency-cruiser (`check:arch`) in a TypeScript frontend, server or monorepo, or the architecture test (`internal/archtest`) in a Go server — when a new package or app is added to a monorepo, or when layer, slice or package boundaries are not enforced by any tool.
---

# Setting up architecture checks

The boundaries come from the frontend layer rules (`rules/frontend/*.md`), the server architecture rules (`rules/server/architecture.md`, `rules/go-server/architecture.md`) and the monorepo rules (`workspace.md`, `tooling.md`). This folder holds the checks that enforce them:

The rule files named here are in the project's `.claude/rules/{area}/` (`rules/frontend/testing.md` is `.claude/rules/frontend/testing.md`). When the project lacks one, read the copy that ships with this skill, in the `rules/` folder two levels above this skill's folder, and say in your report that the project does not have it; the `installing-rules` skill copies it in.

| File | Rules |
|---|---|
| `dependency-cruiser.cjs` | Root config: `no-circular`, `not-to-unresolvable`, and the rule files below |
| `fsd-rules.cjs` | `fsd-layer-direction-*`, `fsd-no-sibling-slice-*`, `fsd-public-api-*` |
| `entity-rules.cjs` | The seven entity rules (`entities.md`) |
| `server-rules.cjs` | The server layer rules: pure domain, application on the domain only, adapters not crossing, modules meeting through `index.ts` |
| `package-rules.cjs` | `pkg-graph-*` from the `ALLOWED` table, `pkg-public-api`, `pkg-no-app` |
| `arch_test.go` | A Go server's nine dependency rules, as a `go test` (section below) |

A Next.js app's route folder at the app root (`apps/web/app/`) sits outside `src/`. It is the top layer, so no direction rule applies to it, and `fsd-public-api-*` still limits it to slice `index.ts` files.

## Steps (TypeScript, dependency-cruiser)

1. **Inputs.** Find out:
   - single app or monorepo; in a monorepo, every directory under `apps/` and `packages/`
   - which kinds of code it holds: frontend apps (FSD layers), a server (`src/modules/`), or both
   - each app's path aliases, from its tsconfig `paths`. A single app uses `@/`. In a monorepo every app has its own (`@web/*`, `@admin/*`), because the check runs once with one tsconfig. If two apps share an alias, stop and report it; renaming the aliases is its own change (`workspace.md`).
   - for each package directory, the package directories it may import (start from the workspace dependencies in its `package.json`, `@repo/ui` → `ui`), and the source file each subpath export points to

   Done when every app has distinct aliases and every package directory has a list of allowed package directories, even an empty one.

2. **Install.** Add `dependency-cruiser` as a root dev dependency, through the catalog when the repo has one. Copy `dependency-cruiser.cjs` to the root as `.dependency-cruiser.cjs`, and the rule files into `.dependency-cruiser/`. Keep the rule sets the repository needs and delete the rest, each with both of its lines (the `require` and the spread in `forbidden`): `fsdRules` and `entityRules` without a frontend, `serverRules` without a server, `packageRules` in a single app, together with the package section.

   Done when `node -e "require('./.dependency-cruiser.cjs')"` runs from the root; in a monorepo it throws `Packages missing from ALLOWED` until step 4.

3. **Resolution.** Create `tsconfig.depcruise.json` at the root. It extends the base the apps' tsconfigs extend, and its `paths` hold every alias of every app, rebased onto the root (`./src/*` in `apps/web` becomes `./apps/web/src/*`):
   ```json
   {
     "extends": "./packages/typescript-config/base.json",
     "compilerOptions": { "paths": { "@web/*": ["./apps/web/src/*"], "@admin/*": ["./apps/admin/src/*"] } }
   }
   ```
   A single app points `tsConfig` in `.dependency-cruiser.cjs` at its own `tsconfig.json` instead.

4. **Package table.** Fill `ALLOWED` in `.dependency-cruiser.cjs`:
   - one key per directory under `packages/`, named by the directory (`ui`), not the package name (`@repo/ui`)
   - its value: the package directories from step 1
   - a one-line comment on each key saying what the package is for; a new arrow is reviewed against it

   Fill `ENTRIES` with a regex for the source file of each subpath export (`'^packages/ui/src/icons/index\\.ts$'`). `src/index.ts` is always allowed; if a package's `.` export points elsewhere, add that file too.

   Done when `node -e "require('./.dependency-cruiser.cjs')"` loads without throwing.

5. **Script.** Add `check:arch` to the root `package.json`: `depcruise apps packages --config .dependency-cruiser.cjs` in a monorepo, `depcruise src --config .dependency-cruiser.cjs` in a single app. Then run the same command in both places (`tooling.md`):
   - pre-commit: a `pnpm check:arch` line in `.husky/pre-commit`
   - CI: its own step, `- run: pnpm check:arch` with `if: ${{ !cancelled() }}` (`ci.md`)

6. **Verify.** Run `pnpm check:arch`. Fix each violation it reports, or list it in your report. Then prove the rules fire: add each temporary file below, run the check, confirm the named rule fails, and delete the file.
   - an `entities` file importing a `features` slice → `fsd-layer-direction-entities`
   - a `features` slice importing another one → `fsd-no-sibling-slice-features`
   - a `pages` file importing a file inside a widget instead of its `index.ts` → `fsd-public-api-widgets`
   - a `features` file importing an entity's `infrastructure/dto/` file → `entity-infrastructure-internals`
   - in a server, a `domain` file importing `@nestjs/common` → `server-domain-is-pure`, and a use case importing another module's `index.ts` → `server-application-no-other-modules`
   - in a monorepo, by relative path, so the import resolves without a workspace dependency:
     - an app importing a package's `src/` file other than its entry → `pkg-public-api`
     - a package importing a package outside its `ALLOWED` list (`../../user/src/index`) → `pkg-graph-*`
     - a package importing an app file → `pkg-no-app`

   Done when the check passes on the real code (or every remaining violation is in your report), each temporary file fails with its named rule, and no temporary file is left.

## Steps (Go server)

dependency-cruiser does not read Go, and golangci-lint's depguard cannot tell a module's own packages from another module's. `arch_test.go` loads every package with `golang.org/x/tools/go/packages` and checks the dependency table of `rules/go-server/architecture.md`, numbered 1 to 9 in its messages, plus the type-level half of rule 3: from its own domain, an inbound adapter uses only value lists.

1. **Install.** Copy `arch_test.go` to `internal/archtest/arch_test.go` and run `go get golang.org/x/tools`. It assumes the layout of `rules/go-server/architecture.md` (`internal/modules/{d}/…`, `internal/app`); if the project's folders differ, adjust `locate` and say so in your report.

2. **Run.** `go test ./internal/archtest/`. It runs with every `go test ./...` from then on, so CI needs no new step. Fix each violation it reports, or list it in your report.

3. **Verify.** Add each temporary file, run the test, confirm the named rule fails, and delete the file:
   - a `domain` file importing `internal/infrastructure/database` → rule 1
   - an `adapters/in/httpapi` file using `domain.ErrUserNotFound` → rule 3
   - another module's `application` file importing `internal/modules/user/adapters/out/persistence` → rule 5
   - the module root (`internal/modules/user/user.go`'s package) importing `adapters/out/persistence` → rule 6
   - a non-test file importing the module's `testkit` → rule 8

   Done when the test passes on the real code (or every remaining violation is in your report), each temporary file fails with its rule, and no temporary file is left.

## Common mistakes

| Mistake | Fix |
|---|---|
| Two apps both map `@/`, so one app's imports resolve into the other's tree | Give each app its own alias; the root check reads one tsconfig |
| A rule regex with an optional group around a repetition (`(\.tsx?)?`) | dependency-cruiser rejects it as unsafe; spell out the alternatives instead |
| Exclude patterns without anchors (`build`) | Anchor to path segments, `(^|/)build(/|$)`; a bare `build` also skips a slice named `pipeline-builder` |
| A package added without an `ALLOWED` entry, silenced by deleting the check | The throw is the point: without an entry, that package can import anything |
| Running the check per app | Paths then start inside each app, so app-to-package deep imports and the package graph go unchecked |
| A Go module wires itself in its root package | The root then imports its adapters, and two modules that call each other form an import cycle; composition belongs in `internal/app` (rule 6) |
