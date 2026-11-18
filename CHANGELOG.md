# Changelog

What changed for projects that use these rules and skills, newest first. Every commit on `main` is a release (README, "Install"); this file lists the ones that change what a rule or skill asks of a project.

## 2026-11-18

### Added

- Skill `setting-up-pr-checks` with `check-pr.sh`: a GitHub Actions job runs the script on every pull request. It checks the PR body against the template, the size, and the comments that added lines carry in Go, TypeScript/JavaScript and SQL files. Missing, empty or out-of-order sections, a missing Verified or Not verified list, a section over its limit, a backtick reference that does not exist, a comment block over 3 lines and a comment share over half block the merge (exit 1). A PR over 1,000 changed lines and a sentence over 25 words, in the body or in a comment, only warn (exit 0). A base with no merge base, as in a shallow clone, exits 2. Generated files are left out: lockfiles, Go files with the `// Code generated … DO NOT EDIT.` header, and files marked `linguist-generated` in `.gitattributes`. Tool comments are not counted as comments: Go directives, `//nolint`, `-- +goose`, sqlc's `-- name:`, drizzle's `--> statement-breakpoint`, swaggo's `// @Summary`, linter and coverage switches. `.github/pr-checks.env` changes the numbers. A project adopts the check by running `setting-up-pr-checks`, then marks the `pr-checks` job as required in branch protection.

### Changed

- `git/pull-request.md`, section limits: Why is at most 3 paragraphs and 1,500 characters, Changes 3,000, Out of scope & follow-ups and Notes 1,000 each. A section with nothing to say contains `None`; an empty section used to be allowed and now fails the check.
- `git/pull-request.md`, references: a path that contains a `/`, or a plain name, in backticks exists in the repository, at the PR head or its base, and a line number after a path is within the file. Bare file names such as `README.md` are not checked, nor are commands, globs, placeholders, dotted names such as `os.Getenv`, names with no lowercase letter such as `NODE_ENV`, host-like paths and ignored paths.
- `git/pull-request.md`, size and sentences: a PR changes at most 1,000 lines, and a larger one says in Notes why it could not be split; a sentence has at most 25 words, from the plain language principles of ISO 24495-1. The check only warns on both and exits 0.
- `go/conventions.md`, `typescript/conventions.md`, `database/conventions.md`: a comment block is at most 3 lines, a comment sits at the line it explains, and a sentence has at most 25 words. Comments are at most half of the comment and code lines a PR adds in Go, TypeScript/JavaScript and SQL files, from 20 such lines; blank lines, delimiter-only lines, tool comments and generated files are not counted. Each rule names its language's tool comments. Longer reasoning goes in the PR body or the commit message. Code that carried longer comments gets them cut or moved. The check warns on long sentences and blocks on the rest.
- `writing-pull-requests`: a new Check step fetches the base and runs `check-pr.sh` on the body file against `origin/<base>` before the PR is created. A section with nothing to say gets `None` where the skill used to accept "deliberately left empty".
- `reviewing-frontend-changes`, `reviewing-go-changes`, `reviewing-go-daemon-changes` and `reviewing-server-changes` fetch the base and run `scripts/check-pr.sh --base "$BASE"` when the project has it, and record its output.
- `installing-rules`: a project that enforces the PR check in CI gets `git/pull-request.md` from `setting-up-pr-checks`, not from the `git` area, which stays personal.

## 2026-10-28

### Changed

- `frontend/forms-rhf-zod.md`: the submit button is off until the form is valid (`!formState.isValid`) and while the request is pending; it used to stay enabled and show every error when pressed. The reason it is off must be on screen: an empty required field, or an error on a field, with cross-field checks given a zod `path`. `isDirty` still does not disable it. `reviewing-frontend-changes` flags only `isDirty` now.
- The frontend rules are split like `go/` under `go-server/` and `go-daemon/`. `frontend/` keeps what any React app follows, under the same file names; what needs a browser moved, with its wording, to `frontend-web/`: the SPA and Next.js layouts and URL-based routes (`frontend/app.md` → `frontend-web/app.md`), URL state and `useSearchParamState` (`frontend/pages.md`, `frontend/shared.md` → `frontend-web/routing.md`), server components, server prefetching and dehydration (`frontend/react.md`, `frontend/pages.md`, `frontend/shared.md` → `frontend-web/nextjs.md`), Tailwind's `cn()` (`frontend-web/styling.md`), semantic elements and `<button type>` (`frontend-web/accessibility.md`), and jsdom, Testing Library and `userEvent` (`frontend-web/testing.md`). A React or Next.js project copies `frontend-web` beside `frontend`; updating `frontend` alone drops those rules. `installing-rules` copies `typescript` `frontend` `frontend-web` for a React or Next.js app.
- `frontend/entity-data-access.md`: an entity that also keeps data on the device has a local adapter in `infrastructure/db/` and exports both instances. The `entity-infrastructure-internals` rule in `setting-up-architecture-checks` keeps `infrastructure/db/*.table.ts` inside `infrastructure/`.

