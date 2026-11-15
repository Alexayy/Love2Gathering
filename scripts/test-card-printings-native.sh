#!/bin/sh
# Compile only the fixture: production classes must come from the packaged jar.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-printings-native.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT INT TERM
mkdir -p "$test_dir/classes" "$test_dir/runtime"
classpath="$project_dir/bridge/target/xmage-bridge-1.0.0.jar:$project_dir/bridge/target/lib/*"
java_command=java;javac_command=javac
if [ -n "${JAVA_HOME:-}" ];then java_command="$JAVA_HOME/bin/java";javac_command="$JAVA_HOME/bin/javac";fi
"$javac_command" -cp "$classpath" -d "$test_dir/classes" "$project_dir/bridge/tests/love2gathering/CardPrintingFixture.java"
cd "$test_dir/runtime"
"$java_command" -Xmx2g -Djava.awt.headless=true -cp "$test_dir/classes:$classpath" love2gathering.CardPrintingFixture "$project_dir"
