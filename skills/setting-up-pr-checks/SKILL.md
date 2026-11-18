---
name: setting-up-pr-checks
description: Use when adding or repairing the pull request check (check-pr.sh) in a project's CI, or when PR size, PR body or comment rules are not enforced by any tool.
---

# Setting up PR checks

`check-pr.sh` in this folder enforces `rules/git/pull-request.md` (the template headers, the section limits, the backtick references, `## Size`) and the Comments sections of `rules/go/conventions.md`, `rules/typescript/conventions.md` and `rules/database/conventions.md` (a block of at most three lines, comments at most half of the added code lines). It prints one line per violation and exits 1 when one blocks the merge. A GitHub Actions job runs it on every pull request.

The rule files named here are in the project's `.claude/rules/{area}/`. When the project lacks one, read the copy that ships with this skill, in the `rules/` folder two levels above this skill's folder, and say in your report that the project does not have it. Find `scripts/` the same way: the project's own first, then `scripts/` two levels above this folder.

## Steps

1. **Inputs.** Find out:
   - whether the project runs GitHub Actions (a `.github/workflows/` folder); if it uses another CI, stop and report it, because the workflow below is GitHub's
   - whether `.github/PULL_REQUEST_TEMPLATE.md` exists
   - the paths of committed generated code: the sqlc output folder, buf's `gen/`, and any other generated source in the repository
   - whether the project already runs `copy-rules.sh --agents-md`, and whether the team wants limits other than the defaults (1,000 changed lines, three paragraphs in Why, and so on, listed in `defaults` at the top of `check-pr.sh`)

   Done when you know the CI, whether the template exists, every generated path, and whether `--agents-md` and custom limits apply.

2. **Install.**
   - Copy `check-pr.sh` to `scripts/check-pr.sh`.
   - A project without `.github/PULL_REQUEST_TEMPLATE.md` gets one from the template in `rules/git/pull-request.md` (`## Body`). Without a template GitHub opens PRs with an empty body, and the author has no list of the headers the check requires.
   - Copy the rule the check cites: `bash scripts/copy-rules.sh <project> git/pull-request`. When step 1 found `--agents-md` in use, the flag goes before `<project>`: `bash scripts/copy-rules.sh --agents-md <project> git/pull-request`. Only this file: the check is a team rule once CI enforces it, so teammates and their agents must be able to read what it requires, and the violation messages name this file. `git/commit.md` stays a personal format and is not copied. Find `copy-rules.sh` in the project's `scripts/`, else two levels above this folder.
   - Create `.github/pr-checks.env` only when step 1 found other limits: one `PR_NAME=number` per line, names as in `defaults` at the top of `check-pr.sh`. The file is parsed, never sourced, and an unknown name exits 2.

   Done when `scripts/check-pr.sh` exists, `.claude/rules/git/pull-request.md` exists, the template exists, and `.github/pr-checks.env` exists only if the limits differ.

3. **Generated files.** Add each path from step 1 to `.gitattributes` with `linguist-generated=true`, for example `**/sqlcgen/** linguist-generated=true` for sqlc's output under `internal/modules/<module>/adapters/out/persistence/sqlcgen/`. The size and comment checks skip these files and the lockfiles (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lock`, `go.sum`). A Go file whose first 10 lines hold the `// Code generated … DO NOT EDIT.` header needs no entry: the checks skip it already. A path missing here counts toward the 1,000 lines, and its comments are checked.

   Done when `git check-attr linguist-generated <path>` prints `<path>: linguist-generated: true` (or `set`, for an entry without `=true`) for a file under each generated path that lacks the Go header.

4. **CI.** Create `.github/workflows/pr-checks.yml`. It follows `rules/monorepo/ci.md`: actions pinned to a SHA, `contents: read` only, untrusted values through `env`, and no path filter, because the job becomes a required check and a workflow skipped by a path filter never reports.
   ```yaml
   # .github/workflows/pr-checks.yml
   name: pr-checks

   on:
     pull_request:
       types: [opened, edited, synchronize, reopened]

   concurrency:
     group: ${{ github.workflow }}-${{ github.event.pull_request.number }}
     cancel-in-progress: true

   permissions:
     contents: read

   jobs:
     pr-checks:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
           with:
             fetch-depth: 0
             persist-credentials: false
         - name: Check the pull request
           env:
             BASE_REF: ${{ github.base_ref }}
             BODY: ${{ github.event.pull_request.body }}
             AUTHOR_TYPE: ${{ github.event.pull_request.user.type }}
           run: |
             if [ "$AUTHOR_TYPE" = Bot ]; then
               bash scripts/check-pr.sh --base "origin/$BASE_REF"
             else
               printf '%s\n' "$BODY" > "$RUNNER_TEMP/pr-body.md"
               bash scripts/check-pr.sh --base "origin/$BASE_REF" --body "$RUNNER_TEMP/pr-body.md"
             fi
   ```
   - `edited` re-runs the check when only the body changes; the default events omit it.
   - A PR opened by a bot (Dependabot, Renovate, a release bot) has no template headers in its body, so the bot branch runs the diff checks only. It is the same job with fewer arguments, so size and comment limits still apply to bot PRs.
   - `fetch-depth: 0` gives the script `origin/$BASE_REF` and the history to diff against. A shallow clone has no merge base, and the script exits 2.

   Done when the file exists with the first line above, and a pull request shows the `pr-checks` job.

5. **Required check.** The skill changes no repository settings. Tell the user to mark the `pr-checks` job as required in branch protection or the ruleset of the default branch; until then a failure does not block the merge.

   Done when the report asks the user for that setting, by name.

6. **Verify.** Run `bash scripts/check-pr.sh --base origin/<default branch>` on the current branch (add `--body <file>` with a body written to the template). Fix each violation, or list it in your report. Then prove the rules fire: make each temporary file below, run the check, confirm the named rule fails, and delete the file.
   - a source file with a four-line comment block (`// a` to `// d`), committed on a scratch branch → a `PR:`-prefixed or file-located comment-block line ending in the language's `conventions.md`
   - a body file without the `## Notes` header → a `missing section` line ending in `git/pull-request.md`
   - a body file naming `` `WithdrawUser` ``, which the repository does not contain → a line saying `` `WithdrawUser` `` is not in the repository

   Done when the check passes on the real branch (or every remaining violation is in your report), each temporary input fails with its rule, and no temporary file or scratch commit is left.

## Common mistakes

| Mistake | Fix |
|---|---|
| `types` leaves out `edited` | Editing the body then never re-runs the check; keep all four types |
| The body interpolated into `run:` (`echo "${{ github.event.pull_request.body }}"`) | A body containing `"; curl …` runs as shell. Pass it through `env` and write it with `printf '%s\n' "$BODY"` (`rules/monorepo/ci.md`) |
| A `paths:` or `paths-ignore:` filter on the workflow | A skipped workflow never reports, and a required check waits forever |
| A generated path missing from `.gitattributes` | The size check counts the generated lines and warns, and the comment checks read the generated comments: a regenerated client fails a PR that changed ten lines by hand |
| A PR edits `.github/pr-checks.env` or `scripts/check-pr.sh` to lower a limit | The check runs the PR's own copy; review changes to these two files in the diff, and name them in CODEOWNERS when the team wants an owner |
| Bot PRs skipped with a job-level `if` | The job then never reports on those PRs and the required check waits; keep one job and drop only `--body` |
| `rules/git/commit.md` copied along with the PR rule | The commit format is personal; only `git/pull-request` goes into the project |