### Fixed

- `go-daemon/outbound.md` and the `scaffolding-go-daemons` example: a server that kept the stream open and stopped answering held the daemon until TCP gave up. The silence check returned from the writer, but the stream had been opened under the session's context, so the reader stayed in `Recv` and the session never ended. The first goroutine to fail now cancels the stream, and silence is checked in its own goroutine so a blocked `Send` does not stop it. The last backoff wait is cut at `ORPHAN_AFTER`, which could otherwise run about 30 seconds late.

### Added

- `go-daemon` rules for long-running Go programs with no inbound port: `architecture.md`, `runtime.md`, `lifecycle.md`, `outbound.md`, `subprocess.md`, `testing.md`, `contract.md` and `release.md`. They sit on `go/` beside `go-server/`; `installing-rules` copies `go` `go-daemon` for a Go daemon.
- Skills `scaffolding-go-daemons` (with an example daemon that builds, lints and passes its tests), `reviewing-go-daemon-changes`, `auditing-go-daemons` and `upgrading-go-daemons`.
- `frontend-native` rules for React Native and Expo apps: `app.md` (routes in a root `app/`, the app layer in `src/app/`), `platform.md`, `runtime.md`, `styling.md`, `accessibility.md`, `env.md`, `build.md` and `testing.md`. `installing-rules` copies `typescript` `frontend` `frontend-native` for an Expo app, and `reviewing-frontend-changes` checks them.
- `frontend/local-data.md`: data kept on the device through local adapters, the database handle, transactions, React Query over local data, migrations and seeds.
- `database/drizzle.md`: Drizzle with postgres-js for a NestJS server, and its migrations bundled into an Expo app. `installing-rules` copies it beside `database/postgres` for a Drizzle server, and `reviewing-server-changes` checks unnamed columns, moments without a time zone, Drizzle's own constraint names and ids the database makes.

## 2026-10-26

### Changed

- `git/commit.md`: a commit carries a DCO `Signed-off-by` line when the repository requires one, as a DCO check on its pull requests or its contributing guide does. The rule used to leave it out everywhere, which failed those checks.
- arthron 2.1 or later is required by `frontend/entity-data-access.md`, `server/adapters.md`, `scaffolding-entity-slices` and both review checklists. Under 2.0 a response whose status text is not Latin-1 (`500 실패`, under Node) or whose status is past 599 rejected with a `TypeError` or a `RangeError` instead of an `ArthronError`, so `apiErrors` let it through. The rules also point to `node_modules/arthron/llms.txt`.
- `setting-up-architecture-checks`: the dependency-cruiser check is verified to cruise more than 0 modules. With TypeScript 7 and no `@swc/core`, dependency-cruiser 18.7 reads nothing and still passes. The Go architecture test runs with `-count=1`: a cached run passed after a violating file was added.
- `frontend/entities.md`: with zod 4 the email value object is `z.email().brand<'Email'>()`; `z.string().email()` is deprecated there.

### Fixed

- `scaffolding-server-modules` example: two test names held an apostrophe inside a single-quoted string, so `nickname.vo.test.ts` and `user.mapper.test.ts` did not parse.
- `frontend/entity-data-access.md`: when `API_BASE_URL` is a path, `bearerAuth`'s `tokenOrigins` lists `location.origin`; the base URL itself threw a `TypeError`. A refresh request through `httpClient` passes `meta: { bearerAuth: false }`; one sent after an `await` in `refreshFn` hung on a 401.
