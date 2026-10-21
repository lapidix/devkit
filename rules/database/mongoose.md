---
paths:
  - "**/adapters/out/persistence/**"
  - "**/migrations/**"
---

# Mongoose

MongoDB from a NestJS server through Mongoose. The engine's rules are in `rules/database/mongodb.md`.

## Files and schemas

- A module's schema is `adapters/out/persistence/{module}.schema.ts`. Sub-document schemas sit in the same file with `_id: false`.
- The collection is named in the schema options: `{ collection: 'user_sessions' }`.
- The repository is `{module}.mongoose.repository.ts`, class `Mongoose{D}Repository` (`rules/server/adapters.md`).
- Ids are `Schema.Types.UUID`. The Mongoose schema is the check: `required`, `enum`, unique indexes.
- `createdAt` is a required field the mapper writes from the aggregate, and `timestamps: { createdAt: false, updatedAt: true }` fills only `updatedAt`. `timestamps: true` would replace the aggregate's `createdAt` with the current time on an upsert.

## Transactions

- The `TransactionRunner` binding is the same as with SQL (`rules/server/nestjs.md`); `ClsModule` gets the Mongoose adapter, `@nestjs-cls/transactional-adapter-mongoose`.
- Its `txHost.tx` is a session, not a client, so **every query chains `.session(this.txHost.tx)`**. `null`, outside a transaction, is accepted.
- Reads end with `.lean()`: the mapper receives a plain object, which is faster than a Mongoose document, and no document leaves `persistence/`.

```ts
// adapters/out/persistence/user.mongoose.repository.ts
async findById(id: string): Promise<User | null> {
  const doc = await this.users.findById(id).session(this.txHost.tx).lean();
  return doc ? UserMapper.toDomain(doc) : null;
}

async save(user: User): Promise<void> {
  const { _id, ...fields } = UserMapper.toPersistence(user);
  await this.users.updateOne({ _id }, fields, { upsert: true }).session(this.txHost.tx);
}
```

## Indexes and migrations

- Indexes are declared in the schema (`schema.index(...)`, each with its query comment), and production runs with `autoIndex: false`; a migration builds them.
- Migrations are scripts (migrate-mongo or similar).
