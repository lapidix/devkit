---
paths:
  - "pnpm-workspace.yaml"
  - "**/package.json"
  - "**/tsconfig*.json"
  - ".npmrc*"
---

# Monorepo workspace and packages

## Layout

```
apps/*        deployable or runnable units
packages/*    code and config the apps import
```

Add a third group (`tooling/`, `services/`) only when its members need rules the other two groups do not share.

## When code becomes a package

Move code into `packages/` when two or more apps use it, or another runtime (a server) must reuse it. Code used by one app stays in that app. Packages never import from apps.

## Naming

- Packages are `@<repo>/<dir>`; the root `package.json` name is the bare repo name.
- Domain packages use the domain name alone: `@repo/todo`.
- Shared config packages end in `-config`: `@repo/typescript-config`, `@repo/vitest-config`.

## Internal packages

- `"private": true`, `"version": "0.0.0"`. They are never published.
- They ship source: `exports` points at `.ts` files and the consuming app's bundler and `tsc` compile them. They have no `build` script.
- One root entry point, `"exports": { ".": "./src/index.ts" }`, with `"sideEffects": false` so bundlers can drop unused exports. Split into subpath exports only when a measured problem calls for it (bundle size, dev-server speed, an import cycle), record the reason in the package README, and add each subpath's source file to the architecture check's `ENTRIES`.
- Imports cross a package boundary only through its `exports` entry points. Inside a package, use relative paths. Path aliases belong to apps; a package resolves through the consuming app's tsconfig, so an alias inside a package would point into that app. A single-app repo uses `@/`. In a monorepo each app takes its own alias (`@web/*`, `@admin/*`), so the architecture check, which runs once from the root with one tsconfig, resolves every app. A package never imports itself by its own name.

## Dependencies

- Internal dependencies use `workspace:*`.
- An external dependency used by two or more workspaces gets its version in the `catalog:` of `pnpm-workspace.yaml`, and each `package.json` says `"catalog:"`. A `check:catalog` script enforces this in pre-commit and CI, root `package.json` included.
- Runtime libraries go in `dependencies`; tooling (`typescript`, `vitest`, `@types/*`) in `devDependencies`. Config packages are consumed as `devDependencies`; the tool a config package wraps is its `peerDependency`.

Why the catalog is enforced: when it was only a comment, five dependencies drifted to per-package versions, and two copies of a library got installed.

## Shared config packages

Shared tsconfig presets, vitest config and similar live in `packages/*-config` and are consumed through `workspace:*`. A package's own `tsconfig.json` extends a preset and lists only `include`.

Why packages instead of root files: turbo sees a change to a config package as a change to every package that depends on it, so affected-only CI picks up the consumers. A root file is invisible to turbo and needs a hand-maintained path list in CI.

## pnpm settings

pnpm settings live in `pnpm-workspace.yaml`. `.npmrc` holds only registries and auth. Every exception (an override, an allowed build script, an ignored advisory) carries a comment with its reason and when to remove it, and is pinned to `name@version`.

## Scripts and versions

- Root scripts: `dev`, `build`, `test`, `lint`, `lint:fix`, `check-types`, `check:arch`, `check:catalog`, `prepare`. They are thin wrappers around `turbo run`, except `check:arch` and `check:catalog`, which look at the whole repository once and run directly.
- Package scripts: `check-types: tsc --noEmit`; `test: vitest run` when the package has tests.
- `packageManager` pins the exact pnpm version.
- `engines.node` is the single source of the Node version; CI reads it with `node-version-file: package.json`. Turn on `engineStrict` only when a tool depends on a minimum Node version.
