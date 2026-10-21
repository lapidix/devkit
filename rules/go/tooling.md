---
paths:
  - "**/Makefile"
  - "**/go.mod"
  - "**/tools/go.mod"
  - "**/Dockerfile"
  - "**/.golangci.yml"
  - ".github/workflows/**"
---

# Go tooling, builds and CI

## Makefile

Every task a person or an agent runs is a `make` target:

```makefile
VERSION ?= dev
TOOL := go tool -modfile=tools/go.mod

.PHONY: run generate lint test vuln build

run: ## the app never reads .env itself, so the shell loads it first
	set -a && . ./.env && set +a && go run .

generate:
	$(TOOL) sqlc generate

lint:
	golangci-lint run

test:
	go test -race -shuffle=on ./...

vuln:
	$(TOOL) govulncheck ./...

build:
	go build -trimpath -ldflags "-s -w -X main.version=$(VERSION)" -o bin/server .
```

`run` is one line because make starts a new shell for each line; the variables a line loads are gone on the next.

## Versions

- **Go**: the `go` line of `go.mod`, kept on the newest patch release (`go 1.26.10`, not `go 1.26.0`). CI reads it with `go-version-file: go.mod`. Standard-library fixes ship in patch releases, and govulncheck reports the ones an older patch lacks.
- **Go-built tools** (sqlc, goose, govulncheck) live in their own module, `tools/go.mod`, and run with `go tool -modfile=tools/go.mod <tool>`. Every machine then runs the same version, and nothing is installed globally. A separate module because a `tool` line in the app's `go.mod` puts the tool's dependencies into the app's graph: sqlc alone adds about 45 modules, can upgrade the app's own dependencies, and raises the app's `go` line to its own minimum.
  - Add or upgrade: `go get -modfile=tools/go.mod -tool github.com/sqlc-dev/sqlc/cmd/sqlc@v1.31.1`, then `cd tools && go mod tidy`. A tidy run from the root would read the app's packages as part of the tools module.
  - `tools/go.mod`'s `go` line never exceeds the app's: the toolchain is chosen from the root `go.mod`, and a higher tools version stops every `go tool` call. Raise both together.
- **golangci-lint** is the exception: its documentation recommends the released binary over building it with `go`. CI pins the version in the action; locally, use the same version. Raise it together with Go: a binary built with an older Go refuses a configuration that targets a newer one.

## Builds

- The version is set at build time, `-ldflags "-X main.version=…"`, logged at startup and returned by `/api/health`, so the running build is always known.
- Images are multi-stage. pgx is pure Go, so the binary is static and the runtime stage is distroless and non-root:

```dockerfile
FROM golang:1.26 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /server .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /server /server
ENTRYPOINT ["/server"]
```

- Migrations run in the pipeline before this image starts, never from it at boot (`rules/database/conventions.md`).

## CI

Each check is its own step (`rules/monorepo/ci.md`):

| Step | Catches |
|---|---|
| `golangci-lint run` | formatting (gofmt, gci) and every linter |
| `go build ./...` | the build |
| `go test -race -shuffle=on ./...` | tests, data races, tests that depend on order, and the architecture test. Database tests run against a service container with every migration applied |
| `make generate && git diff --exit-code` | queries changed without regenerating |
| `go mod tidy && git diff --exit-code`, and the same in `tools/` | `go.mod` and `go.sum` out of date |
| `make vuln` | known vulnerabilities in dependencies and the standard library, reported only where the code actually calls them |
