---
paths:
  - "**/entities/**/infrastructure/**"
  - "**/libs/http/**"
---

# Entity data access

```
entities/{domain}/infrastructure/
├── api/
│   ├── {d}.adapter.ts            create{D}Adapter + the {D}Adapter instance
│   └── {d}.url.const.ts          URLS
├── dto/
│   ├── {d}.dto.ts                the resource shape
│   ├── {d}.request.dto.ts        request bodies and query params
│   └── {d}.response.dto.ts       response wrappers
└── mapper/{d}.mapper.ts          {D}Mapper
```

`infrastructure/` exports exactly one thing through the slice's `index.ts`: the adapter instance (value and type). DTOs, URLs and the mapper are used inside `infrastructure/` only, so the server's wire format never reaches the rest of the app.

Data kept on the device goes through a local adapter beside this one, in `infrastructure/db/` (`rules/frontend/local-data.md`). An entity with both sources exports the two adapter instances, and still nothing else from `infrastructure/`.

## Adapter

```ts
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
});
export type UserAdapter = ReturnType<typeof createUserAdapter>;
export const UserAdapter = createUserAdapter(httpClient); // httpClient from shared/libs/http
```

- **One instance, created in the same file.** The file creates the instance once at module level from the shared `httpClient`; ES modules run once, so the app has exactly one. Tests import `createUserAdapter` from the file and pass the shared client with a fake `fetchFn` (`rules/frontend/testing.md`).
- **In a monorepo package**, the package cannot import the app's `httpClient`. The package exports only `createUserAdapter` and the type; the app's own entities slice creates the instance the same way. App slices export instances; packages export create functions.
- **Domain shapes in, domain shapes out.** Inputs are camelCase domain types; outputs are entities, `PageResult<Entity>`, `Pick<Entity, 'id'>` from a create (the server answers 201 with the id only, `rules/api/contract.md`), or `void` for operations with no result (a delete). The adapter converts requests and responses through the mapper, and reads every body with `unwrap`, so the standard response never reaches the mapper.
- **The adapter is the outer boundary.** There is no repository layer between it and the use cases.
- **Errors pass through untouched.** The adapter has no `try`/`catch`, toasts or `console` calls; the error the HTTP client throws reaches the use case as is. Turning an error into a result (404 → `null`) or into a domain error is the use case's decision, because only it knows what a failure means there.
- **No mock data.** The adapter, mapper, use cases and service never return made-up data or branch on a mock flag. When the backend is not ready, wait for it or keep the change local and uncommitted. A demo mode that is a product feature is a separate implementation of the same type, chosen on the line that creates the instance (`createUserAdapter(httpClient)`), not branches inside the adapter.

## URLs

`api/{d}.url.const.ts` holds path templates, used only by the adapter in the same slice:

```ts
export const URLS = {
  list: '/users',
  detail: '/users/{id}',
} as const;
```

- Placeholders use OpenAPI syntax, `{name}`, so paths copy straight from API docs. Keep each name exactly as the docs write it, snake_case included (`{user_id}` → `pathParams: { user_id: id }`); the `pathParams` object is built inside the adapter, so that casing never leaves infrastructure.
- Prefixes shared by every path (`/api/v1`, a service segment) belong to the HTTP client's base URL.

## HTTP client

The shared client is an arthron 2.1 (or later) client, built once in `shared/libs/http` (or the common package). That folder is the only code that imports `arthron` and the only code that knows the standard response (`rules/api/contract.md`); slices import `httpClient`, `HttpClient` and the helpers below from it. arthron's whole API is in `node_modules/arthron/llms.txt`; read it before using an option this file does not show.

```ts
// shared/libs/http/http.client.ts
export type HttpClient = ArthronClient;

export const httpClient: HttpClient = arthron({
  baseURL: ENV.API_BASE_URL,
  plugins: [apiErrors, retry()], // apiErrors first: it wraps retry, so it sees each call's final outcome
});

// shared/libs/http/api.response.ts
export async function unwrap<T>(call: ResponsePromise): Promise<T> {
  const body = await call.json<ApiResponse<T>>();
  return body.result;
}

// shared/libs/http/api.errors.ts
export const apiErrors = createPlugin({
  pluginName: 'apiErrors',
  async middleware(requestContext, next) {
    try {
      return await next(requestContext);
    } catch (error) {
      if (!isArthronError(error) || error.status === 0) throw error;
      const body = typeof error.payload === 'object' ? (error.payload as Partial<ApiResponse<unknown>> | null) : null;
      throw new ApiError(
        {
          status: error.status,
          errorCode: body?.errorCode ?? null,
          requestId: body?.requestId ?? null,
          message: body?.message ?? error.message,
        },
        { cause: error },
      );
    }
  },
});
```

