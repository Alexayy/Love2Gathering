#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${LOVE2GATHERING_CATALOG_PORT:?Use an isolated temporary API7 catalog port}"
test_dir=$(mktemp -d /tmp/love2gathering-builder-modes.XXXXXX)
export LOVE2GATHERING_BUILDER_TEST_IDS="$test_dir/created.json"
cleanup(){
 python3 - "$test_dir" <<'PY'
import json,os,pathlib,shutil,sys,urllib.request
p=pathlib.Path(sys.argv[1]);base='http://127.0.0.1:'+os.environ['LOVE2GATHERING_CATALOG_PORT']
receipt={'deletedCopies':0,'restored':{}}
def req(method,path,data=None):
 r=urllib.request.Request(base+path,data=None if data is None else json.dumps(data).encode(),method=method,headers={'Content-Type':'application/json'})
 with urllib.request.urlopen(r,timeout=20)as f:return json.load(f)
for id in json.loads((p/'created.json').read_text())if(p/'created.json').exists()else[]:
 try:
  item=req('GET','/decks/'+id);item=item.get('deck',item);assert item.get('origin')=='user'and item['name'].startswith('Builder UI acceptance ')
  req('DELETE','/decks/'+id)
  receipt['deletedCopies']+=1
 except Exception as e:print('Builder copy cleanup:',e,file=sys.stderr)
for file,path in [('settings.json','/settings'),('layout.json','/ui-layout')]:
 if(p/file).exists():
  try:
   original=json.loads((p/file).read_text());req('PUT',path,original);receipt['restored'][path]=req('GET',path)==original
  except Exception as e:print('Builder preference cleanup:',e,file=sys.stderr)
pathlib.Path('/tmp/love2gathering-builder-modes-cleanup.json').write_text(json.dumps(receipt))
assert all(receipt['restored'].values()),'Temporary test preferences were not fully restored'
assert p.parent==pathlib.Path('/tmp')and p.name.startswith('love2gathering-builder-modes.');shutil.rmtree(p)
PY
}
trap cleanup EXIT INT TERM
python3 - "$test_dir" <<'PY'
import json,os,pathlib,sys,urllib.request
p=pathlib.Path(sys.argv[1]);port=int(os.environ['LOVE2GATHERING_CATALOG_PORT']);assert port>=17400
base='http://127.0.0.1:'+str(port)
h=json.load(urllib.request.urlopen(base+'/health'));assert h['ready']and h['apiVersion']>=7
assert pathlib.Path('/tmp')in pathlib.Path(h['storage']['dataDirectory']).resolve().parents,'Never use user save data'
for file,path in [('settings.json','/settings'),('layout.json','/ui-layout')]:p.joinpath(file).write_text(json.dumps(json.load(urllib.request.urlopen(base+path))))
p.joinpath('created.json').write_text('[]')
PY
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme runtime;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/tests/builder_modes_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'CONF'
function love.conf(t)
 t.identity='love2gathering-builder-modes-tests';t.window.title='Love: 2 Gathering — builder layout acceptance'
 t.window.width=2560;t.window.height=1080;t.window.resizable=true;t.window.vsync=0
 t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
CONF
LOVE2GATHERING_ENGINE_PORT=17499 LOVE2GATHERING_ROOM_PORT=17498 love "$test_dir"
python3 - "$test_dir" "$project_dir" <<'PY'
import json,pathlib,hashlib,sys
run,root=map(pathlib.Path,sys.argv[1:]);r=json.loads(pathlib.Path('/tmp/love2gathering-builder-modes-ui-report.json').read_text())
files=list((run/'app').glob('*.lua'))+list((run/'lib/Slab').rglob('*.lua'))+[run/'main.lua']
r['sourceSha256']={('tests/builder_modes_ui.lua'if p==run/'main.lua'else str(p.relative_to(run))):hashlib.sha256(p.read_bytes()).hexdigest()for p in files}
(root/'tests/builder-modes-ui-report.json').write_text(json.dumps(r,indent=2)+'\n')
PY
