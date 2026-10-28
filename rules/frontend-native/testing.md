---
paths:
  - "**/*.test.{ts,tsx}"
  - "**/vitest.config.*"
---

# Native tests

What to test, fakes and coverage are in `rules/frontend/testing.md`.

- The tested code imports no `react-native`, Expo module or native library. Entity behavior, mappers, schemas, use cases and hook decisions are plain functions already; a decision that sits in a component moves to a function beside it, which Vitest runs in Node without a simulator.
- An adapter over the device database is tested against the same SQL engine in Node (SQLite through `better-sqlite3` or `node:sqlite` for expo-sqlite), with the app's migrations applied, never against a hand-written fake of the database.
- Rendering components in tests (jest-expo with React Native Testing Library) is the project's decision. A project that renders runs those tests under jest-expo: React Native ships Flow-typed source that Vitest does not transform.
- What only a device shows (a native module, a permission dialog, a gesture, the two themes) is checked on a simulator or device, and the pull request says which.
