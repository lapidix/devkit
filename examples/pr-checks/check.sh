#!/usr/bin/env bash
# shellcheck disable=SC2317,SC2329
# Runs skills/setting-up-pr-checks/check-pr.sh against fixture repositories in .build/:
# each case_<name> function builds a repository, runs the script and compares its output
# and exit code with what the case expects.
# Usage: bash examples/pr-checks/check.sh
# The case_* functions are called through "$case_name".
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

# cases

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

good_body() {
  cat <<'B'
## Issue
Resolves #1

## Why
Readers need a short reason.

## Changes
- Adds `a.go`.

## Verification
**Verified**
- `bash check.sh`: passed
**Not verified**
- None

## Out of scope & follow-ups
None

## Notes
None
B
}

# body_with SED-ARGS...: good_body edited by sed, written to a file whose path is printed
body_with() { good_body | sed "$@" | body_file body; }

case_body_good()         { repo_init; expect 0 --base main --no-diff --body "$(good_body | body_file body)" </dev/null; }
case_template_matches_rule() {
  repo_init
  awk '/^## Body/ {b=1} b && /^```markdown/ {t=1; next} t && /^```/ {exit} t {sub(/[ \t]+$/, ""); print}' \
    "$repo/rules/git/pull-request.md" >"$build/rule-template.txt"
  awk '/^ *cat <<.TEMPLATE.$/ {t=1; next} /^TEMPLATE$/ {t=0} t' "$script" >"$build/script-template.txt"
  [ -s "$build/rule-template.txt" ] && diff -q "$build/rule-template.txt" "$build/script-template.txt" >/dev/null ||
    printf 'FAIL %s (template differs from the rule)\n' "$case_name" >>"$fails"
}
case_body_missing_header() { repo_init; expect 1 --base main --no-diff --body "$(body_with '/^## Notes$/,$d')" <<'E'
PR body: missing section "## Notes" (git/pull-request.md)
E
}
case_body_out_of_order() { repo_init
  f=$(good_body | awk '/^## Changes/ {s=1} /^## Verification/ {s=0} s {c = c $0 "\n"; next} /^## Out of scope/ {printf "%s", c} {print}' | body_file body)
  expect 1 --base main --no-diff --body "$f" <<'E'
PR body: section "## Verification" is out of order (git/pull-request.md)
E
}
case_body_extra_header_ok() { repo_init; expect 0 --base main --no-diff --body "$(body_with '/^## Issue$/{n;a\
\
## ⚠️ Merge #41 first\
Merge #41 first.
}')" </dev/null; }
case_body_empty_section() { repo_init; expect 1 --base main --no-diff --body "$(body_with '/^## Notes$/{n;s/.*/<!-- later -->/;}')" <<'E'
PR body: section "## Notes" is empty; write None when there is nothing to say (git/pull-request.md)
E
}
case_body_bullet_only_empty() { repo_init; f=$(body_with '/^- Adds/s/.*/- /')
  expect 1 --base main --no-diff --body "$f" <<'E'
PR body: section "## Changes" is empty; write None when there is nothing to say (git/pull-request.md)
E
}
case_verified_missing()  { repo_init; expect 1 --base main --no-diff --body "$(body_with '/^\*\*Not verified\*\*$/,/^- None$/d')" <<'E'
PR body: Verification needs a **Not verified** list with at least one item; write - None when there are none (git/pull-request.md)
E
}
case_verified_empty_item() { repo_init; expect 1 --base main --no-diff --body "$(body_with '/^- `bash check.sh`/s/.*/-/')" <<'E'
PR body: Verification needs a **Verified** list with at least one item; write - None when there are none (git/pull-request.md)
E
}
case_project_template_without_markers() { repo_init
  printf '## Summary\n\n## Test plan\n- [ ] tested\n' | put .github/PULL_REQUEST_TEMPLATE.md; commit t
  expect 0 --base main --no-diff --body "$(printf '## Summary\nFixes it.\n\n## Test plan\n- [x] tested\n' | body_file body)" </dev/null
}
case_body_crlf()         { repo_init; expect 0 --base main --no-diff --body "$(good_body | sed "s/\$/$(printf '\r')/" | body_file body)" </dev/null; }
case_body_empty()        { repo_init; expect 1 --base main --no-diff --body "$(body_file body </dev/null)" <<'E'
PR body: missing section "## Issue" (git/pull-request.md)
PR body: missing section "## Why" (git/pull-request.md)
PR body: missing section "## Changes" (git/pull-request.md)
PR body: missing section "## Verification" (git/pull-request.md)
PR body: missing section "## Out of scope & follow-ups" (git/pull-request.md)
PR body: missing section "## Notes" (git/pull-request.md)
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
