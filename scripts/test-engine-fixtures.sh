#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$ROOT/bridge/target/test-classes" "$ROOT/data/engine-tests"
javac -cp "$ROOT/bridge/target/xmage-bridge-1.0.0.jar:$ROOT/bridge/target/lib/*" -d "$ROOT/bridge/target/test-classes" "$ROOT/bridge/tests/love2gathering/TriggerFixture.java" "$ROOT/bridge/tests/love2gathering/ActionabilityFixture.java" "$ROOT/bridge/tests/love2gathering/ManualManaFixture.java" "$ROOT/bridge/tests/love2gathering/MultiplayerFixture.java" "$ROOT/bridge/tests/love2gathering/BotCommanderFixture.java" "$ROOT/bridge/tests/love2gathering/PriorityFixture.java" "$ROOT/bridge/tests/love2gathering/RoomMultiplayerFixture.java" "$ROOT/bridge/tests/love2gathering/DraftFixture.java" "$ROOT/bridge/tests/love2gathering/NativeViewFixture.java" "$ROOT/bridge/tests/love2gathering/ProfileFixture.java" "$ROOT/bridge/tests/love2gathering/CombatTimingFixture.java" "$ROOT/bridge/tests/love2gathering/StartingPresentationFixture.java" "$ROOT/bridge/tests/love2gathering/ReplayRelocationFixture.java" "$ROOT/bridge/tests/love2gathering/UpstreamCompatibilityFixture.java"
cd "$ROOT/data/engine-tests"
java -Xmx2g -Djava.awt.headless=true -cp "$ROOT/bridge/target/test-classes:$ROOT/bridge/target/xmage-bridge-1.0.0.jar:$ROOT/bridge/target/lib/*" love2gathering.TriggerFixture "$ROOT"
java -Xmx2g -Djava.awt.headless=true -cp "$ROOT/bridge/target/test-classes:$ROOT/bridge/target/xmage-bridge-1.0.0.jar:$ROOT/bridge/target/lib/*" love2gathering.ActionabilityFixture "$ROOT"
java -Xmx768m -Djava.awt.headless=true -cp "$ROOT/bridge/target/test-classes:$ROOT/bridge/target/xmage-bridge-1.0.0.jar:$ROOT/bridge/target/lib/*" love2gathering.ManualManaFixture "$ROOT"
java -Xmx2g -Djava.awt.headless=true -cp "$ROOT/bridge/target/test-classes:$ROOT/bridge/target/xmage-bridge-1.0.0.jar:$ROOT/bridge/target/lib/*" love2gathering.MultiplayerFixture "$ROOT"
java -Xmx768m -Djava.awt.headless=true -cp "$ROOT/bridge/target/test-classes:$ROOT/bridge/target/xmage-bridge-1.0.0.jar:$ROOT/bridge/target/lib/*" love2gathering.BotCommanderFixture "$ROOT"
java -Xmx2g -Djava.awt.headless=true -cp "$ROOT/bridge/target/test-classes:$ROOT/bridge/target/xmage-bridge-1.0.0.jar:$ROOT/bridge/target/lib/*" love2gathering.PriorityFixture "$ROOT"
java -Xmx2g -Djava.awt.headless=true -cp "$ROOT/bridge/target/test-classes:$ROOT/bridge/target/xmage-bridge-1.0.0.jar:$ROOT/bridge/target/lib/*" love2gathering.RoomMultiplayerFixture "$ROOT"
java -Xmx2g -Djava.awt.headless=true -cp "$ROOT/bridge/target/test-classes:$ROOT/bridge/target/xmage-bridge-1.0.0.jar:$ROOT/bridge/target/lib/*" love2gathering.DraftFixture "$ROOT"
java -Xmx2g -Djava.awt.headless=true -cp "$ROOT/bridge/target/test-classes:$ROOT/bridge/target/xmage-bridge-1.0.0.jar:$ROOT/bridge/target/lib/*" love2gathering.NativeViewFixture "$ROOT"
java -Xmx2g -Djava.awt.headless=true -cp "$ROOT/bridge/target/test-classes:$ROOT/bridge/target/xmage-bridge-1.0.0.jar:$ROOT/bridge/target/lib/*" love2gathering.ProfileFixture "$ROOT"
java -Xmx2g -Djava.awt.headless=true -cp "$ROOT/bridge/target/test-classes:$ROOT/bridge/target/xmage-bridge-1.0.0.jar:$ROOT/bridge/target/lib/*" love2gathering.CombatTimingFixture "$ROOT"

java -Xmx2g -Djava.awt.headless=true -cp "$ROOT/bridge/target/test-classes:$ROOT/bridge/target/xmage-bridge-1.0.0.jar:$ROOT/bridge/target/lib/*" love2gathering.StartingPresentationFixture "$ROOT"
java -Xmx512m -Djava.awt.headless=true -cp "$ROOT/bridge/target/test-classes:$ROOT/bridge/target/xmage-bridge-1.0.0.jar:$ROOT/bridge/target/lib/*" love2gathering.ReplayRelocationFixture "$ROOT"

java -Xmx768m -Djava.awt.headless=true -cp "$ROOT/bridge/target/test-classes:$ROOT/bridge/target/xmage-bridge-1.0.0.jar:$ROOT/bridge/target/lib/*" love2gathering.UpstreamCompatibilityFixture "$ROOT"
