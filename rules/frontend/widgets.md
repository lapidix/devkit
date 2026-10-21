---
paths:
  - "**/widgets/**"
---

# Frontend widgets layer

A widget is one section of a screen. It composes entity UI (domain atoms) and feature UI (components that perform an action) into something a page places: a list section, a detail panel, a header.

## Who fetches what

| Page | Widget |
|---|---|
| Passes identifiers to its widgets | Receives identifiers from the page as props |
| Starts the first screen's requests (`usePrefetchQuery`, or a server prefetch in Next.js) and owns the `AsyncBoundary` | Reads the data it shows with `useSuspenseQuery({D}Queries…)`: `useSuspenseQuery(UserQueries.list({ page: 1 }))` |

A widget's read joins the request the page already started, so the page never fetches data only to hand it down.

## Structure

```
widgets/
├── section/
│   ├── user-list/               UserListSection.tsx
│   └── project-overview/        ProjectOverviewSection.tsx
├── panel/
│   └── user-detail/             UserDetailPanel.tsx
└── header/
    └── main/                    MainHeader.tsx
```

- Widgets are grouped by kind: `widgets/{kind}/{name}/`. The project defines one list of kind names and every widget uses it.
- `{name}` is the widget's own name: the domain plus purpose when it shows one domain (`user-list`), the screen or purpose when it combines several or none (`project-overview`, `main`).
- A slice is two levels deep, `widgets/{kind}/{name}/`. Boundary rules for widgets treat that pair as the slice.
- The component is named `{Name}{Kind}`: `UserListSection`, `UserDetailPanel`, `MainHeader`.

## Inside a widget

```
widgets/section/user-list/
├── UserListSection.tsx
├── UserListSection.test.tsx
└── index.ts
```

- Files sit directly in the slice. A sub-component used by this widget alone stays in the same file or sits beside it with the widget's name as a prefix: `UserListSectionToolbar.tsx`.
- A widget has no hooks of its own. It reads data with `useSuspenseQuery({D}Queries…)`, runs actions with `useMutation({D}Mutations…)`, keeps domain UI state in feature hooks (`useUserFilter`), reads client state shared by many components from an entity or shared store (`rules/frontend/state.md`), keeps section-only screen state in `useState`, and puts display settings such as table columns in constants or functions in its file.

Why no widget hooks: everything a widget needs already has a home. Wanting a widget hook is a signal; domain state or flow belongs in the feature, and a widget that needs one for its own complexity should be split.

## Props

A widget takes identifiers and slots, never fetched data.

```tsx
<UserDetailPanel userId={id} actions={<SuspendUserButton userId={id} />} />

export function UserDetailPanel({ userId, actions }: UserDetailPanelProps) {
  const { data: user } = useSuspenseQuery(UserQueries.detail({ id: userId }));
  …
}
```

## Imports and public API

- A widget imports from entities, features and shared. It never imports another widget; anything two widgets share moves down to features, entities or shared.
- `index.ts` exports the widget component, plus its props type when a page uses it. Sub-components stay inside.

```ts
export { UserDetailPanel } from './UserDetailPanel';
export type { UserDetailPanelProps } from './UserDetailPanel';
```
