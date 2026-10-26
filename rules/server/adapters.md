---
paths:
  - "**/modules/*/adapters/**"
---

# Server adapters

Adapters translate between the outside world and the application. Inbound adapters (`adapters/in/`) call use cases; outbound adapters (`adapters/out/`) implement ports.

## File names

| What | File | Class |
|---|---|---|
| Controller | `adapters/in/http/user.controller.ts` | `UserController` |
| Request DTOs | `adapters/in/http/dto/user.request.dto.ts` | `CreateUserRequestDto`, `UserListParamsDto` |
| Response DTOs | `adapters/in/http/dto/user.response.dto.ts` | `UserResponseDto`, `UserSummaryResponseDto` |
| Repository | `adapters/out/persistence/user.prisma.repository.ts` | `PrismaUserRepository` |
| Mapper | `adapters/out/persistence/user.mapper.ts` | `UserMapper` |
| Any other outbound adapter | `adapters/out/crypto/identity-hasher.hmac.adapter.ts` | `HmacIdentityHasher` |

The role stays last (`rules/typescript/conventions.md`), so `*.repository.ts`, `*.adapter.ts` or `*.request.dto.ts` finds every file of that role. The middle part names how the port is implemented (`prisma`, `mongoose`, `hmac`, `auth`); the class reads implementation first, then the port (`MongooseUserRepository` in `user.mongoose.repository.ts`).

## Inbound: HTTP

```ts
// adapters/in/http/dto/user.request.dto.ts
import { WITHDRAWAL_REASONS } from '../../../../domain/user.const'; // the only domain file inbound adapters import

export const WithdrawUserRequestSchema = z.object({ reason: z.enum(WITHDRAWAL_REASONS) });
export class WithdrawUserRequestDto extends createZodDto(WithdrawUserRequestSchema) {}

// adapters/in/http/dto/user.response.dto.ts
export const UserResponseSchema = z.object({
  id: z.string(),
  nickname: z.string(),
  status: z.enum(USER_STATUSES),
  createdAt: z.string().datetime(),
});
export class UserResponseDto extends createZodDto(UserResponseSchema) {
  static from(result: GetUserDetailResult): UserResponseDto {
    return { ...result, createdAt: result.createdAt.toISOString() };
  }
}

// adapters/in/http/user.controller.ts
@Post(':id/withdraw')
async withdraw(@Param('id') id: string, @Body() body: WithdrawUserRequestDto): Promise<void> {
  await this.withdrawUser.execute({ userId: id, reason: body.reason });
}

@Get(':id')
async getDetail(@Param('id') id: string): Promise<UserResponseDto> {
  return UserResponseDto.from(await this.getUserDetail.execute({ userId: id }));
}
```

- **Request DTOs are zod schemas.** `{Action}{D}RequestDto` comes from `{Action}{D}RequestSchema`; list query parameters are `{D}ListParamsDto`. A global pipe validates every request against its schema (`rules/server/http-api.md`). This is the shape check; rules such as the nickname pattern belong to the domain.
- **The controller picks fields.** It builds the command from the fields the use case needs, never by spreading the DTO, so an unknown field can never reach the use case.
- **Responses come from `static from()`.** `{D}ResponseDto.from(result)` turns a use case result into the response, so inbound adapters never import the domain; list items use `{D}SummaryResponseDto`, and a list goes through `PageResponseDto.from(page, UserSummaryResponseDto.from)` from `src/common/http/page.response.dto.ts`. Instants become ISO strings.
- **The controller only translates.** No business decisions, and no response wrapping: it returns the response DTO and the standard response is built globally.

Request DTOs carry the same names as the frontend's (`CreateUserRequestDto`, `UserListParamsDto` in `rules/frontend/entity-data-access.md`). A server response DTO is what the frontend calls the resource DTO: server `UserResponseDto` and `UserSummaryResponseDto` are frontend `UserDto` and `UserSummaryDto`.

Other inbound adapters (a cron job in `adapters/in/schedule/`) call a use case the same way a controller does.

## Outbound: persistence

```ts
// adapters/out/persistence/user.prisma.repository.ts
@Injectable()
export class PrismaUserRepository extends UserRepository {
  constructor(private readonly txHost: TransactionHost<TransactionalAdapterPrisma<PrismaService>>) { super(); }

  async findById(id: string) {
    const row = await this.txHost.tx.user.findUnique({ where: { id } }); // the open transaction, or the default connection
    return row ? UserMapper.toDomain(row) : null;
  }

  async save(user: User) {
    await this.txHost.tx.user.upsert(UserMapper.toPersistence(user));
  }
}
```

- **Queries go through the client that joins the open transaction** (`rules/server/application.md`). How it is wired is in `rules/server/nestjs.md`; the client's type argument is explained in `rules/database/prisma.md`.
- **The mapper keeps rows inside `persistence/`.** `UserMapper.toDomain(row)` rebuilds through `User.fromSnapshot()`, and `toPersistence(user)` starts from `user.toSnapshot()`. No row type leaves the folder.
- **Database errors become domain errors here.** A unique violation on the email becomes `UserEmailTakenError` (`kind: 'conflict'`); errors the adapter does not recognize are rethrown.

## Outbound: other modules and integrations

- An adapter for another module calls that module's public use case from its `index.ts` (`rules/server/architecture.md`).
- An optional integration (payments, maps) whose configuration is absent still lets the server start. Its adapter throws a clear error when called, so only that feature fails (`rules/server/runtime.md`).
- **An external HTTP API** is called through an arthron client in `src/infrastructure/http/{service}.client.ts`, built once from `ENV` with the service's base URL, its credentials and `timeout()`. The client's headers go to its `baseURL`'s origin only, so the credentials cannot reach another host; fetch has no timeout of its own, so without one a slow service holds the request open. The module hands the client to the adapter: `{ provide: PaymentGateway, useFactory: () => new TossPaymentGateway(tossClient) }`.
- The client is arthron 2.1 or later. Under 2.0, a response whose status text is not Latin-1 (`500 실패`) failed with a `TypeError` instead of an `ArthronError`, and once `timeout()` was on, so did a `200`. arthron's whole API is in `node_modules/arthron/llms.txt`.
- The adapter turns the failures it recognizes into a domain result or a domain error, by status or by the service's own code in `error.payload`, and rethrows the rest. The service's wire format stays in the adapter.

```ts
// src/infrastructure/http/toss.client.ts
export const tossClient = arthron({
  baseURL: ENV.TOSS_API_URL,
  headers: { authorization: `Basic ${btoa(`${ENV.TOSS_SECRET_KEY}:`)}` },
  plugins: [timeout(10_000), retry()], // timeout before retry bounds the whole call, retries included
});

// modules/payment/adapters/out/payment/payment-gateway.toss.adapter.ts
export class TossPaymentGateway extends PaymentGateway {
  constructor(private readonly http: ArthronClient) {
    super();
  }

  async findPayment(paymentKey: string): Promise<PaymentInfo | null> {
    try {
      const dto = await this.http.get('/v1/payments/{paymentKey}', { pathParams: { paymentKey } }).json<TossPaymentDto>();
      return { paymentKey: dto.paymentKey, status: STATUS[dto.status], amount: dto.totalAmount };
    } catch (error) {
      if (isArthronError(error) && error.status === 404) return null;
      throw error;
    }
  }
}
```
