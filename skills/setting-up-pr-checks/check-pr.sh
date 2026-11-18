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
# The diff checks read base...HEAD and B5 reads the base; without a merge base (a shallow clone, an
# unrelated branch) git diff fails inside a process substitution and every check would pass.
git merge-base "$base" HEAD >/dev/null 2>&1 ||
  die "no merge base between $base and HEAD; fetch more history (git fetch --unshallow) or pass another --base"

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

# The body template of rules/git/pull-request.md, without trailing whitespace.
default_template() {
  cat <<'TEMPLATE'
## Issue
Resolves #N

## Why

## Changes

## Verification
**Verified**
-
**Not verified**
-

## Out of scope & follow-ups

## Notes
TEMPLATE
}

# Functions every awk program below starts with, so a PR body and a code comment are read alike.
# shellcheck disable=SC2016 # awk code: its backticks and $ are awk's, not the shell's
awk_lib='
function trim(s) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", s); return s }
# line without its HTML comments; inc carries an open <!-- over to the next line
function strip_html(line,   text, i) {
  text = ""
  while (1) {
    if (inc) {
      i = index(line, "-->")
      if (!i) return text
      line = substr(line, i + 3); inc = 0
    } else {
      i = index(line, "<!--")
      if (!i) return text line
      text = text substr(line, 1, i - 1); line = substr(line, i + 4); inc = 1
    }
  }
}
# Splits s into words (sw; a backtick span is one word, its spaces kept as \001) and sentences
# ending in . ? or !. Returns how many have more than max_words words; long_at and long_len hold
# the first word and the length of each.
function long_sentences(s,   out, q, n, i, st, k) {
  out = ""
  while (match(s, /`[^`]*`/)) {
    q = substr(s, RSTART, RLENGTH); gsub(/[ \t]/, "\001", q)
    out = out substr(s, 1, RSTART - 1) q
    s = substr(s, RSTART + RLENGTH)
  }
  n = split(out s, sw, /[ \t]+/)
  st = 1; k = 0
  for (i = 1; i <= n; i++) {
    if (sw[i] !~ /[.?!]$/ && i != n) continue
    if (i - st + 1 > max_words + 0) { long_at[++k] = st; long_len[k] = i - st + 1 }
    st = i + 1
  }
  return k
}
'

body_awk() { # body_awk TEMPLATE BODY: prints the violations of B1 to B4 and the warnings of B6
  LC_ALL=C awk -v rule="git/pull-request.md" -v max_paras="$PR_MAX_WHY_PARAGRAPHS" \
    -v max_why="$PR_MAX_WHY_CHARS" -v max_changes="$PR_MAX_CHANGES_CHARS" \
    -v max_scope="$PR_MAX_SCOPE_CHARS" -v max_notes="$PR_MAX_NOTES_CHARS" \
    -v max_words="$PR_MAX_SENTENCE_WORDS" "$awk_lib"'
function nonempty(s) { s = trim(s); sub(/^([-*+]|[0-9]+\.)([ \t]+|$)/, "", s); return trim(s) != "" }
function item(s) { s = trim(s); return s ~ /^[-*+]([ \t]|$)/ }
# A prose chunk (a paragraph or one list item) ends here: warn on each long sentence in it.
function flush(   n, j, k, q) {
  if (chunk == "") return
  n = long_sentences(chunk); chunk = ""
  for (j = 1; j <= n; j++) {
    q = ""
    for (k = long_at[j]; k < long_at[j] + 6; k++) q = q (k > long_at[j] ? " " : "") sw[k]
    gsub(/\001/, " ", q)
    warn[++nw] = "warning: PR body: a sentence has " long_len[j] " words, at most " max_words ": \"" q " …\" (" rule ")"
  }
}
FILENAME != cur_file { cur_file = FILENAME; fence = 0; inc = 0; phase = (FILENAME == ARGV[1]) ? 1 : 2; sec = 0 }
{
  gsub(/\r/, "")
  line = $0
  t = trim(line)
  fl = 0
  if (t ~ /^(```|~~~)/) { fence = !fence; text = line; fl = 1 }
  else if (fence) { text = line; fl = 1 }
  else text = strip_html(line)
  t = trim(text)
  if (!fence && text ~ /^## /) {
    if (phase == 2) flush()
    if (phase == 1) { tn++; tname[tn] = t; tidx[t] = tn }
    else { bn++; bname[bn] = t; sec = bn; if (!(t in bidx)) bidx[t] = bn; active = (bidx[t] == bn); mk = ""; inpara = 0
      if (active && (t in tidx)) {
        k = tolower(trim(substr(t, 4)))
        if (k == "why" || k == "changes" || k == "notes") kind[bn] = k
        else if (k ~ /^out of scope/) kind[bn] = "scope"
      }
    }
    next
  }
  if (phase == 1) {
    if (t == "**Verified**") vsec = tn
    if (t == "**Not verified**") nsec = tn
  } else if (sec && active) {
    if (nonempty(text)) has[sec] = 1
    c = t; gsub(/[\200-\277]/, "", c); chars[sec] += length(c)
    # a fenced block, blank lines included, belongs to the paragraph it sits in
    if (t == "" && !fl) inpara = 0
    else if (!inpara) { inpara = 1; paras[sec]++ }
    if (t == "**Verified**") mk = "V"
    else if (t == "**Not verified**") mk = "N"
    else if (mk != "" && item(t)) { sub(/^[-*+]/, "", t); if (trim(t) != "") cnt[mk]++ }
  }
  if (phase == 2) {
    t = trim(text)
    if (fl || t == "" || t ~ /^#/ || t ~ /^\|/ || t ~ /^>/) flush()
    else {
      if (t ~ /^([-*+]|[0-9]+\.)([ \t]+|$)/) { flush(); sub(/^([-*+]|[0-9]+\.)[ \t]*/, "", t) }
      chunk = (chunk == "" ? "" : chunk " ") t
    }
  }
}
END {
  for (i = 1; i <= tn; i++)
    if (!(tname[i] in bidx)) print "PR body: missing section \"" tname[i] "\" (" rule ")"
  for (p = 1; p <= bn; p++) {
    if (bidx[bname[p]] != p || !(bname[p] in tidx)) continue
    for (q = p + 1; q <= bn; q++)
      if (bidx[bname[q]] == q && (bname[q] in tidx) && tidx[bname[q]] < tidx[bname[p]]) {
        print "PR body: section \"" bname[p] "\" is out of order (" rule ")"
        break
      }
  }
  for (p = 1; p <= bn; p++)
    if (bidx[bname[p]] == p && (bname[p] in tidx) && !has[p])
      print "PR body: section \"" bname[p] "\" is empty; write None when there is nothing to say (" rule ")"
  if (vsec && nsec && vsec == nsec && (tname[vsec] in bidx)) {
    if (cnt["V"] < 1) print "PR body: Verification needs a **Verified** list with at least one item; write - None when there are none (" rule ")"
    if (cnt["N"] < 1) print "PR body: Verification needs a **Not verified** list with at least one item; write - None when there are none (" rule ")"
  }
  flush()
  for (p = 1; p <= bn; p++) {
    k = kind[p]
    if (k == "") continue
    lim = (k == "why") ? max_why : (k == "changes") ? max_changes : (k == "scope") ? max_scope : max_notes
    if (k == "why" && paras[p] > max_paras + 0)
      print "PR body: " substr(bname[p], 4) " has " paras[p] " paragraphs, at most " max_paras " (" rule ")"
    if (chars[p] > lim + 0)
      print "PR body: " substr(bname[p], 4) " has " chars[p] " characters, at most " lim " (" rule ")"
  }
  for (i = 1; i <= nw; i++) print warn[i]
}
' "$@"
}

