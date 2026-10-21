---
paths:
  - "**/internal/modules/*/domain/**"
  - "**/internal/shared/**"
---

# Go server domain

The domain is plain Go: the standard library and `internal/shared`, nothing else. It holds the aggregates, their value objects and errors, and each aggregate root's repository port. The shapes are the NestJS server's (`rules/server/domain.md`) in Go.

## Aggregates

```go
// internal/modules/user/domain/user.go
type User struct {
	id          string
	nickname    Nickname
	status      UserStatus
	createdAt   time.Time
	withdrawnAt *time.Time
}

type UserSnapshot struct { // what storage reads and writes: exported fields, plain types
	ID          string
	Nickname    string
	Status      UserStatus
	CreatedAt   time.Time
	WithdrawnAt *time.Time
}

func RegisterUser(in RegisterUserInput, now time.Time) (*User, error) {
	nickname, err := NewNickname(in.Nickname)
	if err != nil {
		return nil, err
	}
	return &User{id: in.ID, nickname: nickname, status: UserStatusActive, createdAt: now}, nil
}

func RestoreUser(s UserSnapshot) *User { /* copies the fields, no checks */ }

func (u *User) Snapshot() UserSnapshot { /* copies them back */ }

func (u *User) ID() string { return u.id }

func (u *User) Withdraw(now time.Time) error {
	if u.status == UserStatusWithdrawn {
		return ErrUserAlreadyWithdrawn
	}
	u.status = UserStatusWithdrawn
	u.withdrawnAt = &now
	return nil
}
```

- The fields are unexported, so no other package can fill a `User` by hand. An aggregate is created through `Register{D}`, or the domain's own verb (`PlaceOrder`, `OpenAccount`), which checks the invariants. Storage rebuilds it through `Restore{D}`, without checks, because the data was valid when it was saved, and reads it back through `Snapshot()`. The mapper calls both.
- State changes only through methods, and invariant violations are returned errors.
- Methods take the current time as `now time.Time`; the domain never calls `time.Now()`.
- Getters exist only for values a use case needs for a decision or a port call (`u.ID()`). Results are built from `Snapshot()`.
- Domain events are not used yet. A reaction in another module goes through a port.

## Value objects

```go
// internal/modules/user/domain/nickname.go
type Nickname struct {
	value string
}

func NewNickname(raw string) (Nickname, error) {
	if !nicknamePattern.MatchString(raw) {
		return Nickname{}, ErrUserInvalidNickname
	}
	return Nickname{value: raw}, nil
}

func RestoreNickname(value string) Nickname { return Nickname{value: value} }

func (n Nickname) String() string { return n.value }
```

- A value that needs validation is a struct around its value: `New{V}` validates, `Restore{V}` trusts a stored value, and methods take value receivers. A defined type (`type Nickname string`) would let any package write `Nickname("anything")` without the check.
- Why `Restore` skips the checks: a rule tightened later would otherwise make every row saved under the old rule fail to load.

## Value lists

A list with no validation of its own is a defined string type, its constants and a slice that lists them, in `domain/constants.go`:

```go
type WithdrawalReason string

const (
	WithdrawalReasonMoved     WithdrawalReason = "moved"
	WithdrawalReasonNotUseful WithdrawalReason = "not_useful"
	WithdrawalReasonOther     WithdrawalReason = "other"
)

var WithdrawalReasons = []WithdrawalReason{WithdrawalReasonMoved, WithdrawalReasonNotUseful, WithdrawalReasonOther}
```

These are the only domain identifiers inbound adapters may use: request schemas take their enum values from the slice (`rules/go-server/adapters.md`).

## Repository ports

```go
// internal/modules/user/domain/repository.go
type UserRepository interface {
	FindByID(ctx context.Context, id string) (*User, error) // ErrUserNotFound when absent
	FindPage(ctx context.Context, criteria UserListCriteria) (page.Result[*User], error)
	Save(ctx context.Context, u *User) error
}
```

Only aggregate roots have their repository port here. Everything else a use case needs from outside is a port in `application/ports.go`.

## Errors

```go
// internal/shared/domainerr/domainerr.go
type Kind string

const (
	Invalid      Kind = "invalid"
	Unauthorized Kind = "unauthorized"
	Forbidden    Kind = "forbidden"
	NotFound     Kind = "not_found"
	Conflict     Kind = "conflict"
)

type Error struct {
	Kind Kind
	Code string
}

func New(kind Kind, code string) *Error { return &Error{Kind: kind, Code: code} }

func (e *Error) Error() string { return e.Code }
```

```go
// internal/modules/user/domain/errors.go
var (
	ErrUserNotFound         = domainerr.New(domainerr.NotFound, "USER_NOT_FOUND")
	ErrUserAlreadyWithdrawn = domainerr.New(domainerr.Conflict, "USER_ALREADY_WITHDRAWN")
)
```

- A module's errors are sentinel values named `Err{D}{Reason}`, with the code `{MODULE}_{REASON}` in upper snake case. Clients branch on the code; it reaches them as `errorCode`.
- `Kind` says what went wrong; the HTTP status is chosen from it in one place (`rules/api/contract.md`). Callers test with `errors.Is(err, domain.ErrUserNotFound)`, and the HTTP layer reads `Kind` and `Code` with `errors.As`.
- The package is `domainerr` because `errors` would shadow the standard library.

**Which layer creates which error.** The lowest layer that knows a result is abnormal creates it (`rules/go/conventions.md`):

| Layer | Creates |
|---|---|
| Outbound adapter | the domain meaning of a technical signal: `pgx.ErrNoRows` → `ErrUserNotFound`, a unique violation → `ErrUserNicknameTaken` |
| Domain | invariant violations: `ErrUserAlreadyWithdrawn`, `ErrUserInvalidNickname` |
| Use case | decisions that combine conditions: a taken nickname, another module's state |
| Handler | nothing; the status comes from the error mapping |

## shared

`internal/shared/` holds only what every module's domain may use:

- `domainerr`: the error type above.
- `ids`: `ids.New()` returns a UUIDv7 string (`rules/database/conventions.md`). The use case calls it and passes the id to `Register{D}`, so the domain stays free of id generation and tests pass fixed ids. The package is `ids` because `id` is the usual name of the variable that holds one.
- `page`: `page.Result[T]{Items, Total, Page, PageSize}` for lists, and `page.Map` to convert its items.

It imports no framework, no driver and no module.
