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
# an unrelated base, or a shallow clone, has no merge base to diff from
case_no_merge_base()     { repo_init
  (cd "$build/repo" && git checkout -q --orphan other && git_t commit -q -m orphan && git checkout -q pr)
  expect_err 2 --base other <<'E'
check-pr.sh: no merge base between other and HEAD; fetch more history (git fetch --unshallow) or pass another --base
E
  expect_err 2 --base other --no-diff --body "$(good_body | body_file body)" <<'E'
check-pr.sh: no merge base between other and HEAD; fetch more history (git fetch --unshallow) or pass another --base
E
}
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
# the lists belong in the section the template puts them in, and a numbered list is a list
case_verified_lists_elsewhere() { repo_init
  f=$(good_body | awk '/^\*\*Verified\*\*$/ {v=1} v && /^$/ {v=0; print "Ran it."} v {l = l $0 "\n"; next} {print} END {printf "%s", l}' | body_file body)
  expect 1 --base main --no-diff --body "$f" <<'E'
PR body: the **Verified** list belongs in Verification, not Notes (git/pull-request.md)
PR body: the **Not verified** list belongs in Verification, not Notes (git/pull-request.md)
E
}
case_verified_numbered() { repo_init
  expect 0 --base main --no-diff --body "$(body_with -e 's/^- `bash check.sh`/1. `bash check.sh`/' -e 's/^- None$/1. None/')" </dev/null
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
# blank lines inside a fenced block (a stack trace) do not start paragraphs
case_why_fence_one_paragraph() { repo_init
  f=$(printf 'It panics on start. The trace shows where.\n\n```\npanic: boom\n\ngoroutine 1 [running]:\n\nmain.main()\n```\n' | body_section Why)
  expect 0 --base main --no-diff --body "$f" </dev/null
  f=$(printf 'one\n\ntwo\n\nthree\n\n```\npanic: boom\n\nmain.main()\n```\n' | body_section Why)
  expect 1 --base main --no-diff --body "$f" <<'E'
PR body: Why has 4 paragraphs, at most 3 (git/pull-request.md)
E
}
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

# refs_init: main has internal/user/service.go (one line), internal/old.go and a .gitignore; pr drops
# internal/old.go
refs_init() {
  repo_init
  git -C "$build/repo" checkout -q main
  printf 'func (s *Service) Withdraw() {}\n' | put internal/user/service.go
  printf 'func OldName() {}\n' | put internal/old.go
  printf 'node_modules/\n' | put .gitignore
  commit refs
  git -C "$build/repo" checkout -q -B pr
  git -C "$build/repo" rm -q internal/old.go
  commit drop
}
# refs_body: good_body with its Changes section replaced by stdin; prints the file path
refs_body() { body_section Changes; }

case_refs_missing_path()  { refs_init; f=$(printf -- '- `internal/user/svc.go`\n' | refs_body); expect 1 --base main --no-diff --body "$f" <<'E'
PR body: `internal/user/svc.go` does not exist; if it is not a path in this repository, drop the backticks (git/pull-request.md)
E
}
case_refs_missing_ident() { refs_init; f=$(printf -- '- `WithdrawUser`\n' | refs_body); expect 1 --base main --no-diff --body "$f" <<'E'
PR body: `WithdrawUser` is not in the repository; if it is not code, drop the backticks (git/pull-request.md)
E
}
case_refs_ok()            { refs_init
  f=$(printf -- '- `user/service.go`\n- `internal/user/`\n- `s.Withdraw()`\n- `OldName`\n- `internal/old.go`\n' | refs_body)
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
  f=$(printf '```\n`internal/Nope.go`\n```\n- fine\n' | refs_body)
  expect 0 --base main --no-diff --body "$f" </dev/null
}
case_refs_dedup()         { refs_init; f=$(printf -- '- `WithdrawUser`\n- again `WithdrawUser`\n' | refs_body); expect 1 --base main --no-diff --body "$f" <<'E'
PR body: `WithdrawUser` is not in the repository; if it is not code, drop the backticks (git/pull-request.md)
E
}

case_refs_dot_slash()     { refs_init
  f=$(printf -- '- `./internal/user/service.go`\n- `./`\n' | refs_body); expect 0 --base main --no-diff --body "$f" </dev/null
  f=$(printf -- '- `./internal/user/svc.go`\n' | refs_body); expect 1 --base main --no-diff --body "$f" <<'E'
PR body: `./internal/user/svc.go` does not exist; if it is not a path in this repository, drop the backticks (git/pull-request.md)
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
# a span after a path on the same line is checked too, in a list item and in a table row
case_refs_spans_after_path() { refs_init
  f=$(printf -- '- `internal/user/service.go` adds `WithdrawUser`\n' | refs_body); expect 1 --base main --no-diff --body "$f" <<'E'
PR body: `WithdrawUser` is not in the repository; if it is not code, drop the backticks (git/pull-request.md)
E
  f=$(printf -- '| `internal/user/service.go` | adds `WithdrawUser` |\n' | refs_body); expect 1 --base main --no-diff --body "$f" <<'E'
PR body: `WithdrawUser` is not in the repository; if it is not code, drop the backticks (git/pull-request.md)
E
}
# a .js name or a dotfile without a / may be a package or a kind of file; it is not checked
case_refs_bare_names_skipped() { refs_init
  f=$(printf -- '- `decimal.js`\n- `chart.js`\n- `.gitattributes`\n- `.env.local`\n' | refs_body); expect 0 --base main --no-diff --body "$f" </dev/null
}
# any other file name without a / is looked up by name anywhere in the tree, with its line number
case_refs_bare_file_names() { refs_init
  f=$(printf -- '- `service.go`\n- `service.go:1`\n- `old.go`\n- `README.md`\n' | refs_body); expect 0 --base main --no-diff --body "$f" </dev/null
  f=$(printf -- '- `UserCard.tsx`\n- `withdraw_user.go`\n- `service.go:5`\n' | refs_body); expect 1 --base main --no-diff --body "$f" <<'E'
PR body: `UserCard.tsx` does not exist; if it is not a path in this repository, drop the backticks (git/pull-request.md)
PR body: `withdraw_user.go` does not exist; if it is not a path in this repository, drop the backticks (git/pull-request.md)
PR body: `service.go:5` is past the end of internal/user/service.go (1 lines) (git/pull-request.md)
E
}
# in a monorepo the same app-relative path names several files; one long enough is enough
case_refs_line_any_match() { repo_init
  lines 10 | put apps/admin/src/app/page.tsx; lines 200 | put apps/web/src/app/page.tsx; commit apps
  f=$(printf -- '- `src/app/page.tsx:150`\n' | refs_body); expect 0 --base main --no-diff --body "$f" </dev/null
  f=$(printf -- '- `src/app/page.tsx:250`\n' | refs_body); expect 1 --base main --no-diff --body "$f" <<'E'
PR body: `src/app/page.tsx:250` is past the end of apps/web/src/app/page.tsx (200 lines) (git/pull-request.md)
E
}

lines() { awk -v n="$1" 'BEGIN { for (i = 1; i <= n; i++) print "line " i }'; } # lines N: N distinct lines

size_warning() { printf 'warning: PR: %s lines changed outside generated files, at most %s; say in Notes why it is not split (git/pull-request.md)\n' "$1" "$2"; }

case_size_over()         { repo_init; lines 1001 | put big.txt; commit big; expect 0 --base main <<E
$(size_warning 1001 1000)
E
}
case_size_lockfile()     { repo_init; lines 5000 | put package-lock.json; lines 500 | put go.sum; lines 1001 | put go.work.sum; commit locks; expect 0 --base main </dev/null; }
# a generated Go file the PR deletes is recognised by its header at the base
case_size_deleted_generated() { repo_init; git -C "$build/repo" checkout -q main
  { printf '// Code generated by sqlc. DO NOT EDIT.\n\npackage db\n\n'; lines 1100 | sed 's/^line /var v/; s/$/ = 1/'; } | put db/q.go; commit gen
  git -C "$build/repo" checkout -q -B pr; git -C "$build/repo" rm -q db/q.go; commit rm
  expect 0 --base main </dev/null
}
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

block_base() { repo_init; git -C "$build/repo" checkout -q main; } # block_base: work on main, then block_branch
block_branch() { git -C "$build/repo" checkout -q -B pr; }

case_block_new()         { repo_init; printf 'package a\n\n// one\n// two\n// three\n// four\n' | put a.go; commit b
  expect 1 --base main <<'E'
a.go:3: comment block of 4 lines, at most 3 (go/conventions.md)
E
}
case_block_grown()       { block_base; printf 'package a\n\n// one\n// two\n// three\n' | put a.go; commit b; block_branch
  printf 'package a\n\n// one\n// two\n// three\n// four\n' | put a.go; commit g
  expect 1 --base main <<'E'
a.go:3: comment block of 4 lines, at most 3 (go/conventions.md)
E
}
case_block_untouched()   { block_base; printf 'package a\n\n// one\n// two\n// three\n// four\n// five\n\nvar x = 1\n' | put a.go; commit b; block_branch
  printf 'package a\n\n// one\n// two\n// three\n// four\n// five\n\nvar x = 2\n' | put a.go; commit g
  expect 0 --base main </dev/null
}
case_block_jsdoc()       { repo_init; printf '/**\n * one\n * two\n * three\n */\nexport const x = 1\n' | put x.ts; commit b
  expect 0 --base main </dev/null
  printf '/**\n * one\n * two\n * three\n * four\n */\nexport const x = 1\n' | put x.ts; commit c
  expect 1 --base main <<'E'
x.ts:1: comment block of 4 lines, at most 3 (typescript/conventions.md)
E
}
# a tool comment neither counts nor ends a block, so prose on both sides of it is one block
case_block_tool_inside() { repo_init; printf 'package a\n\n// a\n// b\n//go:generate x\n// c\n// d\n' | put a.go; commit b
  expect 1 --base main <<'E'
a.go:3: comment block of 4 lines, at most 3 (go/conventions.md)
E
}
# staticcheck directives and test or JSX pragmas are tool comments
case_tool_lint_and_pragmas() { repo_init
  printf 'package a\n\n//lint:ignore SA1019 the old API stays until v2\n// one\n// two\n// three\nvar x = 1\n' | put a.go
  printf '// @vitest-environment jsdom\n// one\n// two\n// three\nexport const x = 1\n' | put x.test.ts
  printf '/** @jsxImportSource preact */\n// @ts-check\n// one\n// two\n// three\nexport const y = 1\n' | put y.tsx
  commit b
  expect 0 --base main </dev/null
}
case_block_trailing()    { repo_init; printf 'package a\n\nvar a = 1 // why\nvar b = 2 // why\nvar c = 3 // why\nvar d = 4 // why\n' | put a.go; commit b
  expect 0 --base main </dev/null
}
case_block_sql()         { repo_init; printf -- '-- one\n-- two\n-- three\n-- four\nSELECT 1;\n' | put m.sql; commit b
  expect 1 --base main <<'E'
m.sql:1: comment block of 4 lines, at most 3 (database/conventions.md)
E
}
case_block_mts_cts()     { repo_init; printf '// 1\n// 2\n// 3\n// 4\nexport const a = 1\n' | put a.mts; printf '// 1\n// 2\n// 3\n// 4\nexport const b = 1\n' | put b.cts; commit b
  expect 1 --base main <<'E'
a.mts:1: comment block of 4 lines, at most 3 (typescript/conventions.md)
b.cts:1: comment block of 4 lines, at most 3 (typescript/conventions.md)
E
}
case_block_other_ext()   { repo_init; printf '# 1\n# 2\n# 3\n# 4\n' | put a.py; printf '# 1\n# 2\n# 3\n# 4\n' | put a.sh
  printf '# 1\n# 2\n# 3\n# 4\n' | put a.yml; commit b
  expect 0 --base main </dev/null
}
case_block_renamed_file() { block_base
  printf 'package a\n\n// o1\n// o2\n// o3\n// o4\n// o5\nfunc f() int {\n\treturn 1\n}\n\nfunc g() int {\n\treturn 2\n}\n' | put a.go; commit b; block_branch
  git -C "$build/repo" mv a.go b.go
  printf '\n// n1\n// n2\n// n3\n// n4\n' >>"$build/repo/b.go"; commit mv
  expect 1 --base main <<'E'
b.go:16: comment block of 4 lines, at most 3 (go/conventions.md)
E
}
case_block_from_config() { block_base; printf 'PR_MAX_COMMENT_LINES=1\n' | put .github/pr-checks.env; commit c; block_branch
  printf 'package a\n\n// one\n// two\n' | put a.go; commit b
  expect 1 --base main <<'E'
a.go:3: comment block of 2 lines, at most 1 (go/conventions.md)
E
}
case_block_glob_in_code() { repo_init; printf 'export const g = "src/**/*.ts"\nexport const n = 1\n// a\n// b\n// c\n// d\n' | put x.ts; commit b
  expect 1 --base main <<'E'
x.ts:3: comment block of 4 lines, at most 3 (typescript/conventions.md)
E
}
case_block_slash_star_in_trailing() { repo_init
  printf 'package a\n\nvar dir = "d" // files in dir/*.go\nvar b = 2\nvar c = 3\nvar d = 4\n' | put a.go; commit b
  expect 0 --base main </dev/null
  printf 'package a\n\nvar v = 1 // see /* x\nvar b = 2\nvar c = 3\nvar d = 4\n' | put a.go; commit c
  expect 0 --base main </dev/null
  printf 'SELECT 1; -- see /* x\nSELECT 2;\nSELECT 3;\nSELECT 4;\n' | put m.sql; commit d
  expect 0 --base main </dev/null
}
# /\/*$/ is a regular expression, not the start of a block comment
case_block_escaped_slash_star() { repo_init
  put x.ts <<'T'
export const trim = (p: string) => p.replace(/\/*$/, '')
export const a = 1
export const b = 2
export const c = 3
export const d = 4
export const e = 5
T
  commit b
  expect 0 --base main </dev/null
}
# a /* after a string that holds /* still opens a block
case_block_after_string_with_slash_star() { repo_init
  printf 'package a\n\nvar s = "a/*" /* one\ntwo\nthree\nfour\nfive */\n' | put a.go; commit b
  expect 1 --base main <<'E'
a.go:4: comment block of 4 lines, at most 3 (go/conventions.md)
E
}
# lines inside a Go raw string or a template literal are code, however they start
case_block_in_backtick_string() { repo_init
  put a.go <<'T'
package a

const fixture = `
// a
// b
// c
// d
`

var tag = struct {
A int `json:"a"`
}{}
T
  put t.ts <<'T'
export const t = `
// a
// b
// c
// d
${'x'}`
T
  commit b
  expect 0 --base main </dev/null
}
# a block after a closed backtick string, or after a rune that holds a backtick, is still a block
case_block_after_backtick_string() { repo_init
  put a.go <<'T'
package a

const q = `select 1`
var r = '`'

// a
// b
// c
// d
var x = 1
T
  put b.go <<'T'
package b

const f = `
x
`

// a
// b
// c
// d
var y = 1
T
  commit b
  expect 1 --base main <<'E'
a.go:6: comment block of 4 lines, at most 3 (go/conventions.md)
b.go:7: comment block of 4 lines, at most 3 (go/conventions.md)
E
}
# sqlc query annotations, drizzle breakpoints and swaggo annotations are tool comments
case_tool_sqlc_name()    { repo_init
  printf -- '-- GetUser reads deleted users too,\n-- so the handler can tell them apart\n-- from users that never existed.\n-- name: GetUser :one\nSELECT * FROM users WHERE id = $1;\n' | put query.sql; commit q
  expect 0 --base main </dev/null
}
case_tool_drizzle_swaggo() { repo_init
  printf 'CREATE TABLE t (id int);\n--> statement-breakpoint\n-- t_id serves the lookup by id\n-- that the user page runs\n-- on every request.\nCREATE INDEX t_id ON t (id);\n' | put drizzle/0001_init.sql
  printf 'package a\n\n// GetUser godoc\n// @Summary Get a user\n// @Param id path string true "user id"\n// @Success 200 {object} string\n// @Router /users/{id} [get]\nfunc GetUser() {}\n' | put a.go; commit b
  expect 0 --base main </dev/null
}
case_ratio_sqlc_queries() { repo_init
  awk 'BEGIN { for (i = 1; i <= 7; i++) { print "-- Get" i " skips soft-deleted rows."; print "-- name: Get" i " :one"; print "SELECT * FROM t" i " WHERE deleted_at IS NULL;" } }' | put query.sql; commit q
  expect 0 --base main </dev/null
}
# Go marks a generated file with a header line, which golangci-lint and GitHub honour too
case_generated_go_header() { repo_init
  put user.pb.go <<'T'
// Code generated by protoc-gen-go. DO NOT EDIT.
// versions:
//   protoc-gen-go v1.36.6
//   protoc        (unknown)
// source: user/v1/user.proto

package userv1
T
  { printf '// Code generated by sqlc. DO NOT EDIT.\n\npackage db\n\n'; lines 1001 | sed 's/^line /var v/; s/$/ = 1/'; } | put db/q.go
  commit g
  expect 0 --base main </dev/null
  repo_init
  put user.pb.go <<'T'
// versions:
//   protoc-gen-go v1.36.6
//   protoc        (unknown)
// source: user/v1/user.proto

package userv1
T
  commit g
  expect 1 --base main <<'E'
user.pb.go:1: comment block of 4 lines, at most 3 (go/conventions.md)
E
}
case_comment_sentence()  { repo_init; printf 'package a\n\n// %s\n' "$(awk 'BEGIN { for (i = 1; i <= 26; i++) printf "w%d ", i }' | sed 's/ $/./')" | put a.go; commit b
  expect 0 --base main <<'E'
warning: a.go:3: a comment sentence has 26 words, at most 25 (go/conventions.md)
E
}
case_comment_sentence_ok() { repo_init; printf 'package a\n\n// %s\n' "$(awk 'BEGIN { for (i = 1; i <= 25; i++) printf "w%d ", i }' | sed 's/ $/./')" | put a.go; commit b
  expect 0 --base main </dev/null
}
case_comment_sentence_joined() { repo_init; printf 'package a\n\n// %s\n// %s\n' "$(awk 'BEGIN { for (i = 1; i <= 13; i++) printf "w%d ", i }' | sed 's/ $//')" \
  "$(awk 'BEGIN { for (i = 14; i <= 26; i++) printf "w%d ", i }' | sed 's/ $/./')" | put a.go; commit b
  expect 0 --base main <<'E'
warning: a.go:3: a comment sentence has 26 words, at most 25 (go/conventions.md)
E
}

# ratio_go BLOCKS EXTRA: a package line, BLOCKS two-line comment blocks each followed by a var, then EXTRA vars.
ratio_go() {
  awk -v b="$1" -v e="$2" 'BEGIN {
    print "package b"
    for (i = 1; i <= b; i++) { print "// c" i " a"; print "// c" i " b"; print "var v" i " = " i }
    for (i = 1; i <= e; i++) print "var x" i " = " i
  }'
}
ratio_ts() { # ratio_ts BLOCKS EXTRA: the same shape without the package line
  awk -v b="$1" -v e="$2" 'BEGIN {
    for (i = 1; i <= b; i++) { print "// c" i " a"; print "// c" i " b"; print "export const v" i " = " i }
    for (i = 1; i <= e; i++) print "export const x" i " = " i
  }'
}
case_ratio_over()        { repo_init; ratio_go 6 1 | put b.go; commit b
  expect 1 --base main <<'E'
PR: 12 added comment lines for 8 added code lines, at most 50% of the code lines (go/conventions.md)
E
}
case_ratio_mixed_rules() { repo_init; ratio_go 3 0 | put b.go; ratio_ts 3 1 | put x.ts; commit b
  expect 1 --base main <<'E'
PR: 12 added comment lines for 8 added code lines, at most 50% of the code lines (go/conventions.md, typescript/conventions.md)
E
}
# the share is of code lines alone: 10 comment lines need 20 code lines, and as many as the code fail
case_ratio_exact_half()  { repo_init; ratio_go 5 14 | put b.go; commit b
  expect 0 --base main </dev/null
  ratio_go 5 13 | put b.go; commit c
  expect 1 --base main <<'E'
PR: 10 added comment lines for 19 added code lines, at most 50% of the code lines (go/conventions.md)
E
  ratio_go 5 4 | put b.go; commit d
  expect 1 --base main <<'E'
PR: 10 added comment lines for 10 added code lines, at most 50% of the code lines (go/conventions.md)
E
}
case_ratio_below_min()   { repo_init; printf -- '-- one\n' | put m.sql; commit b
  expect 0 --base main </dev/null
}
case_ratio_goose()       { repo_init
  awk 'BEGIN { for (i = 1; i <= 8; i++) { print "-- +goose Up"; print "-- ListOrdersByUser"; print "CREATE INDEX i" i " ON t (c);"; print "-- +goose Down"; print "DROP INDEX i" i ";" } }' | put m.sql; commit b
  expect 0 --base main </dev/null
}
case_no_diff()           { repo_init; ratio_go 6 1 | put b.go; printf 'package c\n\n// one\n// two\n// three\n// four\n' | put c.go; commit b
  expect 0 --base main --no-diff --body "$(good_body | body_file body)" </dev/null
}

# the run: block of the workflow in the skill, dedented, in a clone that has origin/main
case_workflow_run_script() {
  local skill="$repo/skills/setting-up-pr-checks/SKILL.md" status=0
  repo_init
  mkdir -p "$build/repo/scripts"
  cp "$script" "$build/repo/scripts/check-pr.sh"
  commit script
  rm -rf "$build/clone"
  git clone -q "$build/repo" "$build/clone"
  awk '
    /^ *```yaml/ && !done { y = 1; next }
    y && /^ *```/ { y = 0; done = 1; next }
    y && !r && /^ *run: \|[ \t]*$/ { match($0, /^ */); ri = RLENGTH; r = 1; next }
    y && r {
      if ($0 ~ /^[ \t]*$/) { print ""; next }
      match($0, /^ */)
      if (RLENGTH <= ri) { r = 0; y = 0; done = 1; next }
      if (bi == "") bi = RLENGTH
      print substr($0, bi + 1)
    }
  ' "$skill" >"$build/run.sh"
  [ -s "$build/run.sh" ] || { printf 'FAIL %s (no run block in SKILL.md)\n' "$case_name" >>"$fails"; return; }
  (cd "$build/clone" && AUTHOR_TYPE=Bot BODY='' BASE_REF=main RUNNER_TEMP="$build" bash "$build/run.sh") \
    >"$build/out.txt" 2>"$build/err.txt" || status=$?
  if [ "$status" != 0 ] || [ -s "$build/out.txt" ]; then
    { echo "FAIL $case_name (bot: exit $status, want 0 and no output)"; cat "$build/out.txt" "$build/err.txt"; } >>"$fails"
  fi
  status=0
  (cd "$build/clone" && AUTHOR_TYPE=User BODY='' BASE_REF=main RUNNER_TEMP="$build" bash "$build/run.sh") \
    >"$build/out.txt" 2>"$build/err.txt" || status=$?
  if [ "$status" != 1 ] || [ "$(grep -c 'missing section' "$build/out.txt")" != 6 ] || [ "$(wc -l <"$build/out.txt" | tr -d ' ')" != 6 ]; then
    { echo "FAIL $case_name (user: exit $status, want 1 and 6 missing section lines)"; cat "$build/out.txt" "$build/err.txt"; } >>"$fails"
  fi
}

# Everything devkit ships to a project (the architecture check files and the code the skill
# examples scaffold) must pass the comment checks it enforces on the project's pull requests.
case_shipped_code_passes() {
  local arch=skills/setting-up-architecture-checks ex n=0 files
  local fail=
  repo_init
  mkdir -p "$build/repo/$arch"
  cp "$repo/$arch/"*.cjs "$repo/$arch/"*.go "$build/repo/$arch/" || fail="cp of $arch"
  for ex in "$repo"/skills/*/example-*.md; do
    # set -e is off inside a case run through ||, so each failure is recorded by hand
    files=$(bash "$repo/examples/extract.sh" "$ex" "$build/repo/shipped/$(basename "$(dirname "$ex")")/$(basename "$ex" .md)" 2>&1) \
      && [ -n "$files" ] || fail="extract of $ex"
    n=$((n + 1))
  done
  [ "$n" -gt 0 ] || fail="no skills/*/example-*.md found"
  if [ -n "$fail" ]; then
    printf 'FAIL %s (%s)\n' "$case_name" "$fail" >>"$fails"
    return 0
  fi
  commit shipped
  PR_MAX_LINES=100000 expect 0 --base main </dev/null
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
