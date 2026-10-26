#!/usr/bin/env bash
# Writes the files an example shows into a folder. Each "## <path>" heading
# names a file, and the first fenced block under it is that file; later blocks
# under the same heading are variants ("Without zod, the same file is:") and
# are skipped. A path heading without a block, or a path shown twice, fails.
# Usage: bash examples/extract.sh <example.md> <dest folder>
set -euo pipefail

[ $# -eq 2 ] || { echo "usage: bash examples/extract.sh <example.md> <dest folder>" >&2; exit 1; }
example=$1
dest=$2
[ -f "$example" ] || { echo "no such example: $example" >&2; exit 1; }
mkdir -p "$dest"

awk -v dest="$dest" -v example="$example" '
  function fail(msg) { print example ": " msg > "/dev/stderr"; failed = 1; exit 1 }
  function finish() { if (path != "" && !written) fail("\"## " path "\" has no code block") }
  /^```/ {
    if (!fence) {
      fence = 1
      if (path != "" && !written) { capture = 1; out = dest "/" path; dir = out; sub(/\/[^\/]*$/, "", dir); system("mkdir -p \"" dir "\""); printf "" > out }
      next
    }
    fence = 0
    if (capture) { close(out); print path; capture = 0; written = 1 }
    next
  }
  fence { if (capture) print > out; next }
  /^## / {
    finish()
    name = substr($0, 4)
    if (name ~ /^[A-Za-z0-9_.\/{}@-]+$/ && name ~ /\./) {
      if (name in seen) fail("\"## " name "\" is shown twice")
      seen[name] = 1; path = name; written = 0
    } else { path = "" }
  }
  END { if (!failed) { if (fence) fail("a code block is not closed"); finish() } }
' "$example"
