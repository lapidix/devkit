# Example slice: `entities/user`

One complete slice that follows the entity rules. The project uses zod and React Query. Shared helpers come from `@/shared/libs/http` (`HttpClient`, the `httpClient` instance, `unwrap`, `PageResult`, `PaginatedDto`, `toEntityList`, `required`), `@/shared/libs/error`, `@/shared/libs/i18n` (`TranslationKey`) and `@/shared/vo/email.vo` (`Email`, `EmailSchema`); in a package the HTTP helpers come from the common package instead, and the app's entities slice creates the instance. The server follows `rules/api/contract.md`: every body is the standard response, which `unwrap` opens, and fields are camelCase. This API's docs write `{id}`; keep whatever names your docs use.

## infrastructure/dto/user.dto.ts

```ts
/** GET /users/{id} answers with this as `result`; the list reuses it. */
export type UserDto = {
  id: string;
  email: string;
  nickname: string;
  status: 'active' | 'invited' | 'suspended';
  bio?: string | null;
  createdAt: string; // ISO 8601
};
```

## infrastructure/dto/user.request.dto.ts

```ts
import type { UserDto } from './user.dto';

export type CreateUserRequestDto = { email: string; nickname: string; bio?: string };
export type UserListParamsDto = { nickname?: string; status?: UserDto['status']; page?: number; pageSize?: number };
```

## infrastructure/dto/user.response.dto.ts

```ts
import type { PaginatedDto } from '@/shared/libs/http';
import type { UserDto } from './user.dto';

export type UserListResponseDto = PaginatedDto<UserDto>;
```

## infrastructure/api/user.url.const.ts

```ts
export const URLS = {
  list: '/users',
  detail: '/users/{id}',
} as const;
```

## domain/nickname.vo.ts

```ts
import { z } from 'zod';

export type Nickname = z.infer<typeof NicknameSchema>;
export const NICKNAME_PATTERN = /^[a-z0-9_]{2,20}$/;
export const NicknameSchema = z.string().regex(NICKNAME_PATTERN).brand<'Nickname'>();

export function parseNickname(raw: string): Nickname {
  return NicknameSchema.parse(raw);
}
```

Without zod, the same file is:

```ts
export type Nickname = string & { readonly __brand: 'Nickname' };
export const NICKNAME_PATTERN = /^[a-z0-9_]{2,20}$/;

export function parseNickname(raw: string): Nickname {
  if (!NICKNAME_PATTERN.test(raw)) throw new Error(`invalid nickname: ${raw}`);
  return raw as Nickname;
}
```

## domain/user.entity.ts

```ts
import type { Email } from '@/shared/vo/email.vo';
import type { Nickname } from './nickname.vo';

export type UserStatus = 'active' | 'invited' | 'suspended';

export type UserEntity = {
  id: string;
  email: Email;
  nickname: Nickname;
  status: UserStatus;
  bio: string | null;
  createdAt: number; // epoch ms
};

export type CreateUserPayload = Pick<UserEntity, 'email' | 'nickname' | 'bio'>;
export type UpdateUserPayload = Partial<Pick<UserEntity, 'nickname' | 'bio'>>;

export function canSuspend(user: UserEntity): boolean {
  return user.status === 'active';
}

export function canResendInvite(user: UserEntity): boolean {
  return user.status === 'invited';
}
```

## constants/user.const.ts

```ts
export const USER_BIO_MAX_LENGTH = 200;
```

## constants/user.message.const.ts

```ts
import type { TranslationKey } from '@/shared/libs/i18n';

export const USER_MESSAGES = {
  bioMax: 'user.validation.bioMax',
  emailTaken: 'user.errors.emailTaken',
  created: 'user.toast.created',
  deleted: 'user.toast.deleted',
} as const satisfies Record<string, TranslationKey>;
```

## errors/user.errors.ts

```ts
import { NotFoundError, ValidationError } from '@/shared/libs/error';

export class UserEmailTakenError extends ValidationError {}
export class UserNotFoundError extends NotFoundError {}
```

## schema/user.form.schema.ts

```ts
import { z } from 'zod';
import { EmailSchema } from '@/shared/vo/email.vo';
import { USER_BIO_MAX_LENGTH } from '../constants/user.const';
import { USER_MESSAGES } from '../constants/user.message.const';
import { NicknameSchema } from '../domain/nickname.vo';

/** One schema for create and edit. An edit form narrows it: userFormSchema().pick({ nickname: true, bio: true }). */
export const userFormSchema = (options?: { bioMaxLength?: number }) =>
  z.object({
    email: EmailSchema,
    nickname: NicknameSchema,
    bio: z.string().max(options?.bioMaxLength ?? USER_BIO_MAX_LENGTH, USER_MESSAGES.bioMax).nullable(),
  });

export type UserFormValues = z.input<ReturnType<typeof userFormSchema>>;
```

## types/user.types.ts

```ts
import type { UserStatus } from '../domain/user.entity';

export type UserListParams = { nickname?: string; status?: UserStatus; page?: number; pageSize?: number };
```

## infrastructure/mapper/user.mapper.ts

```ts
import { required } from '@/shared/libs/http';
import type { Email } from '@/shared/vo/email.vo';
import type { Nickname } from '../../domain/nickname.vo';
import type { CreateUserPayload, UserEntity } from '../../domain/user.entity';
import type { UserListParams } from '../../types/user.types';
import type { UserDto } from '../dto/user.dto';
import type { CreateUserRequestDto, UserListParamsDto } from '../dto/user.request.dto';

export const UserMapper = {
  toEntity(dto: UserDto): UserEntity {
    return {
      id: required(dto.id, 'user.id'),
      status: required(dto.status, 'user.status'),
      email: dto.email as Email, // validated by the server
      nickname: dto.nickname as Nickname,
      bio: dto.bio ?? null,
      createdAt: Date.parse(dto.createdAt),
    };
  },
  toCreateRequestDto(payload: CreateUserPayload): CreateUserRequestDto {
    return { email: payload.email, nickname: payload.nickname, bio: payload.bio ?? undefined };
  },
  toListParamsDto(params: UserListParams): UserListParamsDto {
    return { nickname: params.nickname, status: params.status, page: params.page, pageSize: params.pageSize };
  },
};
```

