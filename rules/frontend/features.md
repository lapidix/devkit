---
paths:
  - "**/features/**"
---

# Frontend features layer

A feature slice holds one domain's use cases, the service that exposes them, the React bindings, and the UI that performs the domain's actions. React Query specifics are in `rules/frontend/react-query.md`.

## Slices are domains

Name a slice after its domain: `features/user`, `features/post`. Only an app capability that belongs to no single domain is named after the capability: `features/sync`, `features/notification`.

Actions are files inside the slice, not slices of their own: `usecases/create.usecase.ts`, `hooks/useCreateUserForm.ts` and `ui/CreateUserForm.tsx` share the action's name. Why: the service, the queries and the mutations each gather a whole domain, and an action-per-slice layout cannot gather them because sibling slices never import each other.

## Slice structure

```
features/{domain}/
├── usecases/
│   ├── create.usecase.ts         CreateUserUseCase + CreateUserCommand + CreateUserResult
│   ├── get-list.usecase.ts       GetUserListUseCase + GetUserListQuery + GetUserListResult
│   └── find.usecase.ts           a read that may find nothing
├── services/{d}.service.ts       createUserService + the UserService instance
├── operations/
│   ├── {d}.queries.ts            UserQueries: query options
│   └── {d}.mutations.ts          UserMutations: mutation options
├── hooks/                        UI hooks only: useCreateUserForm.ts, useUserFilter.ts
├── ui/                           components that perform one action
└── index.ts                      public API
```

## Use cases

Every use case has its own file, named by the verb without the domain the folder already names: `create.usecase.ts`, `update.usecase.ts`, `get-list.usecase.ts`, `get-detail.usecase.ts`. Each file exports the use case and its types.

```ts
// features/user/usecases/create.usecase.ts
export interface CreateUserCommand extends CreateUserPayload {
  organizationId: string;
}
export type CreateUserResult = Pick<UserEntity, 'id'>;

export const CreateUserUseCase = {
  async execute(
    deps: { user: Pick<UserAdapter, 'create'>; organization: Pick<OrganizationAdapter, 'getDetail'> },
    command: CreateUserCommand,
  ): Promise<CreateUserResult> {
    userFormSchema().parse(command);
    const organization = await deps.organization.getDetail(command.organizationId);
    if (organization.remainingSeats === 0) throw new OrganizationSeatLimitExceededError();
    try {
      return await deps.user.create(command);
    } catch (error) {
      if (isApiError(error) && error.errorCode === 'USER_EMAIL_TAKEN') throw new UserEmailTakenError();
      throw error;
    }
  },
};
```

- **Names.** Writes take a `{Verb}{D}Command`, reads a `{Verb}{D}Query`; both return a `{Verb}{D}Result`, an alias even when it equals the entity type. The use case is `{Verb}{D}UseCase` with one method, `execute`.
- **Commands and queries are interfaces that extend entity types** and add only the context the call needs (`organizationId`).
- **`deps` names only the adapter methods this use case calls**, with `Pick`. The file imports only the adapters' types; the service passes the instances. The type shows exactly what the use case depends on, and a test fake holds only those methods (`rules/frontend/testing.md`).
- **Validate first.** The use case checks its command with the entity's form schema before calling an adapter. A failure there means invalid data got past the form, so the schema's message keys are not shown to anyone.
- **The use case interprets errors.** It translates server errors it knows into the entity's domain errors and rethrows everything else.
- **`get` must find; `find` may not.** A `get…` use case throws `{D}NotFoundError` when the resource is missing. A read that can legitimately find nothing is its own `find…` use case returning `null`. Most domains need only `get`.

## Service

```ts
// features/user/services/user.service.ts
export const createUserService = (deps: { user: UserAdapter; organization: OrganizationAdapter }) => ({
  create: (command: CreateUserCommand) => CreateUserUseCase.execute(deps, command),
  getList: (query: GetUserListQuery) => GetUserListUseCase.execute(deps, query),
});
export type UserService = ReturnType<typeof createUserService>;
export const UserService = createUserService({ user: UserAdapter, organization: OrganizationAdapter });
```

- The service is always there, even when a method only forwards. It binds the adapter instances to the use cases once, so `UserQueries` and `UserMutations` call `UserService.create(command)` without assembling `deps`.
- One method per use case. The method name is the use case file name in camelCase: `get-list.usecase.ts` → `getList`.
- The file creates the single instance from the entities' adapter instances. In a monorepo package, export only `createUserService` and its type; the app's features slice creates the instance.

## operations/

`{d}.queries.ts` (`UserQueries`) and `{d}.mutations.ts` (`UserMutations`) connect React Query to the service. They hold query and mutation options, not hooks: components pass them to `useSuspenseQuery` and `useMutation`, and a Next.js page passes them to a server-side prefetch. Their rules are in `rules/frontend/react-query.md`.

## hooks/

`hooks/` holds hooks only, named after what they are:
  - the flow of one action: `use{Verb}{D}{Thing}`, as in `useCreateUserForm`, `useSuspendUserConfirm`
  - UI state about the domain: `use{D}{Thing}`, as in `useUserFilter`, `useUserSelection`

## ui/

| Where | What | Example |
|---|---|---|
| `entities/{d}/ui` | Domain atoms; props only | `UserStatusBadge` |
| `features/{d}/ui` | A component that performs one domain action; it may use the domain's queries and mutations | `CreateUserForm`, `SuspendUserButton`, `UserFilterBar` |
| `widgets` | A section of a screen that composes entity and feature UI | the user list section |

- Keep `ui/` flat. When it passes roughly ten files, group by kind, choosing folder names only from one list of kind names that the project defines; every slice uses the same list.
- A sub-component used by one component stays in that file, or sits beside it named with the parent's prefix: `CreateUserFormFields.tsx`.
- The same layout applies to `entities/{d}/ui`.

## index.ts

An explicit list of named exports; types use `export type`.

```ts
export { UserQueries } from './operations/user.queries';
export { UserMutations } from './operations/user.mutations';
export { useUserFilter } from './hooks/useUserFilter';
export { CreateUserForm } from './ui/CreateUserForm';
export type { CreateUserCommand, CreateUserResult } from './usecases/create.usecase';
export type { GetUserListQuery, GetUserListResult } from './usecases/get-list.usecase';
```

`UserService`, the use cases and hooks used only inside the slice stay out of it. Why the service stays inside: calling `UserService.create()` from outside skips the cache updates in `UserMutations`, and screens keep showing stale lists. Export it only when code outside React genuinely needs it.
