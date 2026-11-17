#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
MAVEN_VERSION=3.9.12
MAVEN="$ROOT/.tools/apache-maven-$MAVEN_VERSION/bin/mvn"
if command -v mvn >/dev/null 2>&1; then MAVEN=$(command -v mvn); fi
if [[ ! -x "$MAVEN" ]]; then
  mkdir -p "$ROOT/.tools"
  ARCHIVE="$ROOT/.tools/apache-maven-$MAVEN_VERSION-bin.tar.gz"
  curl --fail --location --retry 2 "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/$MAVEN_VERSION/apache-maven-$MAVEN_VERSION-bin.tar.gz" -o "$ARCHIVE"
  curl --fail --location --retry 2 "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/$MAVEN_VERSION/apache-maven-$MAVEN_VERSION-bin.tar.gz.sha512" -o "$ARCHIVE.sha512"
  python3 - "$ARCHIVE" <<'PY'
import hashlib, pathlib, sys
p=pathlib.Path(sys.argv[1]); expected=p.with_suffix(p.suffix+'.sha512').read_text().strip().split()[0]
if hashlib.sha512(p.read_bytes()).hexdigest()!=expected: raise SystemExit('Maven checksum mismatch')
PY
  tar -xzf "$ARCHIVE" -C "$ROOT/.tools"
fi
export MAVEN_OPTS="${MAVEN_OPTS:--Xmx3g}"
MAVEN_FLAGS=(-Dmaven.repo.local="$ROOT/.tools/m2" -DskipTests -Dmaven.javadoc.skip=true -Dcheckstyle.skip=true)
# Core API changes can leave unchanged card classes linked to old signatures.
# Recompile the complete selected reactor before publishing its runtime JARs.
"$MAVEN" -f "$ROOT/engine/mage/pom.xml" "${MAVEN_FLAGS[@]}" -pl Mage.Sets,Mage.Server.Plugins/Mage.Player.Human,Mage.Server.Plugins/Mage.Player.AI.MAD,Mage.Server.Plugins/Mage.Game.TwoPlayerDuel,Mage.Server.Plugins/Mage.Game.CommanderDuel,Mage.Server.Plugins/Mage.Game.CommanderFreeForAll,Mage.Server.Plugins/Mage.Deck.Constructed,Mage.Server.Plugins/Mage.Game.FreeForAll,Mage.Server.Plugins/Mage.Deck.Limited,Mage.Server.Plugins/Mage.Tournament.BoosterDraft -am clean install
python3 "$ROOT/bridge/build_card_map.py"
# Build the adapter away from the live runtime path. Existing desktop engines
# may still hold the old JAR open; publishing by rename preserves their ZipFile.
BRIDGE_STAGE=$(mktemp -d "$ROOT/.tools/bridge-build.XXXXXX")
trap 'rm -rf -- "$BRIDGE_STAGE"' EXIT
mkdir -p "$BRIDGE_STAGE/bridge"
cp "$ROOT/bridge/pom.xml" "$BRIDGE_STAGE/bridge/pom.xml"
cp -R "$ROOT/bridge/src" "$BRIDGE_STAGE/bridge/src"
"$MAVEN" -f "$BRIDGE_STAGE/bridge/pom.xml" "${MAVEN_FLAGS[@]}" package
mkdir -p "$ROOT/bridge/target/lib"
for DEPENDENCY in "$BRIDGE_STAGE/bridge/target/lib/"*.jar; do
  DESTINATION="$ROOT/bridge/target/lib/$(basename -- "$DEPENDENCY")"
  TEMPORARY=$(mktemp "$DESTINATION.new.XXXXXX")
  cp "$DEPENDENCY" "$TEMPORARY"
  chmod 0644 "$TEMPORARY"
  mv -f -- "$TEMPORARY" "$DESTINATION"
done
TEMPORARY=$(mktemp "$ROOT/bridge/target/xmage-bridge-1.0.0.jar.new.XXXXXX")
cp "$BRIDGE_STAGE/bridge/target/xmage-bridge-1.0.0.jar" "$TEMPORARY"
chmod 0644 "$TEMPORARY"
mv -f -- "$TEMPORARY" "$ROOT/bridge/target/xmage-bridge-1.0.0.jar"
printf 'XMage bridge built. Start with scripts/run-engine.sh\n'
