#!/usr/bin/env bash
# Runs skills/setting-up-pr-checks/check-pr.sh against fixture repositories in .build/:
# each case_<name> function builds a repository, runs the script and compares its output
# and exit code with what the case expects.
# Usage: bash examples/pr-checks/check.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/../.." && pwd)
build="$here/.build"
script="$repo/skills/setting-up-pr-checks/check-pr.sh"
fails="$build/fails"

git_t() { git -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }

repo_init() {
  rm -rf "$build/repo"
  mkdir -p "$build/repo"
  git -C "$build/repo" init -q -b main
  (
    cd "$build/repo"
    printf '# t\n' >README.md
    printf 'package a\n' >a.go
    git add -A
    git_t commit -q -m init
    git checkout -q -b pr
  )
}

put() { # put PATH, content on stdin
  mkdir -p "$(dirname "$build/repo/$1")"
  cat >"$build/repo/$1"
}

commit() { # commit MESSAGE
  (cd "$build/repo" && git add -A && git_t commit -q -m "$1")
}

body_file() { # body_file NAME, content on stdin; prints the path
  cat >"$build/$1.md"
  printf '%s\n' "$build/$1.md"
}

compare() { # compare STREAM EXIT ARGS..., expected output on stdin
  local stream=$1 want=$2 got status=0
  shift 2
  cat >"$build/want.txt"
  (cd "$build/repo" && bash "$script" "$@" >"$build/out.txt" 2>"$build/err.txt") || status=$?
  if [ "$stream" = out ]; then got="$build/out.txt"; else got="$build/err.txt"; fi
  if [ "$status" != "$want" ] || ! diff -q "$build/want.txt" "$got" >/dev/null; then
    {
      echo "FAIL $case_name (exit $status, want $want)"
      diff -u "$build/want.txt" "$got" || true
    } >>"$fails"
  fi
}

expect() { compare out "$@"; }     # expect EXIT ARGS..., stdout on stdin
expect_err() { compare err "$@"; } # expect_err EXIT ARGS..., stderr on stdin

# cases (called through "$case_name", which shellcheck cannot follow)
# shellcheck disable=SC2317,SC2329

case_usage_no_base()     { repo_init; expect_err 2 <<'E'
usage: check-pr.sh --base <ref> [--body <file>] [--no-diff]
E
}
case_usage_bad_base()    { repo_init; expect_err 2 --base nope <<'E'
check-pr.sh: base nope not found
E
}
case_clean_diff_only()   { repo_init; printf 'x\n' | put a.txt; commit a; expect 0 --base main </dev/null; }
case_config_bad_line()   { repo_init; printf 'PR_MAX_LINES=ten\n' | put .github/pr-checks.env; commit c; expect_err 2 --base main <<'E'
.github/pr-checks.env:1: expected PR_NAME=number
E
}
case_config_unknown()    { repo_init; printf '# limits\nPR_FOO=1\n' | put .github/pr-checks.env; commit c; expect_err 2 --base main <<'E'
.github/pr-checks.env:2: unknown setting PR_FOO
E
}
case_config_line_start_keys() { repo_init; printf 'PR_MAX_SCOPE_CHARS=5\nPR_MAX_COMMENT_PERCENT=40\n' | put .github/pr-checks.env; commit c; expect 0 --base main </dev/null; }
case_missing_body_file() { repo_init; expect_err 2 --base main --body /nonexistent <<'E'
check-pr.sh: body file /nonexistent not found
E
}

# runner

mkdir -p "$build"
rm -f "$fails"
: >"$fails"
total=0
failed=0
for case_name in $(declare -F | awk '$3 ~ /^case_/ {print $3}' | sort); do
  total=$((total + 1))
  before=$(wc -c <"$fails")
  ( "$case_name" ) || printf 'FAIL %s (case aborted)\n' "$case_name" >>"$fails"
  after=$(wc -c <"$fails")
  [ "$before" = "$after" ] || failed=$((failed + 1))
done

if [ "$failed" -gt 0 ]; then
  cat "$fails"
  echo "$failed of $total cases failed"
  exit 1
fi
echo "$total cases passed"
