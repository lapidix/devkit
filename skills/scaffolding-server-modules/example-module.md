# Example module: `modules/user`

One complete module that follows the server rules. It uses NestJS, Prisma through `@nestjs-cls/transactional`, zod with `nestjs-zod`, and Vitest. `@/` maps to `src/`. The two shared pieces at the top exist once per project, as does `PrismaService` in `src/infrastructure/database/prisma.service.ts` (`rules/database/prisma.md`); the `auth` module it calls exports `RevokeAllTokensUseCase` from its `index.ts`. Creating users (and so generating ids) is left out.

## src/shared/types/page.types.ts

```ts
export type PageResult<T> = { items: T[]; total: number; page: number; pageSize: number };
```

## src/common/http/page.response.dto.ts

```ts
import type { PageResult } from '@/shared/types/page.types';

/** A list response keeps the use case's PageResult and turns each item into its response DTO. */
export const PageResponseDto = {
  from<T, R>(page: PageResult<T>, toItem: (item: T) => R): PageResult<R> {
    return { ...page, items: page.items.map(toItem) };
  },
};
```

## src/modules/user/domain/user.const.ts

```ts
export const USER_STATUSES = ['active', 'withdrawn'] as const;
export type UserStatus = (typeof USER_STATUSES)[number];

export const WITHDRAWAL_REASONS = ['moved', 'not_useful', 'other'] as const;
export type WithdrawalReason = (typeof WITHDRAWAL_REASONS)[number];

export const NICKNAME_PATTERN = /^[a-z0-9_]{2,20}$/;
```

## src/modules/user/domain/user.errors.ts

```ts
import { DomainError } from '@/shared/domain/domain.error';

export class UserInvalidNicknameError extends DomainError {
  readonly code = 'USER_INVALID_NICKNAME';
  readonly kind = 'invalid';
}

export class UserNotFoundError extends DomainError {
  readonly code = 'USER_NOT_FOUND';
  readonly kind = 'not_found';
}

export class UserAlreadyWithdrawnError extends DomainError {
  readonly code = 'USER_ALREADY_WITHDRAWN';
  readonly kind = 'conflict';
}
```

## src/modules/user/domain/nickname.vo.ts

```ts
import { NICKNAME_PATTERN } from './user.const';
import { UserInvalidNicknameError } from './user.errors';

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

## src/modules/user/domain/nickname.vo.test.ts

```ts
import { describe, expect, it } from 'vitest';
import { Nickname } from './nickname.vo';
import { UserInvalidNicknameError } from './user.errors';

describe('Nickname', () => {
  it('rejects a new nickname that breaks the rules', () => {
    expect(() => Nickname.create('Kim Lee')).toThrow(UserInvalidNicknameError);
  });

  it('restores a stored nickname even when today's rules reject it', () => {
    expect(Nickname.restore('Kim Lee').value).toBe('Kim Lee');
  });
});
```

## src/modules/user/domain/user.entity.ts

```ts
import { Nickname } from './nickname.vo';
import type { UserStatus } from './user.const';
import { UserAlreadyWithdrawnError } from './user.errors';

export type UserSnapshot = {
  id: string;
  nickname: string;
  status: UserStatus;
  createdAt: Date;
  withdrawnAt: Date | null;
};

type UserState = {
  id: string;
  nickname: Nickname;
  status: UserStatus;
  createdAt: Date;
  withdrawnAt: Date | null;
};

export interface RegisterUserInput {
  id: string;
  nickname: string;
}

export class User {
  private constructor(private state: UserState) {}

