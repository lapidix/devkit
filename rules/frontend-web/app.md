---
paths:
  - "**/src/app/**"
  - "**/src/App.tsx"
  - "**/src/index.tsx"
  - "**/app/**"
  - "**/pages/README.md"
---

# Web app layer

The app layer's job is in `rules/frontend/app.md`. This file lays it out for a React SPA and for Next.js.

## React SPA

```
src/
├── index.tsx                     imports global styles and renders <App />
├── App.tsx                       stacks the providers and creates the router
└── app/
    ├── providers/
    │   ├── tanstack-query-provider/TanstackQueryProvider.tsx + index.ts
    │   └── i18n-provider/I18nProvider.tsx + index.ts
    ├── routes/
    │   ├── index.ts              gathers route groups per layout
    │   ├── users/users.route.ts
    │   ├── auth/auth.route.ts
    │   └── error/error.route.ts
    ├── layouts/
    │   ├── main/MainLayout.tsx + index.ts
    │   └── auth/AuthLayout.tsx + index.ts
    └── styles/index.css
```

`App.tsx` stacks the providers.

## Next.js

```
app/                              Next.js routes, kept thin
├── layout.ts                     export { RootLayout as default } from '@/app/layouts/root'
├── (main)/
│   ├── layout.ts                 export { MainLayout as default } from '@/app/layouts/main'
│   └── users/
│       ├── page.ts               export { UserListPage as default } from '@/pages/user'
│       └── [id]/page.tsx         reads params, renders <UserDetailPage userId={id} />
pages/README.md                   keeps Next.js from reading src/pages as the Pages Router
src/app/
├── providers/
├── layouts/root/RootLayout.tsx   <html>, <body> and the providers
└── styles/
```

- A route file re-exports a page or a layout. A dynamic route awaits its `params` and passes them to the page as props:
  ```tsx
  interface PageProps {
    params: Promise<{ id: string }>;
  }

  export default async function Page({ params }: PageProps) {
    const { id } = await params;
    return <UserDetailPage userId={id} />;
  }
  ```
- Routes that share a layout are grouped with a route group: `(main)`, `(auth)`.
- `RootLayout` wraps the providers. Providers are client components (`'use client'`).

## Routes in a React SPA

A route group per first URL segment: `app/routes/{segment}/{segment}.route.ts`, plus `auth/` and `error/`.

```ts
// app/routes/users/users.route.ts
export const UserRoutes: RouteConfig[] = [
  { path: '/users/new', component: lazy(() => import('@/pages/user').then((m) => ({ default: m.CreateUserPage }))) },
  { path: '/users/$id', component: lazy(() => import('@/pages/user').then((m) => ({ default: m.UserDetailPage }))) },
  { path: '/users', component: lazy(() => import('@/pages/user').then((m) => ({ default: m.UserListPage }))) },
];

// app/routes/index.ts — gathers groups per layout, defines no routes itself
import { AuthRoutes as AuthGroupRoutes } from './auth/auth.route';

export const LayoutRoutes: RouteConfig[] = [...UserRoutes, ...OrganizationRoutes, ...ErrorRoutes];
export const AuthRoutes: RouteConfig[] = [...AuthGroupRoutes];
```

- A route only lazy-imports its page; the page reads params with the router's `useParams`.
- When the app nests URLs under a scope (`/organizations/:organizationId/…`), the project names its scope prefixes once, and the group is the first segment after the prefix: `/organizations/:organizationId/users` → `routes/users/`.
- More specific paths come before general ones: `/users/new` above `/users/$id`.
- Path parameters use the router's own syntax (`$id` in TanStack Router, `:id` in React Router).
- In a React SPA each layout wraps its route group from `routes/index.ts`; in Next.js the `layout.ts` files in `app/` re-export them.
