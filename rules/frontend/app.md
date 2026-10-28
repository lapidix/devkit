---
paths:
  - "**/src/app/**"
  - "**/app/**"
---

# Frontend app layer

The app layer holds what exists once for the whole app: providers, layouts, global styles and the routes. Routes map URLs or screens to pages; pages are organized by domain (`rules/frontend/pages.md`). The layout of the folder depends on the platform: `rules/frontend-web/app.md` for a React SPA and Next.js, `rules/frontend-native/app.md` for Expo.

## Providers

`providers/{name}-provider/{Name}Provider.tsx` wraps the app in one thing the whole app needs exactly once. TanStack Query and i18n are the common ones; the rest depend on the product.

The app's root (`App.tsx`, Next.js's `RootLayout`, expo-router's root `_layout.tsx`) stacks them, in the order the platform rule gives.

```tsx
interface TanstackQueryProviderProps {
  children: ReactNode;
}

export function TanstackQueryProvider({ children }: TanstackQueryProviderProps) {
  return <QueryClientProvider client={getQueryClient()}>{children}</QueryClientProvider>;
}
```

`getQueryClient` lives in `shared/libs/client/query.client.ts` (`rules/frontend/shared.md`).

## Layouts

`layouts/{name}/{Name}Layout.tsx` is the shell around a group of routes: side navigation, header and other widgets composed together. A layout may read app-wide data such as the current user or the project list.
