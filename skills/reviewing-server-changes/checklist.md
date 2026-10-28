# Judgment checklist

Apply the sections whose rule files cover the file under review. Each item names its rule file; the rule has the detail and the reason.

## Every TypeScript file (`typescript/conventions.md`)

- File names are `{subject}.{role}.ts` with the role last (`user.prisma.repository.ts`, `identity-hasher.port.ts`, `withdraw.usecase.ts`).
- Contracts a function receives (commands, queries) are `interface`; data shapes (snapshots, results) are `type`.
- Names shared between test files carry `Test`; comments say why, in English.
- In a Nest server, a class injected through a constructor is imported as a value, not with `import type`; the decorator metadata needs it.

## Structure (`architecture.md`)

- The file sits where its job belongs: model in `domain/`, use cases and ports in `application/`, inbound adapters in `adapters/in/`, outbound adapters in `adapters/out/`, domain-free clients in `src/infrastructure/`, framework glue in `src/common/`.
- An adapter that knows the module's data lives in the module; a client that knows no domain lives in `src/infrastructure/`.
- Another module is reached through a port in `application/ports` and an adapter in `adapters/out`, never by injecting its use case into a use case.
- `index.ts` exports the module class, its public use cases, their query and result types and the domain errors they throw; never entities, repositories or adapters.

## Domain (`domain.md`)

- Aggregates are classes with a private constructor, `register` (or the domain's verb) that checks invariants, `fromSnapshot`, `toSnapshot`, and state changes only through methods.
- Snapshots hold primitives; `fromSnapshot` rebuilds value objects with `restore`, never `create`.
- Value objects have `create` (validates) and `restore` (trusts stored values).
- Domain methods take `now: Date`.
- Each error is a `DomainError` subclass named `{D}{Reason}Error` with a `{MODULE}_{REASON}` code and a fitting `kind`.
- Only aggregate roots' repository ports live in `domain/`; value lists live in `{d}.const.ts`.

## Application (`application.md`)

- One use case per operation: `{Verb}{D}UseCase` with one `execute`, its command or query interface and its result type in the same file.
- Ports come in through the constructor; `@Injectable()` is the only framework import.
- The result is a plain type built from the snapshot, never an aggregate or a response DTO.
- No second validation of the command.
- Writes that must succeed together run inside `transaction.run()`; external side effects (notifications, mail, external APIs) run after it.
- Settings arrive as policy ports, never from `ENV` or a config service.

## Adapters (`adapters.md`, `http-api.md`, `api/contract.md`)

- Request DTOs are zod schemas (`{Action}{D}RequestDto` from `{Action}{D}RequestSchema`); the controller picks the fields the command needs.
- Responses come from `{D}ResponseDto.from(result)` built on the use case result; controllers import nothing from the domain except `{d}.const.ts`.
- Controllers make no business decisions, catch no errors and build no standard response.
- Repositories query through the client that joins the open transaction, map rows through the mapper, and turn constraint violations they recognize into domain errors.
- An external HTTP API is called through its arthron client (2.1 or later) in `src/infrastructure/http/`, which sets `timeout()`; the adapter turns only the failures it recognizes into domain results or domain errors and rethrows the rest.
- Routes are protected unless marked `@Public()`; abusable routes have rate limits.

## Database (`database/conventions.md`, the engine's and the ORM's files)

- Names follow the engine: PostgreSQL tables and columns snake_case with plural tables (`@@map`/`@map` in Prisma, the column name as the first argument in Drizzle); MongoDB collections snake_case plural, named explicitly.
- Ids are created by the use case with `newId()`; no `@default` (Prisma) or `.defaultRandom()` (Drizzle) on the id column.
- Types: `uuid` ids, `timestamptz` moments, `date` calendar dates, money as `bigint` with a currency code, `jsonb` only for outside payloads; never a float for money, never a moment stored as a string.
- References inside a module state their delete behavior and have an index; references to another module are ids without a foreign key, and no repository reads another module's tables.
- Every index serves an existing query, carries a comment naming it, and is not the leading part of another index.
- A migration only adds, unless it is release 2 of expand → contract: a new column is nullable or has a default, and becomes required only in release 2. A merged migration is never edited.
- `created_at` comes from the aggregate; the ORM fills only `updated_at` (Mongoose `timestamps: { createdAt: false, updatedAt: true }`; Drizzle `defaultNow().$onUpdate(…)`, with `updatedAt` left out of the mapper's row).
- Drizzle: unique constraints, indexes and foreign keys are named in the `database/postgres.md` shape; a unique violation is read from `DrizzleQueryError`'s `cause`, and its message, which holds the parameters, is not logged; no script runs `drizzle-kit push`.
- MongoDB: every repository query chains `.session(this.txHost.tx)`; reads use `.lean()`.
- Tests against a database exist only for database-specific behavior, use their own fresh ids, and never empty a table.

## Runtime (`runtime.md`)

- Environment values are read only in `env.config.ts`, validated at boot; composition roots import `ENV`.
- Logs go through the logger, carry the `requestId`, and never include bodies or secrets; domain errors are not logged as `error`.

## Tests (`testing.md`)

- Aggregates, value objects, use cases, mappers and the shared HTTP pieces changed in this diff have a test file beside them in the same change.
- Repository tests exist only for database-specific behavior and run against a real database; no test asserts a mocked ORM's arguments.
- Use case tests construct the use case with fake ports typed with `satisfies`; test data comes from the module's testkit; names are English sentences that state the behavior.

## NestJS (`nestjs.md`)

- Modules bind ports with `{ provide: Port, useClass: Adapter }`, fill policies with `useFactory` from `ENV`, and `export` only the use cases other modules call.
- No string or symbol tokens.
