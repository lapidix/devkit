---
paths:
  - "**/drizzle.config.ts"
  - "**/migrations/**"
  - "**/adapters/out/persistence/**"
  - "**/infrastructure/database/**"
  - "**/libs/db/**"
---

# Drizzle

Drizzle ORM 0.44.4 or later with PostgreSQL through postgres-js, and drizzle-kit 0.31 for migrations; checked with drizzle-orm 0.45.2, drizzle-kit 0.31.10, postgres 3.4.9 and `@nestjs-cls/transactional-adapter-drizzle-orm` 2.0.2. What the columns are is in `rules/database/postgres.md`; this file is how to write it in Drizzle.

## Files

```
drizzle.config.ts                         the schema folder, the migrations folder, the URL the CLI uses
src/infrastructure/database/
├── database.ts                           createDatabase, the Database type, the injection token
└── schema/
    └── user.schema.ts                    one file per module (rules/database/conventions.md)
migrations/                               generated SQL and meta/, committed
```

```ts
// drizzle.config.ts
import { defineConfig } from 'drizzle-kit';

export default defineConfig({
  dialect: 'postgresql',
  schema: './src/infrastructure/database/schema',
  out: './migrations',
  migrations: { prefix: 'timestamp' },
  dbCredentials: { url: process.env.DIRECT_URL ?? '' }, // the CLI migrates; without a pooler, DATABASE_URL
  strict: true,
});
```

```ts
// src/infrastructure/database/database.ts
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';

export function createDatabase(url: string, poolSize: number) {
  return drizzle(postgres(url, { max: poolSize, prepare: false }));
}
export type Database = ReturnType<typeof createDatabase>;

/** The injection token for the Drizzle instance; only the transaction plugin injects it. */
export abstract class DrizzleDatabase {}
```

- Tables and row types are imported from `src/infrastructure/database/schema/` in outbound adapters and `src/infrastructure/` only. The architecture checks reject `drizzle-orm` in the domain, `shared`, `application` and inbound adapters (`setting-up-architecture-checks`).
- The module that provides the database binds `{ provide: DrizzleDatabase, useFactory: () => createDatabase(ENV.DATABASE_URL, ENV.DATABASE_POOL_SIZE) }`. The token is a class, as every token in the server is (`rules/server/nestjs.md`).
- `migrations/` is committed, `meta/` included: drizzle-kit diffs the schema against the last snapshot there, not against a database.

## Transactions

`ClsModule` gets `@nestjs-cls/transactional-adapter-drizzle-orm`, with the `Database` type as its type argument and the token:

```ts
// app.module.ts
new ClsPluginTransactional({
  imports: [/* the module that provides DrizzleDatabase */],
  adapter: new TransactionalAdapterDrizzleOrm<Database>({ drizzleInstanceToken: DrizzleDatabase }),
}),
```

A repository queries through `txHost.tx`, which is the open transaction or the default connection:

```ts
// adapters/out/persistence/user.drizzle.repository.ts
@Injectable()
export class DrizzleUserRepository extends UserRepository {
  constructor(private readonly txHost: TransactionHost<TransactionalAdapterDrizzleOrm<Database>>) { super(); }

  async findById(id: string) {
    const [row] = await this.txHost.tx.select().from(users).where(eq(users.id, id)).limit(1);
    return row ? UserMapper.toDomain(row) : null;
  }

  async save(user: User) {
    const { id, ...fields } = UserMapper.toPersistence(user);
    await this.txHost.tx.insert(users).values({ id, ...fields }).onConflictDoUpdate({ target: users.id, set: fields });
  }
}
```

Without the type argument `txHost.tx` loses the table types, and a query on a column that does not exist still compiles.

## Tables

```ts
// src/infrastructure/database/schema/user.schema.ts
export const userStatus = pgEnum('user_status', ['active', 'withdrawn']);

export const users = pgTable(
  'users',
  {
    id: uuid('id').primaryKey(),
    nickname: text('nickname').notNull(),
    status: userStatus('status').notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow().$onUpdate(() => new Date()),
    withdrawnAt: timestamp('withdrawn_at', { withTimezone: true }),
  },
  (t) => [
    uniqueIndex('users_nickname_key').on(t.nickname),
    index('users_status_created_at_idx').on(t.status, t.createdAt), // admin user list: by status, newest first
  ],
);
```

