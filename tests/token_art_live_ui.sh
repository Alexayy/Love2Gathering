#!/bin/sh
set -eu
: "${LOVE2GATHERING_CATALOG_PORT:?Use an explicitly isolated catalog port}"
: "${LOVE2GATHERING_TOKEN_FIXTURE:?Use an explicitly named temporary fixture deck}"
python3 - <<'PY'
import json,os,urllib.request
port=int(os.environ['LOVE2GATHERING_CATALOG_PORT'])
h=json.load(urllib.request.urlopen(f'http://127.0.0.1:{port}/health',timeout=10))
assert h.get('ready') and h.get('apiVersion',0)>=11
assert h['storage']['dataDirectory'].startswith('/tmp/') and h['storage']['cacheDirectory'].startswith('/tmp/'), 'Refusing user storage'
assert os.environ['LOVE2GATHERING_TOKEN_FIXTURE'].startswith('ui-token-'), 'Refusing a non-fixture deck'
identifier=os.environ['LOVE2GATHERING_TOKEN_FIXTURE'];url=f'http://127.0.0.1:{port}/decks/{identifier}'
deck=json.load(urllib.request.urlopen(url,timeout=10));assert deck['name'].startswith('Token Artwork'), 'Refusing a deck without the fixture name'
request=urllib.request.Request(url+'/token-art',data=json.dumps({'mode':'default','selected':[],'overrides':{}}).encode(),method='PUT',headers={'Content-Type':'application/json'})
with urllib.request.urlopen(request,timeout=10)as response:json.load(response)
PY
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-token-live-ui.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT INT TERM
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme runtime;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/tests/token_art_live_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'CONF'
function love.conf(t)
 t.identity='love2gathering-token-live-tests';t.window.title='Love: 2 Gathering — real cached token artwork'
 t.window.width=1440;t.window.height=900;t.window.vsync=0;t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
CONF
LOVE2GATHERING_ENGINE_PORT=17498 LOVE2GATHERING_ROOM_PORT=17497 love "$test_dir"
python3 - "$test_dir" "$project_dir" <<'PY'
import hashlib,json,pathlib,sys
run,root=map(pathlib.Path,sys.argv[1:]);r=json.loads(pathlib.Path('/tmp/love2gathering-token-art-live-ui-report.json').read_text())
files=['app/library.lua','app/library_ui.lua','app/token_art_ui.lua','app/artwork.lua','app/model.lua','app/assets.lua']
r['sourceSha256']={name:hashlib.sha256((run/name).read_bytes()).hexdigest()for name in files}
r['sourceSha256']['tests/token_art_live_ui.lua']=hashlib.sha256((run/'main.lua').read_bytes()).hexdigest()
r['captures']=['/tmp/love2gathering-token-live-'+name+'.png'for name in ('families','random-selected','random-all','manual-active')]
(root/'tests/token-art-live-ui-report.json').write_text(json.dumps(r,indent=2)+'\n')
PY
