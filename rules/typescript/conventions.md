---
paths:
  - "**/*.{ts,tsx}"
  - "**/tsconfig*.json"
---

# TypeScript conventions

## Compiler strictness

Shared tsconfig bases turn on:

```jsonc
{
  "strict": true,
  "noUncheckedIndexedAccess": true,
  "noImplicitOverride": true,
  "noFallthroughCasesInSwitch": true,
  "verbatimModuleSyntax": true
}
```

- Unused variables and imports are caught by Biome (`noUnusedVariables`, `noUnusedImports`), not by `noUnusedLocals`/`noUnusedParameters`, so work-in-progress code still type-checks.
- `noUncheckedIndexedAccess` makes `arr[i]` and `record[key]` include `undefined`; narrow before use.
- `verbatimModuleSyntax` requires `import type` for type-only imports.
- **NestJS servers that use constructor injection** turn off Biome's `useImportType`. Nest reads constructor parameter types from decorator metadata at runtime; rewriting those imports to `import type` erases the class and breaks injection.
- **NestJS servers build CommonJS**, so they turn off `verbatimModuleSyntax`, which rejects ESM syntax in a CommonJS module, and turn on `isolatedModules` to keep files safe for per-file compilers (SWC, Vitest).

## Formatting

Biome formats. Run `biome check --write <files you changed>` instead of adjusting whitespace or quotes by hand; scoping it to your files keeps unrelated files out of the diff. Line width and quote style are set per project in `biome.json`.

## Naming exported values

| Value | Case | Example |
|---|---|---|
| Module-level object declared `as const`, whether its members are values or functions | `SCREAMING_SNAKE` | `URLS`, `USER_QUERY_KEYS`, `MAX_RETRY_COUNT` |
| Members of such an object | `camelCase` | `URLS.detail`, `USER_QUERY_KEYS.detail(id)` |
| Function that builds an adapter or service instance (an object of methods) from injected dependencies | `create{Name}` | `createUserAdapter(http)`, `createUserService(deps)` |
| Type of that instance | `PascalCase`, same name as the instance | `type UserAdapter = ReturnType<typeof createUserAdapter>` |
| Instance, or any other namespace object of functions | `PascalCase` | `UserAdapter`, `UserMapper` |

- An `as const` object used outside its own slice carries a domain prefix (`USER_QUERY_KEYS`). One used only inside its slice does not (`URLS`).
- A value and a type may share a name; TypeScript keeps them in separate spaces. Use that instead of a `Type` suffix.
- The `create` prefix as a function name belongs to functions that build a new object from their arguments: the adapter and service instance builders above, the store helper `createStore`, and testkit factories (`createTestUserEntity(overrides)`). Names for an action put the **verb first**: `CreateUserPayload`, `CreateUserRequestDto`, `CreateUserUseCase`, `CreateUserCommand`. Names for the domain itself carry no verb: `UserEntity`, `userFormSchema()`.
- A name that exists for tests and is shared between test files carries `Test`: `createTestUserEntity`, `createTestQueryClient`. Names local to one test file need not; the file already says it is a test.
- Members of a domain namespace drop the domain the namespace already names: `UserService.create`, `UserService.getList`, `UserAdapter.getDetail`.

```ts
export const createUserAdapter = (http: HttpClient) => ({ /* methods */ });
export type UserAdapter = ReturnType<typeof createUserAdapter>;

export const UserAdapter: UserAdapter = createUserAdapter(httpClient);
```

## Interface or type

| Declares | Use | Example |
|---|---|---|
| A contract for what a function or component receives: component props, use case commands and queries | `interface` | `interface UserCardProps`, `interface CreateUserCommand extends CreateUserPayload { organizationId: string }` |
| The shape of data | `type` | `UserEntity`, value objects, DTOs, `CreateUserPayload`, `CreateUserResult`, read models |

- Props that must be a union (one shape or another) use `type`.
- Augmenting a library's declarations uses `interface`, which is the only form that merges.

## Comments

A comment says why, never what; the code already shows what it does. Comments in project code are English, in plain declarative sentences:

```ts
roles: dto.roles ?? [], // a user the server sends no roles for has none
```

The examples in these rule files keep English comments, matching the rule text.

## File names

Files are kebab-case and end in their role: `{subject}.{role}.ts`. When one subject has several files of the same role, a qualifier goes between them: `{subject}.{qualifier}.{role}.ts`.

```
user.entity.ts   user.mapper.ts   user.adapter.ts
user.dto.ts      user.request.dto.ts      user.response.dto.ts
user.const.ts    user.query-key.const.ts  user.url.const.ts
```

Keeping the role last means one glob (`*.dto.ts`, `*.const.ts`) finds every file of that role, which is what dependency rules and searches match on.

Three kinds of file are named after what they export instead:

- React components: PascalCase, `UserCard.tsx`.
- React hooks: the hook's name, `useUserFilter.ts`.
- A shared helper that exports a single function: its name in kebab-case, `create-store.ts`.
