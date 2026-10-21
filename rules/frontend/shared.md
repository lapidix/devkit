---
paths:
  - "**/shared/**"
---

# Frontend shared layer

Shared holds what every layer may use and that knows no domain. It never imports from entities, features, widgets, pages or app, and it never names a domain: anything that mentions users, orders or projects belongs in an entity or above.

## Structure

```
shared/
├── libs/
│   ├── http/                     httpClient (arthron), HttpClient, unwrap, ApiError, required, toEntityList
│   ├── client/query.client.ts    getQueryClient; other library clients sit beside it (socket.client.ts)
│   ├── i18n/                     TranslationKey, zod.error-map.ts (rules/frontend/i18n.md)
│   ├── router/                   useSearchParamState
│   ├── store/create-store.ts     createStore, when the project does not use Zustand
│   ├── error/common.errors.ts    NotFoundError, ValidationError and other shared error classes
│   └── boundary/AsyncBoundary.tsx
├── store/                        stores that belong to no domain (rules/frontend/state.md)
├── ui/                           generic components and the boundary fallbacks
├── utils/                        pure functions
├── config/env.config.ts          the only place that reads environment variables
├── constants/                    common.message.const.ts: COMMON_MESSAGES (rules/frontend/i18n.md)
├── types/
└── vo/                           value objects whose rules come from an external standard
```

| Folder | Holds |
|---|---|
| `libs/` | The technical base the whole app relies on: the HTTP client set up for the project's API (`http`, `rules/frontend/entity-data-access.md`), the clients and setup of external libraries (`client`, `i18n`, `router`), and domain-free shared behavior (`store`, `error`, `boundary`) |
| `utils/` | Pure functions with no state or setup: formatters, `cn` |
| `ui/` | Things drawn on screen. Same folder layout as entity and feature `ui/`: flat, grouped by the project's kind list past roughly ten files |

Standard value objects in `vo/` follow `rules/frontend/entities.md`.

## libs/client

`client/` holds the instances of external library clients, one `{subject}.client.ts` each. The HTTP client stays in `http/`, with the response and error handling the project's API needs.

```ts
// shared/libs/client/query.client.ts
function makeQueryClient() {
  return new QueryClient({
    defaultOptions: { queries: { /* product values */ }, mutations: { /* product values */ } },
    mutationCache: new MutationCache({ /* default reactions, rules/frontend/react-query.md */ }),
  });
}

let browserQueryClient: QueryClient | undefined;

export function getQueryClient() {
  if (typeof window === 'undefined') return makeQueryClient();
  return (browserQueryClient ??= makeQueryClient());
}
```

- The server builds a new client per request, so users never share a cache.
- The browser keeps one. A client created with `useState` in the provider can be discarded when a component suspends during the first render, and every query restarts.
- In Next.js, where pages prefetch on the server without awaiting, the client also hands over queries that are still pending, so their results stream to the browser:
  ```ts
  defaultOptions: {
    dehydrate: {
      shouldDehydrateQuery: (query) => defaultShouldDehydrateQuery(query) || query.state.status === 'pending',
    },
  },
  ```
  Give queries a `staleTime` above zero there too; with `0`, the browser refetches everything right after hydration.

## libs/router

URL state (a page's tab, list filters, sort, page number) goes through one hook:

```ts
const [tab, setTab] = useSearchParamState('tab', { defaultValue: 'overview' });
```

It owns the rules every URL state shares: the default value is not written to the URL, changing state replaces the history entry instead of pushing one, and numbers are parsed.

## libs/error and libs/boundary

```ts
// shared/libs/error/common.errors.ts
export class NotFoundError extends Error {}
export class ValidationError extends Error {}

// entities/user/errors/user.errors.ts
export class UserNotFoundError extends NotFoundError {}
export class UserEmailTakenError extends ValidationError {}
```

Entity errors extend these, so shared code recognizes the kind of failure from any domain without importing it:

- `NotFoundError`: `AsyncBoundary` shows the not-found screen.
- `ValidationError`: a value the server rejected, which a form shows on its field (`rules/frontend/forms-rhf-zod.md`). The default failure reaction skips it.

Text from the server never reaches the screen. The default failure reaction and `ErrorFallback` show translated text chosen by the kind of failure (unreachable server → `common.errors.network`, 403 → `common.errors.forbidden`, 5xx → `common.errors.server`, anything else → `common.errors.unknown`, all from `COMMON_MESSAGES`), and that mapping lives in one function in `libs/error`. Callers never rebuild it with `error instanceof Error ? error.message : …`.

`AsyncBoundary` combines a Suspense boundary, React Query's `QueryErrorResetBoundary` and an error boundary:

```tsx
<AsyncBoundary pending={<PageSkeleton />}>…</AsyncBoundary>
<AsyncBoundary level="section" pending={<SectionSkeleton />}>…</AsyncBoundary>
```

- `level="page"` (the default) renders `NotFoundFallback` for a `NotFoundError` and `ErrorFallback` with a retry for anything else.
- `level="section"` renders `ErrorFallback` for that section only.
- `NotFoundFallback` and `ErrorFallback` live in `shared/ui`; how they look is the product's decision.

## config/env.config.ts

```ts
export const ENV = {
  API_BASE_URL: import.meta.env.VITE_API_BASE_URL,
} as const;
```

No other file reads `import.meta.env` or `process.env`. Variable prefixes follow the framework (`rules/monorepo/env.md`).
