---
paths:
  - "turbo.json"
  - "biome.json*"
  - ".dependency-cruiser.*"
  - ".husky/**"
  - "knip.json*"
  - "package.json"
---

# Monorepo tooling

## One command set

The commands you run before saying work is done, the commands the git hooks run, and the commands CI runs are the same commands. When one changes, change all three.

## Turbo

```jsonc
{
  "tasks": {
    "transit":     { "dependsOn": ["^transit"] },
    "build":       { "dependsOn": ["^build"], "outputs": ["dist/**"] },
    "check-types": { "dependsOn": ["^check-types"] },
    "test":        { "dependsOn": ["transit"] },
    "lint":        { "dependsOn": ["transit"] },
    "dev":         { "cache": false, "persistent": true }
  }
}
```

- A task that reads dependency sources but has no `^<same task>` dependency (`test`, `lint`) depends on the `transit` node. Without it, editing a dependency leaves the dependent's cache key unchanged and turbo replays an old passing result. `check-types` already gets this through `^check-types`.
- Environment variables that change a task's output go in `env`; run-time knobs that do not (`VITEST_MAX_WORKERS`) go in `passThroughEnv`. Env files go in `inputs`.
- A root config file that changes every package's result goes in `globalDependencies`.
- CI sets `TURBO_UI=0`; the interactive UI hides logs there.

## Biome

Biome is the only linter and formatter; there is no ESLint or Prettier. One `biome.json` sits at the root, and `biome check .` runs once from the root.

## dependency-cruiser

- One run from the repository root covers every app and package: `check:arch` is `depcruise apps packages` in a monorepo, `depcruise src` in a single app. The config and its rule files (frontend layers and slices, entities, server layers, the package graph) come from the `setting-up-architecture-checks` skill.
- `no-circular` is an error.
- Every rule has a `comment` stating why it exists and how to fix a violation.
- Anchor exclude patterns to path segments: `(^|/)build(/|$)`, not `build`. An unanchored `build` also excluded a slice named `pipeline-builder` from every check.

## Git hooks

Husky v9 installs through `"prepare": "husky"`. There is no lint-staged.

| Hook | Runs |
|---|---|
| `pre-commit` | `biome check --staged --no-errors-on-unmatched`, plus fast static checks (`check:arch`, `check:catalog`, …) |
| `pre-push` | `check-types` and `test` |

Commits stay fast enough to make often; CI is the final gate.

## knip

knip runs in CI. Its config lists every entry point and ignores stories, testkits and tests, so a false positive does not block PRs.
