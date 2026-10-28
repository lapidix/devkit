---
paths:
  - "**/*.tsx"
---

# Native accessibility

- A pressable view says what it is with `role` (`button`, `checkbox`, `switch`, `link`), and one that shows only an icon has an `aria-label`. React Native 0.71 and later take `role` and the `aria-*` props on every core component, and React Native for Web renders them as the same attributes.
- A control that toggles reports its state: `aria-checked` on a checkbox or switch, `aria-selected` on a tab, `aria-disabled` when it cannot be pressed.
- A touch target is at least 44 × 44 points, the size Apple's Human Interface Guidelines set; Android's is 48 dp. A small icon gets the area from padding (`rules/frontend-native/platform.md`).
- A label is a translated key like any other text (`rules/frontend/i18n.md`).
