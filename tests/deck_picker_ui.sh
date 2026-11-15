#!/bin/sh
set -eu
: "${LOVE2GATHERING_ENGINE_PORT:?Explicit test-only native facade port is required}"
: "${LOVE2GATHERING_CATALOG_PORT:?Explicit temporary catalog port is required}"
python3 - <<'PY'
import json,os,urllib.request
engine=int(os.environ['LOVE2GATHERING_ENGINE_PORT']);catalog=int(os.environ['LOVE2GATHERING_CATALOG_PORT'])
assert engine>=17400 and catalog>=17400 and engine!=catalog
for port in [engine,catalog]:
 with urllib.request.urlopen(f'http://127.0.0.1:{port}/health',timeout=5) as r:d=json.load(r)
 if port==catalog:assert d.get('ready')and d.get('storage',{}).get('dataDirectory','').startswith('/tmp/'),'A ready temporary catalog is required'
with urllib.request.urlopen(f'http://127.0.0.1:{engine}/session/state')as r:d=json.load(r)
assert not d.get('running'),'Only an idle owned native engine is allowed'
PY
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-deck-picker-ui.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT INT TERM
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/main.lua" "$test_dir/application.lua"
cp "$project_dir/tests/deck_picker_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'EOF'
function love.conf(t)
 t.identity='love2gathering-deck-picker-ui-tests';t.window.title='Love: 2 Gathering — deck picker acceptance'
 t.window.width=1440;t.window.height=900;t.window.vsync=0;t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
EOF
cp -R "$project_dir/assets/kenney/runtime" "$test_dir/assets/kenney/"
cp "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
love "$test_dir"
