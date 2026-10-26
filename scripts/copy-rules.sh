#!/usr/bin/env bash
# Copies rule areas into a project's .claude/rules/{area}/. They are copied,
# not linked: Claude Code does not load a rule with paths: through a symlink
# that leaves the project.
# Usage: bash scripts/copy-rules.sh [--update] [--prefix <app folder>]... [--agents-md] <project> <area | area/file>...
#   --prefix apps/web puts each "**/…" glob under apps/web, for a monorepo app;
#   given twice, each glob is listed once per app. Rerun with the same flags.
#   --agents-md writes an index of the copied rules into the project's AGENTS.md
#   for Codex, which does not read .claude/rules/; later runs keep it current.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)

usage() {
  echo "usage: bash scripts/copy-rules.sh [--update] [--prefix <app folder>]... [--agents-md] <project> <area | area/file>..." >&2
  echo "areas: $(for dir in "$repo"/rules/*/; do dir=${dir%/}; printf '%s ' "${dir##*/}"; done)" >&2
  exit 1
}

update=false
agents_md=false
prefixes=()
while [ $# -gt 0 ]; do
  case $1 in
    --update) update=true; shift ;;
    --prefix) [ $# -ge 2 ] || usage; prefixes+=("${2%/}"); shift 2 ;;
    --agents-md) agents_md=true; shift ;;
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

# Rules cite other areas: frontend rules lean on rules/api/contract.md, while api/contract.md only
# mentions the Go server for comparison. List each area the project lacks with the files citing it.
missing=$(grep -oE 'rules/[a-z-]+/' "$project/.claude/rules"/*/*.md 2>/dev/null | sort -u |
  sed -nE 's#^.*/\.claude/rules/([^:]+):rules/([a-z-]+)/$#\2 \1#p' |
  while read -r cited file; do
    [ -d "$repo/rules/$cited" ] && [ ! -d "$project/.claude/rules/$cited" ] && echo "$cited $file"
  done | awk '{ files[$1] = files[$1] (files[$1] ? ", " : "") $2 } END { for (a in files) print "  " a " (cited by " files[a] ")" }' | sort || true)
if [ -n "$missing" ]; then
  echo "areas the copied rules cite that this project does not have; copy the ones that apply:"
  echo "$missing"
fi

# Codex reads AGENTS.md, not .claude/rules/: keep a marked index of every copied rule there,
# created by --agents-md and refreshed on every later run. The rest of AGENTS.md is the project's.
agents="$project/AGENTS.md"
start='<!-- lapidix-rules:start -->'
end='<!-- lapidix-rules:end -->'
if $agents_md || grep -qF "$start" "$agents" 2>/dev/null; then
  index=$(mktemp)
  {
    echo "$start"
    echo "## Rules"
    echo
    echo "Before you edit a file, read every rule below whose paths match it. A rule without paths applies to every task. lapidix devkit's copy-rules.sh writes this block; edits to it are replaced."
    echo
    echo "| Rule | Paths |"
    echo "|---|---|"
    for file in "$project/.claude/rules"/*/*.md; do
      globs=$(awk 'NR == 1 && $0 == "---" { front = 1; next }
        front && $0 == "---" { exit }
        front && /^  - "/ { glob = $0; sub(/^  - "/, "", glob); sub(/"$/, "", glob); printf "%s`%s`", (n++ ? ", " : ""), glob }' "$file")
      echo "| \`${file#"$project"/}\` | ${globs:-every task} |"
    done
    echo "$end"
  } > "$index"
  if grep -qF "$start" "$agents" 2>/dev/null; then
    awk -v start="$start" -v end="$end" -v index_file="$index" '
      $0 == start { while ((getline line < index_file) > 0) print line; skip = 1; next }
      $0 == end { skip = 0; next }
      !skip { print }' "$agents" > "$agents.tmp"
    mv "$agents.tmp" "$agents"
    echo "indexed  $agents (refreshed)"
  else
    if [ -s "$agents" ]; then echo >> "$agents"; fi
    cat "$index" >> "$agents"
    echo "indexed  $agents"
  fi
  rm -f "$index"
fi

if [ "$differs" -gt 0 ]; then
  echo "$differs file(s) differ from this repo and were left alone; rerun with --update to overwrite them, losing the project's edits to them" >&2
  exit 2
fi
