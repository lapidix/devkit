---
paths:
  - ".github/workflows/**"
  - ".github/actions/**"
---

# CI workflows

## Pull request checks

- Checks run on pull requests. A new push to the same PR cancels the previous run:
  ```yaml
  concurrency:
    group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
    cancel-in-progress: true
  ```
- Install with `pnpm install --frozen-lockfile`.
- Check only what changed: `fetch-depth: 0`, then turbo's affected filter against the base branch (`--affected` with `TURBO_SCM_BASE=origin/$BASE_REF`, or `--filter="...[origin/$BASE_REF]"`).
- Put each check in its own step with `if: ${{ !cancelled() }}`, so one failure still shows every other result.
- A server with a database runs it as a service container (same engine and major version as production), applies every migration to it, then runs the tests with `TEST_DATABASE_URL` set (`rules/database/conventions.md`).

## Skipping docs-only changes

- No required status checks: skip with `paths-ignore` (`**/*.md`, `.claude/**`, `docs/**`).
- Required status checks exist: use a `changes` job and a job-level `if`. A workflow skipped by path filters never reports, and a required check then waits forever. When the `changes` job fails, run everything.

## Untrusted values

Pass `github.*` context values through `env` and quote them in the script:

```yaml
env:
  BASE_REF: ${{ github.base_ref }}
run: git fetch origin "$BASE_REF"
```

Interpolating `${{ github.head_ref }}` directly into `run:` lets a branch name inject shell.

## Actions

- Pin every action to a full commit SHA and note the version: `uses: actions/checkout@<sha> # v4`. A tag can be moved to different code.
- Give each job the least `permissions` it needs.
- Set up Node with `node-version-file: package.json`.

## Deploy builds

A deploy job installs and builds only the target app and its dependencies: `pnpm install --filter @repo/<app>...`, `turbo run build --filter=@repo/<app>`.
