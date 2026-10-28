#!/usr/bin/env bash
# Builds skills/scaffolding-entity-slices/example-slice.md into a frontend project and checks it:
# the skeleton in project/ supplies package.json, the lockfile, tsconfig and the shared helpers the
# example imports; the example becomes src/entities/user/.
# Steps: copy the skeleton to .build/, extract the example, npm ci, tsc, vitest, dependency-cruiser
# with the fsd and entity rules of skills/setting-up-architecture-checks.
# Usage: bash examples/frontend/check.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/../.." && pwd)
build=$here/.build
example=$repo/skills/scaffolding-entity-slices/example-slice.md
arch=$repo/skills/setting-up-architecture-checks

step() { printf '\n==> %s\n' "$*"; }

step "Copy the skeleton to ${build#"$repo/"}"
rm -rf "$build"
mkdir -p "$build"
cp -R "$here/project/." "$build/"

step "Extract ${example#"$repo/"} into src/entities/user/"
bash "$repo/examples/extract.sh" "$example" "$build/src/entities/user"

cd "$build"

step "npm ci (node $(node --version), npm $(npm --version))"
npm ci --no-audit --no-fund

step "tsc --noEmit"
node_modules/.bin/tsc --noEmit
echo "no type errors"

step "vitest run"
node_modules/.bin/vitest run

# A single app, as SKILL.md steps 2 and 3 set it up: the rule files as they ship, and the root
# config without the server and package rule sets, pointed at tsconfig.json.
step "dependency-cruiser with ${arch#"$repo/"}/fsd-rules.cjs and entity-rules.cjs"
mkdir -p .dependency-cruiser
cp "$arch/fsd-rules.cjs" "$arch/entity-rules.cjs" .dependency-cruiser/
grep -v -e serverRules -e packageRules "$arch/dependency-cruiser.cjs" |
  sed "s/fileName: 'tsconfig.depcruise.json'/fileName: 'tsconfig.json'/" > .dependency-cruiser.cjs
node_modules/.bin/depcruise src --config .dependency-cruiser.cjs

step "dependency-cruiser rejects the violations in SKILL.md step 6"
# Each file breaks one rule; the check must fail and name it. A pass would mean a rule file did not
# load, @/ did not resolve, or dependency-cruiser could not load TypeScript and cruised nothing.
expect_violation() { # <rule> <file> <content>
  mkdir -p "$(dirname "$2")"
  printf '%s\n' "$3" > "$2"
  if out=$(node_modules/.bin/depcruise src --config .dependency-cruiser.cjs 2>&1); then
    printf '%s\n%s passed, but it breaks %s\n' "$out" "$2" "$1" >&2
    exit 1
  fi
  if ! grep -q "$1" <<< "$out"; then
    printf '%s\n%s fails without naming %s\n' "$out" "$2" "$1" >&2
    exit 1
  fi
  rm "$2"
  echo "$1: rejected"
}
mkdir -p src/features/probe
printf '%s\n' "export const probe = 'probe';" > src/features/probe/index.ts
# A type-only import is seen only with tsPreCompilationDeps.
expect_violation entity-infrastructure-internals src/features/probe/arch-probe.ts \
  "import type { UserDto } from '@/entities/user/infrastructure/dto/user.dto'; export type Probe = UserDto;"
expect_violation fsd-layer-direction-entities src/entities/user/arch-probe.ts \
  "import { probe } from '@/features/probe'; export const userProbe = probe;"
rm -r src/features

step "All checks passed"
