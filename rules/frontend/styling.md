---
paths:
  - "**/*.tsx"
  - "**/*.css"
---

# Styling

The project picks the styling tool (Tailwind, CSS Modules, …).

## Tokens

- Colors and spacing come from the design tokens only. No raw palette classes (`text-blue-500`), hex values, or inline `style` carrying those values.
- Values that look the same but mean different things get separate tokens (`danger` and `holiday` can share a red). Changing one then never changes the other by accident.

## Dates, numbers and empty values

Dates and numbers are displayed through the formatters in `shared/utils`, never `dayjs().format` or `toLocaleString` in a component. Entities hold instants as epoch milliseconds (`rules/frontend/entity-data-access.md`); the formatter turns them into text when the screen renders. The same formatters decide how an empty value is shown (`-` or whatever the product uses).

## If you use Tailwind

Merge class names with `cn()` (clsx + tailwind-merge) from `shared/utils`, never with template strings. A template string lets `undefined` into the class list and leaves conflicting classes (`p-2 p-4`) for the browser to settle.
