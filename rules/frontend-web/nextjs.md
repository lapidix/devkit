---
paths:
  - "**/*.tsx"
  - "**/pages/**"
  - "**/*query.client.ts"
---

# Next.js

What changes when the frontend rules run on Next.js with server components. The route layout is in `rules/frontend-web/app.md`.

## Server and client components

- `'use client'` goes on widgets and on feature components that use hooks: the outermost components that need hooks or interaction. Pages, layouts and route files stay server components; a page prefetches on the server instead of calling hooks.
- A server component inside a client component arrives as a slot (`children` or a prop), never as an import.

Why: everything a client component imports becomes client code and re-renders with it. A server component passed as a slot is rendered once on the server and stays that way when the client component re-renders.

## A page

The route file awaits `params` and passes them to the page as props (`rules/frontend-web/app.md`). The page is a server component with no `'use client'`:

```tsx
export function UserDetailPage({ userId }: UserDetailPageProps) {
  const queryClient = getQueryClient();
  void queryClient.prefetchQuery(UserQueries.detail({ id: userId })); // not awaited: the result streams in

  return (
    <HydrationBoundary state={dehydrate(queryClient)}>
      <AsyncBoundary pending={<PageSkeleton />}>
        <UserDetailPanel userId={userId} />
      </AsyncBoundary>
    </HydrationBoundary>
  );
}
```

- The page prefetches on the server and hands the result over through `HydrationBoundary`; the HTTP client must then work on the server too (base URL, forwarded cookies). Widgets read the data with `useSuspenseQuery`, joining the request already in flight.
- A Next.js page calls no hooks, so it stays a server component.
- The page's `index.ts` exports its props type, which the route file passes.

## The query client

`getQueryClient` (`rules/frontend/shared.md`) builds a new client per request on the server, so users never share a cache, and keeps one in the browser.

The client also hands over queries that are still pending, so their results stream to the browser:

```ts
defaultOptions: {
  dehydrate: {
    shouldDehydrateQuery: (query) => defaultShouldDehydrateQuery(query) || query.state.status === 'pending',
  },
},
```

Give queries a `staleTime` above zero too; with `0`, the browser refetches everything right after hydration.
