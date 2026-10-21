---
paths:
  - "**/prisma/**"
  - "**/migrations/**"
  - "**/adapters/out/persistence/**"
  - "**/infrastructure/database/**"
---

# PostgreSQL

The engine-independent rules are in `rules/database/conventions.md`; the tool's syntax is in its file (`rules/database/prisma.md`, `rules/database/sqlc.md`).

## Names

- Tables and columns are snake_case. Code stays camelCase; the ORM or the generated code maps between them.
- Tables are plural: `users`, `orders`. `user`, `order` and `group` are reserved words, so singular names would need quoting in every query.
- Plurals follow English (`categories`, `people`); uncountable nouns stay as they are (`news`). A join table is `{singular}_{plural}`: `user_roles`.
- Index and constraint names have the shape Prisma generates by default: `users_nickname_key`, `users_status_created_at_idx`, `order_items_order_id_fkey`. Hand-written SQL, and every migration when there is no ORM, names them the same way.

## Types

| Value | Type | Not |
|---|---|---|
| Id | `uuid` | `text` |
| A moment | `timestamptz` | `timestamp` without a time zone, a string |
| A calendar date | `date` | `timestamptz` at midnight |
| Text | `text`; the value object checks its length (a request schema may repeat it for the documentation) | `varchar(n)`, unless an outside system enforces that length |
| A value list | an enum type whose values are the domain's lowercase snake_case values | upper-case values the mapper has to convert |
| Money | `bigint` for the amount, `text` for the currency code | `integer` (overflows at about 2.1 billion), `real`, `double precision`, `money` |
| A ratio with fractions (exchange rate, interest, tax rate) | `numeric` | `real`, `double precision` |
| An outside payload kept as received | `jsonb` | `json` |

- Enum values are only added. Removing one follows expand → contract (`rules/database/conventions.md`).
- `jsonb` keeps what an outside system sent (a webhook body, a store receipt) for disputes and debugging; the values the code uses (amount, status) are copied into their own columns. A value used in `WHERE` or `ORDER BY` is a column, never a field inside `jsonb`, and "the shape is not settled yet" is not a reason for `jsonb`. When the domain reads a field inside `jsonb`, the mapper validates it while parsing (zod in TypeScript, a typed struct with checks in Go), because the database does not check the shape.

## References inside a module

- A foreign key, with `ON DELETE` always stated: `RESTRICT` by default, `CASCADE` only for children the aggregate owns (an order's items).
- Every foreign key column has an index. PostgreSQL does not create one, and without it deleting the parent or joining scans the whole child table.

## Indexes

- A query that reads only some rows gets a partial index: `CREATE INDEX … WHERE withdrawn_at IS NOT NULL`.
- A unique index over a nullable column allows any number of NULLs. When that is intended, say so in a comment; when only one NULL may exist, add `NULLS NOT DISTINCT` (PostgreSQL 15+).

## Connections

PostgreSQL runs one server process per connection, so connections are capped (`max_connections`, 100 by default).

- The application's pool size comes from the environment (`DATABASE_POOL_SIZE`, `rules/server/runtime.md`, `rules/go-server/runtime.md`). Instances × pool size stays below `max_connections`, leaving room for migrations and admin tools.
- Behind a connection pooler (PgBouncer, Supabase's pooler, RDS Proxy), the application connects through `DATABASE_URL`, the pooler, and migrations through `DIRECT_URL`, the database itself. A migration holds one connection and its locks for its whole run, and a pooler would hand that connection to another client mid-way.
- A pooler in transaction mode gives each transaction whichever server connection is free, so a statement prepared on one connection is missing on the next. The driver must not keep named prepared statements; how depends on the tool (`rules/database/prisma.md`, `rules/database/sqlc.md`).