# refs_awk BODY: prints one TAB-separated candidate per backtick span outside code (B5).
# A span is a path (has a / once a leading ./ is dropped, and ends in /, a dotfile or a known
# extension), a file name with a known extension and no /, or an identifier (camelCase, PascalCase
# or snake_case with a lowercase letter, no dot). Skipped as unsure: .js names and dotfiles without
# a / (decimal.js, .gitattributes), hosts (docs.example.com/a.html), dotted library APIs
# (os.Getenv) and names with no lowercase letter (NODE_ENV).
refs_awk() {
  LC_ALL=C awk "$awk_lib"'
function span(s,   tok, ln, p, first, last, ext, ispath) {
  tok = s
  if (s == "" || (tok in seen)) return
  seen[tok] = 1
  if (s ~ /[ \t]/) return
  ln = 0
  if (match(s, /:[0-9]+(-[0-9]+)?$/)) {
    split(substr(s, RSTART + 1), p, "-")
    ln = (p[2] != "") ? p[2] : p[1]
    s = substr(s, 1, RSTART - 1)
  }
  while (s ~ /^\.\//) s = substr(s, 3)
  if (s == "" || s ~ /^[-#@$~\/]/ || s ~ /[]*{}<>=|@[]/ || index(s, "://") || s ~ /^v?[0-9][0-9.]*$/) return
  last = s; sub(/.*\//, "", last)
  ext = ""
  if (match(last, /\.[A-Za-z0-9]+$/)) ext = substr(last, RSTART + 1)
  ispath = (s ~ /\/$/ || last ~ /^\.[A-Za-z0-9_-]+$/ || (ext != "" && index(" md go ts tsx js jsx mjs cjs json yml yaml sql sh toml mod sum proto txt env lock css html ", " " ext " ")))
  if (ispath && index(s, "/")) {
    first = s; sub(/\/.*/, "", first)
    if (first ~ /^[^.]/ && index(first, ".")) return
    print "P\t" s "\t" ln + 0 "\t" tok; return
  }
  # a file name without a / matches a file of that name anywhere in the tree
  if (ispath && ext != "js" && s !~ /^\./ && s !~ /\/$/) { print "P\t" s "\t" ln + 0 "\t" tok; return }
  if (s ~ /^[A-Za-z_][A-Za-z0-9_]*(\(\))?$/ && s ~ /[a-z]/ && (s ~ /_/ || s ~ /[a-z][A-Z]/)) {
    sub(/\(\)$/, "", s)
    print "I\t" s "\t0\t" tok
  }
}
{
  gsub(/\r/, "")
  line = $0
  t = trim(line)
  if (t ~ /^(```|~~~)/) { fence = !fence; next }
  if (fence) next
  line = strip_html(line)
  # span() calls match() too, so the position of this span is saved first
  while (match(line, /`[^`]*`/)) {
    rs = RSTART; rl = RLENGTH
    span(substr(line, rs + 1, rl - 2))
    line = substr(line, rs + rl)
  }
}
' "$1"
}

# B5: a path or name in backticks exists in HEAD or the base. Unsure cases are skipped. A line
# number passes when any file at HEAD that the path names is that long (an app-relative path in a
# monorepo names one file per app).
check_refs() {
  local cands files kind a n tok p res found hfs hf lines long longf rc=0
  cands=$(refs_awk "$body")
  [ -n "$cands" ] || return 0
  files=$({ git -C "$root" -c core.quotepath=off ls-tree -r --name-only HEAD | sed 's/^/H /'
    git -C "$root" -c core.quotepath=off ls-tree -r --name-only "$base" | sed 's/^/B /'; })
  while IFS=$'\t' read -r kind a n tok; do
    if [ "$kind" = P ]; then
      rc=0
      git -C "$root" check-ignore -q --no-index -- "$a" 2>/dev/null || rc=$?
      [ "$rc" -eq 1 ] || continue
      p=${a%/}
      res=$(P=$p LC_ALL=C awk '
BEGIN { p = ENVIRON["P"]; lp = length(p) }
{
  f = substr($0, 3)
  sfx = (f == p || (length(f) > lp && substr(f, length(f) - lp) == "/" p))
  if (sfx || index(f, p "/") == 1 || index(f, "/" p "/") > 0) found = 1
  if (sfx && substr($0, 1, 1) == "H") hf[++nh] = f
}
END { print found ? "Y" : "N"; for (i = 1; i <= nh; i++) print hf[i] }' <(printf '%s\n' "$files"))
      found=${res%%$'\n'*}
      hfs=""
      case $res in *$'\n'*) hfs=${res#*$'\n'} ;; esac
      if [ "$found" != Y ]; then
        echo "PR body: \`$tok\` does not exist; if it is not a path in this repository, drop the backticks (git/pull-request.md)"
      elif [ "$n" -gt 0 ] && [ -n "$hfs" ]; then
        long=-1
        while IFS= read -r hf; do
          lines=$(git -C "$root" cat-file blob "HEAD:$hf" | LC_ALL=C awk 'END { print NR }')
          if [ "$lines" -gt "$long" ]; then long=$lines; longf=$hf; fi
        done <<<"$hfs"
        if [ "$n" -gt "$long" ]; then
          echo "PR body: \`$tok\` is past the end of $longf ($long lines) (git/pull-request.md)"
        fi
      fi
    else
      git -C "$root" grep -q -w -F -e "$a" HEAD -- 2>/dev/null && continue
      git -C "$root" grep -q -w -F -e "$a" "$base" -- 2>/dev/null && continue
      echo "PR body: \`$tok\` is not in the repository; if it is not code, drop the backticks (git/pull-request.md)"
    fi
  done <<<"$cands"
}

# B1 to B6: the template's sections, in order, each with content; Verification lists; section caps;
# references that exist; long sentences (warnings).
check_body() {
  local tpl="" f out blocking refs warnings all=""
  for f in .github/PULL_REQUEST_TEMPLATE.md .github/pull_request_template.md \
    PULL_REQUEST_TEMPLATE.md docs/PULL_REQUEST_TEMPLATE.md; do
    if [ -f "$root/$f" ]; then tpl="$root/$f"; break; fi
  done
  if [ -n "$tpl" ]; then
    out=$(body_awk "$tpl" "$body")
  else
    out=$(body_awk <(default_template) "$body")
  fi
  blocking=$(printf '%s\n' "$out" | awk '!/^warning: /')
  warnings=$(printf '%s\n' "$out" | awk '/^warning: /')
  refs=$(check_refs)
  for f in "$blocking" "$refs" "$warnings"; do
    [ -z "$f" ] || all="$all${all:+$'\n'}$f"
  done
  [ -z "$all" ] && return 0
  printf '%s\n' "$all"
  # warnings alone leave the exit code at 0
  if [ -n "$blocking$refs" ]; then failed=1; fi
}


# is_generated PATH: a lockfile, a Go file whose first 10 lines at HEAD hold Go's generated-code
# header (also honoured by golangci-lint and GitHub), or a file marked linguist-generated in
# .gitattributes.
is_generated() {
  local value
  case ${1##*/} in
    package-lock.json | pnpm-lock.yaml | yarn.lock | bun.lock | go.sum) return 0 ;;
  esac
  case $1 in
    *.go)
      # awk reads to the end so git never gets SIGPIPE, which pipefail would report
      if git -C "$root" cat-file blob "HEAD:$1" 2>/dev/null |
        LC_ALL=C awk 'NR <= 10 && /^\/\/ Code generated .* DO NOT EDIT\.$/ { f = 1 } END { exit !f }'; then
        return 0
      fi
      ;;
  esac
  value=$(git -C "$root" check-attr linguist-generated -- "$1" | sed 's/^.*: //')
  [ "$value" = set ] || [ "$value" = true ]
}

# D1: lines changed outside generated files (a warning). A rename counts under its new path and a
# binary file (-\t-) has no lines.
size_lines=0
check_size() {
  local rec added deleted path new _
  size_lines=0
  while IFS= read -r -d '' rec; do
    added=${rec%%$'\t'*}
    rec=${rec#*$'\t'}
    deleted=${rec%%$'\t'*}
    path=${rec#*$'\t'}
    if [ -z "$path" ]; then
      IFS= read -r -d '' _
      IFS= read -r -d '' new
      path=$new
    fi
    [ "$added" != "-" ] || continue
    ! is_generated "$path" || continue
    size_lines=$((size_lines + added + deleted))
  done < <(git -C "$root" diff --numstat -z -M "$base"...HEAD)
  if [ "$size_lines" -gt "$PR_MAX_LINES" ]; then
    echo "warning: PR: $size_lines lines changed outside generated files, at most $PR_MAX_LINES; say in Notes why it is not split (git/pull-request.md)"
  fi
}

# comments_awk: reads the hunks of `git diff -U0` (first file), then the file as of HEAD (second).
# Prints D2 violations and D4 warnings, then `counts <added comment lines> <added code lines>`.
# A block is a run of comment lines; a blank, code or tool-comment line ends it, a delimiter line
# (/*, /**, */, **/ alone) neither counts nor ends it.
comments_awk() { # comments_awk PATH RULE LANG(go|ts|sql) DIFF FILE
  LC_ALL=C awk -v path="$1" -v rule="$2" -v lang="$3" -v max_lines="$PR_MAX_COMMENT_LINES" \
    -v max_words="$PR_MAX_SENTENCE_WORDS" "$awk_lib"'
# Tool comments: Go directives, generated-file headers, migration and query annotations (goose, sqlc
# -- name:, drizzle --> statement-breakpoint), swaggo // @Summary-style lines, linter and coverage
# switches, license tags.
function istool(t) {
  return t ~ /^\/\/go:/ || t ~ /^\/\/nolint/ || t ~ /^\/\/ ?Code generated/ || t ~ /^-- [+]goose/ ||
    t ~ /^-- name: / || t ~ /^--> statement-breakpoint/ || t ~ /^\/\/ @[A-Z]/ ||
    t ~ /eslint-(disable|enable)/ || t ~ /@ts-(expect-error|ignore|nocheck)/ || t ~ /^\/\/\/ <reference/ ||
    t ~ /SPDX-License-Identifier/ || t ~ /biome-ignore/ || t ~ /prettier-ignore/ || t ~ /(v8|c8|istanbul) ignore/
}
# an odd number of quote characters before a position means it sits inside a string
function instring(p,   q) {
  q = sprintf("%c", 39)
  return (split(p, tmp, "\"") - 1) % 2 || (split(p, tmp, q) - 1) % 2 || (split(p, tmp, "`") - 1) % 2
}
# the position of the first tok in t outside a string and not escaped (\/* in a regular
# expression); 0 when there is none
function outside(t, tok,   off, p, rest) {
  off = 0; rest = t
  while ((p = index(rest, tok)) > 0) {
    if (!instring(substr(t, 1, off + p - 1)) && substr(t, off + p - 1, 1) != "\\") return off + p
    off += p
    rest = substr(rest, p + 1)
  }
  return 0
}
# the first sentence of the block text over the limit, as its word count; 0 when none
function longest(s) { return long_sentences(s) ? long_len[1] : 0 }
function endblock(   w) {
  if (!bopen) return
  bopen = 0
  if (!badd) return
  if (bcnt > max_lines + 0) print path ":" bstart ": comment block of " bcnt " lines, at most " max_lines " (" rule ")"
  w = longest(btext)
  if (w) print "warning: " path ":" bstart ": a comment sentence has " w " words, at most " max_words " (" rule ")"
}
FILENAME != cur { cur = FILENAME; phase = (FILENAME == ARGV[1]) ? 1 : 2 }
phase == 1 {
  if ($0 !~ /^@@ / || !match($0, /[+][0-9]+(,[0-9]+)?/)) next
  split(substr($0, RSTART + 1, RLENGTH - 1), h, ",")
  c = h[1] + 0; d = (h[2] == "") ? 1 : h[2] + 0
  for (i = 0; i < d; i++) added[c + i] = 1
  next
}
{
  t = trim($0)
  kind = "X"
  if (t == "") kind = "B"
  else if (inblk) {
    kind = "C"
    if (index(t, "*/")) inblk = 0
  } else if (t ~ /^\/\*/) {
    kind = "C"
    if (!index(substr(t, 3), "*/")) inblk = 1
  } else if ((lang == "sql" && t ~ /^--/) || (lang != "sql" && t ~ /^\/\//)) kind = "C"
  else {
    p = outside(t, "/*")
    cp = outside(t, (lang == "sql") ? "--" : "//")
    if (p && (!cp || p < cp) && !index(substr(t, p + 2), "*/")) inblk = 1
  }
  if (kind == "C" && (t == "/*" || t == "/**" || t == "*/" || t == "**/")) kind = "D"
  else if (kind == "C" && istool(t)) kind = "T"
  isadd = (FNR in added)
  if (kind == "C" || kind == "D") {
    if (!bopen) { bopen = 1; bstart = FNR; bcnt = 0; badd = 0; btext = "" }
    if (isadd) badd = 1
    if (kind == "C") {
      bcnt++
      if (isadd) ncomment++
      s = t
      sub(/^\/\*+/, "", s); sub(/\*+\/$/, "", s); sub(/^(\/\/+|--+|\*+)/, "", s)
      s = trim(s)
      if (s != "") btext = btext (btext == "" ? "" : " ") s
    }
  } else {
    endblock()
    if (kind == "X" && isadd) ncode++
  }
}
END { endblock(); print "counts " ncomment + 0 " " ncode + 0 }
' "$4" "$5"
}

# Totals for the ratio check: added comment and code lines, and which areas had a checked file.
comment_total=0
code_total=0
seen_go=0
seen_typescript=0
seen_database=0
comment_warnings=""

# D2 (blocking) and D4 (warnings, kept in comment_warnings): comment blocks of added or changed
# lines in Go, TypeScript/JavaScript and SQL files, outside generated files.
# shellcheck disable=SC2034 # the seen_* flags are read by the ratio check (D3)
check_comments() {
  local status path old rule lang out line d2=""
  while IFS= read -r -d '' status; do
    IFS= read -r -d '' path
    old=$path
    case $status in R*) IFS= read -r -d '' path ;; esac
    case $path in
      *.go) rule=go/conventions.md; lang=go ;;
      *.ts | *.tsx | *.js | *.jsx | *.mjs | *.cjs) rule=typescript/conventions.md; lang=ts ;;
      *.sql) rule=database/conventions.md; lang=sql ;;
      *) continue ;;
    esac
    ! is_generated "$path" || continue
    out=$(comments_awk "$path" "$rule" "$lang" \
      <(git -C "$root" diff -U0 -M --no-ext-diff --no-color "$base"...HEAD -- ":(literal)$old" ":(literal)$path") \
      <(git -C "$root" show "HEAD:$path"))
    case $lang in go) seen_go=1 ;; ts) seen_typescript=1 ;; sql) seen_database=1 ;; esac
    while IFS= read -r line; do
      case $line in
        "counts "*)
          line=${line#counts }
          comment_total=$((comment_total + ${line% *}))
          code_total=$((code_total + ${line#* }))
          ;;
        "warning: "*) comment_warnings="$comment_warnings${comment_warnings:+$'\n'}$line" ;;
        *) d2="$d2${d2:+$'\n'}$line" ;;
      esac
    done <<<"$out"
  done < <(git -C "$root" diff --name-status -z -M --diff-filter=AMR "$base"...HEAD)
  if [ -n "$d2" ]; then
    printf '%s\n' "$d2"
    failed=1
  fi
}

# D3 (blocking): added comment lines may be at most PR_MAX_COMMENT_PERCENT of the added code
# lines, once comment and code lines together reach PR_MIN_LINES_FOR_RATIO.
check_ratio() {
  local rules=""
  [ $((comment_total + code_total)) -ge "$PR_MIN_LINES_FOR_RATIO" ] || return 0
  [ $((comment_total * 100)) -gt $((PR_MAX_COMMENT_PERCENT * code_total)) ] || return 0
  [ "$seen_go" -eq 0 ] || rules="go/conventions.md"
  [ "$seen_typescript" -eq 0 ] || rules="$rules${rules:+, }typescript/conventions.md"
  [ "$seen_database" -eq 0 ] || rules="$rules${rules:+, }database/conventions.md"
  printf 'PR: %s added comment lines for %s added code lines, at most %s%% of the code lines (%s)\n' \
    "$comment_total" "$code_total" "$PR_MAX_COMMENT_PERCENT" "$rules"
  failed=1
}

# D1 to D4: size, comment blocks, comment share, restating comments.
check_diff() {
  check_size
  check_comments
  check_ratio
  [ -z "$comment_warnings" ] || printf '%s\n' "$comment_warnings"
}

load_config
[ -z "$body" ] || check_body
[ "$no_diff" -eq 1 ] || check_diff
exit "$failed"
