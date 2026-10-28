---
paths:
  - "**/config/env.config.ts"
  - "**/.env*"
  - "**/app.config.{js,ts}"
---

# Expo env

`shared/config/env.config.ts` stays the only file that reads the environment (`rules/frontend/shared.md`). In an Expo app it reads each variable by its full name:

```ts
// shared/config/env.config.ts
export const ENV = {
  API_BASE_URL: process.env.EXPO_PUBLIC_API_BASE_URL,
  SENTRY_DSN: process.env.EXPO_PUBLIC_SENTRY_DSN,
} as const;
```

- Only `EXPO_PUBLIC_*` reaches the app. babel-preset-expo replaces each `process.env.EXPO_PUBLIC_…` it finds written out; `const { EXPO_PUBLIC_API_BASE_URL } = process.env` and `process.env[name]` are left alone and read `undefined` on the device.
- A production bundle holds the value itself, written in during the Babel transform. A value in the bundle is public: secrets never get the prefix.
- Expo reads `.env.{mode}.local`, `.env.local`, `.env.{mode}`, then `.env`, and the first file that sets a variable wins. A leftover `.env.local` therefore overrides `.env.development` and `.env.production` alike; keep per-mode values in the per-mode files.

## Checking a value

After changing a value, export with a clean cache and look for it in the bundle:

```bash
npx expo export --platform ios --clear --output-dir /tmp/bundle
grep -rc "<part of the value>" /tmp/bundle/_expo/static/js/ios/
```

The transform cache can hold a module compiled before the value was set; the export then logs the variable as loaded while the bundle lacks it. A count of zero means the value is not in the app.
