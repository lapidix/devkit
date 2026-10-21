---
paths:
  - "**/prisma/**"
  - "**/prisma.config.ts"
  - "**/adapters/out/persistence/**"
  - "**/infrastructure/database/**"
---

# Prisma

Prisma 7 with PostgreSQL. What the columns are is in `rules/database/postgres.md`; this file is how to write it in Prisma.

## Files

```
prisma.config.ts           the schema folder, the migrations folder, the URL the CLI uses
prisma/
├── schema/
│   ├── schema.prisma      generator and datasource only
│   └── user.prisma        one file per module
└── migrations/
src/generated/prisma/      the generated client, not committed
```

```prisma
// prisma/schema/schema.prisma
generator client {
  provider     = "prisma-client"
  output       = "../../src/generated/prisma"
  moduleFormat = "cjs"
}

datasource db {
  provider = "postgresql"
}
```

```ts
// prisma.config.ts
import 'dotenv/config'; // the Prisma 7 CLI does not load .env itself
import { defineConfig, env } from 'prisma/config';

export default defineConfig({
  schema: 'prisma/schema',
  migrations: { path: 'prisma/migrations' },
  datasource: { url: env('DIRECT_URL') }, // the CLI migrates; without a pooler, DATABASE_URL
});
```

- The client and row types are imported from `@/generated/prisma/client`, in outbound adapters and `src/infrastructure/` only. The architecture checks reject the import in the domain, `shared`, `application` and inbound adapters (`setting-up-architecture-checks`).
- `src/generated/` is in `.gitignore`. CI and the Dockerfile run `prisma generate` before type checks and builds. It needs no database, but `env('DIRECT_URL')` must resolve, so they set a placeholder URL.
- `PrismaService` in `src/infrastructure/database/prisma.service.ts` extends the generated `PrismaClient`. The module that provides it builds it with the `@prisma/adapter-pg` driver adapter from `ENV.DATABASE_URL` and `ENV.DATABASE_POOL_SIZE`.

## Transactions

`TransactionalAdapterPrisma` assumes the client comes from `@prisma/client`, which the `prisma-client` generator does not write. So the client type goes in as a type argument wherever a `TransactionHost` is injected, and the plugin gets the client's token:

```ts
// a repository
constructor(private readonly txHost: TransactionHost<TransactionalAdapterPrisma<PrismaService>>) { super(); }

// app.module.ts
new ClsPluginTransactional({
  imports: [/* the module that provides PrismaService */],
  adapter: new TransactionalAdapterPrisma({ prismaInjectionToken: PrismaService }),
}),
```

Without the type argument `txHost.tx` loses the generated types, and a query with a wrong field still compiles.

## Models

```prisma
// prisma/schema/user.prisma
model User {
  id          String     @id @db.Uuid
  nickname    String     @unique
  status      UserStatus
  createdAt   DateTime   @default(now()) @map("created_at") @db.Timestamptz
  updatedAt   DateTime   @updatedAt @map("updated_at") @db.Timestamptz
  withdrawnAt DateTime?  @map("withdrawn_at") @db.Timestamptz

  @@index([status, createdAt]) // admin user list: by status, newest first
  @@map("users")
}

enum UserStatus {
  active
  withdrawn

  @@map("user_status")
}
```

- Every model has `@@map("{table}")`, every enum `@@map("{type}")`, and every multi-word field `@map("{column}")`. Without them Prisma creates `"User"` and `"createdAt"`, which raw SQL has to quote.
- `@id` has no `@default`: the application creates ids (`rules/database/conventions.md`).
- Ids are `@db.Uuid` and moments `@db.Timestamptz`; Prisma's defaults are `text` and `timestamp` without a time zone. Calendar dates are `@db.Date`, money `BigInt`, outside payloads `Json` (stored as `jsonb`).
- Enum values are written as the domain's values, so the mapper passes them through.
- `createdAt` comes from the aggregate (`rules/database/conventions.md`); `@default(now())` only covers rows inserted outside the application, such as hand-written SQL. `@updatedAt` fills `updatedAt`.
- A `BigInt` column comes back as a JavaScript `bigint`, which `JSON.stringify` rejects. The mapper turns it into a `number` and throws when it is beyond `Number.MAX_SAFE_INTEGER`.

## Migrations

An agent never runs `prisma migrate dev` or `prisma migrate reset`: both can wipe the database. It writes the migration file instead, only while `prisma.config.ts` points at its own local database:

```bash
pnpm prisma validate
DIR="prisma/migrations/$(date -u +%Y%m%d%H%M%S)_add_users_nickname"
mkdir -p "$DIR"
pnpm prisma migrate diff --from-config-datasource --to-schema prisma/schema --script > "$DIR/migration.sql"
pnpm prisma migrate deploy   # the local database only
pnpm prisma generate
```

- `--from-config-datasource` compares against the local database, so every earlier migration must already be applied to it.
- Read the generated SQL before committing. A renamed column comes out as a drop and an add, which loses the data; write the expand step by hand (`rules/database/conventions.md`).
- The deploy pipeline runs `prisma migrate deploy`.

## Errors

A unique violation is `Prisma.PrismaClientKnownRequestError` with code `P2002`. The repository turns the violations it recognizes into domain errors and rethrows the rest (`rules/server/adapters.md`).

## Behind a pooler

`@prisma/adapter-pg` sends unnamed statements, which a transaction-mode pooler handles (`rules/database/postgres.md`). Leave its `statementNameGenerator` option unset behind one: named statements are what the pooler loses.
