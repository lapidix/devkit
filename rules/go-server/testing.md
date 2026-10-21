---
paths:
  - "**/*_test.go"
  - "**/testkit/**"
  - "**/internal/archtest/**"
  - "**/internal/infrastructure/database/dbtest/**"
---

# Go server tests

## Tools, files and names

- The standard `testing` package with testify: `require` for checks the test cannot continue without, `assert` for the rest.
- A test sits beside its source: `withdraw_user.go` and `withdraw_user_test.go`.
- Tests use the package from outside, `package application_test`, through its exported API, so internals can change without breaking them. A test that must reach an unexported function (a mapper's `toDomain`) uses the same package.
- The function names the subject; each behavior is a `t.Run` whose name, an English sentence, states what must hold:

```go
func TestWithdrawUser(t *testing.T) {
	t.Run("withdraws, saves and revokes access", func(t *testing.T) { … })
	t.Run("changes nothing for a missing user", func(t *testing.T) { … })
}
```

  When only the inputs change, use a table test whose rows have `name`s that state the case.
- Contexts come from `t.Context()`.

## Fakes and test data

```go
type fakeUsers struct {
	found []*domain.User
	saved []*domain.User
}

var _ domain.UserRepository = (*fakeUsers)(nil) // a changed port breaks the build here

func (f *fakeUsers) Save(_ context.Context, u *domain.User) error {
	f.saved = append(f.saved, u)
	return nil
}
```

- Fakes are written by hand, in a `fakes_test.go` the package's tests share; no mock generators (mockery, gomock). Ports are small, so a hand-written fake is shorter than a generated mock, and it checks results rather than recording which arguments were passed.
- Use cases are constructed directly with fakes and a fixed clock: `application.NewWithdrawUser(users, revoker, fakeTransaction{}, func() time.Time { return now })`.
- Test data comes from the module's testkit, `internal/modules/{d}/testkit`, imported only by that module's tests: `testkit.User(func(s *domain.UserSnapshot) { s.Status = domain.UserStatusWithdrawn })`. The package name already says "test", so its functions carry no `Test` prefix.

## What to test

Test code that makes decisions. Code that only forwards has nothing to decide.

| Code | Test it | How |
|---|---|---|
| Domain: aggregates, value objects | Yes | Plain unit tests; pass `now` to fix the time |
| Use cases | Yes | Construct with fakes |
| Mappers | Yes | Without a database: enum conversion, nullable fields, a `Snapshot` → `Restore` round trip |
| Repository behavior the database decides: a constraint it enforces and the domain error it becomes, a row it does not find, row locks, aggregation or filtering that reading the SQL does not settle | Yes | Against a real database, below |
| Plain CRUD and simple queries | No | sqlc checked their columns and types against the schema when it generated the code |
| Other outbound adapters that make a decision | Yes | Construct with a fake of what they call |
| Handlers | No | They only translate |
| Standard response, error mapping, middleware | Yes | A few `httptest` tests of the shared behavior |
| Dependency rules | Yes | `internal/archtest` |

When you create or change code in a "Yes" row, create or update its tests in the same change.

## Tests against a database

They follow `rules/database/conventions.md`. One helper opens the connection:

```go
// internal/infrastructure/database/dbtest/dbtest.go
func Open(t *testing.T) *database.DB {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		if os.Getenv("CI") == "true" {
			t.Fatal("TEST_DATABASE_URL is required in CI")
		}
		t.Skip("TEST_DATABASE_URL is not set")
	}
	db, err := database.New(t.Context(), url, 4)
	if err != nil {
		t.Fatalf("open test database: %v", err)
	}
	t.Cleanup(db.Close)
	return db
}
```

- Each test creates its own rows with fresh ids and reads only within them; no test empties a table.
- A value that must be unique across runs takes the **random tail** of a UUIDv7, never its head: the first characters are a timestamp and repeat within a minute.

## Reliable runs

- CI runs `go test -race -shuffle=on ./...`: `-race` finds data races between goroutines, `-shuffle` finds tests that depend on order.
- No `time.Sleep` to wait. Time is passed in (`now`, the clock), and a test that must wait polls for its condition with a deadline.
- Listeners open on `:0`; goroutines, listeners and files are cleaned up with `t.Cleanup`.

## Architecture test

`internal/archtest/arch_test.go` loads every package with `golang.org/x/tools/go/packages` and fails on any import that breaks the dependency table in `rules/go-server/architecture.md`, and on any domain identifier other than a value list used from an inbound adapter. It runs with every `go test ./...`. Its template and rules are in the `setting-up-architecture-checks` skill.

## Coverage

Coverage measures `domain/` and `application/` of every module. Its thresholds ratchet: just below the measured values, raised when tests are added, lowered only with a stated reason.
