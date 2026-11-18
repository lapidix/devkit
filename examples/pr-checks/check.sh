#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2317,SC2329
# Runs skills/setting-up-pr-checks/check-pr.sh against fixture repositories in .build/:
# each case_<name> function builds a repository, runs the script and compares its output
# and exit code with what the case expects.
# Usage: bash examples/pr-checks/check.sh
# The case_* functions are called through "$case_name" (SC2317, SC2329). The single-quoted sed and
# printf scripts hold backticks and $ on purpose (SC2016).
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

rep() { local s; s=$(printf '%*s' "$2" ''); printf '%s' "${s// /$1}"; } # rep CHAR N

# body_section NAME: good_body with the content of section NAME replaced by stdin
body_section() {
  local new
  new=$(cat)
  good_body | NEW="$new" awk -v h="## $1" '
    $0 == h { print; print ENVIRON["NEW"]; print ""; skip = 1; next }
    /^## / { skip = 0 }
    !skip' | body_file body
}
words() { awk -v n="$1" 'BEGIN { for (i = 1; i <= n; i++) printf "%sw%d", (i > 1 ? " " : ""), i }'; } # words N: w1 w2 ... wN

case_why_paragraphs()    { repo_init; printf 'one\n\ntwo\n\nthree\n\nfour\n' | { f=$(body_section Why); expect 1 --base main --no-diff --body "$f" <<'E'
PR body: Why has 4 paragraphs, at most 3 (git/pull-request.md)
E
}; }
case_why_chars()         { repo_init; f=$(rep a 1501 | body_section Why); expect 1 --base main --no-diff --body "$f" <<'E'
PR body: Why has 1501 characters, at most 1500 (git/pull-request.md)
E
}
case_changes_chars()     { repo_init; f=$(rep a 3001 | body_section Changes); expect 1 --base main --no-diff --body "$f" <<'E'
PR body: Changes has 3001 characters, at most 3000 (git/pull-request.md)
E
}
case_scope_chars()       { repo_init; f=$(rep a 1001 | body_section 'Out of scope & follow-ups'); expect 1 --base main --no-diff --body "$f" <<'E'
PR body: Out of scope & follow-ups has 1001 characters, at most 1000 (git/pull-request.md)
E
}
case_notes_chars()       { repo_init; f=$(rep a 1001 | body_section Notes); expect 1 --base main --no-diff --body "$f" <<'E'
PR body: Notes has 1001 characters, at most 1000 (git/pull-request.md)
E
}
case_verification_no_cap() { repo_init; f=$(printf '**Verified**\n- %s\n**Not verified**\n- None\n' "$(rep a 5000)" | body_section Verification)
  expect 0 --base main --no-diff --body "$f" </dev/null
}
case_caps_multibyte()    { repo_init
  f=$(rep 가 1500 | body_section Why); expect 0 --base main --no-diff --body "$f" </dev/null
  f=$(rep 가 1501 | body_section Why); expect 1 --base main --no-diff --body "$f" <<'E'
PR body: Why has 1501 characters, at most 1500 (git/pull-request.md)
E
}
case_caps_from_config()  { repo_init; printf 'PR_MAX_WHY_PARAGRAPHS=1\n' | put .github/pr-checks.env; commit c
  f=$(printf 'one\n\ntwo\n' | body_section Why); expect 1 --base main --no-diff --body "$f" <<'E'
PR body: Why has 2 paragraphs, at most 1 (git/pull-request.md)
E
}
case_caps_skip_absent_section() { repo_init; printf '## Summary\n%s\n' "$(rep a 5000)" | put .github/PULL_REQUEST_TEMPLATE.md; commit t
  expect 0 --base main --no-diff --body "$(printf '## Summary\n%s\n' "$(rep a 5000)" | body_file body)" </dev/null
}
case_sentence_long()     { repo_init; f=$(printf '%s.\n' "$(words 26)" | body_section Why); expect 0 --base main --no-diff --body "$f" <<'E'
warning: PR body: a sentence has 26 words, at most 25: "w1 w2 w3 w4 w5 w6 …" (git/pull-request.md)
E
}
case_sentence_ok()       { repo_init; f=$(printf '%s `a b c d`.\n' "$(words 24)" | body_section Why); expect 0 --base main --no-diff --body "$f" </dev/null; }
case_sentence_split()    { repo_init; f=$(printf '%s. %s.\n' "$(words 25)" "$(words 25)" | body_section Why); expect 0 --base main --no-diff --body "$f" </dev/null; }
case_sentence_skips_code() { repo_init; f=$(printf '```\n%s.\n```\n> %s.\n| %s |\n' "$(words 30)" "$(words 30)" "$(words 30)" | body_section Why)
  expect 0 --base main --no-diff --body "$f" </dev/null
}
case_sentence_list_items() { repo_init; f=$(printf -- '- %s.\n- %s.\n' "$(words 20)" "$(words 20)" | body_section Changes); expect 0 --base main --no-diff --body "$f" </dev/null; }