  static register(input: RegisterUserInput, now: Date): User {
    return new User({
      id: input.id,
      nickname: Nickname.create(input.nickname),
      status: 'active',
      createdAt: now,
      withdrawnAt: null,
    });
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

## src/modules/user/domain/user.entity.test.ts

```ts
import { describe, expect, it } from 'vitest';
import { createTestUser } from '../testkit/user.testkit';
import { User } from './user.entity';
import { UserInvalidNicknameError, UserAlreadyWithdrawnError } from './user.errors';

const now = new Date('2026-10-19T00:00:00Z');

describe('User', () => {
  it('refuses to register a nickname that breaks the rules', () => {
    expect(() => User.register({ id: 'user-1', nickname: 'A!' }, now)).toThrow(UserInvalidNicknameError);
  });

  it('records the withdrawal time', () => {
    const user = createTestUser();
    user.withdraw(now);
    expect(user.toSnapshot()).toMatchObject({ status: 'withdrawn', withdrawnAt: now });
  });

  it('rejects withdrawing a user who already withdrew', () => {
    const user = createTestUser({ status: 'withdrawn', withdrawnAt: now });
    expect(() => user.withdraw(now)).toThrow(UserAlreadyWithdrawnError);
  });
});
```

## src/modules/user/domain/user.repository.ts

```ts
import type { PageResult } from '@/shared/types/page.types';
import type { UserStatus } from './user.const';
import type { User } from './user.entity';

export interface UserListCriteria {
  status?: UserStatus;
  page: number;
  pageSize: number;
}

export abstract class UserRepository {
  abstract findById(id: string): Promise<User | null>;
  abstract findPage(criteria: UserListCriteria): Promise<PageResult<User>>;
  abstract save(user: User): Promise<void>;
}
```

## src/modules/user/application/ports/transaction-runner.port.ts

```ts
export abstract class TransactionRunner {
  abstract run<T>(fn: () => Promise<T>): Promise<T>;
}
```

## src/modules/user/application/ports/account-access-revoker.port.ts

```ts
export abstract class AccountAccessRevoker {
  abstract revokeAll(userId: string): Promise<void>;
}
```

## src/modules/user/application/usecases/get-detail.usecase.ts

```ts
import { Injectable } from '@nestjs/common';
import type { UserStatus } from '../../domain/user.const';
import { UserNotFoundError } from '../../domain/user.errors';
import { UserRepository } from '../../domain/user.repository';

export interface GetUserDetailQuery {
  userId: string;
}
export type GetUserDetailResult = { id: string; nickname: string; status: UserStatus; createdAt: Date };

@Injectable()
export class GetUserDetailUseCase {
  constructor(private readonly users: UserRepository) {}

  async execute(query: GetUserDetailQuery): Promise<GetUserDetailResult> {
    const user = await this.users.findById(query.userId);
    if (!user) throw new UserNotFoundError();
    const { id, nickname, status, createdAt } = user.toSnapshot();
    return { id, nickname, status, createdAt };
  }
}
```

## src/modules/user/application/usecases/get-detail.usecase.test.ts

```ts
import { describe, expect, it, vi } from 'vitest';
import type { User } from '../../domain/user.entity';
import { UserNotFoundError } from '../../domain/user.errors';
import type { UserRepository } from '../../domain/user.repository';
import { createTestUser } from '../../testkit/user.testkit';
import { GetUserDetailUseCase } from './get-detail.usecase';

function setup(found: User | null) {
  const users = { findById: vi.fn().mockResolvedValue(found), findPage: vi.fn(), save: vi.fn() } satisfies UserRepository;
  return new GetUserDetailUseCase(users);
}

describe('GetUserDetailUseCase', () => {
  it('returns a plain result, not the entity', async () => {
    const result = await setup(createTestUser()).execute({ userId: 'user-1' });
    expect(result).toEqual({ id: 'user-1', nickname: 'kim', status: 'active', createdAt: new Date('2026-10-01T00:00:00Z') });
  });

  it('throws UserNotFoundError for a missing user', async () => {
    await expect(setup(null).execute({ userId: 'nobody' })).rejects.toThrow(UserNotFoundError);
  });
});
```

## src/modules/user/application/usecases/get-list.usecase.ts

```ts
import { Injectable } from '@nestjs/common';
import type { PageResult } from '@/shared/types/page.types';
import type { UserStatus } from '../../domain/user.const';
import { UserRepository } from '../../domain/user.repository';

export interface GetUserListQuery {
  status?: UserStatus;
  page: number;
  pageSize: number;
}
export type UserSummary = { id: string; nickname: string; status: UserStatus };
export type GetUserListResult = PageResult<UserSummary>;

@Injectable()
export class GetUserListUseCase {
  constructor(private readonly users: UserRepository) {}

  async execute(query: GetUserListQuery): Promise<GetUserListResult> {
    const page = await this.users.findPage(query);
    return {
      ...page,
      items: page.items.map((user) => {
        const { id, nickname, status } = user.toSnapshot();
        return { id, nickname, status };
      }),
    };
  }
}
```

## src/modules/user/application/usecases/get-list.usecase.test.ts

```ts
import { describe, expect, it, vi } from 'vitest';
import type { UserRepository } from '../../domain/user.repository';
import { createTestUser } from '../../testkit/user.testkit';
import { GetUserListUseCase } from './get-list.usecase';

describe('GetUserListUseCase', () => {
  it('keeps the page info and maps only the items to summaries', async () => {
    const page = { items: [createTestUser()], total: 21, page: 2, pageSize: 20 };
    const users = { findById: vi.fn(), findPage: vi.fn().mockResolvedValue(page), save: vi.fn() } satisfies UserRepository;

    const result = await new GetUserListUseCase(users).execute({ page: 2, pageSize: 20 });

    expect(result).toEqual({ items: [{ id: 'user-1', nickname: 'kim', status: 'active' }], total: 21, page: 2, pageSize: 20 });
  });
});
```

## src/modules/user/application/usecases/withdraw.usecase.ts

```ts
import { Injectable } from '@nestjs/common';
import type { WithdrawalReason } from '../../domain/user.const';
import { UserNotFoundError } from '../../domain/user.errors';
import { UserRepository } from '../../domain/user.repository';
import { AccountAccessRevoker } from '../ports/account-access-revoker.port';
import { TransactionRunner } from '../ports/transaction-runner.port';

export interface WithdrawUserCommand {
  userId: string;
  reason: WithdrawalReason;
}
export type WithdrawUserResult = void;

@Injectable()
export class WithdrawUserUseCase {
  constructor(
    private readonly users: UserRepository,
    private readonly accessRevoker: AccountAccessRevoker,
    private readonly transaction: TransactionRunner,
  ) {}

  async execute(command: WithdrawUserCommand, now = new Date()): Promise<WithdrawUserResult> {
    const user = await this.users.findById(command.userId);
    if (!user) throw new UserNotFoundError();

    await this.transaction.run(async () => {
      user.withdraw(now);
      await this.users.save(user);
      await this.accessRevoker.revokeAll(command.userId);
    });
  }
}
```

## src/modules/user/application/usecases/withdraw.usecase.test.ts

```ts
import { describe, expect, it, vi } from 'vitest';
import type { User } from '../../domain/user.entity';
import { UserNotFoundError } from '../../domain/user.errors';
import type { UserRepository } from '../../domain/user.repository';
import { createTestUser } from '../../testkit/user.testkit';
import type { AccountAccessRevoker } from '../ports/account-access-revoker.port';
import type { TransactionRunner } from '../ports/transaction-runner.port';
import { WithdrawUserUseCase } from './withdraw.usecase';

const now = new Date('2026-10-19T00:00:00Z');

function setup(found: User | null = createTestUser()) {
  const users = {
    findById: vi.fn().mockResolvedValue(found),
    findPage: vi.fn(),
    save: vi.fn().mockResolvedValue(undefined),
  } satisfies UserRepository;
  const accessRevoker = { revokeAll: vi.fn().mockResolvedValue(undefined) } satisfies AccountAccessRevoker;
  const transaction = { run: <T,>(fn: () => Promise<T>) => fn() } satisfies TransactionRunner; // runs the work in place
  return { users, accessRevoker, useCase: new WithdrawUserUseCase(users, accessRevoker, transaction) };
}

describe('WithdrawUserUseCase', () => {
  it('saves the withdrawn user and revokes all their access', async () => {
    const { users, accessRevoker, useCase } = setup();

    await useCase.execute({ userId: 'user-1', reason: 'moved' }, now);

    expect(users.save.mock.calls[0]?.[0].toSnapshot()).toMatchObject({ status: 'withdrawn', withdrawnAt: now });
    expect(accessRevoker.revokeAll).toHaveBeenCalledWith('user-1');
  });

  it('changes nothing for a missing user', async () => {
    const { users, useCase } = setup(null);

    await expect(useCase.execute({ userId: 'nobody', reason: 'other' }, now)).rejects.toThrow(UserNotFoundError);
    expect(users.save).not.toHaveBeenCalled();
  });
});
```

## prisma/schema/user.prisma

```prisma
model User {
  id          String     @id @db.Uuid
  nickname    String     @unique
  status      UserStatus
  createdAt   DateTime   @default(now()) @map("created_at") @db.Timestamptz
  updatedAt   DateTime   @updatedAt @map("updated_at") @db.Timestamptz
  withdrawnAt DateTime?  @map("withdrawn_at") @db.Timestamptz

  @@index([status, createdAt]) // admin user list: by status, newest first
  @@map("users")
}

enum UserStatus {
  active
  withdrawn

  @@map("user_status")
}
```

## src/modules/user/adapters/out/persistence/user.mapper.ts

```ts
import type { User as UserRow } from '@/generated/prisma/client';
import { User } from '../../../domain/user.entity';

export const UserMapper = {
  toDomain(row: UserRow): User {
    return User.fromSnapshot({
      id: row.id,
      nickname: row.nickname,
      status: row.status,
      createdAt: row.createdAt,
      withdrawnAt: row.withdrawnAt,
    });
  },
  toPersistence(user: User) {
    const snapshot = user.toSnapshot();
    return { where: { id: snapshot.id }, create: snapshot, update: snapshot };
  },
};
```

## src/modules/user/adapters/out/persistence/user.mapper.test.ts

```ts
import { describe, expect, it } from 'vitest';
import type { User as UserRow } from '@/generated/prisma/client';
import { UserMapper } from './user.mapper';

// updatedAt is filled by the ORM, so it never comes back through the domain
const stored = {
  id: 'user-1',
  nickname: 'kim',
  status: 'active',
  createdAt: new Date('2026-10-01T00:00:00Z'),
  withdrawnAt: null,
} satisfies Omit<UserRow, 'updatedAt'>;
const row: UserRow = { ...stored, updatedAt: new Date('2026-10-02T00:00:00Z') };

describe('UserMapper', () => {
  it('round-trips a row through the entity unchanged', () => {
    const user = UserMapper.toDomain(row);
    expect(UserMapper.toPersistence(user).create).toEqual(stored);
  });

  it('restores an old nickname that today's rules reject, without checking it', () => {
    expect(UserMapper.toDomain({ ...row, nickname: 'Old Name' }).toSnapshot().nickname).toBe('Old Name');
  });
});
```

## src/modules/user/adapters/out/persistence/user.prisma.repository.ts

```ts
import { Injectable } from '@nestjs/common';
import { TransactionHost } from '@nestjs-cls/transactional';
import type { TransactionalAdapterPrisma } from '@nestjs-cls/transactional-adapter-prisma';
import type { PrismaService } from '@/infrastructure/database/prisma.service';
import type { PageResult } from '@/shared/types/page.types';
import type { User } from '../../../domain/user.entity';
import { type UserListCriteria, UserRepository } from '../../../domain/user.repository';
import { UserMapper } from './user.mapper';

@Injectable()
export class PrismaUserRepository extends UserRepository {
  constructor(private readonly txHost: TransactionHost<TransactionalAdapterPrisma<PrismaService>>) {
    super();
  }

  async findById(id: string): Promise<User | null> {
    const row = await this.txHost.tx.user.findUnique({ where: { id } });
    return row ? UserMapper.toDomain(row) : null;
  }

  async findPage({ status, page, pageSize }: UserListCriteria): Promise<PageResult<User>> {
    const where = status ? { status } : {};
    const [rows, total] = await Promise.all([
      this.txHost.tx.user.findMany({
        where,
        orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
      this.txHost.tx.user.count({ where }),
    ]);
    return { items: rows.map(UserMapper.toDomain), total, page, pageSize };
  }

  async save(user: User): Promise<void> {
    await this.txHost.tx.user.upsert(UserMapper.toPersistence(user));
  }
}
```

## src/modules/user/adapters/out/auth/account-access-revoker.auth.adapter.ts

```ts
import { Injectable } from '@nestjs/common';
import { RevokeAllTokensUseCase } from '@/modules/auth';
import { AccountAccessRevoker } from '../../../application/ports/account-access-revoker.port';

@Injectable()
export class AuthAccountAccessRevoker extends AccountAccessRevoker {
  constructor(private readonly revokeTokens: RevokeAllTokensUseCase) {
    super();
  }

  revokeAll(userId: string): Promise<void> {
    return this.revokeTokens.execute({ userId });
  }
}
```

## src/modules/user/adapters/in/http/dto/user.request.dto.ts

```ts
import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';
import { USER_STATUSES, WITHDRAWAL_REASONS } from '../../../../domain/user.const';

export const WithdrawUserRequestSchema = z.object({ reason: z.enum(WITHDRAWAL_REASONS) });
export class WithdrawUserRequestDto extends createZodDto(WithdrawUserRequestSchema) {}

export const UserListParamsSchema = z.object({
  status: z.enum(USER_STATUSES).optional(),
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(20),
});
export class UserListParamsDto extends createZodDto(UserListParamsSchema) {}
```

## src/modules/user/adapters/in/http/dto/user.response.dto.ts

```ts
import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';
import type { GetUserDetailResult } from '../../../../application/usecases/get-detail.usecase';
import type { UserSummary } from '../../../../application/usecases/get-list.usecase';
import { USER_STATUSES } from '../../../../domain/user.const';

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

export const UserSummaryResponseSchema = z.object({ id: z.string(), nickname: z.string(), status: z.enum(USER_STATUSES) });
export class UserSummaryResponseDto extends createZodDto(UserSummaryResponseSchema) {
  static from(summary: UserSummary): UserSummaryResponseDto {
    return { ...summary };
  }
}
```

## src/modules/user/adapters/in/http/user.controller.ts

```ts
import { Body, Controller, Get, HttpCode, Param, Post, Query } from '@nestjs/common';
import { PageResponseDto } from '@/common/http/page.response.dto';
import type { PageResult } from '@/shared/types/page.types';
import { GetUserDetailUseCase } from '../../../application/usecases/get-detail.usecase';
import { GetUserListUseCase } from '../../../application/usecases/get-list.usecase';
import { WithdrawUserUseCase } from '../../../application/usecases/withdraw.usecase';
import { UserListParamsDto, WithdrawUserRequestDto } from './dto/user.request.dto';
import { UserResponseDto, UserSummaryResponseDto } from './dto/user.response.dto';

@Controller('users')
export class UserController {
  constructor(
    private readonly getUserList: GetUserListUseCase,
    private readonly getUserDetail: GetUserDetailUseCase,
    private readonly withdrawUser: WithdrawUserUseCase,
  ) {}

  @Get()
  async getList(@Query() params: UserListParamsDto): Promise<PageResult<UserSummaryResponseDto>> {
    const page = await this.getUserList.execute({ status: params.status, page: params.page, pageSize: params.pageSize });
    return PageResponseDto.from(page, UserSummaryResponseDto.from);
  }

  @Get(':id')
  async getDetail(@Param('id') id: string): Promise<UserResponseDto> {
    return UserResponseDto.from(await this.getUserDetail.execute({ userId: id }));
  }

  @Post(':id/withdraw')
  @HttpCode(200)
  async withdraw(@Param('id') id: string, @Body() body: WithdrawUserRequestDto): Promise<void> {
    await this.withdrawUser.execute({ userId: id, reason: body.reason });
  }
}
```

## src/modules/user/testkit/user.testkit.ts

```ts
import { User, type UserSnapshot } from '../domain/user.entity';

export function createTestUser(overrides: Partial<UserSnapshot> = {}): User {
  return User.fromSnapshot({
    id: 'user-1',
    nickname: 'kim',
    status: 'active',
    createdAt: new Date('2026-10-01T00:00:00Z'),
    withdrawnAt: null,
    ...overrides,
  });
}
```

## src/modules/user/user.module.ts

```ts
import { Module } from '@nestjs/common';
import { TransactionHost } from '@nestjs-cls/transactional';
import { AuthModule } from '@/modules/auth';
import { AuthAccountAccessRevoker } from './adapters/out/auth/account-access-revoker.auth.adapter';
import { PrismaUserRepository } from './adapters/out/persistence/user.prisma.repository';
import { UserController } from './adapters/in/http/user.controller';
import { AccountAccessRevoker } from './application/ports/account-access-revoker.port';
import { TransactionRunner } from './application/ports/transaction-runner.port';
import { GetUserDetailUseCase } from './application/usecases/get-detail.usecase';
import { GetUserListUseCase } from './application/usecases/get-list.usecase';
import { WithdrawUserUseCase } from './application/usecases/withdraw.usecase';
import { UserRepository } from './domain/user.repository';

@Module({
  imports: [AuthModule],
  controllers: [UserController],
  providers: [
    GetUserListUseCase,
    GetUserDetailUseCase,
    WithdrawUserUseCase,
    { provide: UserRepository, useClass: PrismaUserRepository },
    { provide: AccountAccessRevoker, useClass: AuthAccountAccessRevoker },
    {
      provide: TransactionRunner,
      useFactory: (txHost: TransactionHost): TransactionRunner => ({ run: (fn) => txHost.withTransaction(fn) }),
      inject: [TransactionHost],
    },
  ],
  exports: [GetUserDetailUseCase],
})
export class UserModule {}
```

## src/modules/user/index.ts

```ts
export {
  type GetUserDetailQuery,
  type GetUserDetailResult,
  GetUserDetailUseCase,
} from './application/usecases/get-detail.usecase';
export { UserNotFoundError } from './domain/user.errors'; // thrown by GetUserDetailUseCase
export { UserModule } from './user.module';
```
