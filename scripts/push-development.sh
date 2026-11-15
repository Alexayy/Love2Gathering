#!/usr/bin/env bash
# Publish only the parent development branch. Never stage or recurse into XMage.
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd -- "$PROJECT_ROOT"
if [[ "$(git branch --show-current)" != development ]]; then
  printf '%s\n' 'Switch to the parent development branch before publishing.' >&2
  exit 1
fi
PUSH_URL=$(git remote get-url --push --all origin)
if [[ "$PUSH_URL" == *$'\n'* ]]; then
  printf '%s\n' 'origin has multiple push destinations; nothing was pushed.' >&2
  exit 1
fi
case "$PUSH_URL" in
  https://github.com/Alexayy/Love2Gathering|https://github.com/Alexayy/Love2Gathering.git|git@github.com:Alexayy/Love2Gathering|git@github.com:Alexayy/Love2Gathering.git|ssh://git@github.com/Alexayy/Love2Gathering|ssh://git@github.com/Alexayy/Love2Gathering.git) ;;
  *) printf '%s\n' 'origin must point to Alexayy/Love2Gathering; nothing was pushed.' >&2; exit 1 ;;
esac
if [[ "$#" -gt 1 || ( "$#" -eq 1 && "$1" != --check-only ) ]]; then
  printf '%s\n' 'Usage: scripts/push-development.sh [--check-only]' >&2
  exit 2
fi

git -c fetch.recurseSubmodules=false fetch --no-recurse-submodules --no-tags origin refs/heads/development:refs/remotes/origin/development
python3 scripts/check-submodule-pin.py --base refs/remotes/origin/development --head HEAD --index
if ! git diff --quiet --ignore-submodules=all || ! git diff --cached --quiet --ignore-submodules=all; then
  printf '%s\n' 'Commit the parent tracked-file changes before pushing. Nested XMage work was left untouched.' >&2
  exit 1
fi
if [[ "${1:-}" == --check-only ]]; then
  printf '%s\n' 'Parent publish checks passed; no push requested.'
  exit 0
fi
git -c push.recurseSubmodules=no push --recurse-submodules=no --no-follow-tags origin HEAD:refs/heads/development
