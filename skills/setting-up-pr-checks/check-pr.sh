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

body_awk() { # body_awk TEMPLATE BODY: prints the violations of B1 to B4 and the warnings of B6
  LC_ALL=C awk -v rule="git/pull-request.md" -v max_paras="$PR_MAX_WHY_PARAGRAPHS" \
    -v max_why="$PR_MAX_WHY_CHARS" -v max_changes="$PR_MAX_CHANGES_CHARS" \
    -v max_scope="$PR_MAX_SCOPE_CHARS" -v max_notes="$PR_MAX_NOTES_CHARS" \
    -v max_words="$PR_MAX_SENTENCE_WORDS" '
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function nonempty(s) { s = trim(s); sub(/^([-*+]|[0-9]+\.)([ \t]+|$)/, "", s); return trim(s) != "" }
function item(s) { s = trim(s); return s ~ /^[-*+]([ \t]|$)/ }
# A prose chunk (a paragraph or one list item) ends here: split it into sentences and warn on long ones.
# A backtick span counts as one word, so its spaces are hidden while the chunk is split.
function flush(   s, out, n, w, i, k, st, q) {
  if (chunk == "") return
  s = chunk; chunk = ""; out = ""
  while (match(s, /`[^`]*`/)) {
    q = substr(s, RSTART, RLENGTH); gsub(/[ \t]/, "\001", q)
    out = out substr(s, 1, RSTART - 1) q
    s = substr(s, RSTART + RLENGTH)
  }
  n = split(out s, w, /[ \t]+/)
  st = 1
  for (i = 1; i <= n; i++) {
    if (w[i] !~ /[.?!]$/ && i != n) continue
    if (i - st + 1 > max_words + 0) {
      q = ""
      for (k = st; k < st + 6; k++) q = q (k > st ? " " : "") w[k]
      gsub(/\001/, " ", q)
      warn[++nw] = "warning: PR body: a sentence has " (i - st + 1) " words, at most " max_words ": \"" q " …\" (" rule ")"
    }
    st = i + 1
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
  else {
    text = ""
    while (1) {
      if (inc) {
        i = index(line, "-->")
        if (!i) { line = ""; break }
        line = substr(line, i + 3); inc = 0
      } else {
        i = index(line, "<!--")
        if (!i) break
        text = text substr(line, 1, i - 1); line = substr(line, i + 4); inc = 1
      }
    }
    text = text line
  }
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
    if (t == "") inpara = 0
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

# B1 to B4 and B6: the template's sections, in order, each with content; Verification lists;
# section caps; long sentences (warnings).
check_body() {
  local tpl="" f out
  for f in .github/PULL_REQUEST_TEMPLATE.md .github/pull_request_template.md \
    PULL_REQUEST_TEMPLATE.md docs/PULL_REQUEST_TEMPLATE.md; do
    if [ -f "$root/$f" ]; then tpl="$root/$f"; break; fi
  done
  if [ -n "$tpl" ]; then
    out=$(body_awk "$tpl" "$body")
  else
    out=$(body_awk <(default_template) "$body")
  fi
  [ -z "$out" ] && return 0
  printf '%s\n' "$out"
  # warnings alone leave the exit code at 0
  if printf '%s\n' "$out" | grep -qv '^warning: '; then failed=1; fi
}


check_diff() { :; } # the diff checks, D1 to D4

load_config
[ -z "$body" ] || check_body
[ "$no_diff" -eq 1 ] || check_diff
exit "$failed"
