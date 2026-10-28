# Working in this repo

lapidix devkit is rules and skills for coding agents, not an application. `rules/` are copied into users' projects, `skills/` ship through the plugin, and `scripts/` copy and link them. README.md says what each rule and skill covers. This file is for work on the repo itself; what projects get goes in `rules/` and `skills/`.

## Commands

```sh
bash scripts/check-catalog.sh        # every rule and skill is listed in README.md and the catalog skill
claude plugin validate . --strict    # the marketplace manifest
claude plugin validate ./skills      # every skill's frontmatter
shellcheck scripts/*.sh examples/*.sh examples/*/check.sh
bash examples/frontend/check.sh      # the entity slice example: tsc, Vitest, dependency-cruiser
bash examples/nestjs/check.sh        # the NestJS module example: prisma generate, tsc, Vitest, dependency-cruiser
bash examples/go/check.sh            # the Go module example: sqlc, build, vet, golangci-lint, tests, govulncheck
bash examples/go-daemon/check.sh     # the example daemon: buf, golangci-lint for Linux, tests, release, buf breaking, govulncheck
```

CI runs the first four on every pull request, with a whitespace check on the diff (`.github/workflows/ci.yml`), and the four examples (`.github/workflows/examples.yml`). The Go example's database tests need `TEST_DATABASE_URL` pointing at a PostgreSQL 17 database; without it they skip, except under `CI=true`, where they fail.

## Layout

```
.claude-plugin/marketplace.json   one plugin, devkit, whose source is the repo root; Codex reads the same file
rules/{area}/{topic}.md           copied into a project's .claude/rules/{area}/ by copy-rules.sh
skills/{name}/SKILL.md            one skill per folder; its other files (checklist.md, example-*.md, configs) sit beside it
scripts/                          copy-rules.sh, link-user.sh, check-catalog.sh
examples/extract.sh               writes the files an example-*.md shows into a folder
examples/{stack}/                 check.sh, and project/: the skeleton and pinned versions an example builds into (.build/, ignored)
CHANGELOG.md                      changes that alter what a rule or skill asks of a project
```

## Rules

- **`paths:` frontmatter.** Every rule outside `git/` starts with `paths:` globs for the files it governs, so Claude Code loads it only while it works on them. `copy-rules.sh --prefix` puts globs that start with `**/` under an app's folder; a glob that must stay at the repo root (`.github/workflows/**`) does not start with `**/`.
- **One topic per file**, named after the topic, inside its area's folder.
- **Stated as fact, in English.** "A feature slice holds one domain's use cases", not "you should put use cases in". The reason sits beside the rule, in the same sentence or in a `Why:` line after it.
- **Code is complete.** A block that stands for a file names it in a first-line comment (`// shared/libs/http/http.client.ts`), and it compiles as shown once its imports are added.
- **Skill examples are built.** In an `example-*.md`, each `## <path>` heading names a file and the first block under it is that file; a second block under the same heading is a variant and is not built. A heading without a dot (`## Makefile`) is not extracted; that stack's `check.sh` takes its block by language. `examples/{stack}/check.sh` builds it with the pieces it assumes from `examples/{stack}/project/`, so a change to an example, or to a rule the support files follow, passes that script before it merges.
- **Cite other rules by full path**, `rules/{area}/{file}.md`. `copy-rules.sh` reads these citations to list the areas a project lacks.

## Library facts

A rule that names a library version, or says how a library behaves, is checked against that version before it changes: its changelog, its source, and the rule's code run against it in a scratch project, outside this repo. Raising a minimum version says in the rule what the older version gets wrong. The README's "What the rules assume" lists the versions; keep it in step. `examples/*/project/` pins the versions the examples are checked against; a raised pin goes through the same checks.

## Skills

- The folder name is the skill's `name:`, a gerund phrase (`reviewing-go-changes`). `description:` starts with "Use when" and says when to use the skill, not what it contains.
- A skill reads rules from the project's `.claude/rules/{area}/`. When the project lacks one, it reads `rules/` two levels above its own folder and says so in its report; it finds `scripts/` the same way. Never `${CLAUDE_PLUGIN_ROOT}`: Codex does not expand it.
- Steps are numbered and titled in bold, and each ends with what "done" means ("Done when …").
- A shell check prints only violations, with a trailing comment naming the rule it enforces.

## Adding, renaming or removing a rule or skill

- List it in README.md's tables and in `skills/using-lapidix-devkit/SKILL.md`; `check-catalog.sh` fails when either misses it.
- A rename changes every citation of the old path: `grep -rn 'area/old-name.md' rules skills README.md`.

## Changes users see

Every commit on `main` reaches users, through a plugin update or a rerun of `copy-rules.sh`. A change to what a rule or skill asks of a project (a new requirement, a raised minimum version, a removed or renamed rule) gets an entry in `CHANGELOG.md` in the same pull request. README and wording changes that ask nothing new need none.

## Commits and pull requests

- Follow `rules/git/commit.md` and `rules/git/pull-request.md`: an issue first, an `issue/<N>-<slug>` branch, a `#<N> <type>: <summary>` title, the body from `.github/PULL_REQUEST_TEMPLATE.md`.
- Types: `feat` adds a rule or skill, `fix` corrects one that says something wrong, `docs` covers README and wording that changes nothing a project does.
- This repo requires DCO: sign off every commit with `git commit -s`, under the author's own name and email.
- `main` changes only through pull requests that pass DCO and CI. A pull request from anyone but the maintainer needs an approving review. Merge with a merge commit.
