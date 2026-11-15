#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
PORT="${1:-17464}"
CLASSES="$ROOT/bridge/target/test-classes"
RUNTIME="$ROOT/bridge/target/xmage-bridge-1.0.0.jar:$ROOT/bridge/target/lib/*"
mkdir -p "$CLASSES" "$ROOT/data/engine-fixture-$PORT"
javac -cp "$RUNTIME" -d "$CLASSES" "$ROOT/bridge/tests/love2gathering/TriggerFixture.java" "$ROOT/bridge/tests/love2gathering/ActionabilityFixture.java" "$ROOT/bridge/tests/love2gathering/NativeViewFixture.java" "$ROOT/bridge/tests/love2gathering/NativeViewServer.java"
cd "$ROOT/data/engine-fixture-$PORT"
exec java -Xmx2g -Djava.awt.headless=true -cp "$CLASSES:$RUNTIME" love2gathering.NativeViewServer "$ROOT" "$PORT"
