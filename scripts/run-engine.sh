#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ ! -f "$ROOT/bridge/target/xmage-bridge-1.0.0.jar" ]]; then
  printf 'XMage bridge needs building. Run scripts/build-engine.sh first.\n' >&2
  exit 1
fi
mkdir -p "$ROOT/data/engine"
cd "$ROOT/data/engine"
exec java -Xms128m -Xmx2g -Djava.awt.headless=true -Dlove2gathering.root="$ROOT" -cp "$ROOT/bridge/target/xmage-bridge-1.0.0.jar:$ROOT/bridge/target/lib/*" love2gathering.EngineBridge "${1:-17371}"
