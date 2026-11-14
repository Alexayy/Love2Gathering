#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-assets-input.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT INT TERM
mkdir -p "$test_dir/app" "$test_dir/assets/fonts" "$test_dir/assets/kenney"
cp -R "$project_dir/lib" "$test_dir/"
cp "$project_dir/app/assets.lua" "$project_dir/app/theme.lua" "$project_dir/app/fonts.lua" "$project_dir/app/surfaces.lua" "$test_dir/app/"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme runtime;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/tests/assets-input/main.lua" "$project_dir/tests/assets-input/conf.lua" "$test_dir/"
cp "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
love "$test_dir"
