# skills

Claude Code rules and skills for building web apps on one architecture: a layered React or Next.js frontend, NestJS or Go servers built domain first around ports and adapters, and one HTTP contract between them.

- **Rules** are the conventions. Each has `paths:` frontmatter, so Claude Code loads it only while it works on matching files: folder structure, naming, errors, transactions, tests.
- **Skills** are the procedures: scaffold a frontend entity or a server module, review a change against the rules, set up architecture checks, write a pull request.

The examples are run, not just written: the frontend slice and the NestJS and Go example modules compile and pass their tests (database tests against PostgreSQL included), and the review and architecture checks were tried against planted violations.

## Install

### Skills: a Claude Code plugin

```
/plugin marketplace add lapidix/skills
/plugin install lapidix-skills@lapidix
```

The skills then work in every project. Claude Code picks one when a task matches its description, or you call it as `/lapidix-skills:<skill>`.

Each commit here is a new version. Update with `claude plugin marketplace update lapidix` and `claude plugin update lapidix-skills@lapidix`, or turn on auto-update under `/plugin` → Marketplaces; it is off by default for marketplaces you add.

### Rules: copied into each project

A plugin cannot carry rules, and Claude Code does not load a path-scoped rule through a symlink that leaves the project, so rules are copied into the project's `.claude/rules/`.

With the plugin installed, ask Claude to install the rules. The `installing-rules` skill reads the project's manifests, picks the areas below, runs `copy-rules.sh` from the plugin and fits the globs. Without the plugin, run the script from a clone:

```bash
git clone https://github.com/lapidix/skills ~/skills
bash ~/skills/scripts/copy-rules.sh ~/work/app typescript frontend api
```

| Project | Copy |
|---|---|
| React or Next.js frontend | `typescript` `frontend`, and `api` in a frontend-only project whose backend follows the contract |
| NestJS server | `typescript` `server` `api` `database/conventions`, an engine and a tool |
| Go server | `go` `go-server` `api` `database/conventions`, an engine and a tool |
| pnpm monorepo | add `monorepo` |

For the database, PostgreSQL is `database/postgres` with `database/prisma` (NestJS) or `database/sqlc` (Go); MongoDB is `database/mongodb` with `database/mongoose` (NestJS) or `database/mongo-go-driver` (Go).

- `copy-rules.sh` takes areas (`frontend`) or single files (`database/postgres`), and names the areas the copied rules cite that the project lacks; copy the ones that apply.
- Run it again after a `git pull`: new files are added, unchanged ones skipped, and files that differ are shown as a diff and left alone (exit code 2) until you pass `--update`, which overwrites them along with any edits made in the project.
- In a monorepo, pass `--prefix <app folder>` for each app a set of areas is for (`--prefix apps/web . frontend`); every `**/` glob goes under that folder, so one app's rules do not load while you work on another. Root areas (`monorepo`, `git`) take no prefix. Rerun with the same flags, and files you have not edited compare as unchanged.
- Each skill reads its rules from the project's `.claude/rules/`. When the project lacks one, a skill from the plugin reads the plugin's copy and says so in its report.

### Git rules: your own machine

`rules/git/` (commit messages and pull requests) has no `paths:`, so it applies in every project. It is opinionated (a fixed commit format, no AI attribution in commits or PRs), so read it before you adopt it. To use it on your machine:

```bash
bash ~/skills/scripts/link-user.sh
```

This links `~/.claude/rules/git` to the clone, so a `git pull` updates it (`CLAUDE_CONFIG_DIR`, if set, replaces `~/.claude`). The `writing-pull-requests` skill follows `rules/git/pull-request.md`.

## What the rules assume

