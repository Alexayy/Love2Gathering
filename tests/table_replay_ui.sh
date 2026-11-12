#!/bin/sh
set -eu
# Start a separate catalog API over a SQLite backup of the recorded test game.
# This harness writes only its temporary UI layout; it never contacts an engine.
LOVE2GATHERING_CATALOG_PORT=${LOVE2GATHERING_CATALOG_PORT:-17380} python3 - <<'PY'
import json,os,pathlib,urllib.request
with urllib.request.urlopen('http://127.0.0.1:'+os.environ['LOVE2GATHERING_CATALOG_PORT']+'/health') as response: health=json.load(response)
data=pathlib.Path(health['storage']['dataDirectory']).resolve()
assert pathlib.Path('/tmp') in data.parents, 'Table/replay acceptance must use a temporary catalog data directory'
PY
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-table-ui.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT INT TERM
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$project_dir/assets/kenney" "$test_dir/assets/"
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/tests/table_replay_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'EOF'
function love.conf(t)
    t.identity='love2gathering-table-replay-ui-tests';t.window.title='Love: 2 Gathering — isolated table / replay acceptance'
    t.window.width=1440;t.window.height=900;t.window.vsync=0;t.window.resizable=true
    t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
EOF
LOVE2GATHERING_CATALOG_PORT=${LOVE2GATHERING_CATALOG_PORT:-17380} LOVE2GATHERING_ENGINE_PORT=17490 love "$test_dir"
LOVE2GATHERING_CATALOG_PORT=${LOVE2GATHERING_CATALOG_PORT:-17380} python3 - <<'PY'
import json,os,urllib.request
report=json.load(open('/tmp/love2gathering-table-replay-ui-report.json'))
with urllib.request.urlopen('http://127.0.0.1:'+os.environ['LOVE2GATHERING_CATALOG_PORT']+'/ui-layout') as response: layout=json.load(response)
assert layout.get('table-replay-quit-probe')==report['quitProbe'], 'Pending UI layout was not flushed to SQLite on quit'
report['quitFlushPassed']=True
with open('/tmp/love2gathering-table-replay-ui-report.json','w') as output:json.dump(report,output,indent=2)
print('TABLE/REPLAY PASS Pending SQLite layout write flushed on actual LÖVE quit')
PY
