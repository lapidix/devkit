---
paths:
  - "**/.env*"
  - "**/.gitignore"
  - "turbo.json"
  - ".github/workflows/**"
---

# Environment variables in a monorepo

## Per app by default

Each app commits its own template (`apps/<app>/.env.example`) and gitignores the real `.env`. Keep the template tracked even if a broad pattern like `.env*` ignores everything else; check with `git check-ignore -v apps/<app>/.env.example`.

Why: a `.env*` line placed after `!.env.example` silently re-ignored every new template, so new apps shipped without one.

## A root `.env` is allowed only with all three of these

1. Client-bundled variables keep the framework prefix (`VITE_`, `NEXT_PUBLIC_`, `EXPO_PUBLIC_`), because every app process now loads every secret.
2. Each app loads the root file explicitly (`dotenv -e ../../.env -- <cmd>`, Vite `envDir`, `node --env-file` for a Node server). Next and Expo read only their own folder by default.
3. `turbo.json` lists each task's variables in `env`, so a change to the shared file invalidates only the tasks that use it.

A root file helps local development only; deployed values are injected per app either way.

## Values that reach the client

Values that end up in a client bundle are injected at build time through the framework's prefix convention. Development-only values are empty in production builds.

## CI and secrets

- Secrets come from GitHub Environments as `secrets.*`; non-secret settings as `vars.*`.
- The source of truth for secrets lives outside the repo (a vault such as 1Password), with the restore steps written down.
