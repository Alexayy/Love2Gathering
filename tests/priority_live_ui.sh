#!/bin/sh
set -eu
# Starts/stops native games. Explicitly isolated idle engine and temporary user
# storage are mandatory; this harness never connects to the default user engine.
: "${LOVE2GATHERING_ENGINE_PORT:?Set an owned isolated idle test engine port}"
: "${LOVE2GATHERING_CATALOG_PORT:?Set a catalog using temporary data}"
export LOVE2GATHERING_ENGINE_PORT LOVE2GATHERING_CATALOG_PORT
python3 - <<'PY'
import json,os,pathlib,urllib.request
def read(port,path):
    with urllib.request.urlopen('http://127.0.0.1:'+port+path,timeout=10) as response:return json.load(response)
engine=os.environ['LOVE2GATHERING_ENGINE_PORT']
assert engine!='17371','Use an explicitly isolated engine, never the default user engine'
health=read(os.environ['LOVE2GATHERING_CATALOG_PORT'],'/health')
data=pathlib.Path(health['storage']['dataDirectory']).resolve()
assert pathlib.Path('/tmp') in data.parents,'Native UI acceptance requires catalog storage under /tmp'
assert read(engine,'/health').get('engine')=='XMage','Expected native XMage'
assert read(engine,'/session/state').get('running') is False,'Test engine must be idle'
PY
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-priority-live-ui.XXXXXX)
cleanup() {
    python3 - <<'PY'
import os,urllib.request
request=urllib.request.Request('http://127.0.0.1:'+os.environ['LOVE2GATHERING_ENGINE_PORT']+'/session/stop',data=b'{}',headers={'Content-Type':'application/json'})
try:
    with urllib.request.urlopen(request,timeout=15) as response:response.read()
except Exception as error:print('Native UI cleanup:',error)
PY
    rm -rf "$test_dir"
}
trap cleanup EXIT INT TERM
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
cp -R "$project_dir/assets/kenney/ui" "$project_dir/assets/kenney/particles" "$project_dir/assets/kenney/theme" "$test_dir/assets/kenney/"
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/tests/priority_live_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'EOF'
function love.conf(t)
    t.identity='love2gathering-priority-live-ui-tests';t.window.title='Love: 2 Gathering — native priority UI acceptance'
    t.window.width=1440;t.window.height=900;t.window.vsync=0;t.window.resizable=true
    t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
EOF
cp -R "$project_dir/assets/kenney/runtime" "$test_dir/assets/kenney/"
cp "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
love "$test_dir"
