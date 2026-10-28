# Changelog

What changed for projects that use these rules and skills, newest first. Every commit on `main` is a release (README, "Install"); this file lists the ones that change what a rule or skill asks of a project.

## 2026-10-28

### Added

- `go-daemon` rules for long-running Go programs with no inbound port: `architecture.md`, `runtime.md`, `lifecycle.md`, `outbound.md`, `subprocess.md`, `testing.md`, `contract.md` and `release.md`. They sit on `go/` beside `go-server/`; `installing-rules` copies `go` `go-daemon` for a Go daemon.
- Skills `scaffolding-go-daemons` (with an example daemon that builds, lints and passes its tests), `reviewing-go-daemon-changes`, `auditing-go-daemons` and `upgrading-go-daemons`.

## 2026-10-26

### Changed

- `git/commit.md`: a commit carries a DCO `Signed-off-by` line when the repository requires one, as a DCO check on its pull requests or its contributing guide does. The rule used to leave it out everywhere, which failed those checks.
- arthron 2.1 or later is required by `frontend/entity-data-access.md`, `server/adapters.md`, `scaffolding-entity-slices` and both review checklists. Under 2.0 a response whose status text is not Latin-1 (`500 실패`, under Node) or whose status is past 599 rejected with a `TypeError` or a `RangeError` instead of an `ArthronError`, so `apiErrors` let it through. The rules also point to `node_modules/arthron/llms.txt`.

### Fixed

- `frontend/entity-data-access.md`: when `API_BASE_URL` is a path, `bearerAuth`'s `tokenOrigins` lists `location.origin`; the base URL itself threw a `TypeError`. A refresh request through `httpClient` passes `meta: { bearerAuth: false }`; one sent after an `await` in `refreshFn` hung on a 401.
