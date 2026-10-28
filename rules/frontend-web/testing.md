---
paths:
  - "**/*.test.{ts,tsx}"
  - "**/vitest.config.*"
---

# Web tests

What to test, fakes and coverage are in `rules/frontend/testing.md`.

- Component tests add jsdom and Testing Library.
- Interactions use `userEvent`, not `fireEvent`.

Why `userEvent`: it fires the events a person's action fires, in order (pointer, focus, key, input), while `fireEvent` dispatches one, so a handler that listens to another event passes the test and fails in the browser.
