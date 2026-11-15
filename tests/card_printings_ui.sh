#!/bin/sh
set -eu
: "${LOVE2GATHERING_CATALOG_PORT:?Explicit temporary catalog port is required}"
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-card-printings-ui.XXXXXX)
cleanup(){
 python3 - "$test_dir/printing-targets.json" <<'PY'
import json,os,pathlib,sys,urllib.request
p=pathlib.Path(sys.argv[1])
if p.exists():
 item=json.loads(p.read_text());identifier=item.get('deckId','')
 if identifier.startswith('card-printing-ui-'):
  try:urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:'+os.environ['LOVE2GATHERING_CATALOG_PORT']+'/decks/'+identifier,method='DELETE'),timeout=10).read()
  except Exception:pass
PY
 rm -rf "$test_dir"
}
trap cleanup EXIT INT TERM
python3 - "$test_dir/printing-targets.json" <<'PY'
import json,os,sqlite3,sys,urllib.request,urllib.parse
port=int(os.environ['LOVE2GATHERING_CATALOG_PORT']);assert port>=17400
base='http://127.0.0.1:'+str(port)
def read(path):
 with urllib.request.urlopen(base+path,timeout=15)as r:return json.load(r)
h=read('/health');s=h['storage'];assert h['apiVersion']>=11 and h['ready']and s['dataDirectory'].startswith('/tmp/')and s['cacheDirectory'].startswith('/tmp/'),'Use an isolated API11 catalog only'
with sqlite3.connect('file:'+s['cacheDatabase']+'?mode=ro',uri=True)as c:keys={r[0]for r in c.execute('SELECT cache_key FROM art_cache')}
out={}
for key,name,suffix in [('forest','Forest','&set=thb'),('commander','Rin and Seri, Inseparable','')]:
 items=read('/printings?name='+urllib.parse.quote(name)+'&limit=60'+suffix)['items']
 cached=[i for i in items if i['printing_id']+'-0-normal.jpg'in keys or i['printing_id']+'-0-large.jpg'in keys]
 assert cached,'Genuine full-card JPEG fixture required for '+name
 out[key]=cached[0]
out['deckId']='card-printing-ui-'+str(os.getpid());out['deckName']='Edition UI acceptance fixture'
open(sys.argv[1],'w').write(json.dumps(out))
PY
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme runtime;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/main.lua" "$test_dir/application.lua";cp "$project_dir/tests/card_printings_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'CONF'
function love.conf(t)
 t.identity='love2gathering-card-printings-tests';t.window.title='Love: 2 Gathering — exact edition acceptance';t.window.width=1440;t.window.height=900;t.window.vsync=0;t.window.resizable=true
 t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
CONF
LOVE2GATHERING_ENGINE_PORT=17562 LOVE2GATHERING_ROOM_PORT=17563 love "$test_dir"
python3 - "$test_dir" "$project_dir" <<'PY'
import hashlib,json,pathlib,sys
run,root=map(pathlib.Path,sys.argv[1:]);report=json.loads(pathlib.Path('/tmp/love2gathering-card-printings-ui-report.json').read_text())
names=['app/card_printings.lua','app/card_printings_ui.lua','app/artwork.lua','app/model.lua','app/builder.lua','app/builder_simplified.lua','app/view.lua','app/renderer.lua','main.lua','tests/card_printings_ui.lua']
report['sourceSha256']={p:hashlib.sha256((run/('main.lua'if p=='tests/card_printings_ui.lua'else'application.lua'if p=='main.lua'else p)).read_bytes()).hexdigest()for p in names}
(root/'tests/card-printings-ui-report.json').write_text(json.dumps(report,indent=2)+'\n')
PY
