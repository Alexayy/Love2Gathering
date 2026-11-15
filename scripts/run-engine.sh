#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# Preserve genuine user overrides while allowing Settings to replace paths
# that a previous launcher resolved automatically.
if [[ -z "${LOVE2GATHERING_DATA_DIR_EXPLICIT+x}" ]]; then
  if [[ -n "${LOVE2GATHERING_DATA_DIR:-}" && -z "${LOVE2GATHERING_STORAGE_RESOLVED:-}" ]]; then export LOVE2GATHERING_DATA_DIR_EXPLICIT=1;else export LOVE2GATHERING_DATA_DIR_EXPLICIT=0;fi
fi
if [[ -z "${LOVE2GATHERING_CACHE_DIR_EXPLICIT+x}" ]]; then
  if [[ -n "${LOVE2GATHERING_CACHE_DIR:-}" && -z "${LOVE2GATHERING_STORAGE_RESOLVED:-}" ]]; then export LOVE2GATHERING_CACHE_DIR_EXPLICIT=1;else export LOVE2GATHERING_CACHE_DIR_EXPLICIT=0;fi
fi
if [[ -n "${LOVE2GATHERING_STORAGE_RESOLVED:-}" ]]; then
  if [[ "$LOVE2GATHERING_DATA_DIR_EXPLICIT" == 0 ]]; then unset LOVE2GATHERING_DATA_DIR;fi
  if [[ "$LOVE2GATHERING_CACHE_DIR_EXPLICIT" == 0 ]]; then unset LOVE2GATHERING_CACHE_DIR;fi
fi
python3 "$ROOT/service/paths.py" --activate-pending >/dev/null
export LOVE2GATHERING_DATA_DIR="$(python3 "$ROOT/service/paths.py")"
CACHE_DIRECTORY=$(python3 "$ROOT/service/paths.py" --cache)
if [[ -n "$CACHE_DIRECTORY" ]]; then export LOVE2GATHERING_CACHE_DIR="$CACHE_DIRECTORY";fi
export LOVE2GATHERING_STORAGE_RESOLVED=1
if [[ ! -f "$ROOT/bridge/target/xmage-bridge-1.0.0.jar" ]]; then
  printf 'XMage bridge needs building. Run scripts/build-engine.sh first.\n' >&2
  exit 1
fi
ENGINE_PORT="${1:-17371}"
ENGINE_WORK_DIR="$ROOT/data/engine-$ENGINE_PORT"
mkdir -p "$ENGINE_WORK_DIR"
cd "$ENGINE_WORK_DIR"
exec java -Xms128m -Xmx2g -Djava.awt.headless=true -Dlove2gathering.root="$ROOT" -cp "$ROOT/bridge/target/xmage-bridge-1.0.0.jar:$ROOT/bridge/target/lib/*" love2gathering.EngineBridge "$ENGINE_PORT"
