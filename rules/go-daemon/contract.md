---
paths:
  - "**/proto/**"
  - "**/gen/**"
  - "**/buf.yaml"
  - "**/buf.gen.yaml"
---

# Go daemon contract

The messages a daemon and its server exchange are one contract, written once in protobuf and generated for both sides. This file covers where it lives, how it is generated, and how it changes without breaking the side that has not updated yet.

## One owner

- **The contract lives in one repository**, the daemon's, under `proto/{package}/v{major}/`. The server imports the generated Go package from the daemon's module at a tagged version; it never copies the `.proto` files or redeclares the types. Two copies of one contract drift apart, and the drift shows only in production.
- **Only `gen/` is public.** Everything else in the daemon's module is under `internal/`, which the server cannot import, so the contract is the one thing the two repositories share.
- Messages are named for the RPC (`ConnectRequest`, `ConnectResponse`) and the service ends in `Service`, as buf's `STANDARD` lint requires; a `oneof` inside each carries the kinds of message the stream moves.

```proto
// proto/link/v1/link.proto
syntax = "proto3";

package link.v1;

option go_package = "example.com/daemon/gen/link/v1;linkv1";

// LinkService is the server's side of the one connection a daemon opens.
service LinkService {
  // Connect is opened by the daemon; its first message is a Hello.
  rpc Connect(stream ConnectRequest) returns (stream ConnectResponse);
}

message ConnectRequest {
  oneof msg {
    Hello hello = 1;
    Heartbeat heartbeat = 2;
    Report report = 3;
    CommandResult command_result = 4;
  }
}

message ConnectResponse {
  oneof msg {
    Welcome welcome = 1;
    RunCommand run_command = 2;
    Heartbeat heartbeat = 3;
  }
}

message Hello {
  string daemon_id = 1;
  // token registers a new daemon once; resume_key reconnects one that has registered.
  string token = 2;
  string resume_key = 3;
  uint32 protocol_major = 4;
  string version = 5;
}

// Welcome, Heartbeat, Report, RunCommand and CommandResult follow; the whole file is in the
// scaffolding-go-daemons skill's example.
```

## Generating

```yaml
# buf.yaml
version: v2
modules:
  - path: proto
lint:
  use:
    - STANDARD
breaking:
  use:
    - FILE
```

```yaml
# buf.gen.yaml
version: v2
clean: true
plugins:
  - local: [go, tool, -modfile=tools/go.mod, protoc-gen-go]
    out: gen
    opt: paths=source_relative
  - local: [go, tool, -modfile=tools/go.mod, protoc-gen-go-grpc]
    out: gen
    opt: paths=source_relative
```

- **buf, `protoc-gen-go` and `protoc-gen-go-grpc` are tools in `tools/go.mod`** and run with `go tool -modfile=tools/go.mod` (`rules/go/tooling.md`). No `protoc` is installed and no plugin comes from a remote registry, so every machine generates the same code.
- **`protoc-gen-go` belongs to the `google.golang.org/protobuf` module**, so its version in `tools/go.mod` is whatever buf requires. The generated header names it; the app's own `google.golang.org/protobuf` stays at or above that version.
- **`make generate` runs `buf lint` and `buf generate`, and the generated code is committed**: the repository builds with `go build ./...` straight after cloning, and the server imports a package that exists in the tagged source. CI regenerates and fails on a diff.
- **`clean: true`** removes generated files whose `.proto` is gone, so `gen/` never keeps a type nothing defines.

## Changing it

- **`buf breaking` runs in CI against the base branch**: `buf breaking --against '.git#branch=main'`. `FILE` is the strictest category: besides what breaks the wire, it reports what breaks code generated from it — a renamed field, a changed `go_package` — which matters because the server compiles against the generated package.
- **A minor change only adds**: a new field with a new number, a new message, a new member of a `oneof`. An old peer ignores what it does not know, so either side may update first.
- **A removed field's number and name are reserved** (`reserved 6; reserved "old_name";`), never reused: an old peer would read the new field as the old one.
- **A breaking change is a new major version**: a new package, `link.v2`, beside `v1`, and the server serves both until no daemon speaks `v1`. The daemon sends its major in its first message (`protocol_major`), and the server refuses one it does not serve, with `codes.FailedPrecondition` and the versions it accepts, instead of misreading it.
- **The daemon's release notes list every contract change** (`rules/go-daemon/release.md`), so the server's owners know which tag to update to.