- **Frontend**: React with React Compiler, TanStack Query v5, react-hook-form and zod, Tailwind, Vitest; a SPA or Next.js. Layers `app → pages → widgets → features → entities → shared`, with the domain model in `entities`. HTTP goes through [arthron](https://github.com/lapidix/arthron) 2.
- **NestJS**: modules split into `domain`, `application` and `adapters/{in,out}`; zod DTOs with nestjs-zod; Prisma 7 or Mongoose; transactions through nestjs-cls; pino; Vitest with SWC.
- **Go**: the same module split under `internal/`; net/http with huma; sqlc, pgx and goose, or the MongoDB driver; caarlos0/env; slog; testify; golangci-lint.
- **Both servers** follow one HTTP contract (`rules/api/contract.md`): every response carries `result`, `message`, `timestamp`, `requestId` and `errorCode`; a create answers 201 with `{ id }`; a domain error's kind decides the status.
- **Databases**: UUIDv7 ids created by the application, expand → contract migrations, indexes that follow real queries.
- **Monorepos**: pnpm workspaces, turbo, Biome, dependency-cruiser.
- **Writing**: comments, test names, commit messages and PR bodies are in English; test names state the behavior they check.

## Rules

| File | Covers |
|---|---|
| `git/commit.md` | Commit message format, the 13 types, no AI attribution |
| `git/pull-request.md` | Issue first, branch, title and body template, `--body-file`, merge method |
| `typescript/conventions.md` | tsconfig strictness, names of exported values, interface or type, comments, file names |
| `monorepo/workspace.md` | apps and packages, package names, dependencies and catalogs, shared config, scripts, pinned versions |
| `monorepo/env.md` | Env per app, when a root env is allowed, CI secrets |
| `monorepo/tooling.md` | turbo, Biome, dependency-cruiser, git hooks, knip |
| `monorepo/ci.md` | PR checks, skipping docs-only changes, script injection, actions pinned by SHA |
| `frontend/entities.md` | The entities slice: entities, value objects, reference types, `@x`, ui, index.ts |
| `frontend/entity-data-access.md` | Adapters, URL templates, the HTTP client (arthron, `unwrap`, `apiErrors`) and what it guarantees, DTOs, mappers, time values |
| `frontend/features.md` | The features slice: use cases, service, query and mutation options, hooks, UI boundaries, index.ts |
| `frontend/react-query.md` | Query keys, queryOptions, mutationOptions, the three layers that react to success and failure |
| `frontend/widgets.md` | The data a widget owns, `{kind}/{name}` layout, no hooks of its own, props, index.ts |
| `frontend/pages.md` | Domain folders, route params, prefetching with AsyncBoundary, URL state, names |
| `frontend/app.md` | SPA and Next.js layout, providers, URL-based routes, layouts |
| `frontend/shared.md` | Domain-free shared code, libs (http, client, i18n, router, store, error, boundary), shared errors, env |
| `frontend/react.md` | Component declarations, props, rendering, React Compiler, effects, Next.js `'use client'` |
| `frontend/state.md` | One store tool per project, where domain and shared stores live |
| `frontend/forms-rhf-zod.md` | react-hook-form with zod: form hooks, when to validate, submit buttons, edit forms, server errors on fields |
| `frontend/testing.md` | Vitest, where tests live and how they are named, what to test, fakes, coverage |
| `frontend/i18n.md` | One engine with typed keys, key format, pairing checks, translation rules, keys passed as data |
| `frontend/styling.md` | Tokens, date and number formatters, Tailwind `cn()` |
| `api/contract.md` | The HTTP contract for any server language: standard response, 201 with `{ id }`, lists, pageSize and cursors, the error table (kind → status, `fields: {path, message}`), unknown fields ignored, `/api` paths, auth defaults and baseline defenses, API docs |
| `server/architecture.md` | Hexagonal layout (domain first, adapters in and out), technical clients and adapters, dependency direction, the U-shaped request flow, calls between modules |
| `server/domain.md` | Class aggregates (register, fromSnapshot, toSnapshot, now as an argument), value objects, repository ports, DomainError (kind, code) |
| `server/application.md` | Use case shape, application ports, transactions (TransactionRunner), policy ports |
| `server/adapters.md` | File names, controllers, zod request DTOs, response `from()`, repositories and mappers, translating DB errors, external APIs (an arthron client with a timeout) |
| `server/http-api.md` | The contract in NestJS: `ApiResponse<T>`, interceptor and exception filter, `@Public()` and `@Roles()`, helmet, nestjs-zod docs |
| `server/runtime.md` | Env validated at boot, structured logs and levels, error tracking, health, metrics |
| `server/testing.md` | What a server tests (mappers without a database, repositories only for database-specific behavior), coverage |
| `server/nestjs.md` | Mapping it all to NestJS: module wiring, global setup (pipe, filter, interceptor, guards, cls, pino), Vitest with SWC |
| `database/conventions.md` | Any engine: choosing an engine and ORM, schema files, UUIDv7 ids, relations between modules, standard columns and deletion, time, money, migrations and destructive changes (expand → contract), agent safety, indexes, list ordering, running database tests |
| `database/postgres.md` | snake_case plural names, the type table (uuid, timestamptz, bigint, jsonb …), foreign keys and onDelete, partial indexes, connections and poolers |
| `database/mongodb.md` | Engine rules: collection and field names, the value table, embedding or referencing, replica sets, indexes created by migrations |
| `database/prisma.md` | Prisma 7: layout and the generated client, `@@map`/`@map` and types, the transaction client type, migrations with `migrate diff`, P2002, poolers |
| `database/mongoose.md` | Mongoose: schema files, `timestamps` (updatedAt only), passing sessions, `.lean()`, autoIndex |
| `database/sqlc.md` | sqlc, pgx and goose for Go: layout, `sqlc.yaml` type mapping, committed generated code, `updated_at` set by queries, `Conn` and `Run`, `IsUniqueViolation`, poolers |
| `database/mongo-go-driver.md` | MongoDB Go driver v2: session transactions carried in ctx (and rerun), `bson` tags, `$currentDate`, duplicate-key checks, golang-migrate |
| `go/conventions.md` | gofmt and gci, golangci-lint config, file, package and identifier names, interfaces, constructors and receivers, errors (wrapping, where they are made, nil rules), comments |
| `go/concurrency.md` | context (first argument, never stored, deadlines), goroutine owners and errgroup, lifecycle and shutdown order |
| `go/tooling.md` | Makefile, Go version and `tools/go.mod`, version injection, distroless images, CI steps (govulncheck included) |
| `go-server/architecture.md` | Domain-first `internal/` layout, package names and aliases, dependency direction, the U-shaped request flow, module public APIs and wiring in `internal/app` |
| `go-server/domain.md` | Aggregates with hidden fields (Register, Restore, Snapshot), value objects, value lists, repository ports, `domainerr`, which layer creates an error, `ids` and `page` |
| `go-server/application.md` | Use case structs and `Execute`, clocks, ports, transactions (carried in ctx, the closure parameter named `ctx`), policy values |
| `go-server/adapters.md` | File and type names, huma request structs, SchemaProvider, responses, repositories, mappers and error translation, calling other modules |
| `go-server/http.md` | huma setup (`$schema` and `/schemas` off), `apiresponse`, the error mapping override, middleware order, auth, 404/405, server timeouts |
| `go-server/runtime.md` | caarlos0/env config (the service's `*time.Location` included), slog with a handler that adds requestId and userId, health and metrics, `main` |
| `go-server/testing.md` | testify, `t.Run` names that state the behavior, hand-written fakes, testkits, `dbtest`, `-race -shuffle`, the architecture test |

## Skills

| Skill | Use it to |
|---|---|
| `installing-rules` | Copy the rules a project needs into its `.claude/rules/` and fit their globs, or update them |
| `scaffolding-entity-slices` | Add a frontend entity slice for an API resource |
| `auditing-entity-slices` | Check entity slices against the entity rules |
| `reviewing-frontend-changes` | Review frontend changes against the rules before a PR: conventions, not bugs |
| `scaffolding-server-modules` | Add a domain module to a NestJS server, with a complete example module |
| `reviewing-server-changes` | Review NestJS changes against the rules before a PR |
| `scaffolding-go-modules` | Add a domain module to a Go server, with an example module that builds, lints and passes its tests and the architecture test |
| `reviewing-go-changes` | Review Go changes against the rules before a PR |
| `setting-up-architecture-checks` | Install or repair architecture checks: dependency-cruiser (`check:arch`) for TypeScript apps and monorepos, `internal/archtest` for Go |
| `writing-pull-requests` | Open a pull request, or write its title and body |

## License

[MIT](LICENSE)
