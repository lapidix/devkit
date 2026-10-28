#!/usr/bin/env bash
# Builds skills/scaffolding-go-daemons/example-daemon.md into a Go daemon and checks it:
# the skeleton in project/ supplies go.mod and tools/go.mod, the example supplies the rest.
# Steps: copy the skeleton to .build/, take .golangci.yml from rules/go/conventions.md and the
# Makefile from the example, extract the example, then the Makefile's targets: generate (buf lint,
# buf generate), lint (GOOS=linux), test (-race -shuffle=on, goleak), vuln, build and release.
# Between them: go mod tidy -diff, `bin/daemon version`, and buf breaking against the changes
# rules/go-daemon/contract.md says it reports. golangci-lint must be on PATH: the Makefile calls it.
# Usage: bash examples/go-daemon/check.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/../.." && pwd)
build="$here/.build"
example="$repo/skills/scaffolding-go-daemons/example-daemon.md"
conventions="$repo/rules/go/conventions.md"

step() { printf '\n==> %s\n' "$*"; }
tool() { go tool -modfile=tools/go.mod "$@"; } # rules/go/tooling.md

# block <language> <file>: prints the first fenced block of that language in the file.
block() {
  awk -v open="^\`\`\`$1\$" '$0 ~ open { inside = 1; found = 1; next } inside && /^```$/ { exit } inside { print } END { if (!found) exit 1 }' "$2"
}

step "Copy the skeleton to ${build#"$repo/"}"
rm -rf "$build"
mkdir -p "$build"
cp -R "$here/project/." "$build"

step "Take .golangci.yml from ${conventions#"$repo/"}"
# The rule's one yaml block is the configuration, so the harness lints with what the rule says.
block yaml "$conventions" > "$build/.golangci.yml" ||
  { echo "${conventions#"$repo/"} has no yaml block" >&2; exit 1; }
head -n 1 "$build/.golangci.yml" | grep -qx 'version: "2"' ||
  { echo "the yaml block in ${conventions#"$repo/"} is not a golangci-lint v2 configuration" >&2; exit 1; }

step "Take the Makefile from ${example#"$repo/"}"
# extract.sh writes only headings with a dot in the name, so it skips "## Makefile".
block makefile "$example" > "$build/Makefile" ||
  { echo "${example#"$repo/"} has no makefile block" >&2; exit 1; }

step "Extract ${example#"$repo/"}"
written=$(bash "$repo/examples/extract.sh" "$example" "$build")
echo "$written"
while IFS= read -r path; do
  if [ -e "$here/project/$path" ]; then
    echo "the example and examples/go-daemon/project both have $path" >&2
    exit 1
  fi
done <<< "$written"

cd "$build"

step "go version"
go version

step "make generate"
make generate
find gen -type f | sort

step "go mod tidy -diff, here and in tools/"
go mod tidy -diff
(cd tools && go mod tidy -diff)
echo "go.mod and go.sum are tidy"

step "go vet ./..."
go vet ./...

step "make lint ($(golangci-lint version --short))"
make lint

step "make test"
make test

step "make build, then bin/daemon version"
make build VERSION=check
[ "$(bin/daemon version)" = check ] ||
  { echo "bin/daemon version did not print the version make build set" >&2; exit 1; }
echo "bin/daemon version: check"

step "make release"
make release
(cd dist && sha256sum -c checksums.txt)

step "buf breaking reports the changes rules/go-daemon/contract.md names"
# Each change is applied to a copy, checked against the extracted contract, and undone. A pass would
# mean the FILE category in buf.yaml did not load or the change is not where the probe looked.
proto=proto/link/v1/link.proto
against=$(mktemp -d)
trap 'rm -rf "$against"' EXIT
cp -R buf.yaml proto "$against/"
expect_breaking() { # <what> <sed expression>
  cp "$proto" "$proto.orig"
  sed -i.bak "$2" "$proto" && rm "$proto.bak"
  if cmp -s "$proto" "$proto.orig"; then
    echo "the probe for $1 changed nothing in $proto" >&2
    exit 1
  fi
  if out=$(tool buf breaking --against "$against" 2>&1); then
    printf '%s\n%s passed buf breaking\n' "$out" "$1" >&2
    exit 1
  fi
  mv "$proto.orig" "$proto"
  echo "$1: reported"
}
expect_breaking "a renamed field" 's/string daemon_id = 1;/string daemon_name = 1;/'
expect_breaking "a changed go_package" 's|gen/link/v1;linkv1|gen/link/v2;linkv1|'
tool buf breaking --against "$against"
echo "the contract as extracted: no breaking changes"

step "make vuln"
make vuln

step "All checks passed"
