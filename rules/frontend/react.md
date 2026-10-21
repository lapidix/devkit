---
paths:
  - "**/*.tsx"
  - "**/use[A-Z]*.ts"
---

# React components and hooks

## Declaring components

```tsx
interface UserCardProps {
  user: UserEntity;
  size?: 'sm' | 'md';
  onSelect?: (id: string) => void;
}

export function UserCard({ user, size = 'md', onSelect }: UserCardProps) {
  const handleSelect = () => onSelect?.(user.id);
  …
}
```

- Components and hooks are `function` declarations. No `React.FC`.
- Props are an interface named `{Component}Props` (`rules/typescript/conventions.md`).
- Defaults come from destructuring defaults. No `defaultProps`.
- Event props are `on{Event}` (`onSelect`, `onClose`); the functions that handle them are `handle{Event}` (`handleSelect`).
- When boolean props start to multiply (`isPrimary`, `isDanger`, `isGhost`), replace them with one `variant: 'primary' | 'danger' | 'ghost'`.
- In React 19, take `ref` as a regular prop instead of wrapping the component in `forwardRef`.

## Component files

- A component file exports its component, its props type and constants that belong to it. Anything else moves to its own file. Why: a file that exports other values breaks Fast Refresh.
- Never define a component inside another component. It becomes a new component on every render, and its state resets. Static objects and pure functions that use no props or state go outside the component too.

## Rendering

- A simple condition uses `&&`. When branches grow, `return` early. Never nest ternaries.
- Repeated UI with the same structure is an array rendered with `map` when two of these hold: three or more items, items are expected to be added or removed, some items are conditional.
- Use the product's dialog instead of `window.alert`, `window.confirm` or React Native's `Alert`. Native dialogs ignore the theme and language and do not show in some desktop shells.
- Web accessibility: use semantic elements (`button`, `a`, `nav`), give every input a label, and give every `<button>` an explicit `type`.

## Memoization

React Compiler is on. Don't write `useMemo`, `useCallback` or `memo`, except for a measured performance problem or a library that requires a stable reference. Only a build that cannot run the compiler memoizes by hand.

## Effects

- A value that can be computed from props or state is computed during render, not synced into state by an effect. The effect costs an extra render and shows a wrong value for a moment.
  ```tsx
  // ❌
  const [fullName, setFullName] = useState('');
  useEffect(() => setFullName(`${first} ${last}`), [first, last]);
  // ✅
  const fullName = `${first} ${last}`;
  ```
- Don't copy a prop into state; the two drift apart. When a value must be editable locally, read `value ?? localValue`.
- To reset state when a prop changes, change the component's `key`.
- A reaction to a user action goes in the event handler, not in an effect that watches a flag.
- An effect only synchronizes with an external system: subscriptions, browser events, a non-React widget. Data fetching goes through React Query (`rules/frontend/react-query.md`).
- Async work in an effect drops late results with a cancel flag set in the cleanup.

## Next.js

- `'use client'` goes on widgets and on feature components that use hooks: the outermost components that need hooks or interaction. Pages, layouts and route files stay server components; a page prefetches on the server instead of calling hooks (`rules/frontend/pages.md`).
- A server component inside a client component arrives as a slot (`children` or a prop), never as an import.

Why: everything a client component imports becomes client code and re-renders with it. A server component passed as a slot is rendered once on the server and stays that way when the client component re-renders.
