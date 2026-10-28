---
paths:
  - "**/*.tsx"
  - "**/*.css"
---

# Styling

The project picks the styling tool (Tailwind, CSS Modules, React Native's `StyleSheet`, …).

## Tokens

- Colors and spacing come from the design tokens only. No raw palette classes (`text-blue-500`), hex values, or inline `style` carrying those values.
- Values that look the same but mean different things get separate tokens (`danger` and `holiday` can share a red). Changing one then never changes the other by accident.

## Dates, numbers and empty values

Dates and numbers are displayed through the formatters in `shared/utils`, never `dayjs().format` or `toLocaleString` in a component. Entities hold instants as epoch milliseconds (`rules/frontend/entity-data-access.md`); the formatter turns them into text when the screen renders. The same formatters decide how an empty value is shown (`-` or whatever the product uses).

## Per platform

Tailwind's `cn()` is in `rules/frontend-web/styling.md`; React Native's `StyleSheet` and theme hook are in `rules/frontend-native/styling.md`.
