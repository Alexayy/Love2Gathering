#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export LOVE2GATHERING_DATA_DIR="$(python3 "$ROOT/service/paths.py")"
if [[ ! -f "$ROOT/bridge/target/xmage-bridge-1.0.0.jar" ]]; then
  printf 'XMage bridge needs building. Run scripts/build-engine.sh first.\n' >&2
  exit 1
fi
ENGINE_PORT="${1:-17371}"
ENGINE_WORK_DIR="$ROOT/data/engine-$ENGINE_PORT"
mkdir -p "$ENGINE_WORK_DIR"
cd "$ENGINE_WORK_DIR"
exec java -Xms128m -Xmx2g -Djava.awt.headless=true -Dlove2gathering.root="$ROOT" -cp "$ROOT/bridge/target/xmage-bridge-1.0.0.jar:$ROOT/bridge/target/lib/*" love2gathering.EngineBridge "$ENGINE_PORT"
