---
paths:
  - "**/src/app/**"
  - "**/app/**"
  - "**/app.json"
  - "**/app.config.{js,ts}"
---

# Expo app layer

The app layer's job is in `rules/frontend/app.md`. In an Expo app, expo-router turns every file in its root folder into a route, so providers and layouts cannot sit beside the routes. The layout follows Next.js's (`rules/frontend-web/app.md`): routes in a root `app/`, the app layer in `src/app/`.

## Structure

```
app/                              expo-router routes, kept thin
├── _layout.tsx                   export { RootLayout as default } from '@/app/layouts/root'
├── (tabs)/
│   ├── _layout.tsx               export { TabsLayout as default } from '@/app/layouts/tabs'
│   └── index.tsx                 export { TodayPage as default } from '@/pages/today'
└── users/[id].tsx                export { UserDetailPage as default } from '@/pages/user'
src/app/
├── providers/
├── layouts/
│   ├── root/RootLayout.tsx       the providers and the root navigator
│   └── tabs/TabsLayout.tsx
└── platform/bind.platform.ts     hands the platform modules to the packages, once
```

- The route root is set in the expo-router plugin: `["expo-router", { "root": "app" }]` in `app.json`. Without it, expo-router uses `src/app/` whenever that folder exists, and every provider and layout file there becomes a route.
- A route file re-exports a page or a layout. It never holds a component of its own.
- Special files stay in the route folder with expo-router's names: `+not-found.tsx`, `+native-intent.tsx`, `+html.tsx`.

## Route params

The page reads them with `useLocalSearchParams`, typed with the params its route declares:

```tsx
export function UserDetailPage() {
  const { id } = useLocalSearchParams<{ id: string }>();
  …
}
```

A param arrives as a string, or a string array when the key repeats; a page that needs a number parses it.

## Screen state

A native app has no address bar. Route params identify the screen, and deep links address it the same way. A tab inside a screen, a filter and a sort are component state; state that must outlive the screen goes in a store (`rules/frontend/state.md`).

## RootLayout

```tsx
// src/app/layouts/root/RootLayout.tsx
export function RootLayout() {
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <TanstackQueryProvider>
        <Stack />
      </TanstackQueryProvider>
    </GestureHandlerRootView>
  );
}
```

- `GestureHandlerRootView` is the outermost view. Without it, `GestureDetector` throws in development on iOS and Android (react-native-gesture-handler 2), and gestures are not recognized in a release build.
- expo-router already wraps the app in `SafeAreaProvider` (expo-router 57's `ExpoRoot`); the root layout does not add another.
- Providers that read the device (the color scheme, the locale) go inside the ones they need.

## Platform modules

A monorepo package cannot import the app, so the app hands it what only the platform has (the database, the id generator) through a setter the package exports. `src/app/platform/bind.platform.ts` calls each setter at module scope, and `RootLayout`'s file imports it first, so the values are in place before any screen renders:

```ts
// src/app/platform/bind.platform.ts
setRuntime({ db, newId });
```

A package's getter throws when nothing was bound. Returning `undefined` would surface far from the cause, at the first write.
