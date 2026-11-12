#!/bin/sh
# The real catalog API must already be listening on the configured catalog port (default localhost:17370).
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-frontend.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT INT TERM
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$project_dir/assets/kenney" "$test_dir/assets/"
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/tests/frontend_harness/main.lua" "$project_dir/tests/frontend_harness/conf.lua" "$test_dir/"
love "$test_dir"
