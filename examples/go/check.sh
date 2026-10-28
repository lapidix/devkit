#!/usr/bin/env bash
# Builds skills/scaffolding-go-modules/example-module.md into a Go server and checks it:
# the skeleton in project/ supplies go.mod, tools/go.mod and the packages the example
# assumes, the example supplies the user module.
# Steps: copy the skeleton to .build/, take .golangci.yml from rules/go/conventions.md,
# extract the example, add internal/archtest from skills/setting-up-architecture-checks,
# sqlc generate, go mod tidy -diff, go build, go vet, golangci-lint, goose up, go test,
# the architecture test against the violations in its SKILL.md, govulncheck.
# The database tests run when TEST_DATABASE_URL is set, after goose applies migrations/;
# without it they skip, and fail with CI=true (rules/database/conventions.md). This script
# never starts a database. GOLANGCI_LINT names the binary (default: golangci-lint on PATH).
# Usage: bash examples/go/check.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/../.." && pwd)
build="$here/.build"
example="$repo/skills/scaffolding-go-modules/example-module.md"
arch="$repo/skills/setting-up-architecture-checks"
conventions="$repo/rules/go/conventions.md"
lint=${GOLANGCI_LINT:-golangci-lint}

step() { printf '\n==> %s\n' "$*"; }
tool() { go tool -modfile=tools/go.mod "$@"; } # rules/go/tooling.md

step "Copy the skeleton to ${build#"$repo/"}"
rm -rf "$build"
mkdir -p "$build"
cp -R "$here/project/." "$build"

step "Take .golangci.yml from ${conventions#"$repo/"}"
# The rule's one yaml block is the configuration, so the harness lints with what the rule says.
awk '/^```yaml$/ { inside = 1; found = 1; next } inside && /^```$/ { exit } inside { print } END { if (!found) exit 1 }' \
  "$conventions" > "$build/.golangci.yml" ||
  { echo "${conventions#"$repo/"} has no yaml block" >&2; exit 1; }
head -n 1 "$build/.golangci.yml" | grep -qx 'version: "2"' ||
  { echo "the yaml block in ${conventions#"$repo/"} is not a golangci-lint v2 configuration" >&2; exit 1; }

step "Extract ${example#"$repo/"}"
written=$(bash "$repo/examples/extract.sh" "$example" "$build")
echo "$written"
while IFS= read -r path; do
  if [ -e "$here/project/$path" ]; then
    echo "the example and examples/go/project both have $path" >&2
    exit 1
  fi
done <<< "$written"

step "Copy ${arch#"$repo/"}/arch_test.go to internal/archtest/"
mkdir -p "$build/internal/archtest"
cp "$arch/arch_test.go" "$build/internal/archtest/"

cd "$build"

step "go version"
go version

step "sqlc generate"
tool sqlc generate
find internal -path '*/sqlcgen/*' -type f | sort

step "go mod tidy -diff, here and in tools/"
go mod tidy -diff
(cd tools && go mod tidy -diff)
echo "go.mod and go.sum are tidy"

step "go build ./..."
go build ./...

step "go vet ./..."
go vet ./...

step "golangci-lint run ($("$lint" version --short))"
"$lint" run

if [ -n "${TEST_DATABASE_URL:-}" ]; then
  step "goose up on TEST_DATABASE_URL"
  tool goose -dir migrations postgres "$TEST_DATABASE_URL" up
else
  step "TEST_DATABASE_URL is not set: the database tests skip, and fail with CI=true"
fi

step "go test -race -shuffle=on ./..."
go test -race -shuffle=on ./...

step "The architecture test rejects the violations in SKILL.md (Go server, step 3)"
# Each file breaks one rule; the test must fail and name it. A pass would mean packages.Load
# found nothing to check. -count=1: a cached pass does not see a new file.
expect_violation() { # <rule> <file> <content>
  printf '%s\n' "$3" > "$2"
  if out=$(go test -count=1 ./internal/archtest/ 2>&1); then
    echo "$2 passed, but it breaks $1" >&2
    exit 1
  fi
  if ! grep -q "$1:" <<< "$out"; then
    printf '%s\n%s fails without naming %s\n' "$out" "$2" "$1" >&2
    exit 1
  fi
  rm "$2"
  echo "$1: rejected"
}
expect_violation "rule 1" internal/modules/user/domain/arch_probe.go \
  $'package domain\n\nimport "example.com/server/internal/infrastructure/database"\n\nvar _ = database.IsUniqueViolation'
expect_violation "rule 3" internal/modules/user/adapters/in/httpapi/arch_probe.go \
  $'package httpapi\n\nimport "example.com/server/internal/modules/user/domain"\n\nvar _ = domain.ErrUserNotFound'
expect_violation "rule 5" internal/modules/auth/application/arch_probe.go \
  $'package application\n\nimport "example.com/server/internal/modules/user/adapters/out/persistence"\n\nvar _ = persistence.NewUserRepository'
expect_violation "rule 6" internal/modules/user/arch_probe.go \
  $'package user\n\nimport "example.com/server/internal/modules/user/adapters/out/persistence"\n\nvar _ = persistence.NewUserRepository'
expect_violation "rule 8" internal/modules/user/adapters/out/persistence/arch_probe.go \
  $'package persistence\n\nimport "example.com/server/internal/modules/user/testkit"\n\nvar _ = testkit.User'

step "govulncheck ./..."
tool govulncheck ./...

step "All checks passed"