- Every column names its database column: `timestamp('created_at', …)`. Without the name Drizzle uses the TypeScript key, and `createdAt` becomes `"createdAt"`, which raw SQL has to quote.
- Moments are `timestamp(…, { withTimezone: true })`; without the option the column is `timestamp` without a time zone. Calendar dates are `date(…)`, read as `'YYYY-MM-DD'` strings; outside payloads `jsonb(…)`.
- Money is `bigint(…, { mode: 'bigint' })`, which reads a JavaScript `bigint`. The mapper turns it into a `number` and throws beyond `Number.MAX_SAFE_INTEGER`; `mode: 'number'` converts without that check.
- The primary key has no `.defaultRandom()`: the application creates ids (`rules/database/conventions.md`).
- Every unique constraint, index and foreign key is named, in the shape `rules/database/postgres.md` gives: `uniqueIndex('users_nickname_key')`, `index('users_status_created_at_idx')`, `foreignKey({ name: 'order_items_order_id_fkey', … })`. Drizzle's own names (`users_nickname_unique` from `.unique()`) differ from it.
- Enum values are written as the domain's values, so the mapper passes them through.
- `createdAt` comes from the aggregate; `defaultNow()` on `updatedAt` covers the insert and `$onUpdate` every update.

### updatedAt stays out of the row

The mapper's `toPersistence` returns the row without `updatedAt` (`Omit<typeof users.$inferInsert, 'updatedAt'>`). `$onUpdate` fills a column only when the update leaves it out: a `set` that carries the row's old `updatedAt` writes that value back, and `updated_at` stops moving with no error.

## Migrations

An agent never runs `drizzle-kit push`: it changes the database to match the schema with no migration file, dropping what the schema lost. It generates the migration file instead:

```bash
DIRECT_URL=<the local database> pnpm drizzle-kit generate --name add_users_nickname
DIRECT_URL=<the local database> pnpm drizzle-kit migrate   # the local database only
```

- `migrations.prefix: 'timestamp'` with `--name` writes `20261019120000_add_users_nickname.sql`, the name `rules/database/conventions.md` asks for. Without the prefix drizzle-kit writes `0000_` and two random words.
- `generate` reads no database; it diffs the schema against `migrations/meta/`.
- A renamed or removed column makes `generate` ask whether it was renamed, and without a terminal it stops with "Interactive prompts require a TTY terminal". Both changes go through expand → contract (`rules/database/conventions.md`): the expand release only adds, which `generate` writes without asking.
- A backfill or other hand-written SQL is `generate --custom --name backfill_users_points`, which writes an empty file in the journal to fill in.
- Read the generated SQL before committing.
- The deploy pipeline runs `drizzle-kit migrate` with `DIRECT_URL`. It records applied migrations in `drizzle.__drizzle_migrations`.

## Errors

drizzle-orm 0.44.4 and later wrap a failed query in `DrizzleQueryError`, with the driver's error in `cause`; up to 0.44.3 the class does not exist, so a check written for it never matches and every unique violation becomes a 500. A unique violation is a postgres-js `PostgresError` there with `code === '23505'` and the constraint's name in `constraint_name`:

```ts
function isUniqueViolation(error: unknown, constraint: string): boolean {
  return (
    error instanceof DrizzleQueryError &&
    error.cause instanceof postgres.PostgresError &&
    error.cause.code === '23505' &&
    error.cause.constraint_name === constraint
  );
}
```

The repository turns the violations it recognizes into domain errors and rethrows the rest (`rules/server/adapters.md`). A `DrizzleQueryError`'s message holds the query and its parameter values, so it is never logged or returned as it is: a log keeps the constraint name and the code.

## Behind a pooler

postgres-js prepares statements under names by default, which a transaction-mode pooler loses (`rules/database/postgres.md`). `createDatabase` passes `prepare: false`. Behind the pooler a missing `prepare: false` does not always fail: it can return another statement's result.

## On the device

Drizzle also reads and writes an Expo app's SQLite (`rules/frontend/local-data.md`). The tables use `drizzle-orm/sqlite-core` with the same naming rules.

- drizzle-kit runs with `dialect: 'sqlite'` and `driver: 'expo'`, which writes `migrations/migrations.js`. That file imports each `.sql` file and `meta/_journal.json`, so it reaches the app only when Metro resolves `.sql` (`resolver.sourceExts` in `metro.config.js`) and Babel inlines it as text (`babel-plugin-inline-import` for `.sql` in `babel.config.js`). With either missing, the app can start with no migrations and no error.
- After a migration is generated, export the bundle and look for its `CREATE TABLE` (`rules/frontend-native/build.md`).
