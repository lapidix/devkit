---
paths:
  - "**/prisma/**"
  - "**/migrations/**"
  - "**/adapters/out/persistence/**"
  - "**/infrastructure/database/**"
---

# Database conventions

Rules every database follows, whatever the engine. The engine's own rules are in `rules/database/postgres.md` or `rules/database/mongodb.md`; the data access tool's in its file: `prisma.md` or `mongoose.md` for a NestJS server, `sqlc.md` or `mongo-go-driver.md` for a Go server. The server rules already place the code: repositories and mappers live in the module's `adapters/out/persistence/` (`rules/server/adapters.md`, `rules/go-server/adapters.md`), and transactions open in use cases.

## Engine and tool

- PostgreSQL by default; MongoDB when the project chooses it.
- One data access tool per project: Prisma, Drizzle or Mongoose in a NestJS server; sqlc or the MongoDB driver in a Go server. Nothing in this file depends on which; what does lives in the tool's file.

## Schema files

- The schema lives in the one folder the ORM reads, one file per module: `prisma/schema/{module}.prisma` with Prisma, `src/infrastructure/database/schema/{module}.schema.ts` with Drizzle. A table is defined only in its owning module's file. With sqlc the migrations are the schema (`rules/database/sqlc.md`).
- MongoDB has no shared schema folder: each module's schema sits beside its repository (`rules/database/mongodb.md`).
- A generated Prisma client goes to `src/generated/` and is not committed; CI and the image build generate it. sqlc's generated code is committed, as Go builds expect (`rules/database/sqlc.md`).

## Ids

- The application creates ids before saving; the database never does. The use case calls `newId()` (TypeScript, `src/shared/domain/id.ts`) or `ids.New()` (Go, `internal/shared/ids`) and passes the id to the aggregate's creation function. Tests pass fixed ids.
- Ids are UUIDv7. They sort by creation time, so new rows land at the end of the index instead of on random pages.
- The domain holds ids as strings; the mapper converts the engine's type.

Why the application creates them: the aggregate is complete before it is saved, and the use case can hand its id to other ports in the same transaction.

## Relations

| Between | Rule |
|---|---|
| Tables of the same module | A real reference, with its delete behavior always stated (`rules/database/postgres.md`, `rules/database/mongodb.md`) |
| Tables of different modules | Only the id, no foreign key. A use case checks that it exists through a port |

A repository reads and writes only its own module's tables or collections, and never joins another module's. Another module's data comes through that module's public use case. A module can then change its tables, or move to another database, without breaking the others.

## Standard columns

- Every table has `created_at` and `updated_at`. A table that only grows (history, logs) has `created_at` only.
- `created_at` belongs to the aggregate: its creation function sets it from `now` and the mapper saves it. The ORM fills `updated_at`, or the query does when there is no ORM (`rules/database/sqlc.md`).
- `updated_at` is storage bookkeeping; the domain snapshot leaves it out unless a rule reads it.
- No blanket `deleted_at`. A deletion the business cares about is a domain state with its time (`withdrawn` and `withdrawn_at`); everything else is deleted for real. When a table truly needs soft delete, the filter lives in one place, its repository, because a query that forgets it shows deleted data.

## Time

| Value | Storage | Domain | API |
|---|---|---|---|
| A moment (signed up, paid) | the engine's time type (`rules/database/postgres.md`, `rules/database/mongodb.md`) | `Date`, `time.Time` | UTC ISO 8601 string |
| A calendar date (birthday, settlement day) | the engine's date type, or a `'YYYY-MM-DD'` string | `'YYYY-MM-DD'` | `'YYYY-MM-DD'` |

- A moment is never stored as a string or a number: the database can then neither compare nor compute with it.
- "Today", "this month" and every other day boundary are computed in the service time zone, `SERVICE_TIME_ZONE` (`rules/server/runtime.md`, `rules/go-server/runtime.md`). Servers run in UTC, so a day taken from the server clock turns over at 09:00 in Korea.

## Money

- An integer in the currency's smallest unit, plus the ISO 4217 currency code: 12,000 KRW is `12000` and `'KRW'`; $19.99 is `1999` and `'USD'`.
- Never a floating-point number: `0.1 + 0.2` is `0.30000000000000004`, and the error accumulates.
- The domain and the API hold the amount as an integer: a TypeScript `number`, exact up to `Number.MAX_SAFE_INTEGER` (about 9 × 10^15), or a Go `int64`. Ratios with fractions (exchange rates, interest, tax rates) use the engine's exact decimal type.

## Migrations

- Names are `YYYYMMDDHHMMSS_{verb}_{target}`, with the verb one of `create`, `add`, `drop`, `rename`, `change`, `backfill`: `20261019120000_add_users_nickname`.
- A merged migration is never edited; a fix is a new migration. Migrations on an unmerged branch may still be squashed.
- Migrations run once in the deploy pipeline, before the new image: migrate → deploy the image → check health. The application never migrates on boot.
- CI applies every migration to an empty database (`rules/monorepo/ci.md`), so a broken migration fails there first.
- Data changes a schema change needs (a backfill) go in the migration. Seed data does not: seeds are separate scripts, guarded by an explicit confirmation (`SEED_CONFIRM=yes`), with fixed ids, in one transaction, safe to run twice.

### Destructive changes: expand, then contract

During a deploy, and after an image rollback, the old server runs against the new schema. So a release's migrations only add. Removing or changing waits for a later release, once no running server uses the old shape.

| Change | Release 1: expand | Release 2: contract |
|---|---|---|
| Drop a column | The server stops reading and writing it | Drop it |
| Rename a column | Add the new column and backfill it; the server reads and writes the new one | Drop the old one |
| Add a required column | Add it nullable or with a default, and backfill | Make it required |
| Remove an enum value | The server stops writing it; stored rows move to another value | Remove the value |

MongoDB fields follow the same order; while both shapes exist, the server reads both.

### What an agent does

- Writes migration files, and applies them only to its own local database (Docker) to check them.
- Leaves to a person: applying migrations to a shared database (development, staging, production), any command that drops or resets data (`migrate reset`, `db push`, `DROP`), and any connection to a production database.

## Indexes

- An index is created for a query that exists (`WHERE`, `ORDER BY`), when that query is written. Every index slows every write, so none are added in advance. The one exception is a reference inside a module, which always has an index (`rules/database/postgres.md`).
- In a compound index, equality fields come first, then the sort field, then range fields. `WHERE status = 'active' ORDER BY created_at DESC` gets `(status, created_at)`.
- No index is the leading part of another, unique ones included: `(status, created_at)` already serves queries on `status` alone.
- Each index carries a one-line comment naming the query that uses it, so it can be dropped when that query goes.

## List queries

Every list's sort ends with the id: `ORDER BY created_at DESC, id DESC`. Rows that tie on the first key otherwise come back in a different order each time, and paging repeats or skips them. Cursors and page sizes are in `rules/api/contract.md`.

## Tests against a database

These tests exist only for code whose correctness depends on the database (`rules/server/testing.md`, `rules/go-server/testing.md`): constraint violations turned into domain errors, hand-written SQL and aggregation, row locks. A module with plain CRUD has none.

- They run against the same engine and major version as production: Docker locally, a service container in CI. Never SQLite or a mock in its place.
- They connect through `TEST_DATABASE_URL`, never the development database's URL, because they delete rows.
- Without `TEST_DATABASE_URL` they are skipped locally and fail in CI (`CI=true`). A skipped suite is otherwise a green check that tested nothing.
- Each test creates its own rows with fresh ids and reads only within them (that user's list). No test empties a table: test files run in parallel.