case_why_paragraphs_after_bare_issue() { repo_init
  f=$(good_body | sed -e '/^Resolves #1$/{n;d;}' -e '/^Readers need/c\
one\
\
two\
\
three\
\
four' | body_file body)
  expect 1 --base main --no-diff --body "$f" <<'E'
PR body: Why has 4 paragraphs, at most 3 (git/pull-request.md)
E
}

# refs_init: main has internal/user/service.go (one line), old.go and a .gitignore; pr drops old.go
refs_init() {
  repo_init
  git -C "$build/repo" checkout -q main
  printf 'func (s *Service) Withdraw() {}\n' | put internal/user/service.go
  printf 'func OldName() {}\n' | put old.go
  printf 'node_modules/\n' | put .gitignore
  commit refs
  git -C "$build/repo" checkout -q -B pr
  git -C "$build/repo" rm -q old.go
  commit drop
}
# refs_body: good_body with its Changes section replaced by stdin; prints the file path
refs_body() { body_section Changes; }

case_refs_missing_path()  { refs_init; f=$(printf -- '- `internal/user/svc.go`\n' | refs_body); expect 1 --base main --no-diff --body "$f" <<'E'
PR body: `internal/user/svc.go` does not exist (git/pull-request.md)
E
}
case_refs_missing_ident() { refs_init; f=$(printf -- '- `WithdrawUser`\n' | refs_body); expect 1 --base main --no-diff --body "$f" <<'E'
PR body: `WithdrawUser` is not in the repository; if it is not code, drop the backticks (git/pull-request.md)
E
}
case_refs_ok()            { refs_init
  f=$(printf -- '- `user/service.go`\n- `internal/user/`\n- `s.Withdraw()`\n- `OldName`\n- `old.go`\n- `.gitignore`\n' | refs_body)
  expect 0 --base main --no-diff --body "$f" </dev/null
}
case_refs_line()          { refs_init; f=$(printf -- '- `internal/user/service.go:99`\n' | refs_body); expect 1 --base main --no-diff --body "$f" <<'E'
PR body: `internal/user/service.go:99` is past the end of internal/user/service.go (1 lines) (git/pull-request.md)
E
  f=$(printf -- '- `internal/user/service.go:1`\n' | refs_body); expect 0 --base main --no-diff --body "$f" </dev/null
}
case_refs_not_paths()     { refs_init
  f=$(printf -- '- `issue/42-x`\n- `origin/main`\n- `node_modules/arthron/llms.txt`\n- `/tmp/pr-body.md`\n- `~/.claude/rules/git`\n- `.claude/rules/{area}/`\n- `actions/checkout@v4`\n- `**/*.md`\n' | refs_body)
  expect 0 --base main --no-diff --body "$f" </dev/null
}
case_refs_skipped_words() { refs_init
  f=$(printf -- '- `zod`\n- `main`\n- `Makefile`\n- `pnpm check:arch`\n- `--body-file`\n- `#42`\n- `v1.2.3`\n- `2.1`\n' | refs_body)
  expect 0 --base main --no-diff --body "$f" </dev/null
}
case_refs_in_fence_ignored() { refs_init
  f=$(printf '```\n`Nope.go`\n```\n- fine\n' | refs_body)
  expect 0 --base main --no-diff --body "$f" </dev/null
}
case_refs_dedup()         { refs_init; f=$(printf -- '- `WithdrawUser`\n- again `WithdrawUser`\n' | refs_body); expect 1 --base main --no-diff --body "$f" <<'E'
PR body: `WithdrawUser` is not in the repository; if it is not code, drop the backticks (git/pull-request.md)
E
}

