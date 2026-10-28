---
paths:
  - "**/Makefile"
  - "**/Dockerfile"
  - "**/CHANGELOG.md"
  - ".github/workflows/**"
---

# Go daemon releases

A server is deployed as its own image (`rules/go/tooling.md`). A daemon often is not: it is a binary that another image copies in, or that a host installs, and it runs next to code its own team does not build. This file is how it is versioned, built and handed over.

## Versions

- **Every release is a semver tag on `main`, `vX.Y.Z`.** The tag is also the Go module version the server imports the contract at (`rules/go-daemon/contract.md`), so one number names the binary and the contract it speaks.
- **The major version moves with the contract's major**: a daemon that speaks `link.v2` is `v2.0.0`. Go requires a module at `v2` or later to end its path in `/v2`, so the server's import path changes in the same release, and the old path keeps serving `v1`. A minor version adds without breaking either side; a patch changes neither the contract nor the configuration.
- **A new required setting is a breaking change** for whoever deploys the daemon, even when the contract is untouched: it gets a major version or a default.
- **`CHANGELOG.md` has one entry per tag**, newest first, in three parts: contract changes (with the messages and fields), configuration changes (with the variables), and behavior changes. Whoever updates the server or the deployment reads only this.

## Building

```makefile
VERSION ?= dev
TOOL := go tool -modfile=tools/go.mod
LDFLAGS := -s -w -X main.version=$(VERSION)
PLATFORMS := linux/amd64 linux/arm64

.PHONY: run generate lint test vuln build release

run: ## the app never reads .env itself, so the shell loads it first
	set -a && . ./.env && set +a && go run .

generate:
	$(TOOL) buf lint
	$(TOOL) buf generate

lint: ## the daemon runs on Linux, so lint sees the Linux build
	GOOS=linux golangci-lint run

test:
	go test -race -shuffle=on ./...

vuln:
	$(TOOL) govulncheck ./...

build:
	CGO_ENABLED=0 go build -trimpath -ldflags "$(LDFLAGS)" -o bin/daemon .

release: ## one static binary per platform and their checksums, in dist/
	rm -rf dist && mkdir -p dist
	for p in $(PLATFORMS); do \
		CGO_ENABLED=0 GOOS=$${p%/*} GOARCH=$${p#*/} go build -trimpath -ldflags "$(LDFLAGS)" -o dist/daemon_$${p%/*}_$${p#*/} . || exit 1; \
	done
	cd dist && sha256sum daemon_* > checksums.txt
```

- **The binary is static** (`CGO_ENABLED=0`), so it runs in whatever image copies it in: distroless, Alpine or a full distribution.
- **`PLATFORMS` lists where the daemon runs**, and no more. Every entry is a binary to build and a platform to test; one nobody runs is one nobody notices failing.
- **`lint` runs as the platform the daemon runs on.** Types in `syscall` differ between Linux and macOS (`Statfs_t.Bsize` is `int64` on one and `uint32` on the other), so a `//nolint` that one build needs is reported unused by the other; linting the Linux build checks the code that ships.
- **`dist/` is not committed**; a tag's CI job builds it and attaches the binaries and `checksums.txt` to the GitHub release (`gh release create "$TAG" dist/*`).

## Handing it over

```dockerfile
# Dockerfile of the image that runs the daemon (the consumer's repository)
FROM debian:bookworm-slim
ARG DAEMON_VERSION=v0.1.0
ARG DAEMON_SHA256=<the linux_amd64 line of that release's checksums.txt>
ADD --checksum=sha256:${DAEMON_SHA256} \
    https://github.com/example/daemon/releases/download/${DAEMON_VERSION}/daemon_linux_amd64 /usr/local/bin/daemon
RUN chmod 0755 /usr/local/bin/daemon
ENTRYPOINT ["/usr/local/bin/daemon"]
```

- **The consumer pins a version and its checksum.** `ADD --checksum` (BuildKit, Dockerfile syntax 1.6 or later) fails the build when the file differs from the one released, so a replaced release asset cannot slip into an image.
- **Never `latest`, never a branch**: an image rebuilt next week would carry a different daemon with the same tag.
- **The daemon is the process the container runs, or a child of an init** (`tini`) when it starts processes of its own: a process whose parent exits is handed to PID 1, and a daemon at PID 1 that never waits for it leaves it a zombie. The daemon waits for its own children (`rules/go-daemon/subprocess.md`); reaping the rest is init's job.
- **A daemon with its own image** (one that runs alone) follows the image rules of `rules/go/tooling.md`: multi-stage, distroless, non-root.

## Compatibility window

- **The server accepts the daemon's current major and the one before it** for as long as the old one is deployed, so the server can be updated before the daemons.
- **A daemon refuses nothing on its side**: it reports its version and major when it registers, and the server decides (`rules/go-daemon/contract.md`).