- `unwrap` lives here because arthron returns the `Response` as the server sent it; opening a backend's response format is the project's job.
- `apiErrors` is middleware placed before `retry()`, so it runs once per call, after the retries. An error interceptor would run on every failed attempt, including one a retry then recovers.
- `ApiError` carries `status`, `errorCode` and `requestId`; its `message` is the server's `message`, for logs. `isApiError` narrows to it. arthron's `description` is not used: what users read is chosen from `errorCode`, never taken from the server.
- With bearer tokens, add `bearerAuth({ tokenOrigins: [ENV.API_BASE_URL], accessTokenFn, refreshFn })` after `apiErrors`; with cookie sessions, set `credentials: 'include'` instead. `tokenOrigins` takes absolute URLs: when `API_BASE_URL` is a path (`/api` behind a dev proxy or a rewrite), the requests go to the page's origin, so list `location.origin`.
- The refresh request, when it goes through `httpClient`, passes `meta: { bearerAuth: false }`. arthron exempts on its own only a request started before `refreshFn`'s first `await`; one started after it carries the expired token, and on a 401 (an expired refresh token, for one) it waits for its own refresh, which never ends.

What the client guarantees:

- **Path values stay in their segment.** `http.get(URLS.detail, { pathParams: { id } })` encodes each value into its own segment; a missing or unused key, `""`, `.` or `..` is a `TypeError` before anything is sent.
- **A forgotten `pathParams` is caught by the adapter test.** arthron does not type `pathParams`, and a call without it sends the braces as written (`/users/{id}`), so the test of each method whose template has a placeholder checks the URL it sends.
- **Query params**: `{ queryParams }` drops `null` and `undefined`, repeats array keys and rejects nested objects. Query strings are always built this way, never concatenated into the path.

Why: an id or name containing `/`, `?` or `#` otherwise calls a different endpoint or truncates the request.

- **Server errors**: `apiErrors` turns an error response into an `ApiError` carrying the status and the server's `errorCode`. Use cases compare `error.errorCode` and never read a body. arthron 2.0 rejected some error responses with a `TypeError` or a `RangeError` instead (a status text that is not Latin-1, such as `500 실패` under Node, or a status past 599), and `apiErrors` let them through; 2.1 makes them `ArthronError`s.
- **Unreachable server**: a request that never reached the server stays an `ArthronError` with `status: 0` (a `TimeoutError` when the project adds `timeout()`), so it is told apart from an `ApiError`.
- **What the client handles itself** (`retry()`, `bearerAuth`'s refresh on 401) is not handled again by adapters, use cases or screens. Which failures the client handles is the project's decision.

A project on another HTTP client gives the same guarantees.

## DTOs

DTO types describe the API contract exactly, in the server's casing: fields the server guarantees are required; only genuinely optional fields are optional.

| File | Holds | Names |
|---|---|---|
| `{d}.dto.ts` | The resource shape, defined once and reused by list and detail | `{D}Dto`; a smaller list shape is `{D}SummaryDto`, with `{D}Dto = {D}SummaryDto & { … }` |
| `{d}.request.dto.ts` | Request bodies and query params | `{Action}{D}RequestDto`, `{D}ListParamsDto` |
| `{d}.response.dto.ts` | Wrappers around the resource | `{D}ListResponseDto` |

- Create only the files the slice needs.
- DTOs describe the standard response's `result`; the keys around it are `unwrap`'s.
- When an endpoint returns the resource unwrapped, use `{D}Dto` directly instead of an alias.
- When the shared HTTP module already defines the pagination wrapper, alias it instead of rewriting it: `type UserListResponseDto = PaginatedDto<UserDto>`.

## Mapper

`mapper/{d}.mapper.ts` is a namespace object of pure functions named `to{ReturnType}`:

```ts
export const UserMapper = {
  toEntity(dto: UserDto): UserEntity {
    return {
      id: required(dto.id, 'user.id'),
      status: required(dto.status, 'user.status'),
      nickname: dto.nickname as Nickname,
      bio: dto.bio ?? null,
      roles: dto.roles ?? [],
      createdAt: Date.parse(dto.createdAt),
    };
  },
  toCreateRequestDto(payload: CreateUserPayload): CreateUserRequestDto { … },
  toListParamsDto(params: UserListParams): UserListParamsDto { … },
};
```

| DTO field | Mapper does |
|---|---|
| Required and essential (id, status, anything without which the entity means nothing) | `required(value, 'path')`: throws a contract error naming the field when it is missing |
| Required, not essential | Assigns it directly |
| Optional | Keeps it as `null` in the entity. Supplies a default only when "absent" and "empty" mean the same thing in the domain |

Why: a server that breaks its contract delivers `undefined` where the type says `string`. Filling `id` with `''` hides that and sends requests to `/users/`; failing on essential fields surfaces it at once.

- An essential embedded object is guarded as a whole, then mapped: `const model = required(dto.model, 'endpoint.model')`.
- Values the server sends were validated by the server, so the mapper brands them with a cast (`nickname: dto.nickname as Nickname`). Value object parse functions validate input the app collects itself.

### Time values

- Instants become **epoch milliseconds** (`number`) in entities: multiply seconds by 1000, parse ISO strings with `Date.parse`.
- Date-only values (birthdays, due dates) become `'YYYY-MM-DD'` strings; a midnight timestamp shifts a day across time zones.
- The mapper produces machine values only. Absolute dates, relative times ("3 seconds ago") and every other display format come from the UI's shared formatter.
