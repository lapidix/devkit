---
paths:
  - "**/entities/**/infrastructure/**"
  - "**/libs/db/**"
  - "**/features/sync/**"
---

# Local data

An app that keeps its data on the device (SQLite on a phone, a desktop shell or the browser) reads and writes it through adapters, like an API. `rules/frontend/entity-data-access.md` holds for these adapters too; this file says what differs.

## Structure

```
entities/{domain}/infrastructure/
├── api/{d}.adapter.ts            the server, when the entity has one
├── db/
│   ├── {d}.adapter.ts            create{D}LocalAdapter + the {D}LocalAdapter instance
│   └── {d}.table.ts              the table, when the ORM defines it in code
└── mapper/{d}.mapper.ts          rows and DTOs to entities
shared/libs/db/                   the database handle, transactions and migrations
```

- The database handle lives in `shared/libs/db` and is the only code that opens the database. With Drizzle, generating and bundling its migrations is in `rules/database/drizzle.md` ("On the device"). A package gets it from the app through a setter (`rules/frontend-native/app.md`) and reads it when a method runs, never at import.
- An entity with both sources has two adapters. Neither knows the other: moving rows between them is a feature (`features/sync`), never an adapter.

## Adapter

```ts
export const createTodoLocalAdapter = (db: Database) => ({
  async getByDate(date: string): Promise<TodoEntity[]> {
    const rows = await db.select().from(todos).where(and(eq(todos.dueDate, date), isNull(todos.deletedAt)));
    return rows.map(TodoMapper.toEntity);
  },
  async create(payload: CreateTodoPayload, id: string, now: number): Promise<Pick<TodoEntity, 'id'>> {
    await db.insert(todos).values(TodoMapper.toRow(payload, id, now));
    return { id };
  },
});
export type TodoLocalAdapter = ReturnType<typeof createTodoLocalAdapter>;
```

- **Domain shapes in, domain shapes out**, as with an API: no row type leaves `infrastructure/`.
- **The mapper converts what differs** between a row and the entity: JSON kept as text, booleans kept as integers, a column the entity does not have. When the ORM's row type already is the entity type, the adapter returns rows as they are and has no mapper.
- **The app creates ids and times.** A row is created offline, so its id is generated on the device (UUIDv7, `rules/database/conventions.md`) and passed in with the time, never read back from the database.
- **Deleting sets `deletedAt`.** A row another device or the server has not seen yet must survive as a tombstone, or the deletion never reaches them.
- **Errors pass through untouched**, as with an API.

## Transactions

Writes that must land together run in one transaction, through the handle the transaction gives its callback:

```ts
await runInTransaction(async (tx) => {
  await createTodoLocalAdapter(tx).markPostponed(id, now);
  await createTodoLocalAdapter(tx).create(payload, newId, now);
});
```

Inside the callback, every read and write goes through `tx`. A call through the shared handle runs outside the transaction, or waits for it to end and never returns.

## React Query over local data

Queries and mutations call the service, which calls the local adapter, as with an API (`rules/frontend/react-query.md`). Two things differ:

- Local reads do not go stale on their own: give them `staleTime: Infinity`, and change them only by invalidating.
- Writes that do not go through `{D}Mutations` (sync applying the server's changes, a background task, a widget's queued action) invalidate the keys they touched through the app's query client when they finish (`getQueryClient().invalidateQueries({ queryKey: TODO_QUERY_KEYS.all() })`). Without it, a screen keeps showing the rows it read before.

## Migrations

- Migrations ship inside the app and run at startup, before any adapter reads. Each one only adds: a column or table removed in the same release breaks the build still installed on another device until it updates.
- Seed rows are inserted by code that checks for them on every start, not by a migration. A migration runs once; a seed missing from that one run never comes back.
