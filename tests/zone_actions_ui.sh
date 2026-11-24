#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
native_dir=${LOVE2GATHERING_NATIVE_ZONE_FRAMES:-"$project_dir/build/table-overhaul/zone-actions"}
test_dir=$(mktemp -d /tmp/love2gathering-zone-actions-ui.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT INT TERM
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney" "$test_dir/native" "$project_dir/build/table-overhaul/zone-actions-ui"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$project_dir/assets/card-backs" "$test_dir/assets/"
for name in runtime ui particles sounds theme;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/"*.ttf "$test_dir/assets/fonts/"
for name in memory-deluge-before-selection memory-deluge-one-selected memory-deluge-complete flashback-offer exile-extension-offered exile-permission-expired foretell-offered-owner foretell-hidden-opponent shark-typhoon-ability-choice;do cp "$native_dir/$name.json" "$test_dir/native/";done
cp "$project_dir/tests/zone_actions_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'EOF'
function love.conf(t)
 t.identity='love2gathering-isolated-zone-actions-ui';t.window.title='Love: 2 Gathering — native zone choices acceptance'
 t.window.width=1440;t.window.height=900;t.window.vsync=0;t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
EOF
LOVE2GATHERING_ZONE_UI_OUTPUT="$project_dir/build/table-overhaul/zone-actions-ui" love "$test_dir"
