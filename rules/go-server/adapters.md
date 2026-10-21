---
paths:
  - "**/internal/modules/*/adapters/**"
  - "**/internal/modules/*/*.go"
---

# Go server adapters

Adapters translate between the outside world and the application. Inbound adapters (`adapters/in/`) call use cases; outbound adapters (`adapters/out/`) implement ports.

## File names

| What | File | Type |
|---|---|---|
| HTTP handler | `adapters/in/httpapi/handler.go` | `httpapi.Handler` |
| Requests | `adapters/in/httpapi/request.go` | `WithdrawUserRequest`, `UserListParams` |
| Responses | `adapters/in/httpapi/response.go` | `UserResponse`, `UserSummaryResponse` |
| Repository | `adapters/out/persistence/user_repository.go` | `persistence.UserRepository` |
| Mapper | `adapters/out/persistence/mapper.go` | unexported functions |
| Another outbound adapter | `adapters/out/auth/access_revoker.go` | `auth.AccessRevoker` |

The package names how the port is implemented, so the type keeps the port's name: `persistence.UserRepository`, `auth.AccessRevoker`. Request names match the frontend's request DTOs without the `Dto` suffix (`rules/frontend/entity-data-access.md`); response names match the NestJS server's response DTOs the same way (`rules/server/adapters.md`).

## Inbound: HTTP

```go
// adapters/in/httpapi/request.go
type WithdrawUserRequest struct {
	ID   string `path:"id" format:"uuid"`
	Body struct {
		_      struct{}         `additionalProperties:"true"` // unknown fields are ignored (rules/api/contract.md)
		Reason withdrawalReason `json:"reason"`
	}
}

type UserListParams struct {
	Status   userStatus `query:"status" required:"false"`
	Page     int        `query:"page" default:"1" minimum:"1"`
	PageSize int        `query:"pageSize" default:"20" minimum:"1" maximum:"100"`
}

type withdrawalReason domain.WithdrawalReason

func (withdrawalReason) Schema(huma.Registry) *huma.Schema {
	return &huma.Schema{Type: huma.TypeString, Enum: enumOf(domain.WithdrawalReasons)}
}
```

```go
// adapters/in/httpapi/handler.go
func (h *Handler) withdraw(ctx context.Context, in *WithdrawUserRequest) (*apiresponse.Output[*struct{}], error) {
	err := h.withdrawUser.Execute(ctx, application.WithdrawUserCommand{
		UserID: in.ID,
		Reason: domain.WithdrawalReason(in.Body.Reason),
	})
	if err != nil {
		return nil, err
	}
	return apiresponse.Empty(ctx), nil
}
```

- **One request struct per operation**, holding the path, query and body with huma's tags; huma validates it before the handler runs. Fields are required unless tagged `required:"false"`; JSON names are camelCase.
- **Every body struct carries `_ struct{} \`additionalProperties:"true"\``.** huma rejects unknown fields by default and has no global switch; the contract ignores them. A body without the line fails closed (400), so the omission shows quickly.
- **Value lists come from the domain** through `huma.SchemaProvider`, never written again as an `enum:"…"` tag. From its domain, an inbound adapter uses only value lists: constants, their types and the slices that list them.
- **The handler picks fields** into the command; it never hands the request struct to the use case.
- **Responses** are `{D}Response` with `New{D}Response(result)`, built from the use case result. Times go out as `.UTC()`. A list is never a nil slice, which encodes as `null`; `apiresponse.FromPage` builds its items with `make`.
- **The handler only translates.** No business decisions, no error handling: it returns the use case's error as it is, and the standard response is built in one place (`rules/go-server/http.md`).
- **A handler that needs the signed-in user** reads `middleware.PrincipalFrom(ctx)`; on a route that is not public it is always there. It never builds an HTTP error itself (`huma.Error401Unauthorized` and its siblings lose the `requestId`); a missing permission is a domain error the use case returns.
- **A create** registers with `DefaultStatus: http.StatusCreated` and returns `apiresponse.Created(ctx, id)` (`rules/api/contract.md`).

Other inbound adapters (a scheduled job in `adapters/in/schedule/`) call a use case the same way a handler does.

## Outbound: persistence

```go
// adapters/out/persistence/user_repository.go
type UserRepository struct {
	db *database.DB
}

var _ domain.UserRepository = (*UserRepository)(nil)

func (r *UserRepository) Save(ctx context.Context, u *domain.User) error {
	params, err := toUpsertParams(u)
	if err != nil {
		return err
	}
	err = sqlcgen.New(r.db.Conn(ctx)).UpsertUser(ctx, params)
	if database.IsUniqueViolation(err, "users_nickname_key") {
		return domain.ErrUserNicknameTaken
	}
	if err != nil {
		return fmt.Errorf("save user %s: %w", u.ID(), err)
	}
	return nil
}
```

- **Queries go through `r.db.Conn(ctx)`**, which returns the transaction open in `ctx` or the pool. A query on the pool directly runs outside the open transaction.
- **The mapper keeps rows inside `persistence/`.** `toDomain(row)` rebuilds through `domain.RestoreUser`, and `toUpsertParams(u)` starts from `u.Snapshot()`. No `sqlcgen` type leaves the package.
- **Database errors become domain errors here**: `pgx.ErrNoRows` → `ErrUserNotFound`, a recognized unique violation → its domain error. Anything else is wrapped with the operation and the id, and returned.
- How sqlc, the generated code and the migrations fit together is in `rules/database/sqlc.md`.

## Outbound: other modules and integrations

```go
// adapters/out/auth/access_revoker.go
package auth

import authmodule "example.com/server/internal/modules/auth"

// tokenRevoker is the one method this adapter calls on the auth module, so a test can pass a fake.
type tokenRevoker interface {
	Execute(ctx context.Context, cmd authmodule.RevokeAllTokensCommand) error
}

type AccessRevoker struct {
	revokeAll tokenRevoker
}

var _ application.AccessRevoker = (*AccessRevoker)(nil)

func NewAccessRevoker(revokeAll tokenRevoker) *AccessRevoker {
	return &AccessRevoker{revokeAll: revokeAll}
}

func (a *AccessRevoker) RevokeAll(ctx context.Context, userID string) error {
	return a.revokeAll.Execute(ctx, authmodule.RevokeAllTokensCommand{UserID: userID})
}
```

- An adapter for another module calls that module's public use case from its root package (`rules/go-server/architecture.md`), imported as `{module}module`.
- It holds that use case through a small unexported interface with only the method it calls, declared in the adapter (`rules/go/conventions.md`); `app` passes the real use case, and a test passes a fake.
- An adapter that makes a decision, such as turning another module's not-found into `false`, gets a test.
- An optional integration (payments, maps) whose configuration is absent still lets the server start. Its adapter returns a clear error when called, so only that feature fails.
