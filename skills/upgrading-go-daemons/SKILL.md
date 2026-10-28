---
name: upgrading-go-daemons
description: Use when upgrading a Go daemon's Go version, tools or dependencies, when govulncheck reports a vulnerability it calls, after changing its contract, or when cutting a release of it.
---

# Upgrading Go daemons

A daemon's upgrades reach code its team does not run: the server that imports its contract and the images that copy its binary. Each step below keeps the daemon building and its tests passing, and ends with a version and a changelog entry that tell those consumers what changed. The rules are `rules/go/tooling.md`, `rules/go-daemon/contract.md` and `rules/go-daemon/release.md`.

The rule files named here are in the project's `.claude/rules/{area}/` (`rules/frontend/testing.md` is `.claude/rules/frontend/testing.md`). When the project lacks one, read the copy that ships with this skill, in the `rules/` folder two levels above this skill's folder, and say in your report that the project does not have it; the `installing-rules` skill copies it in.

## Steps

1. **Scope.** Decide what this change upgrades, from the user or the trigger: the Go version, the tools in `tools/go.mod`, golangci-lint, the app's dependencies, the contract, or a release of what is already on `main`. One kind per change: a Go upgrade and a dependency's major version in one diff cannot be told apart when a test fails. Start from a clean tree with `make lint` and `make test` passing. Done when the kind is named and the baseline passes.

2. **Go.** Raise the `go` line of `go.mod` and of `tools/go.mod` together, to the newest patch of the target release (`rules/go/tooling.md`). Raise golangci-lint in CI and locally at the same time when the new Go is newer than the one it was built with. Done when `go version` in CI and locally match the `go` line.

3. **Tools.** Upgrade each tool with `go get -modfile=tools/go.mod -tool <path>@<version>`, then `cd tools && go mod tidy`. buf pins the `google.golang.org/protobuf` version that `protoc-gen-go` comes from (`rules/go-daemon/contract.md`); after upgrading it, raise the app's `google.golang.org/protobuf` to at least that version. Then run `make generate` and read the diff in `gen/`: only the version header and generator output should change. Done when `make generate` leaves no further diff and the app builds against the regenerated code.

4. **Dependencies.** List what can move with `go list -m -u all`.
   - Patch and minor versions: `go get <module>@<version>` per module, or `go get -u=patch ./...` for patches only, then `go mod tidy`.
   - A new major version is its own change, read against its release notes first.
   - For gRPC, read the release notes for deprecations the daemon uses: a deprecated call still compiles, and `staticcheck` in `make lint` reports it (SA1019).
   - A vulnerability govulncheck reports in code the daemon calls is fixed by the version it names, in this change, before anything else.

   Done when `go list -m -u all` shows only the versions deliberately left behind, each with its reason in the report.

5. **Contract.** When the change touches `proto/`: `make generate`, then `buf breaking --against '.git#branch=main'`. No report means a minor change. A report means either reworking the change into an addition, or a new major package beside the old one (`rules/go-daemon/contract.md`); never a breaking change inside `v1`. Done when `buf breaking` passes or the new major package exists and the server's owners have been told.

6. **Verify.** `make lint`, `make test`, `make vuln`, `make generate` with no diff, `go mod tidy` with no diff in both modules, and `make build` followed by `bin/{binary} version`. Done when every check passes and the binary reports its version.

7. **Release.** When the upgrade ships:
   - pick the version by `rules/go-daemon/release.md`: major for a new contract major or a new required setting, minor for an addition, patch for neither
   - add the `CHANGELOG.md` entry: contract changes, configuration changes, behavior changes, and the dependency or Go upgrade with the vulnerability it fixes
   - after the change is merged, tag `main`: `git tag vX.Y.Z && git push origin vX.Y.Z`; the tag's CI job runs `make release VERSION=vX.Y.Z` and `gh release create vX.Y.Z dist/*`
   - give the consumers the new version and the line for their platform from `checksums.txt`, for their `ADD --checksum`

   Done when the release has its binaries and checksums, and the report names who must update.

8. **Report.** What was upgraded from which version to which, each check from step 6 with its command, the versions deliberately left behind and why, the version released and the consumers to tell.
