#!/bin/sh
set -eu
: "${LOVE2GATHERING_ENGINE_PORT:?Set an isolated native test engine}"
: "${LOVE2GATHERING_CATALOG_PORT:?Set a catalog using temporary data}"
: "${LOVE2GATHERING_ROOM_HOST_PORT:?Set an owned test host gateway}"
: "${LOVE2GATHERING_ROOM_GUEST_PORT:?Set a second owned test client gateway}"
export LOVE2GATHERING_ENGINE_PORT LOVE2GATHERING_CATALOG_PORT LOVE2GATHERING_ROOM_HOST_PORT LOVE2GATHERING_ROOM_GUEST_PORT
python3 - <<'PY'
import json,os,pathlib,urllib.request
assert os.environ['LOVE2GATHERING_ENGINE_PORT']!='17371','Do not use the default user engine'
assert os.environ['LOVE2GATHERING_ROOM_HOST_PORT']!=os.environ['LOVE2GATHERING_ROOM_GUEST_PORT'],'Two distinct gateways are required'
with urllib.request.urlopen('http://127.0.0.1:'+os.environ['LOVE2GATHERING_CATALOG_PORT']+'/health',timeout=10)as response:h=json.load(response)
assert pathlib.Path('/tmp') in pathlib.Path(h['storage']['dataDirectory']).resolve().parents,'Use temporary test storage'
for key in ['LOVE2GATHERING_ROOM_HOST_PORT','LOVE2GATHERING_ROOM_GUEST_PORT']:
 with urllib.request.urlopen('http://127.0.0.1:'+os.environ[key]+'/client/capabilities',timeout=20)as response:c=json.load(response)
 assert c['network']['codeOnly'] and c['draft']['modes'],'Expected a real invite-only gateway with native draft capabilities'
PY
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-rooms-live-ui.XXXXXX)
cleanup() {
    python3 - "$test_dir/ownership.json" <<'PY'
import json,pathlib,sys,urllib.request
path=pathlib.Path(sys.argv[1])
if path.exists():
 for item in json.loads(path.read_text()):
  request=urllib.request.Request('http://127.0.0.1:'+str(item['port'])+'/client/rooms/'+item['connectionId']+'/leave',data=b'{}',headers={'Content-Type':'application/json'})
  try:
   with urllib.request.urlopen(request,timeout=20)as response:response.read()
  except Exception:pass
PY
    rm -rf "$test_dir"
}
trap cleanup EXIT INT TERM
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/tests/rooms_live_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'EOF'
function love.conf(t)
    t.identity='love2gathering-rooms-live-ui-tests';t.window.title='Love: 2 Gathering — native invite room and draft UI acceptance'
    t.window.width=1440;t.window.height=900;t.window.vsync=0;t.window.resizable=true
    t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
EOF
cp -R "$project_dir/assets/kenney/runtime" "$test_dir/assets/kenney/"
cp "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
love "$test_dir"