## infrastructure/api/user.adapter.ts

```ts
import { type HttpClient, httpClient, type PageResult, toEntityList, unwrap } from '@/shared/libs/http';
import type { CreateUserPayload, UserEntity } from '../../domain/user.entity';
import type { UserListParams } from '../../types/user.types';
import type { UserDto } from '../dto/user.dto';
import type { UserListResponseDto } from '../dto/user.response.dto';
import { UserMapper } from '../mapper/user.mapper';
import { URLS } from './user.url.const';

export const createUserAdapter = (http: HttpClient) => ({
  async getList(params: UserListParams): Promise<PageResult<UserEntity>> {
    const dto = await unwrap<UserListResponseDto>(http.get(URLS.list, { queryParams: UserMapper.toListParamsDto(params) }));
    return toEntityList(dto, UserMapper.toEntity);
  },
  async getDetail(id: string): Promise<UserEntity> {
    const dto = await unwrap<UserDto>(http.get(URLS.detail, { pathParams: { id } }));
    return UserMapper.toEntity(dto);
  },
  async create(payload: CreateUserPayload): Promise<Pick<UserEntity, 'id'>> {
    return unwrap<Pick<UserEntity, 'id'>>(http.post(URLS.list, UserMapper.toCreateRequestDto(payload)));
  },
  async delete(id: string): Promise<void> {
    await http.delete(URLS.detail, { pathParams: { id } });
  },
});

export type UserAdapter = ReturnType<typeof createUserAdapter>;
export const UserAdapter = createUserAdapter(httpClient);
```

## constants/user.query-key.const.ts

```ts
import type { UserListParams } from '../types/user.types';

export const USER_QUERY_KEYS = {
  all: () => ['user'] as const,
  lists: () => [...USER_QUERY_KEYS.all(), 'list'] as const,
  list: (params: UserListParams) => [...USER_QUERY_KEYS.lists(), params] as const,
  details: () => [...USER_QUERY_KEYS.all(), 'detail'] as const,
  detail: (id: string) => [...USER_QUERY_KEYS.details(), id] as const,
} as const;
```

## testkit/user.testkit.ts

```ts
import type { Email } from '@/shared/vo/email.vo';
import type { Nickname } from '../domain/nickname.vo';
import type { UserEntity } from '../domain/user.entity';

export function createTestUserEntity(overrides: Partial<UserEntity> = {}): UserEntity {
  return {
    id: 'user-1',
    email: 'kim@example.com' as Email,
    nickname: 'kim' as Nickname,
    status: 'active',
    bio: null,
    createdAt: Date.parse('2026-10-17T00:00:00Z'),
    ...overrides,
  };
}
```

## infrastructure/api/user.adapter.test.ts

```ts
import { describe, expect, it, vi } from 'vitest';
import { httpClient } from '@/shared/libs/http';
import type { UserDto } from '../dto/user.dto';
import { createUserAdapter } from './user.adapter';

const dto: UserDto = { id: 'user-1', email: 'kim@example.com', nickname: 'kim', status: 'active', createdAt: '2026-10-17T00:00:00Z' };

function fakeFetch(result: unknown) {
  return vi.fn<typeof fetch>(async () =>
    Response.json({ result, message: null, timestamp: '2026-10-17T00:00:00Z', requestId: 'req-1', errorCode: null }),
  );
}

const adapterOn = (fetchFn: typeof fetch) => createUserAdapter(httpClient.extend({ baseURL: 'https://api.test/api', fetchFn }));

describe('createUserAdapter', () => {
  it('maps the list to entities with the sign-up time in milliseconds', async () => {
    const fetchFn = fakeFetch({ items: [dto], total: 1, page: 1, pageSize: 20 });

    const page = await adapterOn(fetchFn).getList({ pageSize: 20 });

    expect(fetchFn.mock.calls[0]?.[0]).toBe('https://api.test/api/users?pageSize=20');
    expect(page.items[0]?.createdAt).toBe(Date.parse(dto.createdAt));
  });

  it('puts the id in the path for the detail and the delete', async () => {
    const fetchFn = fakeFetch(dto);

    await adapterOn(fetchFn).getDetail('user-1');
    await adapterOn(fetchFn).delete('user-1');

    expect(fetchFn.mock.calls.map(([url]) => url)).toEqual(['https://api.test/api/users/user-1', 'https://api.test/api/users/user-1']);
  });
});
```

## index.ts

```ts
export { USER_BIO_MAX_LENGTH } from './constants/user.const';
export { USER_MESSAGES } from './constants/user.message.const';
export { USER_QUERY_KEYS } from './constants/user.query-key.const';
export { type Nickname, NicknameSchema, parseNickname } from './domain/nickname.vo';
export {
  canResendInvite,
  canSuspend,
  type CreateUserPayload,
  type UpdateUserPayload,
  type UserEntity,
  type UserStatus,
} from './domain/user.entity';
export { UserEmailTakenError, UserNotFoundError } from './errors/user.errors';
export { UserAdapter } from './infrastructure/api/user.adapter';
export { userFormSchema, type UserFormValues } from './schema/user.form.schema';
export type { UserListParams } from './types/user.types';
```
