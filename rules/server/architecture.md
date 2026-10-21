---
paths:
  - "**/src/modules/**"
  - "**/src/shared/**"
  - "**/src/infrastructure/**"
  - "**/src/common/**"
---

# Server architecture

A server is hexagonal. The domain and the use cases know no framework; everything that touches the outside world is an adapter at the edge. Code is grouped by domain first. How the framework fits in is in `rules/server/nestjs.md`.

## Structure

```
src/
├── main.ts
├── app.module.ts
├── modules/                       one folder per domain
│   └── user/
│       ├── domain/                entities, value objects, domain errors, the aggregate's repository port
│       ├── application/
│       │   ├── usecases/          {verb}.usecase.ts
│       │   └── ports/             everything else the use cases need from outside
│       ├── adapters/
│       │   ├── in/                what calls into the app: http/ (controllers, dto/), schedule/, …
│       │   └── out/               what the app calls: persistence/ (repositories, mappers), crypto/, other modules, …
│       ├── testkit/               test data factories (createTestUser), imported only by tests
│       ├── user.module.ts         composition: binds each port to its adapter
│       └── index.ts               public API
├── shared/                        the small kernel: base types every module shares (DomainError, PageResult, newId)
├── infrastructure/                technical clients and configuration that know no domain (prisma, redis, http, config)
└── common/                        framework glue: exception filter, interceptors, guards, decorators, pipes, http/
```

- Every adapter sits under `in/` or `out/`, so a new kind of adapter needs no new folder rule.
- Why domain first: a change to one feature stays in one folder. A tree split by layer first (`api/`, `application/`, `database/`, each with a `user/` inside) spreads one change over five folders, and layer violations pile up where nobody looks.

## Technical clients and adapters

| Code | Knows a domain | Lives in |
|---|---|---|
| A technical client: `PrismaService`, a Redis or S3 client, an external API's arthron client, configuration | No | `src/infrastructure/` |
| An adapter: implements one module's port and knows its data (`PrismaUserRepository`, `UserMapper`) | Yes | `modules/{d}/adapters/out/` |

The adapter receives the client by injection. It is the same split as the frontend's `shared/libs/http` and `entities/{d}/infrastructure/`.

DB schema definitions (tables, columns, indexes) are neither ports nor adapters. They live where the DB tool reads all of them at once.

## Dependency direction

| From | May import |
|---|---|
| `domain` | `shared` |
| `application` | `domain`, `shared`, and from the framework only `@nestjs/common` for `@Injectable` |
| `adapters/in` | `application`, `shared`, `common`, and from `domain` only `{d}.const.ts` (value lists and their types) |
| `adapters/out` | `application` (the ports it implements), `domain`, `shared`, `infrastructure`, another module's `index.ts` |
| `shared`, `infrastructure`, `common` | never `modules` |

- `adapters/in` and `adapters/out` never import each other.
- Another module is reached only through its `index.ts`, and use cases never import another module.
- `server-rules.cjs` in the `setting-up-architecture-checks` skill enforces this table.

## How a request flows

```
        down: outside shapes become inside shapes              up: inside results become outside shapes

 [client] POST /api/users/:id/withdraw                   [client] 2xx + standard response
          │                                                        ▲
 middleware  requestId                                   interceptor  { result, message, timestamp, requestId, errorCode }
          ▼                                                        ▲
 guard       authentication                              controller   UserResponseDto.from(result), on reads
          ▼                                                        ▲
 zod pipe    body → WithdrawUserRequestDto                         │
          ▼                                                        │
 controller  RequestDto → WithdrawUserCommand                      │
          ▼                                                        │
 use case    ───────────────────────────────────────▶ use case    returns WithdrawUserResult
          │                                                        ▲
          ▼                                                        │
 adapters/out  query → row → UserMapper → User.fromSnapshot()      │
          │                                                        │
          └──────────▶ domain  user.withdraw(now) ─────────────────┘
                       invariants, state change; saving goes back through toSnapshot() → mapper

 any failure (validation, a DomainError, an unexpected error) → exception filter: kind → HTTP status,
 { result: null, message, timestamp, requestId, errorCode }
```

| Layer | Handles | Never sees |
|---|---|---|
| Controller | request DTO, command, use case result, response DTO | the database, the standard response |
| Use case | command, ports, entities, result | HTTP, DTOs, the database |
| Domain | entities, value objects, domain errors | everything else |
| Outbound adapter | ports, entities, rows, mappers | HTTP |
| Interceptor and filter | the standard response, a domain error's `kind` and `code` | what any module does |

## Modules talking to each other

A use case that needs another module declares its own port in `application/ports`, in its own words. An adapter in `adapters/out` implements the port by calling the other module's public use case.

```ts
// modules/user/application/ports/account-access-revoker.port.ts
export abstract class AccountAccessRevoker {
  abstract revokeAll(userId: string): Promise<void>;
}

// modules/user/adapters/out/auth/account-access-revoker.auth.adapter.ts
@Injectable()
export class AuthAccountAccessRevoker extends AccountAccessRevoker {
  constructor(private readonly revokeTokens: RevokeAllTokensUseCase) { super(); } // from the auth module's index.ts
  revokeAll(userId: string) {
    return this.revokeTokens.execute({ userId });
  }
}
```

- Never inject another module's use case into a use case. The use case then depends only on its own port, tests replace that port, and a change in the other module touches one adapter.
- A module's `index.ts` exports its public use cases, its module class, the types they use and the domain errors they throw, so a calling adapter recognizes a failure with `instanceof` instead of comparing codes. Entities, repositories and adapters stay inside.
- When two modules would call each other, the one higher in the flow reads what the lower one needs and passes it in.
