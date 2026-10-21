#!/usr/bin/env bash
# Copies rule areas into a project's .claude/rules/{area}/. They are copied,
# not linked: Claude Code does not load a rule with paths: through a symlink
# that leaves the project.
# Usage: bash scripts/copy-rules.sh [--update] [--prefix <app folder>]... <project> <area | area/file>...
#   --prefix apps/web puts each "**/…" glob under apps/web, for a monorepo app;
#   given twice, each glob is listed once per app. Rerun with the same flags.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)

usage() {
  echo "usage: bash scripts/copy-rules.sh [--update] [--prefix <app folder>]... <project> <area | area/file>..." >&2
  echo "areas: $(cd "$repo/rules" && ls -d */ | tr -d / | tr '\n' ' ')" >&2
  exit 1
}

update=false
prefixes=()
while [ $# -gt 0 ]; do
  case $1 in
    --update) update=true; shift ;;
    --prefix) [ $# -ge 2 ] || usage; prefixes+=("${2%/}"); shift 2 ;;
    -*) usage ;;
    *) break ;;
  esac
done
[ $# -ge 2 ] || usage
project=$1
shift
[ -d "$project" ] || { echo "no such project folder: $project" >&2; exit 1; }

# render SOURCE: the rule as the project gets it, each "**/…" glob in its paths: under every --prefix
render() {
  if [ ${#prefixes[@]} -eq 0 ]; then cat "$1"; return; fi
  awk -v prefixes="${prefixes[*]}" '
    BEGIN { n = split(prefixes, prefix, " ") }
    NR == 1 && $0 == "---" { front = 1; print; next }
    front && $0 == "---" { front = 0; print; next }
    front && /^  - "\*\*\// {
      rest = substr($0, length("  - \"**/") + 1)
      for (i = 1; i <= n; i++) print "  - \"" prefix[i] "/**/" rest
      next
    }
    { print }
  ' "$1"
}

rendered=$(mktemp)
trap 'rm -f "$rendered"' EXIT

differs=0
for arg in "$@"; do
  case $arg in
    */*) # one file of an area: database/postgres
      area=${arg%%/*}
      file=${arg#*/}
      sources=("$repo/rules/$area/${file%.md}.md") ;;
    *)
      area=$arg
      sources=("$repo/rules/$area"/*.md) ;;
  esac
  [ -f "${sources[0]}" ] || { echo "no such area or rule file: $arg" >&2; usage; }
  mkdir -p "$project/.claude/rules/$area"
  for source in "${sources[@]}"; do
    dest="$project/.claude/rules/$area/$(basename "$source")"
    render "$source" > "$rendered"
    if [ ! -e "$dest" ]; then
      cp "$rendered" "$dest"
      echo "added    $dest"
    elif cmp -s "$rendered" "$dest"; then
      echo "same     $dest"
    elif $update; then
      cp "$rendered" "$dest"
      echo "updated  $dest"
    else
      echo "differs  $dest"
      diff -u -L "$dest" -L "${source#"$repo"/}" "$dest" "$rendered" || true
      differs=$((differs + 1))
    fi
  done
done

# Rules cite other areas (frontend rules cite rules/api/contract.md); name the ones the project has not copied.
missing=$(grep -ohE 'rules/[a-z-]+/' "$project/.claude/rules"/*/*.md 2>/dev/null | sort -u | sed -E 's#rules/([a-z-]+)/#\1#' |
  while read -r cited; do
    [ -d "$repo/rules/$cited" ] && [ ! -d "$project/.claude/rules/$cited" ] && echo "$cited"
  done | tr '\n' ' ' || true)
[ -z "$missing" ] || echo "the copied rules cite areas this project does not have: $missing(copy the ones that apply)"

if [ "$differs" -gt 0 ]; then
  echo "$differs file(s) differ from this repo and were left alone; rerun with --update to overwrite them, losing the project's edits to them" >&2
  exit 2
fi
