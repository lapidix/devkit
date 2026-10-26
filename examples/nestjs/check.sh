#!/usr/bin/env bash
# Builds skills/scaffolding-server-modules/example-module.md into a NestJS project and checks it:
# the skeleton in project/ supplies what the example assumes, the example supplies the module.
# Steps: copy the skeleton to .build/, extract the example, npm ci, prisma generate, tsc, vitest,
# dependency-cruiser with the server rules of skills/setting-up-architecture-checks.
# Usage: bash examples/nestjs/check.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/../.." && pwd)
build="$here/.build"
example="$repo/skills/scaffolding-server-modules/example-module.md"
arch="$repo/skills/setting-up-architecture-checks"

step() { printf '\n==> %s\n' "$*"; }

step "Copy the skeleton to ${build#"$repo/"}"
rm -rf "$build"
mkdir -p "$build"
cp -R "$here/project/." "$build"

step "Extract ${example#"$repo/"}"
bash "$repo/examples/extract.sh" "$example" "$build"

cd "$build"

step "npm ci"
npm ci --no-audit --no-fund

step "prisma generate"
# Generating needs no database, but prisma.config.ts reads DIRECT_URL (rules/database/prisma.md).
# CHECKPOINT_DISABLE turns off Prisma's update check and its banner.
DIRECT_URL=postgresql://placeholder:placeholder@localhost:5432/placeholder CHECKPOINT_DISABLE=1 \
  node_modules/.bin/prisma generate

step "tsc --noEmit"
node_modules/.bin/tsc --noEmit
echo "no type errors"

step "vitest run"
node_modules/.bin/vitest run

# A single server, as SKILL.md steps 2 and 3 set it up: the rule file as it ships, and the root
# config without the fsd, entity and package rule sets, pointed at tsconfig.json.
step "dependency-cruiser with ${arch#"$repo/"}/server-rules.cjs"
mkdir -p .dependency-cruiser
cp "$arch/server-rules.cjs" .dependency-cruiser/
grep -v -e fsdRules -e entityRules -e packageRules "$arch/dependency-cruiser.cjs" |
  sed "s/fileName: 'tsconfig.depcruise.json'/fileName: 'tsconfig.json'/" > .dependency-cruiser.cjs
node_modules/.bin/depcruise src --config .dependency-cruiser.cjs

step "dependency-cruiser rejects the violations in SKILL.md step 6"
# Each file breaks one rule; the check must fail and name it, or the rule matches nothing.
expect_violation() { # <rule> <file> <content>
  mkdir -p "$(dirname "$2")"
  printf '%s\n' "$3" > "$2"
  if out=$(node_modules/.bin/depcruise src --config .dependency-cruiser.cjs 2>&1); then
    echo "$2 passed, but it breaks $1" >&2
    exit 1
  fi
  if ! grep -q "$1" <<< "$out"; then
    printf '%s\n%s fails without naming %s\n' "$out" "$2" "$1" >&2
    exit 1
  fi
  rm "$2"
  echo "$1: rejected"
}
expect_violation server-domain-is-pure src/modules/user/domain/arch-probe.ts \
  "import { Injectable } from '@nestjs/common'; export const probe = Injectable;"
expect_violation server-application-no-other-modules src/modules/user/application/arch-probe.ts \
  "import { AuthModule } from '@/modules/auth'; export const probe = AuthModule;"
# A type-only import is seen only with tsPreCompilationDeps; rules/database/prisma.md keeps rows out of the domain.
expect_violation server-domain-is-pure src/modules/user/domain/arch-probe.ts \
  "import type { User } from '@/generated/prisma/client'; export type Probe = User;"

step "All checks passed"
