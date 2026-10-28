---
paths:
  - "**/*.test.{ts,tsx}"
  - "**/testkit/**"
  - "**/vitest.config.*"
  - "**/entities/**"
  - "**/features/**"
  - "**/shared/libs/**"
---

# Frontend tests

## Tools, files and names

- Vitest. How components are rendered in tests depends on the platform: `rules/frontend-web/testing.md`, `rules/frontend-native/testing.md`.
- A test sits beside its source: `user.adapter.ts` and `user.adapter.test.ts`. No `__tests__/` folders.
- Test names are English sentences that state the behavior that must hold, not the implementation: `it('converts the creation time to milliseconds')`, not `it('calls toEntity')`.

## What to test

Test code that makes decisions. Code that only forwards or composes has nothing to decide.

| Code | Test it |
|---|---|
| entities: behavior functions, value objects, mapper, form schema | Yes |
| entities: adapter, with the shared client on a fake `fetchFn` | Yes |
| features: use cases, with fake adapters in `deps` | Yes |
| features: decisions a hook makes, kept in plain functions beside it (`toFieldError`, `toCreateUserCommand`) | Yes |
| `shared/libs` | Yes |
| features: service, `{D}Queries`, `{D}Mutations` | No |
| components, widgets, pages | Only for branching logic of their own |

When you create or change code in a "Yes" row, create or update its tests in the same change. End-to-end tests are the project's decision.

## Fakes

- Inject fakes through arguments: `CreateUserUseCase.execute({ user, organization }, command)`. An adapter gets the shared client with a fake `fetchFn`, `createUserAdapter(httpClient.extend({ baseURL: 'https://api.test', fetchFn }))`, so the path, the query and `unwrap` run as they do in the app; `globalThis.fetch` is never stubbed. Each method whose URL template has a placeholder gets a test that checks the URL it sends: arthron sends a forgotten `pathParams` as literal braces, and nothing else catches it.
- `vi.mock` only replaces boundaries we don't own, such as the i18n library or the router. Needing it for our own module means that module does not take its dependencies as arguments.
- A hook reaches module-level instances (`UserMutations` → `UserService` → `UserAdapter`), so it cannot take fakes. Keep its decisions in exported plain functions beside it and test those; the hook only wires React to them.
- Type a fake with `satisfies`, never `as unknown as`.
- Test data comes from the entity's testkit: `createTestUserEntity({ status: 'suspended' })`. Names shared between test files carry `Test` (`rules/typescript/conventions.md`).
- A test that renders React Query gets a new `QueryClient` with `retry: false` per test (`createTestQueryClient()` when it is a shared helper).

A use case's `deps` names only the methods it calls (`rules/frontend/features.md`), so a fake holds only those:

```ts
const user = { create: vi.fn().mockResolvedValue({ id: 'user-1' }) } satisfies Pick<UserAdapter, 'create'>;
const organization = { getDetail: vi.fn().mockResolvedValue({ remainingSeats: 0 }) } satisfies Pick<OrganizationAdapter, 'getDetail'>;

await expect(CreateUserUseCase.execute({ user, organization }, command)).rejects.toThrow(OrganizationSeatLimitExceededError);
```

## Coverage

Coverage measures the "Yes" rows only:

```ts
// vitest.config.ts
coverage: {
  include: ['src/entities/**', 'src/features/**/usecases/**', 'src/features/**/hooks/**', 'src/shared/libs/**'],
  exclude: [
    '**/*.test.{ts,tsx}', '**/testkit/**', '**/index.ts',
    '**/*.service.ts', '**/*.queries.ts', '**/*.mutations.ts', '**/ui/**',
  ],
  thresholds: { /* just below the measured values */ },
},
```

- Files with no logic stay out. Counting them raises the number without adding any safety.
- Thresholds ratchet: set them just below the measured values, raise them when tests are added, and state the reason when lowering one.
