---
paths:
  - "**/modules/*/application/**"
---

# Server application layer

## Use cases

```ts
// modules/user/application/usecases/withdraw.usecase.ts
export interface WithdrawUserCommand {
  userId: string;
  reason: WithdrawalReason;
}
export type WithdrawUserResult = void;

@Injectable()
export class WithdrawUserUseCase {
  constructor(
    private readonly users: UserRepository,                 // domain: the aggregate's repository
    private readonly accessRevoker: AccountAccessRevoker,   // application/ports
    private readonly transaction: TransactionRunner,        // application/ports
  ) {}

  async execute(command: WithdrawUserCommand, now = new Date()): Promise<WithdrawUserResult> {
    const user = await this.users.findById(command.userId);
    if (!user) throw new UserNotFoundError();

    await this.transaction.run(async () => {
      user.withdraw(now);
      await this.users.save(user);
      await this.accessRevoker.revokeAll(command.userId); // the auth module's writes join this transaction
    });
  }
}
```

- **Place.** `application/usecases/{verb}.usecase.ts`; the module folder already names the domain. The test sits beside it.
- **Names.** `{Verb}{D}UseCase`, a `{Verb}{D}Command` interface for writes or a `{Verb}{D}Query` for reads, and a `{Verb}{D}Result` type, all defined and exported in the use case file.
- **Shape.** A class with its ports injected through the constructor and one method, `execute`. `@Injectable()` is the only framework import allowed in this layer.
- **Errors.** Use cases and the domain throw `DomainError`s, never the framework's HTTP exceptions (`NotFoundException`, `ConflictException`). An HTTP exception decides a status code inside the application, skips the `errorCode`, and means nothing when a cron job or another module calls the use case.
- **Time.** `execute(command, now = new Date())` passes `now` to the domain; a test passes a fixed `now`.
- **Conditions on another module.** A rule that needs another module's data ("only an active author may publish") is checked by the use case through a port, before it calls the aggregate's method. The aggregate checks only its own state; it never imports another module.
- **No second validation.** The boundary has checked the shape (`rules/server/adapters.md`) and the domain checks the rules. Unlike the frontend, a server use case does not validate its command again.
- **Result.** A use case returns a plain `Result` type built from the entity (primitives, and domain unions such as `UserStatus`), never an aggregate and never a response DTO. Controllers build responses from it and other modules receive it, so neither ever holds the domain model, and only use cases change aggregates.
  ```ts
  export type GetUserDetailResult = { id: string; nickname: string; status: UserStatus; createdAt: Date };

  async execute(query: GetUserDetailQuery): Promise<GetUserDetailResult> {
    const user = await this.users.findById(query.userId);
    if (!user) throw new UserNotFoundError();
    const { id, nickname, status, createdAt } = user.toSnapshot();
    return { id, nickname, status, createdAt };
  }
  ```

## Ports

Everything a use case needs from outside, other than an aggregate root's repository, is a port in `application/ports/{name}.port.ts`: technical capabilities, another module, settings, transactions.

```ts
// modules/user/application/ports/identity-hasher.port.ts
export abstract class IdentityHasher {
  abstract hash(value: string): string;
}
```

- A port is an abstract class, which doubles as the DI token. Its class name carries no `Port` suffix (`IdentityHasher`).
- Another module is always reached through a port here (`rules/server/architecture.md`).

## Transactions

```ts
// modules/user/application/ports/transaction-runner.port.ts
export abstract class TransactionRunner {
  abstract run<T>(fn: () => Promise<T>): Promise<T>;
}
```

- The use case decides the boundary. A transaction opens only inside a use case's `transaction.run()`.
- The open transaction travels with the call (AsyncLocalStorage), so ports take no transaction argument, and work done through another module's adapter inside `run()` joins the same transaction.
- External side effects (notifications, mail, external APIs) run after the commit, outside `run()`. A rollback then never leaves a message already sent.

## Settings

A use case never reads configuration. A value it needs arrives as a policy, a port the module fills from the validated environment (`rules/server/nestjs.md`):

```ts
// modules/user/application/ports/resignup-policy.port.ts
export abstract class ResignupPolicy {
  abstract readonly cooldownDays: number;
}
```
