---
paths:
  - "**/pages/**"
---

# Frontend pages layer

A page composes widgets into one screen. Routes map URLs or screens to pages (`rules/frontend/app.md`); pages are organized by domain.

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
- **Next.js:** the route file awaits `params` and passes them to the page as props (`rules/frontend-web/nextjs.md`).
- **Expo:** the page reads params with expo-router's `useLocalSearchParams` (`rules/frontend-native/app.md`).

## What a page does

A page rendered on the client (a React SPA, an Expo app):

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

- **Start the first screen's requests.** A page rendered on the client calls `usePrefetchQuery` above the boundary; a Next.js page prefetches on the server instead (`rules/frontend-web/nextjs.md`). Either way, widgets read the data with `useSuspenseQuery`, joining the request already in flight.
- **Own the boundary.** The page wraps its widgets in `AsyncBoundary` (`rules/frontend/shared.md`), which shows a not-found screen for a `NotFoundError` and a retryable error for anything else.
- **Isolate independent sections.** A section the page can live without gets its own `AsyncBoundary level="section"`, so its failure does not replace the whole screen.
- Data behind a tab or below the fold is fetched by its widget when it renders.
- A page defines no hooks. It calls `usePrefetchQuery` and the router's param hook; a Next.js page calls none, so it stays a server component.

Why prefetch in the page: a component that suspends does not render its children, so a fetching widget that renders a fetching child sends the two requests one after the other. The page composes the widgets, so it is the place that knows what the first screen needs.

## Screen state

Which state survives a reload depends on the platform. In a web app, a page's tab, list filters, sort and page number live in the URL (`rules/frontend-web/routing.md`). A native app has no address bar: route params identify the screen, and the rest is component or store state (`rules/frontend-native/app.md`).

## Only pages

A page folder holds page components and its `index.ts`. Everything a screen draws is a widget, headers included.

## Names

- A page that shows a domain is `{D}{Purpose}Page`: `UserListPage`, `UserDetailPage`.
- A page for an action puts the verb first: `CreateUserPage`.
- A page with no domain takes the screen's name: `HomePage`, `SettingsPage`.

## Pages belong to apps

Monorepo packages never export pages. Each app composes its own pages from the widgets, features and entities packages provide.

## index.ts

Export the page components, plus a page's props type when a route file passes props.

```ts
export { UserListPage } from './UserListPage';
export { UserDetailPage, type UserDetailPageProps } from './UserDetailPage';
export { CreateUserPage } from './CreateUserPage';
```
