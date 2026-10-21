---
paths:
  - "**/*.module.ts"
  - "**/*.controller.ts"
  - "**/main.ts"
  - "**/src/common/**"
---

# NestJS

How the server rules (`rules/server/*.md`) map onto NestJS. The domain never imports Nest; the application imports only `@Injectable`.

## Modules are composition roots

```ts
// modules/user/user.module.ts
@Module({
  imports: [AuthModule],                                   // provides RevokeAllTokensUseCase to the adapter below
  controllers: [UserController],
  providers: [
    WithdrawUserUseCase,
    GetUserDetailUseCase,
    { provide: UserRepository, useClass: PrismaUserRepository },
    { provide: AccountAccessRevoker, useClass: AuthAccountAccessRevoker },
    { provide: ResignupPolicy, useFactory: () => ({ cooldownDays: ENV.RESIGNUP_COOLDOWN_DAYS }) },
    {
      provide: TransactionRunner,
      useFactory: (txHost: TransactionHost) => ({ run: (fn) => txHost.withTransaction(fn) }),
      inject: [TransactionHost],
    },
  ],
  exports: [GetUserDetailUseCase],                         // only what other modules' adapters call
})
export class UserModule {}
```

- Ports are abstract classes, so the class itself is the token: `{ provide: Port, useClass: Adapter }`. No string or symbol tokens, no `@Inject()`.
- Policies are filled with `useFactory` from the validated `ENV` (`rules/server/runtime.md`), so use cases never see a config service.
- One implementation serving two ports is bound once and aliased with `useExisting`.
- A module `exports` only the public use cases another module's adapter injects, and lists the modules it depends on in `imports`.
- Use cases and adapters carry `@Injectable()`; constructor injection needs the decorator metadata, which is why Biome's `useImportType` is off in Nest servers (`rules/typescript/conventions.md`).
- The server builds CommonJS: its tsconfig turns off `verbatimModuleSyntax` and turns on `isolatedModules`, with `emitDecoratorMetadata` and `experimentalDecorators` on (`rules/typescript/conventions.md`).

## Global setup

| Concern | NestJS piece |
|---|---|
| `/api` prefix | `app.setGlobalPrefix('api')` |
| Request validation | A global zod validation pipe (`nestjs-zod`) |
| Standard response | A global interceptor for successes, a global exception filter for every error (`rules/server/http-api.md`) |
| Authentication | The auth guard registered as `APP_GUARD`; `@Public()` and `@Roles()` decorators in `common/decorators/` |
| Transactions | `ClsModule` with `@nestjs-cls/transactional` and the adapter for the ORM; repositories query through `TransactionHost.tx`. With Prisma the adapter gets `prismaInjectionToken: PrismaService` and `TransactionHost` the client type (`rules/database/prisma.md`) |
| Logs and `requestId` | `nestjs-pino`, generating the id or taking `X-Request-Id` |
| Rate limits | `@nestjs/throttler`, applied to the routes that need it |
| Security headers, CORS, body size | `helmet`, `app.enableCors({ origin: ENV.CORS_ORIGINS })`, an explicit body parser limit |
| API documentation | The OpenAPI document generated from the zod DTOs (`nestjs-zod`), mounted at `/api/docs` outside production |

`common/` holds these pieces: `filters/`, `interceptors/`, `guards/`, `decorators/`, `pipes/`, and `http/` for `ApiResponse<T>` and `PageResponseDto`. It knows no module.

## Tests

Vitest compiles with esbuild, which drops decorator metadata; add the SWC plugin (`unplugin-swc`) so Nest can resolve constructor injection in tests that build a testing module. Unit tests of use cases construct them directly and need no Nest at all.
