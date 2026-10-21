#!/usr/bin/env bash
# Checks that every rule and skill is listed in README.md and in the
# using-lapidix-skills catalog, so neither falls behind the repo.
# Usage: bash scripts/check-catalog.sh
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
catalog="$repo/skills/using-lapidix-skills/SKILL.md"
missing=0

expect() { # expect DOC NAME
  grep -qF "\`$2\`" "$1" || { echo "${1#"$repo"/}: \`$2\` is not listed"; missing=1; }
}

for file in "$repo"/rules/*/*.md; do
  expect "$repo/README.md" "${file#"$repo"/rules/}"
  expect "$catalog" "${file#"$repo"/rules/}"
done
for dir in "$repo"/skills/*/; do
  skill=$(basename "$dir")
  expect "$repo/README.md" "$skill"
  [ "$skill" = using-lapidix-skills ] || expect "$catalog" "$skill"
done

[ "$missing" -eq 0 ] && echo "every rule and skill is listed in README.md and the catalog"
exit "$missing"
