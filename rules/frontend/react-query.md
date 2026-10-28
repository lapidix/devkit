---
paths:
  - "**/*.queries.ts"
  - "**/*.mutations.ts"
  - "**/*.query-key.const.ts"
  - "**/features/*/operations/**"
  - "**/*query.client.ts"
---

# React Query

## Query keys

Keys live in the entity: `entities/{d}/constants/{d}.query-key.const.ts`.

```ts
export const USER_QUERY_KEYS = {
  all: () => ['user'] as const,
  lists: () => [...USER_QUERY_KEYS.all(), 'list'] as const,
  list: (params: UserListParams) => [...USER_QUERY_KEYS.lists(), params] as const,
  details: () => [...USER_QUERY_KEYS.all(), 'detail'] as const,
  detail: (id: string) => [...USER_QUERY_KEYS.details(), id] as const,
} as const;
```

- Every key extends `all()`, so a prefix invalidates a whole group.
- Every input that changes the response goes into the key, including scope sent in headers (cluster, project).
- Keys are always built through this object.

Why keys live in entities: a mutation in one feature invalidates another domain's keys. Features can import any entity, but not a sibling feature.

## Queries

`features/{d}/operations/{d}.queries.ts` gathers the domain's query options. There are no hand-written query hooks.

```ts
export const UserQueries = {
  list: (query: GetUserListQuery) =>
    queryOptions({ queryKey: USER_QUERY_KEYS.list(query), queryFn: () => UserService.getList(query) }),
  detail: (query: GetUserDetailQuery) =>
    queryOptions({ queryKey: USER_QUERY_KEYS.detail(query.id), queryFn: () => UserService.getDetail(query) }),
};

// widget
const { data } = useSuspenseQuery(UserQueries.list({ page: 1 }));
// page (React SPA)
usePrefetchQuery(UserQueries.detail({ id }));
```

- Reads use `useSuspenseQuery`, so a widget renders with its data present; loading and errors are handled by the boundaries the page sets up.
- The page starts the first screen's requests: `usePrefetchQuery` in a page rendered on the client (`rules/frontend/pages.md`), a server-side `prefetchQuery` in Next.js (`rules/frontend-web/nextjs.md`).

Why options instead of hooks: a hook that bundled every read would run every query the moment it is called, and the same options serve `useSuspenseQuery`, `usePrefetchQuery`, `useQueries` and server prefetching.

## Mutations

`features/{d}/operations/{d}.mutations.ts` gathers the domain's mutation options, the counterpart of `UserQueries`.

```ts
export const UserMutations = {
  create: () =>
    mutationOptions({
      mutationFn: (command: CreateUserCommand) => UserService.create(command),
      onSuccess: (_created, _command, _result, { client }) =>
        client.invalidateQueries({ queryKey: USER_QUERY_KEYS.lists() }),
      meta: { successMessage: USER_MESSAGES.created },
    }),
  remove: () =>
    mutationOptions({
      mutationFn: (command: DeleteUserCommand) => UserService.delete(command),
      onSuccess: (_data, _command, _result, { client }) =>
        client.invalidateQueries({ queryKey: USER_QUERY_KEYS.lists() }),
      meta: { successMessage: USER_MESSAGES.deleted },
    }),
};

// a component
const create = useMutation(UserMutations.create());
```

- Callbacks invalidate through the client they receive (`{ client }`), so the options need no hook. That needs a TanStack Query v5 release with `mutationOptions` and the callback context; on an older release, call `getQueryClient()` (`rules/frontend/shared.md`) instead.
- A screen creates only the mutations it uses.

## Reacting to success and failure

| Layer | Does | Where |
|---|---|---|
| Data consistency | What must happen after every call, on any screen: invalidations, cache updates | `onSuccess` in `{D}Mutations` |
| Screen reaction | What this screen does: close a drawer, navigate, set form field errors | the caller: `mutate(command, { onSuccess, onError })`, or an action-flow hook |
| Defaults | Success toast from `meta.successMessage`; a failure toast for errors no screen handled | the app's `QueryClient` |

```ts
// the caller
create.mutate(command, { onSuccess: ({ id }) => navigate(`/users/${id}`) });

// makeQueryClient in shared/libs/client/query.client.ts (rules/frontend/shared.md)
new QueryClient({
  mutationCache: new MutationCache({
    onSuccess: (_data, _vars, _ctx, mutation) => {
      if (mutation.meta?.successMessage) { /* show translated meta.successMessage with the app's toast */ }
    },
    onError: (error, _vars, _ctx, mutation) => {
      if (error instanceof ValidationError) return; // a form shows it on its field
      if (mutation.meta?.handlesError) return; // the screen handles this failure itself
      /* show a failure toast with the app's toast */
    },
  }),
});

// typing meta once
declare module '@tanstack/react-query' {
  interface Register {
    mutationMeta: { successMessage?: TranslationKey; handlesError?: boolean }; // TranslationKey from shared/libs/i18n
  }
}
```

Why three layers: cache consistency left to screens gets forgotten on one of them, and screen reactions placed in the domain's mutation options would have to know every screen that uses them.

The default reaction runs before the caller's `onError`. That is why a field error is recognized by its class (`ValidationError`, `rules/frontend/shared.md`) rather than by the screen, and why `handlesError` turns off the default for every failure of that mutation.
