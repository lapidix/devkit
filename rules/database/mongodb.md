---
paths:
  - "**/adapters/out/persistence/**"
  - "**/migrations/**"
  - "**/infrastructure/database/**"
---

# MongoDB

The engine's rules, whatever the language. The engine-independent rules are in `rules/database/conventions.md`; the client's in its file: `rules/database/mongoose.md` for Node, `rules/database/mongo-go-driver.md` for Go.

## Names

- Collections are snake_case plural and always named explicitly; client libraries otherwise derive names such as `usersessions`.
- Fields are camelCase, as in the code and in JSON.
- A module's document shape (a Mongoose schema, a Go struct) sits beside the one repository that uses it, in `adapters/out/persistence/`.

## Documents

| Value | Stored as |
|---|---|
| Id | `_id` as a BSON UUID; the mapper turns it into the domain's string |
| A moment | BSON `Date` |
| A calendar date | a `'YYYY-MM-DD'` string |
| A value list | a string holding the domain's lowercase snake_case value |
| Money | a number for the amount, a string for the currency code |
| An outside payload kept as received | a sub-document, as received |

- Inside a module, a child the aggregate owns, with a bounded count, is embedded (an order's items); anything else is referenced by id. Between modules, only the id. A document is capped at 16 MB, so an array that can grow without limit is never embedded.
- `createdAt` comes from the aggregate; only `updatedAt` is filled by the client or the database (`rules/database/conventions.md`).

## Transactions

- Transactions need a replica set; a standalone server rejects them. Local Docker and CI run a single-node replica set (`--replSet rs0`, then `rs.initiate()` once). Managed services such as Atlas already are one.
- Every query inside a transaction must run on its session. How the session reaches the query depends on the client; a query that misses it runs outside the transaction, and nothing reports it.

## Indexes and migrations

- In production, indexes are created by migrations, never by the application at boot: building an index on a large collection loads the database. A client that builds them at boot in development (Mongoose's `autoIndex`) turns that off in production.
- Migrations are scripts and follow the SQL migration rules (`rules/database/conventions.md`): index builds and data moves, timestamped names, never edited once merged.
- Index names are given explicitly, in the same shape as PostgreSQL constraints (`users_nickname_key`), so duplicate-key errors can be recognized by name.
- A query that reads only some documents gets a partial index (`partialFilterExpression`).
