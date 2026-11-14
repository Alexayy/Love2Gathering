#!/bin/sh
set -eu
: "${LOVE2GATHERING_CATALOG_PORT:?Explicit temporary catalog port is required}"
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-profile-ui.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT INT TERM
prepare_fixture(){ python3 - "$test_dir/profile-test-art.json" <<'PY'
import json,os,sqlite3,sys,urllib.request,urllib.parse
port=int(os.environ['LOVE2GATHERING_CATALOG_PORT']);assert port>=17400,'Use an explicitly isolated test catalog'
def read(path):
 with urllib.request.urlopen('http://127.0.0.1:'+str(port)+path,timeout=10)as r:return json.load(r)
health=read('/health');root=health.get('storage',{}).get('dataDirectory','');assert health.get('apiVersion',0)>=7 and health.get('ready')and root.startswith('/tmp/'),'Ready API7 catalog in temporary storage required'
with sqlite3.connect('file:'+root+'/app.sqlite?mode=ro',uri=True)as c:rows=list(c.execute("SELECT cache_key,metadata FROM art_cache WHERE cache_key LIKE '%-art_crop.jpg'"))
result={}
for slot,name in(('avatar','Angel of Vitality'),('playmat','Forest')):
 entry=next((key,json.loads(meta))for key,meta in rows if json.loads(meta).get('name')==name)
 printing=entry[0].rsplit('-0-art_crop.jpg',1)[0];card=read('/cards/by-name?name='+urllib.parse.quote(name)+'&printing='+printing)
 query=name+' '+card['set'];items=read('/gallery?q='+urllib.parse.quote(query)+'&limit=60')['items'];item=next(i for i in items if i['printing_id']==printing and i['face']==0)
 result[slot]={'printingId':printing,'face':0,'query':query,'name':item['name']}
rin=read('/gallery?q='+urllib.parse.quote('Rin & Seri sld')+'&limit=60')['items']
cached=next((i for i in rin if i.get('art_cached')),None);missing=next((i for i in rin if not i.get('art_cached')),None)
if cached and missing:
 def ref(item):return{'printingId':item['printing_id'],'oracleId':item['oracle_id'],'face':item['face'],'name':item['name']}
 result['rin']={'query':'Rin & Seri sld','cached':ref(cached),'missing':ref(missing)}
open(sys.argv[1],'w').write(json.dumps(result))
print('Temporary profile catalog and exact genuine cached illustrations verified')
PY
}
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme runtime;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/main.lua" "$test_dir/application.lua";cp "$project_dir/tests/profile_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'EOF'
function love.conf(t)
 t.identity='love2gathering-profile-ui-tests';t.window.title='Love: 2 Gathering — profile acceptance'
 t.window.width=tonumber(os.getenv('PROFILE_TEST_WIDTH'))or 1440;t.window.height=tonumber(os.getenv('PROFILE_TEST_HEIGHT'))or 900;t.window.vsync=0;t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
EOF
for dimensions in '1440 900' '1120 760' '2560 1080';do
 set -- $dimensions
 prepare_fixture
 PROFILE_TEST_WIDTH="$1" PROFILE_TEST_HEIGHT="$2" love "$test_dir"
done
python3 - "$project_dir/tests/profile-ui-report.json" <<'PY'
import json,sys
reports=[json.load(open('/tmp/love2gathering-profile-ui-'+str(width)+'-report.json'))for width in(1440,1120,2560)]
json.dump({'passed':all(r['passed']for r in reports),'checks':sum(len(r['checks'])for r in reports),'cases':reports},open(sys.argv[1],'w'),indent=2)
PY
