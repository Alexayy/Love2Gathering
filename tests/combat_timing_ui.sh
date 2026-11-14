#!/bin/sh
set -eu
: "${LOVE2GATHERING_ENGINE_PORT:?Explicit test-only native facade port is required}"
: "${LOVE2GATHERING_CATALOG_PORT:?Explicit temporary catalog port is required}"
python3 - <<'PY'
import json,os,urllib.request
engine=int(os.environ['LOVE2GATHERING_ENGINE_PORT']);catalog=int(os.environ['LOVE2GATHERING_CATALOG_PORT'])
assert engine>=17400 and catalog>=17400 and engine!=catalog,'Only explicit isolated test ports are allowed'
def read(port,path):
 with urllib.request.urlopen(f'http://127.0.0.1:{port}{path}',timeout=5) as response:return json.load(response)
facade=read(engine,'/fixture/report');assert 'completed' in facade and 'current' in facade,'A test-only native facade is required'
health=read(catalog,'/health');assert health.get('ready') and health.get('storage',{}).get('dataDirectory','').startswith('/tmp/'),'A ready catalog in temporary storage is required'
print('Native fixture facade and temporary ready catalog verified')
PY
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-combat-timing-ui.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT INT TERM
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/main.lua" "$test_dir/application.lua"
cp "$project_dir/tests/combat_timing_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'EOF'
function love.conf(t)
 t.identity='love2gathering-combat-timing-ui-tests';t.window.title='Love: 2 Gathering — combat timing acceptance'
 t.window.width=1440;t.window.height=900;t.window.vsync=0;t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
EOF
cp -R "$project_dir/assets/kenney/runtime" "$test_dir/assets/kenney/"
cp "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
COMBAT_TEST_WIDTH=1440 love "$test_dir"
COMBAT_TEST_WIDTH=1120 love "$test_dir"
python3 - "$project_dir/tests/combat-timing-ui-report.json" <<'PY'
import json,sys
cases=[json.load(open('/tmp/love2gathering-combat-timing-ui-'+str(width)+'-report.json'))for width in(1440,1120)]
json.dump({'passed':all(case['passed']for case in cases),'checks':sum(len(case['checks'])for case in cases),'runs':cases},open(sys.argv[1],'w'),indent=2)
PY
