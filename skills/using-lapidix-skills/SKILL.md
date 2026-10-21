---
name: using-lapidix-skills
description: Use when starting work in a project built on the lapidix/skills rules, or when unsure which of its rules or skills covers a task.
---

# Using lapidix skills

Rules are the conventions; skills are the procedures. A rule the project installed is in its `.claude/rules/{area}/` and loads on its own when you touch a file its `paths:` match. To read one before that, or one the project lacks, open it there or, when this skill came from the lapidix-skills plugin, at `${CLAUDE_PLUGIN_ROOT}/rules/{area}/`, and say in your report that the project lacks it. A project with no rules yet gets them through `installing-rules`.

## Tasks and skills

| Task | Skill |
|---|---|
| Add a frontend entity slice for an API resource | `scaffolding-entity-slices` |
| Check entity slices against the rules | `auditing-entity-slices` |
| Review frontend changes before a PR | `reviewing-frontend-changes` |
| Add a domain module to a NestJS server | `scaffolding-server-modules` |
| Review NestJS changes before a PR | `reviewing-server-changes` |
| Add a domain module to a Go server | `scaffolding-go-modules` |
| Review Go changes before a PR | `reviewing-go-changes` |
| Install or repair architecture checks | `setting-up-architecture-checks` |
| Copy the rules into a project, or update them | `installing-rules` |
| Open a pull request | `writing-pull-requests` |

A change inside an existing slice or module needs no skill: read the rules for its topics below.

## Topics and rules

**Frontend** (React, Next.js), with `typescript/conventions.md` for names, types and comments:

| Topic | Rule |
|---|---|
| Which layer code belongs in, and each layer's folders and public API | `frontend/app.md`, `frontend/pages.md`, `frontend/widgets.md`, `frontend/features.md`, `frontend/entities.md`, `frontend/shared.md` |
| Calling the API: adapters, URL templates, the HTTP client, DTOs, mappers, time values | `frontend/entity-data-access.md` |
| What the server sends: the standard response, error codes, field errors | `api/contract.md` |
| Use cases, services, query and mutation options, reacting to success and failure | `frontend/features.md`, `frontend/react-query.md` |
| Components, effects, React Compiler, `'use client'` | `frontend/react.md` |
| Forms, validation, a server rejection shown on a field | `frontend/forms-rhf-zod.md` |
| Stores | `frontend/state.md` |
| Translation keys | `frontend/i18n.md` |
| Tokens, Tailwind, date and number formatting | `frontend/styling.md` |
| Tests | `frontend/testing.md` |

**Servers**: `api/contract.md` is the HTTP contract both follow.

| Topic | NestJS | Go |
|---|---|---|
| Module layout, where technical clients go (database, Redis, S3, an external API), dependency direction, calls between modules | `server/architecture.md` | `go-server/architecture.md` |
| Aggregates, value objects, domain errors | `server/domain.md` | `go-server/domain.md` |
| Use cases, ports, transactions | `server/application.md` | `go-server/application.md` |
| Controllers or handlers, request and response DTOs, repositories and mappers, database errors turned into domain errors, external APIs | `server/adapters.md` | `go-server/adapters.md` |
| Response format, statuses, errors, auth, routes | `api/contract.md`, `server/http-api.md` | `api/contract.md`, `go-server/http.md` |
| Config, logging, health, metrics | `server/runtime.md` | `go-server/runtime.md` |
| Tests | `server/testing.md` | `go-server/testing.md` |
| Framework wiring | `server/nestjs.md` | |
| Language conventions | `typescript/conventions.md` | `go/conventions.md`, `go/concurrency.md`, `go/tooling.md` |

**Databases**:

| Topic | Rule |
|---|---|
| Any engine: ids, standard columns, time, money, migrations, indexes, list order, database tests | `database/conventions.md` |
| The engine | `database/postgres.md`, `database/mongodb.md` |
| The tool | `database/prisma.md`, `database/mongoose.md` (NestJS); `database/sqlc.md`, `database/mongo-go-driver.md` (Go) |

**Repository**:

| Topic | Rule |
|---|---|
| pnpm workspace, env files, turbo, Biome, dependency-cruiser, git hooks, CI | `monorepo/workspace.md`, `monorepo/env.md`, `monorepo/tooling.md`, `monorepo/ci.md` |
| Commit messages and pull requests | `git/commit.md`, `git/pull-request.md` |
