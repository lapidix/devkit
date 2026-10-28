---
paths:
  - "**/*.tsx"
  - "**/*.css"
---

# Web styling

Tokens, formatters and empty values are in `rules/frontend/styling.md`.

## If you use Tailwind

Merge class names with `cn()` (clsx + tailwind-merge) from `shared/utils`, never with template strings. A template string lets `undefined` into the class list and leaves conflicting classes (`p-2 p-4`) for the browser to settle.
