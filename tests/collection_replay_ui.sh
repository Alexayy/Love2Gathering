#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${LOVE2GATHERING_CATALOG_PORT:?Use an explicit temporary catalog port}"
test_dir=$(mktemp -d /tmp/love2gathering-collection-replay.XXXXXX)
export LOVE2GATHERING_UI_CREATED_IDS="$test_dir/created-ids.json"
cleanup() {
    python3 - "$test_dir" <<'PY'
import json,os,pathlib,re,sys,urllib.request
p=pathlib.Path(sys.argv[1]);base='http://127.0.0.1:'+os.environ['LOVE2GATHERING_CATALOG_PORT']
def request(method,path,body=None):
 data=None if body is None else json.dumps(body).encode();req=urllib.request.Request(base+path,data=data,method=method,headers={'Content-Type':'application/json'})
 with urllib.request.urlopen(req,timeout=20)as r:return json.load(r)
for id in json.loads((p/'created-ids.json').read_text())if(p/'created-ids.json').exists()else[]:
 assert re.fullmatch(r'deck-[0-9a-f]{16}',id),'Only delete specifically recorded generated copies'
 try:
  item=request('GET','/decks/'+id);item=item.get('deck',item)
  assert item.get('origin')=='user','Source collections must never be deleted'
  request('DELETE','/decks/'+id)
 except Exception as e:print('UI cleanup copy:',e,file=sys.stderr)
if(p/'layout-before.json').exists():
 try:request('PUT','/ui-layout',json.loads((p/'layout-before.json').read_text()))
 except Exception as e:print('UI cleanup layout:',e,file=sys.stderr)
PY
    rm -rf "$test_dir"
}
trap cleanup EXIT INT TERM
python3 - "$test_dir" <<'PY'
import json,os,pathlib,sqlite3,sys,time,urllib.request
p=pathlib.Path(sys.argv[1]);port=int(os.environ['LOVE2GATHERING_CATALOG_PORT']);assert port>=17400,'Use an isolated test catalog'
base='http://127.0.0.1:'+str(port)
for attempt in range(40):
 try:
  health=json.load(urllib.request.urlopen(base+'/health',timeout=3))
  if health.get('ready')and health.get('apiVersion',0)>=6:break
 except Exception:pass
 time.sleep(.25)
else:raise SystemExit('An API6 temporary ready catalog is required')
store=pathlib.Path(health['storage']['dataDirectory']).resolve();assert pathlib.Path('/tmp')in store.parents,'Do not use user save data'
(p/'layout-before.json').write_text(json.dumps(json.load(urllib.request.urlopen(base+'/ui-layout'))));(p/'created-ids.json').write_text('[]')
db=sqlite3.connect('file:'+str(store/'app.sqlite')+'?mode=ro',uri=True);refs=[]
for name in ['Ayara, First of Locthwain','Angel of Vitality']:
 for key,metadata in db.execute("SELECT cache_key,metadata FROM art_cache WHERE json_extract(metadata,'$.name')=? AND json_extract(metadata,'$.kind')='art_crop' LIMIT 1",(name,)):
  meta=json.loads(metadata);refs.append({'name':name,'oracleId':meta['oracleId'],'printingId':key[:36],'face':0})
assert len(refs)==2,'Seed the two genuine profile-art JPEGs in the temporary cache'
(p/'profile-art.json').write_text(json.dumps(refs))
PY
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme runtime; do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/"; done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/tests/collection_replay_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'EOF'
function love.conf(t)
 t.identity='love2gathering-collection-replay-tests';t.window.title='Love: 2 Gathering — collection and replay acceptance'
 t.window.width=1440;t.window.height=900;t.window.vsync=0;t.window.resizable=true
 t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
EOF
LOVE2GATHERING_ENGINE_PORT=17499 LOVE2GATHERING_ROOM_PORT=17498 love "$test_dir"
python3 - "$test_dir" "$project_dir" <<'PY'
import hashlib,json,pathlib,sys
run=pathlib.Path(sys.argv[1]);root=pathlib.Path(sys.argv[2]);report=json.loads(pathlib.Path('/tmp/love2gathering-collection-replay-ui-report.json').read_text())
files=list((run/'app').glob('*.lua'))+[run/'main.lua']+list((run/'assets/kenney/runtime').rglob('*'))
report['sourceSha256']={('tests/collection_replay_ui.lua'if p==run/'main.lua'else str(p.relative_to(run))):hashlib.sha256(p.read_bytes()).hexdigest()for p in files if p.is_file()}
(root/'tests/collection-replay-ui-report.json').write_text(json.dumps(report,indent=2)+'\n')
PY
