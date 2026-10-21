#!/usr/bin/env bash
# Links this repo's git rules into your user-level Claude Code folder, so they
# load in every project and `git pull` here updates them. Skills come from the
# plugin (README, "Install").
# Usage: bash scripts/link-user.sh   (CLAUDE_CONFIG_DIR, if set, replaces ~/.claude)
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
dest=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/rules/git

if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$repo/rules/git" ]; then
  echo "ok       $dest"
elif [ -e "$dest" ] || [ -L "$dest" ]; then
  echo "skipped  $dest (something else is there; move it away to link this repo's copy)" >&2
  exit 1
else
  mkdir -p "$(dirname "$dest")"
  ln -s "$repo/rules/git" "$dest"
  echo "linked   $dest -> $repo/rules/git"
fi
