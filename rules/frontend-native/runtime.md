---
paths:
  - "**/*.{ts,tsx}"
---

# React Native runtime

React Native is not a browser. TypeScript's DOM types describe globals the app does not have, so code that type-checks fails at runtime, often on the first tap that reaches it.

## Missing web APIs

| Missing | Use |
|---|---|
| `crypto` (`randomUUID`, `getRandomValues`) | `expo-crypto`, behind `shared/libs/id` |
| `localStorage`, `sessionStorage` | a storage module (`expo-secure-store` for secrets, a key-value store or the database for the rest), behind `shared/libs/storage` |
| `window.alert`, `window.confirm` | the product's dialog (`rules/frontend/react.md`) |
| `document`, DOM events | nothing: a native view has no DOM |

Expo installs a few globals before the app runs (Expo SDK 57: `URL`, `URLSearchParams`, `TextDecoder`, `TextDecoderStream`, `TextEncoderStream`, `DOMException`, `structuredClone`, `fetch`), so the app may use those. A shared package assumes none of them: it runs in an Expo app, a Node server and a browser alike.

## Native modules

- A library that ships native code reaches the app through a new native build; reloading JavaScript does not load it. Expo Go runs only the modules it ships with.
- A native module is imported only from `shared/libs/{subject}/` (`rules/frontend-native/platform.md`), so a platform without it gets another file there instead of a crash in a component.
