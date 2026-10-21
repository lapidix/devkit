---
paths:
  - "**/adapters/out/persistence/**"
  - "**/internal/infrastructure/database/**"
  - "**/migrations/**"
---

# MongoDB from Go

The official driver, `go.mongodb.org/mongo-driver/v2`. The engine's rules are in `rules/database/mongodb.md`; the transaction port is the same as with SQL (`rules/go-server/application.md`).

## Transactions

The session travels in the context, so queries need no session argument:

```go
// internal/infrastructure/database/mongo.go
func (m *Mongo) Run(ctx context.Context, fn func(ctx context.Context) error) error {
	if mongo.SessionFromContext(ctx) != nil {
		return fn(ctx) // join the transaction already open
	}
	sess, err := m.client.StartSession()
	if err != nil {
		return fmt.Errorf("start session: %w", err)
	}
	defer sess.EndSession(ctx)
	_, err = sess.WithTransaction(ctx, func(ctx context.Context) (any, error) {
		return nil, fn(ctx) // every query run with this ctx is inside the transaction
	})
	return err
}
```

- It satisfies every module's `TransactionRunner`, and the use case never knows the engine. The closure parameter is named `ctx` for the same reason as with SQL.
- `WithTransaction` **runs the closure again** after a transient error. A side effect inside it (a mail, an external call) could happen twice, so side effects run after `Run` returns.

## Documents

```go
// adapters/out/persistence/document.go
type userDocument struct {
	ID          bson.Binary `bson:"_id"` // UUID, subtype 4
	Nickname    string      `bson:"nickname"`
	Status      string      `bson:"status"`
	CreatedAt   time.Time   `bson:"createdAt"`
	UpdatedAt   time.Time   `bson:"updatedAt,omitempty"`
	WithdrawnAt *time.Time  `bson:"withdrawnAt,omitempty"`
}
```

- **Every field has a `bson` tag.** Without one the driver lowercases the field name (`CreatedAt` → `createdat`) and the camelCase rule breaks.
- The struct takes the place of a Mongoose schema and never leaves `persistence/`. The mapper converts the id between `bson.Binary{Subtype: bson.TypeBinaryUUID}` and the domain's string.
- There is no schema library to check documents: new values pass through the aggregate and its value objects, and unique indexes reject duplicates. A collection validator (`$jsonSchema`) created by a migration is the project's choice.

## Writes and reads

```go
_, err := r.users.UpdateOne(ctx,
	bson.D{{Key: "_id", Value: doc.ID}},
	bson.D{
		{Key: "$set", Value: bson.D{
			{Key: "nickname", Value: doc.Nickname},
			{Key: "status", Value: doc.Status},
			{Key: "createdAt", Value: doc.CreatedAt}, // the aggregate's
			{Key: "withdrawnAt", Value: doc.WithdrawnAt},
		}},
		{Key: "$currentDate", Value: bson.D{{Key: "updatedAt", Value: true}}},
	},
	options.UpdateOne().SetUpsert(true),
)
if database.IsDuplicateKey(err, "users_nickname_key") {
	return domain.ErrUserNicknameTaken
}
```

- `updatedAt` is set by the database with `$currentDate`; `createdAt` comes from the aggregate.
- `mongo.ErrNoDocuments` becomes the module's not-found error in the repository.
- A duplicate key (code 11000) is recognized by its index name with one helper in `internal/infrastructure/database`, `IsDuplicateKey(err, index)`. Indexes are named explicitly by their migration.

## Migrations

golang-migrate with its MongoDB driver: each migration is a JSON file of database commands, named like the SQL ones (`20261019120000_create_users_indexes.up.json`), and the rules in `rules/database/conventions.md` apply. goose cannot be used: it runs SQL only.
