---
paths:
  - "**/*.tsx"
  - "**/*.style.ts"
---

# Native styling

Tokens, formatters and empty values are in `rules/frontend/styling.md`.

## StyleSheet and the theme

- Styles are `StyleSheet.create` objects at the bottom of the component file, or in `{Component}.style.ts` beside it when they grow.
- Colors come from one theme hook (`useTheme()`), which picks the light or dark value. A style that needs a color takes it at render: `[styles.row, { backgroundColor: theme.surface }]`. A hex value in a component is wrong in one of the two themes.
- Spacing, radii and font sizes come from token objects (`Spacing.three`, `Radius.md`), never numbers written in the style.
- Text is drawn by one themed text component that takes a `type` (`<ThemedText type="title">`), so the font, size, letter spacing and color come together. A bare `Text` falls back to the system font and color.

## Checking

A screen change is checked in both light and dark, on a device or simulator. A color that is wrong in one theme passes every static check.
