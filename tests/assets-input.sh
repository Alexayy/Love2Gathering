#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-assets-input.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT INT TERM
mkdir -p "$test_dir/app" "$test_dir/assets/fonts"
cp -R "$project_dir/lib" "$test_dir/"
cp "$project_dir/app/assets.lua" "$test_dir/app/"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$project_dir/assets/kenney" "$test_dir/assets/"
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/tests/assets-input/main.lua" "$project_dir/tests/assets-input/conf.lua" "$test_dir/"
love "$test_dir"
