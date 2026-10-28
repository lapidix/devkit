# Changelog

What changed for projects that use these rules and skills, newest first. Every commit on `main` is a release (README, "Install"); this file lists the ones that change what a rule or skill asks of a project.

## 2026-10-28

### Fixed

- `go-daemon/outbound.md` and the `scaffolding-go-daemons` example: a server that kept the stream open and stopped answering held the daemon until TCP gave up. The silence check returned from the writer, but the stream had been opened under the session's context, so the reader stayed in `Recv` and the session never ended. The first goroutine to fail now cancels the stream, and silence is checked in its own goroutine so a blocked `Send` does not stop it. The last backoff wait is cut at `ORPHAN_AFTER`, which could otherwise run about 30 seconds late.

### Added

- `go-daemon` rules for long-running Go programs with no inbound port: `architecture.md`, `runtime.md`, `lifecycle.md`, `outbound.md`, `subprocess.md`, `testing.md`, `contract.md` and `release.md`. They sit on `go/` beside `go-server/`; `installing-rules` copies `go` `go-daemon` for a Go daemon.
- Skills `scaffolding-go-daemons` (with an example daemon that builds, lints and passes its tests), `reviewing-go-daemon-changes`, `auditing-go-daemons` and `upgrading-go-daemons`.

## 2026-10-26

### Changed

- `git/commit.md`: a commit carries a DCO `Signed-off-by` line when the repository requires one, as a DCO check on its pull requests or its contributing guide does. The rule used to leave it out everywhere, which failed those checks.
- arthron 2.1 or later is required by `frontend/entity-data-access.md`, `server/adapters.md`, `scaffolding-entity-slices` and both review checklists. Under 2.0 a response whose status text is not Latin-1 (`500 실패`, under Node) or whose status is past 599 rejected with a `TypeError` or a `RangeError` instead of an `ArthronError`, so `apiErrors` let it through. The rules also point to `node_modules/arthron/llms.txt`.
- `setting-up-architecture-checks`: the dependency-cruiser check is verified to cruise more than 0 modules. With TypeScript 7 and no `@swc/core`, dependency-cruiser 18.7 reads nothing and still passes. The Go architecture test runs with `-count=1`: a cached run passed after a violating file was added.
- `frontend/entities.md`: with zod 4 the email value object is `z.email().brand<'Email'>()`; `z.string().email()` is deprecated there.

### Fixed

- `scaffolding-server-modules` example: two test names held an apostrophe inside a single-quoted string, so `nickname.vo.test.ts` and `user.mapper.test.ts` did not parse.
- `frontend/entity-data-access.md`: when `API_BASE_URL` is a path, `bearerAuth`'s `tokenOrigins` lists `location.origin`; the base URL itself threw a `TypeError`. A refresh request through `httpClient` passes `meta: { bearerAuth: false }`; one sent after an `await` in `refreshFn` hung on a 401.
