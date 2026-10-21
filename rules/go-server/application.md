---
paths:
  - "**/internal/modules/*/application/**"
---

# Go server application layer

## Use cases

```go
// internal/modules/user/application/withdraw_user.go
type WithdrawUserCommand struct {
	UserID string
	Reason domain.WithdrawalReason
}

type WithdrawUser struct {
	users       domain.UserRepository
	revoker     AccessRevoker
	transaction TransactionRunner
	now         func() time.Time // app passes time.Now, tests a fixed clock
}

func NewWithdrawUser(users domain.UserRepository, revoker AccessRevoker, transaction TransactionRunner, now func() time.Time) *WithdrawUser {
	return &WithdrawUser{users: users, revoker: revoker, transaction: transaction, now: now}
}

func (uc *WithdrawUser) Execute(ctx context.Context, cmd WithdrawUserCommand) error {
	return uc.transaction.Run(ctx, func(ctx context.Context) error {
		u, err := uc.users.FindByID(ctx, cmd.UserID)
		if err != nil {
			return err
		}
		if err := u.Withdraw(uc.now()); err != nil {
			return err
		}
		if err := uc.users.Save(ctx, u); err != nil {
			return err
		}
		return uc.revoker.RevokeAll(ctx, cmd.UserID) // the auth module's writes join this transaction
	})
}
```

- One operation, one struct with one `Execute(ctx, command or query)`. The name is the operation, `WithdrawUser`, without a `UseCase` suffix: the package and the method already say it.
- The command or query and the result types sit in the same file, `withdraw_user.go`.
- The result is a plain struct built from `Snapshot()`, never a `*domain.User` and never a response type. Handlers and other modules never hold the domain model.
- Dependencies come through the constructor; the package imports its own domain, `internal/shared` and the standard library only.
- The clock is a constructor parameter, `now func() time.Time`, because Go has no default arguments. Domain methods still take `now time.Time`.
- The command arrives already shape-checked by the request schema; the use case does not validate it again. Rules that belong to the domain (the nickname pattern) stay in the domain.
- A condition that depends on another module is checked through a port before the aggregate's method runs; the aggregate checks only its own state.
- Errors are domain errors from the domain or the repository, passed up unchanged (`rules/go-server/domain.md`). A use case never produces an HTTP error.

## Ports

Everything a use case needs from outside, other than an aggregate root's repository, is an interface in `application/ports.go`: another module, a technical capability, transactions.

```go
// internal/modules/user/application/ports.go
type TransactionRunner interface {
	Run(ctx context.Context, fn func(ctx context.Context) error) error
}

type AccessRevoker interface {
	RevokeAll(ctx context.Context, userID string) error
}
```

- Named for what the use case needs, in its own words (`AccessRevoker`, not `AuthClient`).
- Small: only the methods this module calls.

## Transactions

- The use case decides the boundary: a transaction opens only inside `transaction.Run`.
- The open transaction travels in `ctx`, so ports take no transaction argument, and work done through another module's adapter inside `Run` joins the same transaction.
- **The closure's parameter is named `ctx`**, hiding the outer one. With another name (`txCtx`), using the outer `ctx` by mistake runs that query outside the transaction, and nothing reports it.
- A nested `Run` joins the open transaction; there are no savepoints.
- Side effects outside the database (notifications, mail, external APIs) run after `Run` returns. A rolled-back transaction must not have sent anything.
- One implementation, `database.DB` in `internal/infrastructure/database`, satisfies every module's `TransactionRunner`, since Go interfaces need only matching methods (`rules/database/sqlc.md`).

## Policies

A setting a use case needs (a cooldown, a limit) arrives as a value in a constructor parameter, filled by the composition root from the configuration:

```go
type SignUpPolicy struct {
	ResignupCooldown time.Duration
	Location         *time.Location // day boundaries: config.ServiceLocation, from SERVICE_TIME_ZONE
}

func NewSignUp(users domain.UserRepository, policy SignUpPolicy, now func() time.Time) *SignUp
```

Use cases never read configuration themselves (`rules/go-server/runtime.md`); tests pass the values they need. A rule about "today" or "this month" computes the day in `Location`, never in the server's time zone (`rules/database/conventions.md`).
