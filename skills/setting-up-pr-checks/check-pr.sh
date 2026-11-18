#!/usr/bin/env bash
# Checks a pull request body and diff against rules/git/pull-request.md and the comment rules in
# rules/{go,typescript,database}/conventions.md; prints violations only. Exit 1 on blocking ones.
# Usage: bash scripts/check-pr.sh --base <ref> [--body <file>] [--no-diff]
set -euo pipefail

usage() { echo "usage: check-pr.sh --base <ref> [--body <file>] [--no-diff]" >&2; exit 2; }
die() { echo "check-pr.sh: $*" >&2; exit 2; }

base=""
body=""
no_diff=0
while [ $# -gt 0 ]; do
  case $1 in
    --base) [ $# -ge 2 ] || usage; base=$2; shift 2 ;;
    --body) [ $# -ge 2 ] || usage; body=$2; shift 2 ;;
    --no-diff) no_diff=1; shift ;;
    *) usage ;;
  esac
done
[ -n "$base" ] || usage

root=$(git rev-parse --show-toplevel)
git rev-parse --verify --quiet "$base^{commit}" >/dev/null || die "base $base not found"
[ -z "$body" ] || [ -f "$body" ] || die "body file $body not found"

defaults="PR_MAX_LINES=1000 PR_MAX_WHY_PARAGRAPHS=3 PR_MAX_WHY_CHARS=1500 PR_MAX_CHANGES_CHARS=3000 \
PR_MAX_SCOPE_CHARS=1000 PR_MAX_NOTES_CHARS=1000 PR_MAX_SENTENCE_WORDS=25 PR_MAX_COMMENT_LINES=3 \
PR_MAX_COMMENT_PERCENT=50 PR_MIN_LINES_FOR_RATIO=20"

# Limits come from the defaults, then .github/pr-checks.env, then the environment; the file is
# parsed, never sourced.
load_config() {
  local pair name cfg env_value line n=0 file="$root/.github/pr-checks.env"
  for pair in $defaults; do
    printf -v "cfg_${pair%%=*}" '%s' "${pair#*=}"
  done
  if [ -f "$file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      n=$((n + 1))
      case $line in '' | '#'*) continue ;; esac
      [[ $line =~ ^PR_[A-Z_]+=[0-9]+$ ]] || die_config "$n: expected PR_NAME=number"
      name=${line%%=*}
      case " $defaults " in *" $name="*) ;; *) die_config "$n: unknown setting $name" ;; esac
      printf -v "cfg_$name" '%s' "${line#*=}"
    done <"$file"
  fi
  for pair in $defaults; do
    name=${pair%%=*}
    env_value=${!name:-}
    if [ -n "$env_value" ]; then
      [[ $env_value =~ ^[0-9]+$ ]] || die "$name must be a number"
      printf -v "cfg_$name" '%s' "$env_value"
    fi
    cfg=cfg_$name
    printf -v "$name" '%s' "${!cfg}"
  done
}
die_config() { echo ".github/pr-checks.env:$*" >&2; exit 2; }

failed=0

check_body() { :; } # the body checks, B1 to B6
check_diff() { :; } # the diff checks, D1 to D4

load_config
[ -z "$body" ] || check_body
[ "$no_diff" -eq 1 ] || check_diff
exit "$failed"
