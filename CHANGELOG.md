# Changelog

What changed for projects that use these rules and skills, newest first. Every commit on `main` is a release (README, "Install"); this file lists the ones that change what a rule or skill asks of a project.

## 2026-10-28

### Changed

- The frontend rules are split like `go/` under `go-server/` and `go-daemon/`. `frontend/` keeps what any React app follows, under the same file names; what needs a browser moved, with its wording, to `frontend-web/`: the SPA and Next.js layouts and URL-based routes (`frontend/app.md` → `frontend-web/app.md`), URL state and `useSearchParamState` (`frontend/pages.md`, `frontend/shared.md` → `frontend-web/routing.md`), server components, server prefetching and dehydration (`frontend/react.md`, `frontend/pages.md`, `frontend/shared.md` → `frontend-web/nextjs.md`), Tailwind's `cn()` (`frontend-web/styling.md`), semantic elements and `<button type>` (`frontend-web/accessibility.md`), and jsdom, Testing Library and `userEvent` (`frontend-web/testing.md`). A React or Next.js project copies `frontend-web` beside `frontend`; updating `frontend` alone drops those rules. `installing-rules` copies `typescript` `frontend` `frontend-web` for a React or Next.js app.
- `frontend/entity-data-access.md`: an entity that also keeps data on the device has a local adapter in `infrastructure/db/` and exports both instances. The `entity-infrastructure-internals` rule in `setting-up-architecture-checks` keeps `infrastructure/db/*.table.ts` inside `infrastructure/`.

### Fixed

- `go-daemon/outbound.md` and the `scaffolding-go-daemons` example: a server that kept the stream open and stopped answering held the daemon until TCP gave up. The silence check returned from the writer, but the stream had been opened under the session's context, so the reader stayed in `Recv` and the session never ended. The first goroutine to fail now cancels the stream, and silence is checked in its own goroutine so a blocked `Send` does not stop it. The last backoff wait is cut at `ORPHAN_AFTER`, which could otherwise run about 30 seconds late.

### Added

- `go-daemon` rules for long-running Go programs with no inbound port: `architecture.md`, `runtime.md`, `lifecycle.md`, `outbound.md`, `subprocess.md`, `testing.md`, `contract.md` and `release.md`. They sit on `go/` beside `go-server/`; `installing-rules` copies `go` `go-daemon` for a Go daemon.
- Skills `scaffolding-go-daemons` (with an example daemon that builds, lints and passes its tests), `reviewing-go-daemon-changes`, `auditing-go-daemons` and `upgrading-go-daemons`.
- `frontend-native` rules for React Native and Expo apps: `app.md` (routes in a root `app/`, the app layer in `src/app/`), `platform.md`, `runtime.md`, `styling.md`, `accessibility.md`, `env.md`, `build.md` and `testing.md`. `installing-rules` copies `typescript` `frontend` `frontend-native` for an Expo app, and `reviewing-frontend-changes` checks them.
- `frontend/local-data.md`: data kept on the device through local adapters, the database handle, transactions, React Query over local data, migrations and seeds.

## 2026-10-26

### Changed

- `git/commit.md`: a commit carries a DCO `Signed-off-by` line when the repository requires one, as a DCO check on its pull requests or its contributing guide does. The rule used to leave it out everywhere, which failed those checks.
- arthron 2.1 or later is required by `frontend/entity-data-access.md`, `server/adapters.md`, `scaffolding-entity-slices` and both review checklists. Under 2.0 a response whose status text is not Latin-1 (`500 실패`, under Node) or whose status is past 599 rejected with a `TypeError` or a `RangeError` instead of an `ArthronError`, so `apiErrors` let it through. The rules also point to `node_modules/arthron/llms.txt`.
- `setting-up-architecture-checks`: the dependency-cruiser check is verified to cruise more than 0 modules. With TypeScript 7 and no `@swc/core`, dependency-cruiser 18.7 reads nothing and still passes. The Go architecture test runs with `-count=1`: a cached run passed after a violating file was added.
- `frontend/entities.md`: with zod 4 the email value object is `z.email().brand<'Email'>()`; `z.string().email()` is deprecated there.

### Fixed

- `scaffolding-server-modules` example: two test names held an apostrophe inside a single-quoted string, so `nickname.vo.test.ts` and `user.mapper.test.ts` did not parse.
- `frontend/entity-data-access.md`: when `API_BASE_URL` is a path, `bearerAuth`'s `tokenOrigins` lists `location.origin`; the base URL itself threw a `TypeError`. A refresh request through `httpClient` passes `meta: { bearerAuth: false }`; one sent after an `await` in `refreshFn` hung on a 401.
