#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$ROOT/bridge/target/test-classes" "$ROOT/data/engine-tests"
javac -cp "$ROOT/bridge/target/xmage-bridge-1.0.0.jar:$ROOT/bridge/target/lib/*" -d "$ROOT/bridge/target/test-classes" "$ROOT/bridge/tests/love2gathering/TriggerFixture.java" "$ROOT/bridge/tests/love2gathering/ActionabilityFixture.java"
cd "$ROOT/data/engine-tests"
java -Xmx2g -Djava.awt.headless=true -cp "$ROOT/bridge/target/test-classes:$ROOT/bridge/target/xmage-bridge-1.0.0.jar:$ROOT/bridge/target/lib/*" love2gathering.TriggerFixture "$ROOT"
java -Xmx2g -Djava.awt.headless=true -cp "$ROOT/bridge/target/test-classes:$ROOT/bridge/target/xmage-bridge-1.0.0.jar:$ROOT/bridge/target/lib/*" love2gathering.ActionabilityFixture "$ROOT"
