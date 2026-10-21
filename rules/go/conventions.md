---
paths:
  - "**/*.go"
  - "**/go.mod"
  - "**/.golangci.yml"
---

# Go conventions

## Format and lint

- `gofmt` formats every file, tabs included. Imports come in three groups — standard library, external, this module — separated by blank lines.
- golangci-lint v2 enforces both, with every other check, from one `.golangci.yml`:

```yaml
version: "2"

linters:
  default: standard # errcheck, govet, ineffassign, staticcheck, unused
  enable:
    - errorlint # %v that cuts the error chain, == instead of errors.Is
    - bodyclose # HTTP response bodies left open
    - noctx # HTTP requests without a context
    - containedctx # a context.Context stored in a struct
    - sqlclosecheck # rows left open
    - rowserrcheck # rows.Err() never checked
    - gosec
    - exhaustive # a switch over a value list that misses a value
    - revive
    - nolintlint
    - misspell
    - ireturn # constructors return concrete types
    - sloglint
    - forbidigo
  settings:
    revive:
      rules: # the default set without the rules that demand comments, and without unused-parameter, which flags every interface method that ignores an argument
        - name: blank-imports
        - name: context-as-argument
        - name: context-keys-type
        - name: dot-imports
        - name: empty-block
        - name: error-naming
        - name: error-return
        - name: error-strings
        - name: errorf
        - name: increment-decrement
        - name: indent-error-flow
        - name: range
        - name: receiver-naming
        - name: redefines-builtin-id
        - name: superfluous-else
        - name: time-naming
        - name: unexported-return
        - name: unreachable-code
        - name: var-declaration
        - name: var-naming
    sloglint:
      attr-only: true
      context: all
      static-msg: true
      key-naming-case: camel
    forbidigo:
      forbid:
        - pattern: ^fmt\.Print.*$
          msg: log through the injected *slog.Logger
        - pattern: ^log\.(Print|Fatal|Panic).*$
          msg: log through the injected *slog.Logger; only main exits
    nolintlint:
      require-explanation: true
      require-specific: true

formatters:
  enable:
    - gofmt
    - gci
  settings:
    gci:
      sections:
        - standard
        - default
        - localmodule
```

How the version is pinned and where it runs is in `rules/go/tooling.md`.

## Names

### Files

- snake_case. The folder is the package and states the role, so a file names only its content: `user.go`, `withdraw_user.go`, `user_repository.go`. No dots, no role suffix.
- A name ending in `_test`, `_linux` or `_amd64` is read as a build constraint; never end a name that way by accident.

### Packages

- The package name is the last folder name; never declare a different one.
- Short, lowercase, one word, named for what it provides. Never `util`, `helper` or `common` as a package name; a folder such as `internal/common/` only holds packages named for their job.
- Never shadow a standard library package used inside it: `httpapi`, not `http`; `logger`, not `log`.
- Alias an import only when two imported packages share a name (the server's alias rule is in `rules/go-server/architecture.md`).

### Identifiers

| Rule | Write | Not |
|---|---|---|
| Initialisms are all caps or all lower | `ID`, `userID`, `GRPCURL`, `httpapi` | `Id`, `GrpcUrl` |
| The package name is not repeated | `user.New`, `config.Load` | `user.NewUser`, `config.LoadConfig` |
| Getters have no `Get` | `u.Status()`, `c.Connection()` | `GetStatus()`, `GetConnection()` |
| One-method interfaces end in `-er`; larger ones are role nouns | `Hasher`, `AccessRevoker`, `UserRepository` | `ClientInterface`, `IUserRepository` |
| Receivers are one or two letters of the type, the same on every method | `func (u *User)` | `this`, `self` |
| Constants are MixedCaps too | `DefaultPageSize`, `maxRetries` | `DEFAULT_PAGE_SIZE` |
| Export only what another package uses | everything else starts lowercase | |

## Interfaces, constructors and receivers

- **The consumer declares the interface**, with only the methods it calls. An interface is never declared next to its implementation "in case": the consumer would inherit methods it does not use, and the implementation could not grow without changing every consumer.
- **Constructors return concrete types**: `func NewAccessRevoker(revokeAll *authmodule.RevokeAllTokens) *AccessRevoker`. The caller converts to an interface where it needs one ("accept interfaces, return structs"). `ireturn` enforces it; a function that genuinely returns one of several concrete types says so in its `nolint` reason.
- **Each implementation checks itself at compile time**: `var _ application.AccessRevoker = (*AccessRevoker)(nil)`. Go has no `implements`, so a drifted signature otherwise surfaces far from the cause.
- **Constructors take their dependencies as parameters**, or one options struct when there are many. A failure is a returned error; a constructor never calls `log.Fatal` or `panic`, which would leave the caller nothing to clean up.
- **Receivers**: pointer receivers for anything with state (aggregates, use cases, adapters); value receivers for small immutable values (value objects). One kind per type: if any method needs a pointer, all take one.

## Errors

- **Wrap what comes from outside** — the database, an external API, a library — with the operation and the subject's id: `fmt.Errorf("get user %s: %w", id, err)`. Always `%w`; `%v` cuts the chain. Messages are lowercase, short and never start with `failed to`, which piles up across layers (`failed to … : failed to …`).
- **Compare with `errors.Is` and `errors.As`**, never `==` or the message text.
- **Handle an error once**: log it or return it, never both, or one failure prints many times.
- **The lowest layer that knows a result is abnormal creates the error.** Layers above pass it up unchanged, or wrapped with context, and never re-create or swallow it. Only the edge — the HTTP error mapping, `main` — turns it into output. Which layer creates which error in a server is in `rules/go-server/domain.md`.
- **A nil error means "nothing" was a normal result:**

  | The method promises | It returns |
  |---|---|
  | A value that must exist (`FindByID`) | the not-found error when it does not |
  | An existence check (`ExistsByNickname`) | `(bool, error)` |
  | A value that may be absent (an open session, if any) | `(T, bool, error)`, the comma-ok form |
  | A list | an empty slice and a nil error |
  | A technical failure | the wrapped error |

  Never `(nil, nil)`: the caller cannot tell "absent" from "forgot to set".
- **`panic`, `log.Fatal` and `os.Exit` appear only in `main`.** `panic` is for programmer errors that cannot happen; input, configuration and I/O failures are returned. `main` calls `os.Exit(run())` so that `run`'s deferred cleanup finishes first.

## Comments

A comment says why, never what. Comments in project code are English, in plain declarative sentences:

```go
return ErrUserAlreadyWithdrawn // a second withdraw would overwrite the withdrawal time and restart the re-signup cooldown
```

- Exported identifiers need no doc comment. The godoc convention serves libraries that others import; in a server it mostly restates the name, so revive's comment rules are off. A doc comment that is written follows the rule above.
- Tool comments stay: `//go:generate`, `//go:build`, `// Code generated … DO NOT EDIT.` A `//nolint` names its linter and gives the reason: `//nolint:gosec // fixed key, tests only`.
- API documentation is not a comment: huma's `doc` tags and an operation's `Summary` are read by the API's users, so their language is chosen for those readers, by the project.
- The examples in these rule files keep English comments, matching the rule text.
