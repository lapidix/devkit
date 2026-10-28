---
paths:
  - "**/store/**"
  - "**/*.store.ts"
---

# Client state stores

A store holds client state that several components share and that outlives any one of them. Server data stays in React Query; URL state, in a web app, goes through `useSearchParamState` (`rules/frontend-web/routing.md`).

## One tool per project

A project uses either Zustand or stores built with the shared `createStore` helper, never both. Doing one thing two ways makes every reader check which one they are looking at.

Without Zustand, every store comes from one helper that wraps `useSyncExternalStore` once:

```ts
// shared/libs/store/create-store.ts
export function createStore<T>(initial: T) {
  /* … */
  return { get, set, subscribe, useStore };
}

// shared/store/sidebar.store.ts
export const SidebarStore = createStore({ collapsed: false });

// a component
const collapsed = SidebarStore.useStore((s) => s.collapsed);
```

## Where a store lives

| The state | Lives in | Example |
|---|---|---|
| Belongs to a domain | that domain's entity slice: `entities/{d}/store/{name}.store.ts` | `entities/project/store/selected-project.store.ts` |
| Belongs to no domain | `shared/store/{name}.store.ts` | `shared/store/sidebar.store.ts` |

- A domain store sits in entities so features, widgets and pages can all import it through the slice's `index.ts`.
- Shared stores never name a domain (`rules/frontend/shared.md`).
- File names end in `.store.ts`.
