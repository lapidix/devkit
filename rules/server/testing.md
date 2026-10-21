---
paths:
  - "**/src/modules/**/*.test.ts"
  - "**/src/common/**/*.test.ts"
  - "**/src/modules/*/domain/**"
  - "**/src/modules/*/application/**"
  - "**/adapters/out/persistence/**"
  - "**/src/common/**"
---

# Server tests

## Tools, files and names

- Vitest. Nest's decorator metadata needs the SWC plugin (`rules/server/nestjs.md`).
- A test sits beside its source: `withdraw.usecase.ts` and `withdraw.usecase.test.ts`.
- Test names are English sentences that state the behavior that must hold: `it('rejects withdrawing a user who already withdrew')`.
- Fakes go in through constructors (`new WithdrawUserUseCase(users, accessRevoker, transaction)`) and are typed with `satisfies`, never `as unknown as`. A port is an abstract class, so `satisfies UserRepository` fits. A concrete class, such as another module's use case faked in an adapter test, has private members, so pick its public methods: `satisfies Pick<GetUserDetailUseCase, 'execute'>`.
- Test data comes from the module's testkit, `modules/{d}/testkit/{d}.testkit.ts`, which only that module's tests import. Names shared between test files carry `Test` (`createTestUser`).

## What to test

Test code that makes decisions. Code that only forwards has nothing to decide, and testing it against a database or a mocked ORM proves nothing.

| Code | Test it | How |
|---|---|---|
| Domain: aggregates, value objects | Yes | Plain unit tests; pass `now` to fix the time |
| Use cases | Yes | Construct with fake ports |
| Mappers | Yes | Unit tests without a database: defaults for missing values, enum conversion, a `toSnapshot` → `fromSnapshot` round trip |
| Repository methods that use database-specific behavior: hand-written SQL, row locks, complex aggregation, constraint violations turned into domain errors | Yes | Integration tests against a real database, run as `rules/database/conventions.md` says |
| Plain CRUD repository methods | No | They hand the call to the ORM |
| Other outbound adapters that make a decision (turning another module's not-found into `false`, mapping an external API's errors) | Yes | Construct with a fake of what they call; an external API's adapter gets `arthron({ baseURL, fetchFn })` with a fake fetch |
| Controllers | No | They only translate |
| Standard response, exception filter, guards, validation pipe | Yes | A few HTTP-level tests of the shared behavior |

When you create or change code in a "Yes" row, create or update its tests in the same change. Never assert which arguments a mocked ORM received: the test breaks on every harmless query change and never shows whether the SQL works.

## Coverage

Coverage measures `domain/` and `application/` of every module, and its thresholds ratchet: just below the measured values, raised when tests are added, lowered only with a stated reason.
