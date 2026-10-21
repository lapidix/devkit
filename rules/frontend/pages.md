---
paths:
  - "**/pages/**"
---

# Frontend pages layer

A page composes widgets into one screen. Routes map URLs to pages (`rules/frontend/app.md`); pages are organized by domain.

## Folders follow the domain

A page lives in `pages/{domain}/`, using the same name as the domain's entity and feature slices; one folder holds every page of that domain. A screen with no domain, or one that combines several, takes the screen's name.

```
pages/user/UserListPage.tsx
pages/user/UserDetailPage.tsx
pages/user/CreateUserPage.tsx
pages/home/HomePage.tsx
pages/dashboard/DashboardPage.tsx
```

URLs, including scope prefixes such as `/organizations/:organizationId/…`, are the routes' concern; renaming a URL never moves a page.

## Route params

- **React SPA:** the page reads params with the router's `useParams`.
- **Next.js:** the route file awaits `params` and passes them to the page as props (`rules/frontend/app.md`).

## What a page does

React SPA:

```tsx
export function UserDetailPage() {
  const { id } = useParams();
  usePrefetchQuery(UserQueries.detail({ id }));
  usePrefetchQuery(UserQueries.activity({ id }));

  return (
    <AsyncBoundary pending={<PageSkeleton />}>
      <UserDetailPanel userId={id} actions={<SuspendUserButton userId={id} />} />
      <AsyncBoundary level="section" pending={<SectionSkeleton />}>
        <UserActivitySection userId={id} />
      </AsyncBoundary>
    </AsyncBoundary>
  );
}
```

Next.js, where the page is a server component with no `'use client'`:

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

- **Start the first screen's requests.** A React SPA page calls `usePrefetchQuery` above the boundary. A Next.js page prefetches on the server and hands the result over through `HydrationBoundary`; the HTTP client must then work on the server too (base URL, forwarded cookies). Either way, widgets read the data with `useSuspenseQuery`, joining the request already in flight.
- **Own the boundary.** The page wraps its widgets in `AsyncBoundary` (`rules/frontend/shared.md`), which shows a not-found screen for a `NotFoundError` and a retryable error for anything else.
- **Isolate independent sections.** A section the page can live without gets its own `AsyncBoundary level="section"`, so its failure does not replace the whole screen.
- Data behind a tab or below the fold is fetched by its widget when it renders.
- A page defines no hooks. A React SPA page calls `usePrefetchQuery`; a Next.js page calls no hooks, so it stays a server component.

Why prefetch in the page: a component that suspends does not render its children, so a fetching widget that renders a fetching child sends the two requests one after the other. The page composes the widgets, so it is the place that knows what the first screen needs.

## State in the URL

| In the URL: must survive sharing a link and reloading | In the component |
|---|---|
| The page's tab (`?tab=usage`) | Tabs inside a drawer or dialog |
| List filters, sort and page number | Form wizard steps |
| | Momentary state such as expanded or collapsed |

URL state is read and written with `useSearchParamState` from `shared/libs/router`.

## Only pages

A page folder holds page components and its `index.ts`. Everything a screen draws is a widget, headers included.

## Names

- A page that shows a domain is `{D}{Purpose}Page`: `UserListPage`, `UserDetailPage`.
- A page for an action puts the verb first: `CreateUserPage`.
- A page with no domain takes the screen's name: `HomePage`, `SettingsPage`.

## Pages belong to apps

Monorepo packages never export pages. Each app composes its own pages from the widgets, features and entities packages provide.

## index.ts

Export the page components, plus a page's props type when a Next.js route file passes props.

```ts
export { UserListPage } from './UserListPage';
export { UserDetailPage, type UserDetailPageProps } from './UserDetailPage';
export { CreateUserPage } from './CreateUserPage';
```
