#!/bin/sh
# Supply an isolated catalog with LOVE2GATHERING_CATALOG_PORT.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-builder.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT INT TERM
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
cp "$project_dir/tests/builder_integration/main.lua" "$project_dir/tests/builder_integration/conf.lua" "$test_dir/"
love "$test_dir"