case_refs_dot_slash()     { refs_init
  f=$(printf -- '- `./internal/user/service.go`\n- `./`\n' | refs_body); expect 0 --base main --no-diff --body "$f" </dev/null
  f=$(printf -- '- `./internal/user/svc.go`\n' | refs_body); expect 1 --base main --no-diff --body "$f" <<'E'
PR body: `./internal/user/svc.go` does not exist (git/pull-request.md)
E
}
case_refs_not_paths_hosts_products() { refs_init
  f=$(printf -- '- `docs.example.com/a.html`\n- `Next.js`\n- `Node.js`\n' | refs_body); expect 0 --base main --no-diff --body "$f" </dev/null
}
case_refs_library_names() { refs_init
  f=$(printf -- '- `os.Getenv`\n- `JSON.stringify`\n- `NODE_ENV`\n- `ERR_CODE`\n' | refs_body); expect 0 --base main --no-diff --body "$f" </dev/null
}
case_refs_line_range()    { refs_init; f=$(printf -- '- `internal/user/service.go:1-99`\n' | refs_body); expect 1 --base main --no-diff --body "$f" <<'E'
PR body: `internal/user/service.go:1-99` is past the end of internal/user/service.go (1 lines) (git/pull-request.md)
E
}

lines() { awk -v n="$1" 'BEGIN { for (i = 1; i <= n; i++) print "line " i }'; } # lines N: N distinct lines

size_warning() { printf 'warning: PR: %s lines changed outside generated files, at most %s; say in Notes why it is not split (git/pull-request.md)\n' "$1" "$2"; }

case_size_over()         { repo_init; lines 1001 | put big.txt; commit big; expect 0 --base main <<E
$(size_warning 1001 1000)
E
}
case_size_lockfile()     { repo_init; lines 5000 | put package-lock.json; lines 500 | put go.sum; commit locks; expect 0 --base main </dev/null; }
case_size_linguist()     { repo_init; printf 'sqlcgen/** linguist-generated=true\n' | put .gitattributes
  { printf 'package sqlcgen\n'; lines 2000 | sed 's|^|// |' | head -5; lines 2000 | sed 's|^|var v|'; } | put sqlcgen/q.go; commit gen
  expect 0 --base main </dev/null
}
case_size_binary()       { repo_init; printf '\000\001\002' | put blob.bin; commit bin; expect 0 --base main </dev/null; }
case_size_rename()       { repo_init; git -C "$build/repo" checkout -q main; lines 1200 | put big.txt; commit big
  git -C "$build/repo" checkout -q -B pr; git -C "$build/repo" mv big.txt moved.txt
  sed -i.bak '1s/.*/changed/' "$build/repo/moved.txt"; rm "$build/repo/moved.txt.bak"; commit mv
  expect 0 --base main </dev/null
}
case_size_from_config()  { repo_init; git -C "$build/repo" checkout -q main; printf 'PR_MAX_LINES=10\n' | put .github/pr-checks.env; commit c
  git -C "$build/repo" checkout -q -B pr; lines 11 | put a.txt; commit a
  expect 0 --base main <<E
$(size_warning 11 10)
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
