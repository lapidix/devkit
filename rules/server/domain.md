---
paths:
  - "**/modules/*/domain/**"
  - "**/src/shared/**"
---

# Server domain

The domain is plain TypeScript: no framework, ORM or HTTP import. It holds the aggregates, their value objects and errors, and each aggregate root's repository port.

## Aggregates are classes

```ts
// modules/user/domain/user.entity.ts
export class User {
  private constructor(private state: UserState) {}

  static register(input: RegisterUserInput, now: Date): User {
    const nickname = Nickname.create(input.nickname); // throws a domain error when invalid
    return new User({ ...input, nickname, status: 'active', withdrawnAt: null, createdAt: now });
  }

  static fromSnapshot(snapshot: UserSnapshot): User {
    return new User({ ...snapshot, nickname: Nickname.restore(snapshot.nickname) });
  }

  toSnapshot(): UserSnapshot {
    return { ...this.state, nickname: this.state.nickname.value };
  }

  withdraw(now: Date): void {
    if (this.state.status === 'withdrawn') throw new UserAlreadyWithdrawnError();
    this.state = { ...this.state, status: 'withdrawn', withdrawnAt: now };
  }
}
```

- The constructor is private. An aggregate is created through `register`, or the domain's own creation verb (`Order.place`, `Account.open`), which checks the invariants. Storage rebuilds it through `fromSnapshot`, without checks, because the data was valid when it was saved. `toSnapshot` hands storage a plain object. The mapper calls both.
- A snapshot holds primitives only. Inside the aggregate, values keep their value object types; `toSnapshot` unwraps them and `fromSnapshot` rebuilds them with `restore`.
- State is private and changes only through methods.
- Methods take the current time as a required `now: Date`; the domain never calls `new Date()`. A rule such as "a user may sign up again 30 days after withdrawing" is then testable without a clock.
- Domain events are not used yet. A reaction in another module goes through a port (`rules/server/architecture.md`).

Why classes here when the frontend uses types and functions (`rules/frontend/entities.md`): frontend entities pass through query caches and `structuredClone`, which strip prototypes. A server has no such step, and an aggregate is the boundary that keeps its invariants: a private constructor and methods are what make that boundary hold.

## Value objects

```ts
// modules/user/domain/nickname.vo.ts
export class Nickname {
  private constructor(readonly value: string) {}

  static create(raw: string): Nickname {
    if (!NICKNAME_PATTERN.test(raw)) throw new UserInvalidNicknameError();
    return new Nickname(raw);
  }

  static restore(value: string): Nickname {
    return new Nickname(value);
  }
}
```

- A value object has a private constructor, a `static create(raw)` that validates a new value and throws a domain error, and a `static restore(value)` that rebuilds a stored value without checks.
- Why `restore` skips the checks: a rule tightened later (a longer minimum length) would otherwise make every row saved under the old rule fail to load. New values are validated; stored values are trusted, as with `register` and `fromSnapshot`.

## Constants

Value lists and the unions derived from them live in `domain/{d}.const.ts`:

```ts
// modules/user/domain/user.const.ts
export const USER_STATUSES = ['active', 'invited', 'withdrawn'] as const;
export type UserStatus = (typeof USER_STATUSES)[number];
export const WITHDRAWAL_REASONS = ['moved', 'not_useful', 'other'] as const;
export type WithdrawalReason = (typeof WITHDRAWAL_REASONS)[number];
```

It is the one domain file inbound adapters may import: request and response schemas need the lists (`z.enum(WITHDRAWAL_REASONS)`). Entities, value objects, repositories and errors stay out of their reach.

## Repository ports

Each aggregate root's repository port is an abstract class in the domain; the abstract class doubles as the DI token.

```ts
// modules/user/domain/user.repository.ts
export abstract class UserRepository {
  abstract findById(id: string): Promise<User | null>;
  abstract save(user: User): Promise<void>;
}
```

Only the repositories of aggregate roots live here. Everything else a use case needs from outside is a port in `application/ports` (`rules/server/application.md`). The test: does it store and load an aggregate root?

## Errors

```ts
// shared/domain/domain.error.ts
export abstract class DomainError extends Error {
  abstract readonly code: string;
  abstract readonly kind: 'invalid' | 'unauthorized' | 'forbidden' | 'not_found' | 'conflict';
}

// modules/user/domain/user.errors.ts
export class UserNotFoundError extends DomainError {
  readonly code = 'USER_NOT_FOUND';
  readonly kind = 'not_found';
}
```

- Names are `{D}{Reason}Error`, in `domain/{d}.errors.ts`.
- `code` is `{MODULE}_{REASON}` in upper snake case. Clients branch on it; it reaches them as `errorCode`.
- `kind` says what went wrong. The HTTP status is chosen from it in one place (`rules/api/contract.md`), so the domain never knows HTTP.

## shared

`src/shared/` holds only the base types every module shares: `DomainError` in `shared/domain/domain.error.ts`, `newId()` in `shared/domain/id.ts`, and `PageResult<T> = { items, total, page, pageSize }` in `shared/types/page.types.ts`, which repository ports and use case results use for lists. It imports no framework, no ORM and no module.

`newId()` returns a UUIDv7 string (`rules/database/conventions.md`). The use case calls it and passes the id to `register`, so the domain stays free of id generation and tests pass fixed ids.
